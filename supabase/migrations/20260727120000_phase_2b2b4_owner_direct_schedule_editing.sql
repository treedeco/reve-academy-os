-- Phase 2B-2B4: Owner direct fixed-schedule editing with future-lesson cascade.
-- Extends replace_pass_schedule_slots with optional effective_from and adds an atomic
-- fixed-schedule change RPC that replaces slots then cascades eligible future lessons.

DROP FUNCTION IF EXISTS public.reve_owner_replace_pass_schedule_slots(uuid, timestamptz, jsonb, text);

CREATE OR REPLACE FUNCTION public.reve_owner_replace_pass_schedule_slots(
  p_pass_id uuid,
  p_expected_pass_updated_at timestamptz,
  p_schedule_slots jsonb,
  p_reason text,
  p_effective_from date DEFAULT NULL
)
RETURNS TABLE (
  pass_id uuid,
  pass_status text,
  pass_updated_at timestamptz,
  previous_active_slot_count integer,
  new_active_slot_count integer,
  deactivated_slot_count integer,
  created_slot_count integer,
  lesson_rows_changed integer,
  no_change boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_pass public.passes%ROWTYPE;
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous_fingerprint text;
  v_new_fingerprint text;
  v_effective_from date;
  v_previous_count integer;
  v_deactivated_count integer;
  v_created_count integer;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_pass_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_pass.status NOT IN ('active', 'reserved') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PASS_SCHEDULE_IMMUTABLE';
  END IF;

  IF v_pass.updated_at IS DISTINCT FROM p_expected_pass_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  IF v_pass.weekly_frequency_snapshot IS NULL
    OR p_schedule_slots IS NULL
    OR jsonb_typeof(p_schedule_slots) <> 'array'
    OR jsonb_array_length(p_schedule_slots) IS DISTINCT FROM v_pass.weekly_frequency_snapshot THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_FREQUENCY_MISMATCH';
  END IF;

  PERFORM reve_private.validate_initial_enrollment_schedule(
    p_schedule_slots,
    v_pass.weekly_frequency_snapshot
  );

  IF reve_private.pass_schedule_matches_fingerprint(p_pass_id, p_schedule_slots) THEN
    SELECT count(*)::integer
    INTO v_previous_count
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p_pass_id
      AND ss.is_active = true;

    pass_id := p_pass_id;
    pass_status := v_pass.status;
    pass_updated_at := v_pass.updated_at;
    previous_active_slot_count := v_previous_count;
    new_active_slot_count := v_previous_count;
    deactivated_slot_count := 0;
    created_slot_count := 0;
    lesson_rows_changed := 0;
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  PERFORM reve_private.assert_recurring_schedule_no_collision(
    p_pass_id,
    v_pass.student_id,
    v_pass.course_id,
    v_pass.status,
    p_schedule_slots
  );

  PERFORM 1
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true
  FOR UPDATE;

  SELECT count(*)::integer
  INTO v_previous_count
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true;

  v_previous_fingerprint := reve_private.active_pass_schedule_fingerprint(p_pass_id);

  UPDATE public.schedule_slots AS ss
  SET is_active = false
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true;

  GET DIAGNOSTICS v_deactivated_count = ROW_COUNT;

  v_effective_from := COALESCE(
    p_effective_from,
    (now() AT TIME ZONE 'Asia/Seoul')::date
  );

  v_created_count := reve_private.create_initial_schedule_slots(
    p_pass_id,
    v_effective_from,
    p_schedule_slots
  );

  UPDATE public.passes AS p
  SET updated_at = now()
  WHERE p.id = p_pass_id
  RETURNING p.status, p.updated_at
  INTO pass_status, pass_updated_at;

  v_new_fingerprint := reve_private.active_pass_schedule_fingerprint(p_pass_id);

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'pass.schedule_slots_replaced',
    'passes',
    p_pass_id,
    jsonb_build_object(
      'schedule_fingerprint', v_previous_fingerprint,
      'effective_from', v_effective_from
    ),
    jsonb_build_object(
      'schedule_fingerprint', v_new_fingerprint,
      'effective_from', v_effective_from
    ),
    v_reason,
    v_correlation_id
  );

  pass_id := p_pass_id;
  previous_active_slot_count := v_previous_count;
  new_active_slot_count := v_created_count;
  deactivated_slot_count := v_deactivated_count;
  created_slot_count := v_created_count;
  lesson_rows_changed := 0;
  no_change := false;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_change_fixed_pass_schedule(
  p_pass_id uuid,
  p_expected_pass_updated_at timestamptz,
  p_effective_from date,
  p_schedule_slots jsonb,
  p_reason text
)
RETURNS TABLE (
  pass_id uuid,
  pass_status text,
  pass_updated_at timestamptz,
  anchor_lesson_id uuid,
  anchor_rescheduled boolean,
  cascaded_lesson_count integer,
  future_eligible_lesson_count integer,
  no_change boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_replace record;
  v_pass public.passes%ROWTYPE;
  v_anchor public.lessons%ROWTYPE;
  v_prev_lesson public.lessons%ROWTYPE;
  v_effective_start timestamptz;
  v_after timestamptz;
  v_new_at timestamptz;
  v_occ record;
  v_reschedule record;
  v_future_count integer := 0;
BEGIN
  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_EFFECTIVE_FROM_REQUIRED';
  END IF;

  SELECT *
  INTO v_replace
  FROM public.reve_owner_replace_pass_schedule_slots(
    p_pass_id,
    p_expected_pass_updated_at,
    p_schedule_slots,
    p_reason,
    p_effective_from
  )
  LIMIT 1;

  pass_id := v_replace.pass_id;
  pass_status := v_replace.pass_status;
  pass_updated_at := v_replace.pass_updated_at;
  no_change := v_replace.no_change;
  anchor_lesson_id := NULL;
  anchor_rescheduled := false;
  cascaded_lesson_count := 0;

  v_effective_start := (p_effective_from::text || ' 00:00:00+09')::timestamptz;

  SELECT count(*)::integer
  INTO v_future_count
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.scheduled_at >= v_effective_start
    AND reve_private.lesson_is_cascade_eligible(l);

  future_eligible_lesson_count := v_future_count;

  IF v_replace.no_change THEN
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT *
  INTO v_anchor
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.scheduled_at >= v_effective_start
    AND reve_private.lesson_is_cascade_eligible(l)
  ORDER BY l.sequence_number ASC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NEXT;
    RETURN;
  END IF;

  anchor_lesson_id := v_anchor.id;

  PERFORM reve_private.lesson_is_schedule_changeable(v_anchor);

  SELECT *
  INTO v_prev_lesson
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.sequence_number < v_anchor.sequence_number
  ORDER BY l.sequence_number DESC
  LIMIT 1;

  IF FOUND AND v_prev_lesson.scheduled_at IS NOT NULL THEN
    v_after := reve_private.lesson_effective_end_at(
      v_prev_lesson.scheduled_at,
      reve_private.lesson_duration_minutes(v_prev_lesson.id)
    );
  ELSE
    v_after := v_effective_start - interval '1 minute';
  END IF;

  IF v_after < v_effective_start - interval '1 minute' THEN
    v_after := v_effective_start - interval '1 minute';
  END IF;

  SELECT *
  INTO v_occ
  FROM reve_private.next_active_slot_occurrence_in_pass(
    p_pass_id,
    v_after,
    NULL
  );

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON';
  END IF;

  v_new_at := v_occ.scheduled_at;

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_pass_id;

  SELECT *
  INTO v_reschedule
  FROM public.reve_owner_direct_reschedule_lesson(
    v_anchor.id,
    v_new_at,
    v_anchor.updated_at,
    p_reason,
    true,
    v_pass.updated_at
  )
  LIMIT 1;

  anchor_rescheduled := COALESCE(NOT v_reschedule.no_change, false);
  cascaded_lesson_count := COALESCE(v_reschedule.cascaded_lesson_count, 0);
  pass_updated_at := v_reschedule.pass_updated_at;

  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text, date
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text, date
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text, date
) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_change_fixed_pass_schedule(
  uuid, timestamptz, date, jsonb, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_change_fixed_pass_schedule(
  uuid, timestamptz, date, jsonb, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_change_fixed_pass_schedule(
  uuid, timestamptz, date, jsonb, text
) TO authenticated;

-- Student overlap guard for direct schedule edits (same contract as teacher collision).
CREATE OR REPLACE FUNCTION reve_private.student_has_operational_lesson_collision(
  p_student_id uuid,
  p_start timestamptz,
  p_duration_minutes integer,
  p_exclude_lesson_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_collision uuid;
BEGIN
  SELECT l.id
  INTO v_collision
  FROM public.lessons AS l
  WHERE l.student_id = p_student_id
    AND l.status IN ('scheduled', 'postponed')
    AND l.scheduled_at IS NOT NULL
    AND (p_exclude_lesson_id IS NULL OR l.id <> p_exclude_lesson_id)
    AND p_start < (
      l.scheduled_at + (
        reve_private.lesson_duration_minutes(l.id) * interval '1 minute'
      )
    )
    AND l.scheduled_at < (
      p_start + (p_duration_minutes * interval '1 minute')
    )
  LIMIT 1;

  IF v_collision IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_STUDENT_SCHEDULE_COLLISION';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION reve_private.student_has_operational_lesson_collision(
  uuid, timestamptz, integer, uuid
) FROM PUBLIC;

-- Patch direct reschedule to reject student self-overlap.
CREATE OR REPLACE FUNCTION public.reve_owner_direct_reschedule_lesson(
  p_lesson_id uuid,
  p_new_scheduled_at timestamptz,
  p_expected_lesson_updated_at timestamptz,
  p_reason text,
  p_cascade boolean DEFAULT false,
  p_expected_pass_updated_at timestamptz DEFAULT NULL
)
RETURNS TABLE (
  lesson_id uuid,
  previous_lesson_status text,
  new_lesson_status text,
  previous_scheduled_at timestamptz,
  new_scheduled_at timestamptz,
  lesson_updated_at timestamptz,
  pass_id uuid,
  pass_updated_at timestamptz,
  schedule_change_event_id uuid,
  cascaded_lesson_count integer,
  sms_notification_status text,
  no_change boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_reason text;
  v_lesson public.lessons%ROWTYPE;
  v_pass public.passes%ROWTYPE;
  v_correlation_id uuid := gen_random_uuid();
  v_duration integer;
  v_previous_lesson jsonb;
  v_new_lesson jsonb;
  v_proposal jsonb;
  v_elem jsonb;
  v_eligible integer := 0;
  v_previous_lesson_status text;
  v_new_lesson_status text;
  v_previous_scheduled_at timestamptz;
  v_new_scheduled_at timestamptz;
  v_move_idx integer;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  SELECT *
  INTO v_lesson
  FROM public.lessons AS l
  WHERE l.id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = v_lesson.pass_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  pass_id := v_pass.id;
  pass_updated_at := v_pass.updated_at;

  IF v_lesson.scheduled_at IS NOT DISTINCT FROM p_new_scheduled_at
    AND EXISTS (
      SELECT 1
      FROM public.lesson_schedule_changes AS lsc
      WHERE lsc.lesson_id = v_lesson.id
        AND lsc.schedule_change_request_id IS NULL
        AND lsc.change_origin = 'direct_user'
        AND lsc.new_scheduled_at IS NOT DISTINCT FROM p_new_scheduled_at
    ) THEN
    SELECT lsc.id
    INTO schedule_change_event_id
    FROM public.lesson_schedule_changes AS lsc
    WHERE lsc.lesson_id = v_lesson.id
      AND lsc.schedule_change_request_id IS NULL
      AND lsc.change_origin = 'direct_user'
      AND lsc.new_scheduled_at IS NOT DISTINCT FROM p_new_scheduled_at
    ORDER BY lsc.created_at ASC
    LIMIT 1;

    lesson_id := v_lesson.id;
    previous_lesson_status := v_lesson.status;
    new_lesson_status := v_lesson.status;
    previous_scheduled_at := v_lesson.scheduled_at;
    new_scheduled_at := v_lesson.scheduled_at;
    lesson_updated_at := v_lesson.updated_at;
    cascaded_lesson_count := 0;
    sms_notification_status := (
      SELECT n.status
      FROM public.sms_notifications AS n
      WHERE n.pass_id = v_pass.id
        AND n.notification_type = 'renewal_reminder'
      LIMIT 1
    );
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_lesson.updated_at IS DISTINCT FROM p_expected_lesson_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  PERFORM reve_private.lesson_is_schedule_changeable(v_lesson);

  v_duration := reve_private.lesson_duration_minutes(v_lesson.id);

  PERFORM reve_private.validate_academy_operating_hours(p_new_scheduled_at, v_duration);

  PERFORM reve_private.teacher_has_operational_lesson_collision(
    v_lesson.assigned_teacher_id,
    p_new_scheduled_at,
    v_duration,
    v_lesson.id
  );

  PERFORM reve_private.student_has_operational_lesson_collision(
    v_lesson.student_id,
    p_new_scheduled_at,
    v_duration,
    v_lesson.id
  );

  IF p_cascade THEN
    IF p_expected_pass_updated_at IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_STALE_STATE';
    END IF;

    SELECT *
    INTO v_pass
    FROM public.passes AS p
    WHERE p.id = v_lesson.pass_id
    FOR UPDATE;

    IF v_pass.updated_at IS DISTINCT FROM p_expected_pass_updated_at THEN
      RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
    END IF;

    IF v_pass.status <> 'active' THEN
      IF v_pass.status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PASS_SCHEDULE_IMMUTABLE';
      END IF;
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_NOT_READY';
    END IF;

    PERFORM 1
    FROM public.lessons AS l
    WHERE l.pass_id = v_pass.id
      AND l.sequence_number > v_lesson.sequence_number
    ORDER BY l.sequence_number ASC
    FOR UPDATE;

    PERFORM 1
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = v_pass.id
      AND ss.is_active = true
    FOR UPDATE;
  END IF;

  v_previous_lesson_status := v_lesson.status;
  v_previous_scheduled_at := v_lesson.scheduled_at;
  v_new_scheduled_at := p_new_scheduled_at;
  v_new_lesson_status := CASE
    WHEN v_lesson.status = 'postponed' THEN 'scheduled'
    ELSE v_lesson.status
  END;

  v_previous_lesson := jsonb_build_object(
    'scheduled_at', v_lesson.scheduled_at,
    'status', v_lesson.status
  );

  UPDATE public.lessons AS l
  SET
    scheduled_at = p_new_scheduled_at,
    status = CASE WHEN l.status = 'postponed' THEN 'scheduled' ELSE l.status END
  WHERE l.id = v_lesson.id
  RETURNING l.updated_at
  INTO lesson_updated_at;

  v_new_lesson := jsonb_build_object(
    'scheduled_at', v_new_scheduled_at,
    'status', v_new_lesson_status
  );

  INSERT INTO public.lesson_schedule_changes (
    lesson_id,
    schedule_change_request_id,
    change_origin,
    previous_scheduled_at,
    new_scheduled_at,
    reason,
    actor_profile_id
  ) VALUES (
    v_lesson.id,
    NULL,
    'direct_user',
    v_previous_scheduled_at,
    v_new_scheduled_at,
    v_reason,
    v_actor
  )
  RETURNING id
  INTO schedule_change_event_id;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'lesson.rescheduled',
    'lessons',
    v_lesson.id,
    v_previous_lesson,
    v_new_lesson,
    v_reason,
    v_correlation_id
  );

  cascaded_lesson_count := 0;

  IF p_cascade THEN
    SELECT *
    INTO v_lesson
    FROM public.lessons AS l
    WHERE l.id = p_lesson_id;

    SELECT count(*)::integer
    INTO v_eligible
    FROM public.lessons AS l
    WHERE l.pass_id = v_pass.id
      AND l.sequence_number > v_lesson.sequence_number
      AND reve_private.lesson_is_cascade_eligible(l);

    v_proposal := reve_private.build_cascade_proposal(v_pass.id, v_lesson);

    IF jsonb_array_length(v_proposal) <> v_eligible THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON';
    END IF;

    PERFORM reve_private.validate_cascade_proposal_collisions(v_proposal);

    FOR v_move_idx IN 0 .. jsonb_array_length(v_proposal) - 1 LOOP
      v_elem := v_proposal->v_move_idx;

      v_previous_lesson := jsonb_build_object(
        'scheduled_at', v_elem->>'previous_scheduled_at',
        'status', v_elem->>'previous_status',
        'schedule_slot_id', v_elem->>'previous_schedule_slot_id',
        'assigned_teacher_id', v_elem->>'previous_teacher_id'
      );

      UPDATE public.lessons AS l
      SET
        scheduled_at = (v_elem->>'new_scheduled_at')::timestamptz,
        schedule_slot_id = (v_elem->>'new_schedule_slot_id')::uuid,
        assigned_teacher_id = (v_elem->>'new_teacher_id')::uuid,
        status = v_elem->>'new_status'
      WHERE l.id = (v_elem->>'lesson_id')::uuid;

      v_new_lesson := jsonb_build_object(
        'scheduled_at', v_elem->>'new_scheduled_at',
        'status', v_elem->>'new_status',
        'schedule_slot_id', v_elem->>'new_schedule_slot_id',
        'assigned_teacher_id', v_elem->>'new_teacher_id'
      );

      INSERT INTO public.lesson_schedule_changes (
        lesson_id,
        schedule_change_request_id,
        change_origin,
        previous_scheduled_at,
        new_scheduled_at,
        reason,
        actor_profile_id
      ) VALUES (
        (v_elem->>'lesson_id')::uuid,
        NULL,
        'cascade_auto',
        (v_elem->>'previous_scheduled_at')::timestamptz,
        (v_elem->>'new_scheduled_at')::timestamptz,
        v_reason,
        v_actor
      );

      PERFORM reve_private.append_audit_log(
        v_actor,
        v_actor_role,
        'lesson.cascade_rescheduled',
        'lessons',
        (v_elem->>'lesson_id')::uuid,
        v_previous_lesson,
        v_new_lesson,
        v_reason,
        v_correlation_id
      );
    END LOOP;

    cascaded_lesson_count := jsonb_array_length(v_proposal);

    UPDATE public.passes AS p
    SET updated_at = now()
    WHERE p.id = v_pass.id
    RETURNING p.updated_at
    INTO pass_updated_at;
  END IF;

  sms_notification_status := reve_private.sync_pass_sms_after_schedule_change(
    v_pass.id,
    v_lesson.student_id,
    v_correlation_id,
    v_actor,
    v_actor_role
  );

  lesson_id := p_lesson_id;
  previous_lesson_status := v_previous_lesson_status;
  new_lesson_status := v_new_lesson_status;
  previous_scheduled_at := v_previous_scheduled_at;
  new_scheduled_at := v_new_scheduled_at;
  no_change := false;
  RETURN NEXT;
END;
$$;

-- REVE ACADEMY OS Phase 2B-2B1R1 — owner direct lesson reschedule + academy hours validation
-- Direct owner reschedule without schedule_change_request; optional cascade; hours guard on apply

-- ===========================================================================
-- Internal helper — academy operating hours (Asia/Seoul)
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.validate_academy_operating_hours(
  p_start timestamptz,
  p_duration_minutes integer
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_local_start time;
  v_start_minutes integer;
  v_end_minutes integer;
BEGIN
  v_local_start := (p_start AT TIME ZONE 'Asia/Seoul')::time;
  v_start_minutes :=
    EXTRACT(HOUR FROM v_local_start)::integer * 60
    + EXTRACT(MINUTE FROM v_local_start)::integer;
  v_end_minutes := v_start_minutes + p_duration_minutes;

  IF v_start_minutes < 13 * 60 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACADEMY_HOURS_BEFORE_OPEN';
  END IF;

  IF v_start_minutes >= 22 * 60 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACADEMY_HOURS_AFTER_CLOSE';
  END IF;

  IF v_end_minutes > 22 * 60 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACADEMY_HOURS_END_AFTER_CLOSE';
  END IF;
END;
$$;

-- ===========================================================================
-- Public RPC — owner direct lesson reschedule (optional cascade)
-- ===========================================================================

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

-- ===========================================================================
-- Patch apply — academy hours validation before collision check
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_apply_schedule_change_request(
  p_request_id uuid,
  p_expected_request_updated_at timestamptz,
  p_expected_lesson_updated_at timestamptz
)
RETURNS TABLE (
  request_id uuid,
  request_status text,
  request_updated_at timestamptz,
  lesson_id uuid,
  previous_lesson_status text,
  new_lesson_status text,
  previous_scheduled_at timestamptz,
  new_scheduled_at timestamptz,
  lesson_updated_at timestamptz,
  schedule_change_event_id uuid,
  cascaded_lesson_count integer,
  no_change boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_request public.schedule_change_requests%ROWTYPE;
  v_lesson public.lessons%ROWTYPE;
  v_correlation_id uuid := gen_random_uuid();
  v_duration integer;
  v_previous_request jsonb;
  v_new_request jsonb;
  v_previous_lesson jsonb;
  v_new_lesson jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();

  SELECT *
  INTO v_request
  FROM public.schedule_change_requests AS scr
  WHERE scr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  SELECT *
  INTO v_lesson
  FROM public.lessons AS l
  WHERE l.id = v_request.target_lesson_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_request.status = 'applied'
    AND v_request.applied_at IS NOT NULL
    AND v_request.approved_scheduled_at IS NOT NULL
    AND v_lesson.scheduled_at IS NOT DISTINCT FROM v_request.approved_scheduled_at
    AND EXISTS (
      SELECT 1
      FROM public.lesson_schedule_changes AS lsc
      WHERE lsc.schedule_change_request_id = v_request.id
        AND lsc.lesson_id = v_lesson.id
        AND lsc.new_scheduled_at IS NOT DISTINCT FROM v_request.approved_scheduled_at
    ) THEN
    SELECT lsc.id
    INTO schedule_change_event_id
    FROM public.lesson_schedule_changes AS lsc
    WHERE lsc.schedule_change_request_id = v_request.id
      AND lsc.lesson_id = v_lesson.id
      AND lsc.new_scheduled_at IS NOT DISTINCT FROM v_request.approved_scheduled_at
    ORDER BY lsc.created_at ASC
    LIMIT 1;

    request_id := v_request.id;
    request_status := v_request.status;
    request_updated_at := v_request.updated_at;
    lesson_id := v_lesson.id;
    previous_lesson_status := v_lesson.status;
    new_lesson_status := v_lesson.status;
    previous_scheduled_at := v_lesson.scheduled_at;
    new_scheduled_at := v_lesson.scheduled_at;
    lesson_updated_at := v_lesson.updated_at;
    cascaded_lesson_count := 0;
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_request.status <> 'approved' OR v_request.applied_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REQUEST_NOT_APPLICABLE';
  END IF;

  IF v_request.approved_scheduled_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_APPROVED_TIME_REQUIRED';
  END IF;

  IF v_request.updated_at IS DISTINCT FROM p_expected_request_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_lesson.updated_at IS DISTINCT FROM p_expected_lesson_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  PERFORM reve_private.validate_schedule_change_request_consistency(v_request, v_lesson);
  PERFORM reve_private.lesson_is_schedule_changeable(v_lesson);

  v_duration := reve_private.lesson_duration_minutes(v_lesson.id);

  PERFORM reve_private.validate_academy_operating_hours(v_request.approved_scheduled_at, v_duration);

  PERFORM reve_private.teacher_has_operational_lesson_collision(
    v_lesson.assigned_teacher_id,
    v_request.approved_scheduled_at,
    v_duration,
    v_lesson.id
  );

  previous_lesson_status := v_lesson.status;
  previous_scheduled_at := v_lesson.scheduled_at;
  new_scheduled_at := v_request.approved_scheduled_at;
  new_lesson_status := CASE
    WHEN v_lesson.status = 'postponed' THEN 'scheduled'
    ELSE v_lesson.status
  END;

  v_previous_request := jsonb_build_object(
    'status', v_request.status,
    'applied_at', v_request.applied_at
  );
  v_previous_lesson := jsonb_build_object(
    'scheduled_at', v_lesson.scheduled_at,
    'status', v_lesson.status
  );

  UPDATE public.lessons AS l
  SET
    scheduled_at = v_request.approved_scheduled_at,
    status = CASE WHEN l.status = 'postponed' THEN 'scheduled' ELSE l.status END
  WHERE l.id = v_lesson.id
  RETURNING l.updated_at
  INTO lesson_updated_at;

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
    v_request.id,
    'direct_user',
    previous_scheduled_at,
    new_scheduled_at,
    v_request.owner_decision_note,
    v_actor
  )
  RETURNING id
  INTO schedule_change_event_id;

  UPDATE public.schedule_change_requests AS scr
  SET
    status = 'applied',
    applied_at = now()
  WHERE scr.id = p_request_id
  RETURNING scr.status, scr.updated_at
  INTO request_status, request_updated_at;

  v_new_request := jsonb_build_object(
    'status', request_status,
    'applied_at', now()
  );
  v_new_lesson := jsonb_build_object(
    'scheduled_at', new_scheduled_at,
    'status', new_lesson_status
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'schedule_change_request.applied',
    'schedule_change_requests',
    p_request_id,
    v_previous_request,
    v_new_request,
    v_request.owner_decision_note,
    v_correlation_id
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'lesson.rescheduled',
    'lessons',
    v_lesson.id,
    v_previous_lesson,
    v_new_lesson,
    v_request.owner_decision_note,
    v_correlation_id
  );

  PERFORM reve_private.sync_pass_sms_after_schedule_change(
    v_lesson.pass_id,
    v_lesson.student_id,
    v_correlation_id,
    v_actor,
    v_actor_role
  );

  request_id := p_request_id;
  lesson_id := v_lesson.id;
  cascaded_lesson_count := 0;
  no_change := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Security grants
-- ===========================================================================

REVOKE ALL ON FUNCTION reve_private.validate_academy_operating_hours(
  timestamptz, integer
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reve_owner_direct_reschedule_lesson(
  uuid, timestamptz, timestamptz, text, boolean, timestamptz
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_direct_reschedule_lesson(
  uuid, timestamptz, timestamptz, text, boolean, timestamptz
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_direct_reschedule_lesson(
  uuid, timestamptz, timestamptz, text, boolean, timestamptz
) TO authenticated;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE (n.nspname = 'reve_private' AND p.proname IN (
      'validate_academy_operating_hours'
    ))
    OR (n.nspname = 'public' AND p.proname IN (
      'reve_owner_direct_reschedule_lesson',
      'reve_owner_apply_schedule_change_request'
    ))
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION reve_private.validate_academy_operating_hours IS
  'Phase 2B-2B1R1 academy hours guard: Asia/Seoul 13:00–22:00 window; start before 22:00, end at or before 22:00.';
COMMENT ON FUNCTION public.reve_owner_direct_reschedule_lesson IS
  'Phase 2B-2B1R1 owner-only direct lesson reschedule without schedule request; optional cascade; anchor moves scheduled_at only.';
COMMENT ON FUNCTION public.reve_owner_apply_schedule_change_request IS
  'Phase 0B-3B-2B-3D-2A/2B owner apply: one lesson direct move + academy hours + SMS sync; cascade deferred to cascade RPC.';

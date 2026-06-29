-- REVE ACADEMY OS Phase 0B-3B-2B-3D-2B — optional cascade rescheduling after direct apply
-- Corrects direct-apply SMS sync; adds owner-triggered future-lesson cascade

-- ===========================================================================
-- Forward schema — cascade completion tracking on schedule_change_requests
-- ===========================================================================

ALTER TABLE public.schedule_change_requests
  ADD COLUMN cascade_completed_at timestamptz,
  ADD COLUMN cascade_completed_by_profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  ADD COLUMN cascaded_lesson_count integer,
  ADD COLUMN cascade_reason text;

ALTER TABLE public.schedule_change_requests
  ADD CONSTRAINT schedule_change_requests_cascaded_count_nonneg
    CHECK (cascaded_lesson_count IS NULL OR cascaded_lesson_count >= 0);

ALTER TABLE public.schedule_change_requests
  ADD CONSTRAINT schedule_change_requests_cascade_after_apply
    CHECK (
      cascade_completed_at IS NULL
      OR (status = 'applied' AND applied_at IS NOT NULL)
    );

COMMENT ON COLUMN public.schedule_change_requests.cascade_completed_at IS
  'Owner cascade completion timestamp; null until optional cascade runs after direct apply.';
COMMENT ON COLUMN public.schedule_change_requests.cascaded_lesson_count IS
  'Count of automatically moved later lessons; 0 when cascade completed with no eligible moves.';

-- ===========================================================================
-- Internal helpers — cascade eligibility, occurrence generation, collision
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.lesson_is_cascade_eligible(p_lesson public.lessons)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT
    p_lesson.scheduled_at IS NOT NULL
    AND p_lesson.actual_start_at IS NULL
    AND p_lesson.actual_end_at IS NULL
    AND p_lesson.status IN ('scheduled', 'postponed');
$$;

CREATE OR REPLACE FUNCTION reve_private.lesson_effective_end_at(
  p_scheduled_at timestamptz,
  p_duration_minutes integer
)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_scheduled_at + (p_duration_minutes * interval '1 minute');
$$;

CREATE OR REPLACE FUNCTION reve_private.next_active_slot_occurrence_in_pass(
  p_pass_id uuid,
  p_after timestamptz,
  p_before timestamptz DEFAULT NULL
)
RETURNS TABLE (
  slot_id uuid,
  teacher_id uuid,
  scheduled_at timestamptz,
  duration_minutes integer,
  slot_order integer
)
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_best_at timestamptz;
  v_best_slot_id uuid;
  v_best_teacher uuid;
  v_best_order integer;
  v_best_duration integer;
  r record;
  v_cand timestamptz;
BEGIN
  v_best_at := NULL;

  FOR r IN
    SELECT
      ss.id,
      ss.teacher_id,
      ss.weekday,
      ss.local_start_time,
      ss.duration_minutes,
      ss.slot_order
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p_pass_id
      AND ss.is_active = true
    ORDER BY ss.slot_order, ss.weekday, ss.local_start_time
  LOOP
    v_cand := reve_private.next_slot_occurrence_after(
      p_after, r.weekday, r.local_start_time
    );

    IF p_before IS NOT NULL AND v_cand >= p_before THEN
      CONTINUE;
    END IF;

    IF v_best_at IS NULL
      OR v_cand < v_best_at
      OR (v_cand = v_best_at AND r.slot_order < v_best_order) THEN
      v_best_at := v_cand;
      v_best_slot_id := r.id;
      v_best_teacher := r.teacher_id;
      v_best_order := r.slot_order;
      v_best_duration := r.duration_minutes;
    END IF;
  END LOOP;

  IF v_best_at IS NULL THEN
    RETURN;
  END IF;

  slot_id := v_best_slot_id;
  teacher_id := v_best_teacher;
  scheduled_at := v_best_at;
  duration_minutes := v_best_duration;
  slot_order := v_best_order;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_has_operational_lesson_collision_excluding(
  p_teacher_id uuid,
  p_start timestamptz,
  p_duration_minutes integer,
  p_exclude_lesson_ids uuid[]
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
  WHERE l.assigned_teacher_id = p_teacher_id
    AND l.status IN ('scheduled', 'postponed')
    AND l.scheduled_at IS NOT NULL
    AND NOT (l.id = ANY (COALESCE(p_exclude_lesson_ids, ARRAY[]::uuid[])))
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
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.proposed_lesson_ranges_overlap(
  p_start_a timestamptz,
  p_duration_a integer,
  p_start_b timestamptz,
  p_duration_b integer
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT
    p_start_a < (p_start_b + (p_duration_b * interval '1 minute'))
    AND p_start_b < (p_start_a + (p_duration_a * interval '1 minute'));
$$;

CREATE OR REPLACE FUNCTION reve_private.validate_cascade_proposal_collisions(
  p_proposal jsonb
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_ids uuid[];
  v_idx integer;
  v_jdx integer;
  v_row_a jsonb;
  v_row_b jsonb;
BEGIN
  IF p_proposal IS NULL OR jsonb_array_length(p_proposal) = 0 THEN
    RETURN;
  END IF;

  SELECT array_agg((elem->>'lesson_id')::uuid)
  INTO v_ids
  FROM jsonb_array_elements(p_proposal) AS elem;

  FOR v_idx IN 0 .. jsonb_array_length(p_proposal) - 1 LOOP
    v_row_a := p_proposal->v_idx;

    PERFORM reve_private.teacher_has_operational_lesson_collision_excluding(
      (v_row_a->>'new_teacher_id')::uuid,
      (v_row_a->>'new_scheduled_at')::timestamptz,
      (v_row_a->>'new_duration_minutes')::integer,
      v_ids
    );

    FOR v_jdx IN v_idx + 1 .. jsonb_array_length(p_proposal) - 1 LOOP
      v_row_b := p_proposal->v_jdx;

      IF (v_row_a->>'new_teacher_id')::uuid = (v_row_b->>'new_teacher_id')::uuid
        AND reve_private.proposed_lesson_ranges_overlap(
          (v_row_a->>'new_scheduled_at')::timestamptz,
          (v_row_a->>'new_duration_minutes')::integer,
          (v_row_b->>'new_scheduled_at')::timestamptz,
          (v_row_b->>'new_duration_minutes')::integer
        ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
      END IF;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.build_cascade_proposal(
  p_pass_id uuid,
  p_anchor_lesson public.lessons
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_cursor timestamptz;
  v_anchor_duration integer;
  v_proposal jsonb := '[]'::jsonb;
  v_segment jsonb := '[]'::jsonb;
  v_lesson public.lessons%ROWTYPE;
  v_occ record;
  v_barrier_at timestamptz;
  v_barrier_duration integer;
  v_elem jsonb;
  v_new_status text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p_pass_id
      AND ss.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_ACTIVE_SCHEDULE';
  END IF;

  v_anchor_duration := reve_private.lesson_duration_minutes(p_anchor_lesson.id);
  v_cursor := reve_private.lesson_effective_end_at(
    p_anchor_lesson.scheduled_at,
    v_anchor_duration
  );

  FOR v_lesson IN
    SELECT l.*
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
      AND l.sequence_number > p_anchor_lesson.sequence_number
    ORDER BY l.sequence_number ASC
  LOOP
    IF reve_private.lesson_is_cascade_eligible(v_lesson) THEN
      v_segment := v_segment || jsonb_build_array(to_jsonb(v_lesson));
    ELSE
      v_barrier_at := v_lesson.scheduled_at;

      FOR v_elem IN
        SELECT value
        FROM jsonb_array_elements(v_segment)
      LOOP
        SELECT *
        INTO v_occ
        FROM reve_private.next_active_slot_occurrence_in_pass(
          p_pass_id,
          v_cursor,
          v_barrier_at
        );

        IF NOT FOUND THEN
          RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON';
        END IF;

        v_new_status := CASE
          WHEN (v_elem->>'status') = 'postponed' THEN 'scheduled'
          ELSE v_elem->>'status'
        END;

        v_proposal := v_proposal || jsonb_build_array(jsonb_build_object(
          'lesson_id', v_elem->>'id',
          'sequence_number', v_elem->>'sequence_number',
          'previous_scheduled_at', v_elem->>'scheduled_at',
          'new_scheduled_at', v_occ.scheduled_at,
          'previous_schedule_slot_id', v_elem->>'schedule_slot_id',
          'new_schedule_slot_id', v_occ.slot_id,
          'previous_teacher_id', v_elem->>'assigned_teacher_id',
          'new_teacher_id', v_occ.teacher_id,
          'previous_status', v_elem->>'status',
          'new_status', v_new_status,
          'new_duration_minutes', v_occ.duration_minutes
        ));

        v_cursor := reve_private.lesson_effective_end_at(
          v_occ.scheduled_at,
          v_occ.duration_minutes
        );
      END LOOP;

      v_segment := '[]'::jsonb;

      IF v_barrier_at IS NOT NULL THEN
        v_barrier_duration := reve_private.lesson_duration_minutes(v_lesson.id);
        v_cursor := reve_private.lesson_effective_end_at(v_barrier_at, v_barrier_duration);
      END IF;
    END IF;
  END LOOP;

  FOR v_elem IN
    SELECT value
    FROM jsonb_array_elements(v_segment)
  LOOP
    SELECT *
    INTO v_occ
    FROM reve_private.next_active_slot_occurrence_in_pass(
      p_pass_id,
      v_cursor,
      NULL
    );

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON';
    END IF;

    v_new_status := CASE
      WHEN (v_elem->>'status') = 'postponed' THEN 'scheduled'
      ELSE v_elem->>'status'
    END;

    v_proposal := v_proposal || jsonb_build_array(jsonb_build_object(
      'lesson_id', v_elem->>'id',
      'sequence_number', v_elem->>'sequence_number',
      'previous_scheduled_at', v_elem->>'scheduled_at',
      'new_scheduled_at', v_occ.scheduled_at,
      'previous_schedule_slot_id', v_elem->>'schedule_slot_id',
      'new_schedule_slot_id', v_occ.slot_id,
      'previous_teacher_id', v_elem->>'assigned_teacher_id',
      'new_teacher_id', v_occ.teacher_id,
      'previous_status', v_elem->>'status',
      'new_status', v_new_status,
      'new_duration_minutes', v_occ.duration_minutes
    ));

    v_cursor := reve_private.lesson_effective_end_at(
      v_occ.scheduled_at,
      v_occ.duration_minutes
    );
  END LOOP;

  RETURN v_proposal;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.sync_pass_sms_after_schedule_change(
  p_pass_id uuid,
  p_student_id uuid,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_remaining integer;
BEGIN
  SELECT u.remaining_lesson_count
  INTO v_remaining
  FROM reve_private.calculate_pass_usage(p_pass_id) AS u;

  RETURN reve_private.synchronize_sms_notification(
    p_pass_id,
    p_student_id,
    v_remaining,
    p_correlation_id,
    p_actor_profile_id,
    p_actor_role
  );
END;
$$;

-- ===========================================================================
-- Public RPC — owner cascade after direct apply
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_cascade_schedule_change_request(
  p_request_id uuid,
  p_expected_request_updated_at timestamptz,
  p_expected_anchor_lesson_updated_at timestamptz,
  p_expected_pass_updated_at timestamptz,
  p_reason text
)
RETURNS TABLE (
  request_id uuid,
  request_status text,
  request_updated_at timestamptz,
  anchor_lesson_id uuid,
  pass_id uuid,
  pass_updated_at timestamptz,
  eligible_lesson_count integer,
  cascaded_lesson_count integer,
  skipped_immutable_lesson_count integer,
  first_cascaded_lesson_at timestamptz,
  last_cascaded_lesson_at timestamptz,
  sms_notification_status text,
  cascade_completed_at timestamptz,
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
  v_request public.schedule_change_requests%ROWTYPE;
  v_anchor public.lessons%ROWTYPE;
  v_pass public.passes%ROWTYPE;
  v_direct_event public.lesson_schedule_changes%ROWTYPE;
  v_direct_count integer;
  v_correlation_id uuid := gen_random_uuid();
  v_proposal jsonb;
  v_elem jsonb;
  v_previous_request jsonb;
  v_new_request jsonb;
  v_previous_lesson jsonb;
  v_new_lesson jsonb;
  v_eligible integer := 0;
  v_skipped integer := 0;
  v_move_idx integer;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  SELECT *
  INTO v_request
  FROM public.schedule_change_requests AS scr
  WHERE scr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_request.cascade_completed_at IS NOT NULL THEN
    SELECT l.*
    INTO v_anchor
    FROM public.lessons AS l
    WHERE l.id = v_request.target_lesson_id;

    SELECT p.*
    INTO v_pass
    FROM public.passes AS p
    WHERE p.id = v_anchor.pass_id;

    request_id := v_request.id;
    request_status := v_request.status;
    request_updated_at := v_request.updated_at;
    anchor_lesson_id := v_anchor.id;
    pass_id := v_pass.id;
    pass_updated_at := v_pass.updated_at;
    eligible_lesson_count := v_request.cascaded_lesson_count;
    cascaded_lesson_count := v_request.cascaded_lesson_count;
    skipped_immutable_lesson_count := 0;
    first_cascaded_lesson_at := (
      SELECT min(lsc.new_scheduled_at)
      FROM public.lesson_schedule_changes AS lsc
      WHERE lsc.schedule_change_request_id = v_request.id
        AND lsc.change_origin = 'cascade_auto'
    );
    last_cascaded_lesson_at := (
      SELECT max(lsc.new_scheduled_at)
      FROM public.lesson_schedule_changes AS lsc
      WHERE lsc.schedule_change_request_id = v_request.id
        AND lsc.change_origin = 'cascade_auto'
    );
    sms_notification_status := (
      SELECT n.status
      FROM public.sms_notifications AS n
      WHERE n.pass_id = v_pass.id
        AND n.notification_type = 'renewal_reminder'
      LIMIT 1
    );
    cascade_completed_at := v_request.cascade_completed_at;
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_request.status <> 'applied' OR v_request.applied_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_NOT_READY';
  END IF;

  IF v_request.updated_at IS DISTINCT FROM p_expected_request_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  SELECT count(*)
  INTO v_direct_count
  FROM public.lesson_schedule_changes AS lsc
  WHERE lsc.schedule_change_request_id = v_request.id
    AND lsc.change_origin = 'direct_user';

  IF v_direct_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_NOT_READY';
  END IF;

  SELECT *
  INTO v_direct_event
  FROM public.lesson_schedule_changes AS lsc
  WHERE lsc.schedule_change_request_id = v_request.id
    AND lsc.change_origin = 'direct_user'
  LIMIT 1;

  SELECT *
  INTO v_anchor
  FROM public.lessons AS l
  WHERE l.id = v_request.target_lesson_id
  FOR UPDATE;

  IF NOT FOUND
    OR v_direct_event.lesson_id IS DISTINCT FROM v_anchor.id
    OR v_request.approved_scheduled_at IS DISTINCT FROM v_anchor.scheduled_at
    OR v_direct_event.new_scheduled_at IS DISTINCT FROM v_anchor.scheduled_at THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_ANCHOR_CHANGED';
  END IF;

  IF v_anchor.updated_at IS DISTINCT FROM p_expected_anchor_lesson_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = v_anchor.pass_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

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
    AND l.sequence_number > v_anchor.sequence_number
  ORDER BY l.sequence_number ASC
  FOR UPDATE;

  PERFORM 1
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass.id
    AND ss.is_active = true
  FOR UPDATE;

  SELECT count(*)::integer
  INTO v_eligible
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass.id
    AND l.sequence_number > v_anchor.sequence_number
    AND reve_private.lesson_is_cascade_eligible(l);

  SELECT count(*)::integer
  INTO v_skipped
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass.id
    AND l.sequence_number > v_anchor.sequence_number
    AND NOT reve_private.lesson_is_cascade_eligible(l);

  v_proposal := reve_private.build_cascade_proposal(v_pass.id, v_anchor);

  IF jsonb_array_length(v_proposal) <> v_eligible THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON';
  END IF;

  PERFORM reve_private.validate_cascade_proposal_collisions(v_proposal);

  v_previous_request := jsonb_build_object(
    'cascade_completed_at', v_request.cascade_completed_at,
    'cascaded_lesson_count', v_request.cascaded_lesson_count
  );

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
      v_request.id,
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

  UPDATE public.passes AS p
  SET updated_at = now()
  WHERE p.id = v_pass.id
  RETURNING p.updated_at
  INTO pass_updated_at;

  sms_notification_status := reve_private.sync_pass_sms_after_schedule_change(
    v_pass.id,
    v_anchor.student_id,
    v_correlation_id,
    v_actor,
    v_actor_role
  );

  UPDATE public.schedule_change_requests AS scr
  SET
    cascade_completed_at = now(),
    cascade_completed_by_profile_id = v_actor,
    cascaded_lesson_count = jsonb_array_length(v_proposal),
    cascade_reason = v_reason
  WHERE scr.id = p_request_id
  RETURNING scr.status, scr.updated_at, scr.cascade_completed_at, scr.cascaded_lesson_count
  INTO request_status, request_updated_at, cascade_completed_at, cascaded_lesson_count;

  v_new_request := jsonb_build_object(
    'cascade_completed_at', cascade_completed_at,
    'cascaded_lesson_count', cascaded_lesson_count,
    'cascade_reason', v_reason
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'schedule_change_request.cascade_completed',
    'schedule_change_requests',
    p_request_id,
    v_previous_request,
    v_new_request,
    v_reason,
    v_correlation_id
  );

  request_id := p_request_id;
  anchor_lesson_id := v_anchor.id;
  pass_id := v_pass.id;
  eligible_lesson_count := v_eligible;
  skipped_immutable_lesson_count := v_skipped;
  first_cascaded_lesson_at := (
    SELECT min((elem->>'new_scheduled_at')::timestamptz)
    FROM jsonb_array_elements(v_proposal) AS elem
  );
  last_cascaded_lesson_at := (
    SELECT max((elem->>'new_scheduled_at')::timestamptz)
    FROM jsonb_array_elements(v_proposal) AS elem
  );
  no_change := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Correct direct apply — SMS synchronization after successful one-lesson move
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

REVOKE ALL ON FUNCTION reve_private.lesson_is_cascade_eligible(public.lessons) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.lesson_effective_end_at(timestamptz, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.next_active_slot_occurrence_in_pass(uuid, timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.teacher_has_operational_lesson_collision_excluding(
  uuid, timestamptz, integer, uuid[]
) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.proposed_lesson_ranges_overlap(
  timestamptz, integer, timestamptz, integer
) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.validate_cascade_proposal_collisions(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.build_cascade_proposal(uuid, public.lessons) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.sync_pass_sms_after_schedule_change(
  uuid, uuid, uuid, uuid, text
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reve_owner_cascade_schedule_change_request(
  uuid, timestamptz, timestamptz, timestamptz, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_cascade_schedule_change_request(
  uuid, timestamptz, timestamptz, timestamptz, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_cascade_schedule_change_request(
  uuid, timestamptz, timestamptz, timestamptz, text
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
      'lesson_is_cascade_eligible',
      'lesson_effective_end_at',
      'next_active_slot_occurrence_in_pass',
      'teacher_has_operational_lesson_collision_excluding',
      'proposed_lesson_ranges_overlap',
      'validate_cascade_proposal_collisions',
      'build_cascade_proposal',
      'sync_pass_sms_after_schedule_change'
    ))
    OR (n.nspname = 'public' AND p.proname IN (
      'reve_owner_cascade_schedule_change_request',
      'reve_owner_apply_schedule_change_request'
    ))
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.reve_owner_cascade_schedule_change_request IS
  'Phase 0B-3B-2B-3D-2B owner-only optional cascade after applied schedule request; moves later eligible lessons only.';
COMMENT ON FUNCTION public.reve_owner_apply_schedule_change_request IS
  'Phase 0B-3B-2B-3D-2A/2B owner apply: one lesson direct move + SMS sync; cascade deferred to cascade RPC.';

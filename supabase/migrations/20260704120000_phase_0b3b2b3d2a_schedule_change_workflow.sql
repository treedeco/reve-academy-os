-- REVE ACADEMY OS Phase 0B-3B-2B-3D-2A — owner schedule change review and apply
-- Review approves/rejects submitted requests; apply mutates lesson scheduled_at only (no cascade)

-- ===========================================================================
-- Forward schema — owner-approved final lesson time
-- ===========================================================================

ALTER TABLE public.schedule_change_requests
  ADD COLUMN approved_scheduled_at timestamptz;

COMMENT ON COLUMN public.schedule_change_requests.approved_scheduled_at IS
  'Owner-approved final lesson time; distinct from proposed_scheduled_at submitted by requester.';

-- ===========================================================================
-- Internal helpers — lesson duration, changeability, collision, consistency
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.lesson_duration_minutes(p_lesson_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT ss.duration_minutes
      FROM public.lessons AS l
      LEFT JOIN public.schedule_slots AS ss ON ss.id = l.schedule_slot_id
      WHERE l.id = p_lesson_id
    ),
    60
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.lesson_is_schedule_changeable(p_lesson public.lessons)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_pass_status text;
BEGIN
  IF p_lesson.scheduled_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_LESSON_NOT_CHANGEABLE';
  END IF;

  IF reve_private.lesson_status_is_deductible(p_lesson.status) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_LESSON_NOT_CHANGEABLE';
  END IF;

  IF p_lesson.actual_start_at IS NOT NULL OR p_lesson.actual_end_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_CHANGE_DENIED';
  END IF;

  IF p_lesson.status NOT IN (
    'scheduled', 'postponed', 'advance_cancelled', 'teacher_cancelled', 'academy_closed'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_LESSON_NOT_CHANGEABLE';
  END IF;

  SELECT p.status
  INTO v_pass_status
  FROM public.passes AS p
  WHERE p.id = p_lesson.pass_id;

  IF v_pass_status NOT IN ('active', 'reserved') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_CHANGE_DENIED';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_has_operational_lesson_collision(
  p_teacher_id uuid,
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
  WHERE l.assigned_teacher_id = p_teacher_id
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
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.validate_schedule_change_request_consistency(
  p_request public.schedule_change_requests,
  p_lesson public.lessons
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF p_request.student_id IS DISTINCT FROM p_lesson.student_id THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_CHANGE_DENIED';
  END IF;

  IF p_request.target_lesson_id IS DISTINCT FROM p_lesson.id THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_CHANGE_DENIED';
  END IF;
END;
$$;

-- ===========================================================================
-- Public RPC — owner review (approve / reject submitted request)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_review_schedule_change_request(
  p_request_id uuid,
  p_decision text,
  p_expected_request_updated_at timestamptz,
  p_decision_reason text,
  p_approved_scheduled_at timestamptz DEFAULT NULL
)
RETURNS TABLE (
  request_id uuid,
  previous_request_status text,
  new_request_status text,
  request_updated_at timestamptz,
  approved_scheduled_at timestamptz,
  decision text,
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
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_decision_reason, '')), '');

  IF p_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_DECISION';
  END IF;

  SELECT *
  INTO v_request
  FROM public.schedule_change_requests AS scr
  WHERE scr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF p_decision = 'approve'
    AND v_request.status = 'approved'
    AND v_request.approved_scheduled_at IS NOT DISTINCT FROM p_approved_scheduled_at
    AND v_request.owner_decision_note IS NOT DISTINCT FROM v_reason THEN
    request_id := v_request.id;
    previous_request_status := v_request.status;
    new_request_status := v_request.status;
    request_updated_at := v_request.updated_at;
    approved_scheduled_at := v_request.approved_scheduled_at;
    decision := p_decision;
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_decision = 'reject'
    AND v_request.status = 'rejected'
    AND v_request.owner_decision_note IS NOT DISTINCT FROM v_reason THEN
    request_id := v_request.id;
    previous_request_status := v_request.status;
    new_request_status := v_request.status;
    request_updated_at := v_request.updated_at;
    approved_scheduled_at := NULL;
    decision := p_decision;
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_request.status <> 'submitted' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REQUEST_NOT_REVIEWABLE';
  END IF;

  IF v_request.updated_at IS DISTINCT FROM p_expected_request_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  IF p_decision = 'approve' THEN
    IF p_approved_scheduled_at IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_APPROVED_TIME_REQUIRED';
    END IF;

    SELECT *
    INTO v_lesson
    FROM public.lessons AS l
    WHERE l.id = v_request.target_lesson_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
    END IF;

    PERFORM reve_private.validate_schedule_change_request_consistency(v_request, v_lesson);
    PERFORM reve_private.lesson_is_schedule_changeable(v_lesson);

    v_previous := jsonb_build_object(
      'status', v_request.status,
      'approved_scheduled_at', v_request.approved_scheduled_at,
      'owner_decision_note', v_request.owner_decision_note
    );

    UPDATE public.schedule_change_requests AS scr
    SET
      status = 'approved',
      approved_scheduled_at = p_approved_scheduled_at,
      owner_decision_note = v_reason,
      decided_by_profile_id = v_actor,
      decided_at = now()
    WHERE scr.id = p_request_id
    RETURNING scr.status, scr.updated_at, scr.approved_scheduled_at
    INTO new_request_status, request_updated_at, approved_scheduled_at;

    v_new := jsonb_build_object(
      'status', new_request_status,
      'approved_scheduled_at', approved_scheduled_at,
      'owner_decision_note', v_reason,
      'decision', p_decision
    );

    PERFORM reve_private.append_audit_log(
      v_actor,
      v_actor_role,
      'schedule_change_request.reviewed',
      'schedule_change_requests',
      p_request_id,
      v_previous,
      v_new,
      v_reason,
      v_correlation_id
    );

    request_id := p_request_id;
    previous_request_status := 'submitted';
    decision := p_decision;
    no_change := false;
    RETURN NEXT;
    RETURN;
  END IF;

  v_previous := jsonb_build_object(
    'status', v_request.status,
    'owner_decision_note', v_request.owner_decision_note
  );

  UPDATE public.schedule_change_requests AS scr
  SET
    status = 'rejected',
    owner_decision_note = v_reason,
    decided_by_profile_id = v_actor,
    decided_at = now()
  WHERE scr.id = p_request_id
  RETURNING scr.status, scr.updated_at
  INTO new_request_status, request_updated_at;

  v_new := jsonb_build_object(
    'status', new_request_status,
    'owner_decision_note', v_reason,
    'decision', p_decision
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'schedule_change_request.reviewed',
    'schedule_change_requests',
    p_request_id,
    v_previous,
    v_new,
    v_reason,
    v_correlation_id
  );

  request_id := p_request_id;
  previous_request_status := 'submitted';
  approved_scheduled_at := NULL;
  decision := p_decision;
  no_change := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Public RPC — owner apply approved schedule change to target lesson
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

REVOKE ALL ON FUNCTION reve_private.lesson_duration_minutes(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.lesson_is_schedule_changeable(public.lessons) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.teacher_has_operational_lesson_collision(
  uuid, timestamptz, integer, uuid
) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.validate_schedule_change_request_consistency(
  public.schedule_change_requests, public.lessons
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reve_owner_review_schedule_change_request(
  uuid, text, timestamptz, text, timestamptz
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_review_schedule_change_request(
  uuid, text, timestamptz, text, timestamptz
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_review_schedule_change_request(
  uuid, text, timestamptz, text, timestamptz
) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_apply_schedule_change_request(
  uuid, timestamptz, timestamptz
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_apply_schedule_change_request(
  uuid, timestamptz, timestamptz
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_apply_schedule_change_request(
  uuid, timestamptz, timestamptz
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
      'lesson_duration_minutes',
      'lesson_is_schedule_changeable',
      'teacher_has_operational_lesson_collision',
      'validate_schedule_change_request_consistency'
    ))
    OR (n.nspname = 'public' AND p.proname IN (
      'reve_owner_review_schedule_change_request',
      'reve_owner_apply_schedule_change_request'
    ))
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.reve_owner_review_schedule_change_request IS
  'Phase 0B-3B-2B-3D-2A owner-only schedule change review: approve with approved_scheduled_at or reject; no lesson mutation.';
COMMENT ON FUNCTION public.reve_owner_apply_schedule_change_request IS
  'Phase 0B-3B-2B-3D-2A owner-only apply: updates lesson scheduled_at from approved request, append-only event, no cascade.';

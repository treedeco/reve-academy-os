-- REVE ACADEMY OS Phase 0B-3B-2B-1 — trusted lesson status transitions
-- Source: docs/state-transitions.md, docs/trusted-operation-contracts.md, docs/project-brief.md §10

-- ===========================================================================
-- Internal helpers (reve_private; not exposed to clients)
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.lesson_status_is_deductible(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_status IN ('completed', 'same_day_cancelled', 'makeup_completed');
$$;

CREATE OR REPLACE FUNCTION reve_private.is_ordinary_lesson_transition(
  p_from_status text,
  p_to_status text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_from_status = 'scheduled'
      AND p_to_status IN (
        'completed', 'same_day_cancelled', 'postponed',
        'advance_cancelled', 'teacher_cancelled', 'academy_closed'
      ) THEN true
    WHEN p_from_status = 'postponed'
      AND p_to_status IN (
        'scheduled', 'completed', 'same_day_cancelled',
        'advance_cancelled', 'teacher_cancelled', 'academy_closed'
      ) THEN true
    WHEN p_from_status = 'advance_cancelled'
      AND p_to_status IN ('scheduled', 'completed') THEN true
    WHEN p_from_status = 'teacher_cancelled'
      AND p_to_status = 'scheduled' THEN true
    WHEN p_from_status = 'academy_closed'
      AND p_to_status IN ('scheduled', 'postponed') THEN true
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION reve_private.is_correction_lesson_transition(
  p_from_status text,
  p_to_status text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT reve_private.lesson_status_is_deductible(p_from_status)
    AND p_to_status IN (
      'scheduled', 'postponed', 'advance_cancelled',
      'teacher_cancelled', 'academy_closed'
    );
$$;

CREATE OR REPLACE FUNCTION reve_private.lesson_status_requires_reason(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_status IN (
    'same_day_cancelled', 'postponed', 'advance_cancelled',
    'teacher_cancelled', 'academy_closed'
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.calculate_pass_usage(p_pass_id uuid)
RETURNS TABLE (
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.registered_lesson_count_snapshot AS registered_lesson_count,
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p.id
        AND reve_private.lesson_status_is_deductible(l.status)
    ), 0) AS used_lesson_count,
    p.registered_lesson_count_snapshot - COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p.id
        AND reve_private.lesson_status_is_deductible(l.status)
    ), 0) AS remaining_lesson_count
  FROM public.passes AS p
  WHERE p.id = p_pass_id;
$$;

CREATE OR REPLACE FUNCTION reve_private.find_next_lesson_at(p_pass_id uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT l.scheduled_at
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.status = 'scheduled'
    AND l.scheduled_at > now()
  ORDER BY l.scheduled_at ASC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION reve_private.sms_renewal_message_body(p_remaining integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT format('회차권 갱신 안내: 잔여 %s회', p_remaining);
$$;

CREATE OR REPLACE FUNCTION reve_private.synchronize_sms_notification(
  p_pass_id uuid,
  p_student_id uuid,
  p_remaining integer,
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
  v_sms public.sms_notifications%ROWTYPE;
  v_final_lesson_at timestamptz;
  v_final_seoul_date date;
  v_today_seoul date;
  v_new_status text;
  v_new_target_date date;
  v_new_body text;
  v_previous jsonb;
  v_new jsonb;
BEGIN
  SELECT *
  INTO v_sms
  FROM public.sms_notifications AS n
  WHERE n.pass_id = p_pass_id
    AND n.notification_type = 'renewal_reminder'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_sms.status = 'sent' THEN
    RETURN v_sms.status;
  END IF;

  v_final_lesson_at := (
    SELECT max(l.scheduled_at)
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
  );
  v_today_seoul := (now() AT TIME ZONE 'Asia/Seoul')::date;
  v_final_seoul_date := CASE
    WHEN v_final_lesson_at IS NULL THEN NULL
    ELSE (v_final_lesson_at AT TIME ZONE 'Asia/Seoul')::date
  END;
  v_new_target_date := CASE
    WHEN v_final_seoul_date IS NULL THEN NULL
    ELSE v_final_seoul_date - 1
  END;

  IF p_remaining > 1 THEN
    v_new_status := 'normal';
  ELSIF p_remaining = 1 THEN
    IF v_final_seoul_date IS NOT NULL
      AND v_today_seoul >= (v_final_seoul_date - 1) THEN
      v_new_status := 'target';
    ELSE
      v_new_status := 'scheduled';
    END IF;
  ELSE
    v_new_status := 'exhausted_unsent';
  END IF;

  v_new_body := reve_private.sms_renewal_message_body(greatest(p_remaining, 0));
  v_previous := jsonb_build_object(
    'status', v_sms.status,
    'message_body_snapshot', v_sms.message_body_snapshot,
    'target_date', v_sms.target_date
  );
  v_new := jsonb_build_object(
    'status', v_new_status,
    'message_body_snapshot', v_new_body,
    'target_date', v_new_target_date
  );

  IF v_sms.status IS DISTINCT FROM v_new_status
    OR v_sms.message_body_snapshot IS DISTINCT FROM v_new_body
    OR v_sms.target_date IS DISTINCT FROM v_new_target_date THEN
    UPDATE public.sms_notifications AS n
    SET
      status = v_new_status,
      message_body_snapshot = v_new_body,
      target_date = v_new_target_date
    WHERE n.id = v_sms.id;

    PERFORM reve_private.append_audit_log(
      p_actor_profile_id,
      p_actor_role,
      'sms_notification.state_sync',
      'sms_notifications',
      v_sms.id,
      v_previous,
      v_new,
      NULL,
      p_correlation_id
    );
  END IF;

  RETURN v_new_status;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.synchronize_pass_after_lesson_change(
  p_pass_id uuid,
  p_registered integer,
  p_used integer,
  p_remaining integer,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text,
  p_is_correction boolean
)
RETURNS TABLE (
  pass_status text,
  reserved_pass_activation_pending boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pass public.passes%ROWTYPE;
  v_previous jsonb;
  v_new jsonb;
  v_status text;
  v_pending boolean := false;
BEGIN
  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_pass_id
  FOR UPDATE;

  IF v_pass.status = 'cancelled' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PASS_CANCELLED';
  END IF;

  v_status := v_pass.status;

  IF p_used > p_registered OR p_remaining < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_USAGE_EXCEEDED';
  END IF;

  IF v_pass.status = 'active' AND p_remaining = 0 THEN
    v_previous := jsonb_build_object(
      'status', v_pass.status,
      'completed_at', v_pass.completed_at
    );
    UPDATE public.passes AS p
    SET
      status = 'completed',
      completed_at = COALESCE(v_pass.completed_at, now())
    WHERE p.id = p_pass_id;
    v_status := 'completed';

    v_new := jsonb_build_object(
      'status', 'completed',
      'completed_at', (SELECT p.completed_at FROM public.passes AS p WHERE p.id = p_pass_id)
    );

    PERFORM reve_private.append_audit_log(
      p_actor_profile_id,
      p_actor_role,
      'pass.completed',
      'passes',
      p_pass_id,
      v_previous,
      v_new,
      NULL,
      p_correlation_id
    );

    IF EXISTS (
      SELECT 1
      FROM public.passes AS rp
      WHERE rp.student_id = v_pass.student_id
        AND rp.course_id = v_pass.course_id
        AND rp.status = 'reserved'
    ) THEN
      v_pending := true;
    END IF;
  ELSIF p_is_correction
    AND v_pass.status = 'completed'
    AND p_remaining > 0 THEN
    v_previous := jsonb_build_object(
      'status', v_pass.status,
      'completed_at', v_pass.completed_at
    );
    UPDATE public.passes AS p
    SET
      status = 'active',
      completed_at = NULL
    WHERE p.id = p_pass_id;
    v_status := 'active';

    v_new := jsonb_build_object(
      'status', 'active',
      'completed_at', NULL
    );

    PERFORM reve_private.append_audit_log(
      p_actor_profile_id,
      p_actor_role,
      'pass.reopened_by_correction',
      'passes',
      p_pass_id,
      v_previous,
      v_new,
      NULL,
      p_correlation_id
    );
  END IF;

  pass_status := v_status;
  reserved_pass_activation_pending := v_pending;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.append_audit_log(
  p_actor_profile_id uuid,
  p_actor_role text,
  p_action text,
  p_resource_table text,
  p_resource_id uuid,
  p_previous_value jsonb,
  p_new_value jsonb,
  p_reason text,
  p_correlation_id uuid
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO public.audit_logs (
    actor_profile_id,
    actor_role_snapshot,
    action,
    resource_table,
    resource_id,
    previous_value,
    new_value,
    reason,
    correlation_id
  ) VALUES (
    p_actor_profile_id,
    p_actor_role,
    p_action,
    p_resource_table,
    p_resource_id,
    p_previous_value,
    p_new_value,
    p_reason,
    p_correlation_id
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.apply_lesson_status_change(
  p_lesson_id uuid,
  p_new_status text,
  p_expected_updated_at timestamptz,
  p_reason text,
  p_actual_started_at timestamptz,
  p_actual_ended_at timestamptz,
  p_is_correction boolean
)
RETURNS TABLE (
  lesson_id uuid,
  previous_status text,
  new_status text,
  lesson_updated_at timestamptz,
  pass_id uuid,
  pass_status text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_lesson_at timestamptz,
  sms_notification_status text,
  reserved_pass_activation_pending boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text;
  v_profile_id uuid;
  v_lesson public.lessons%ROWTYPE;
  v_pass_id uuid;
  v_trimmed_reason text;
  v_previous_lesson jsonb;
  v_new_lesson jsonb;
  v_correlation_id uuid := gen_random_uuid();
  v_registered integer;
  v_used integer;
  v_remaining integer;
  v_pass_status text;
  v_reserved_pending boolean;
  v_sms_status text;
  v_next_at timestamptz;
  v_lesson_updated_at timestamptz;
  v_new_status text;
  v_new_actual_start timestamptz;
  v_new_actual_end timestamptz;
  v_new_change_reason text;
BEGIN
  v_profile_id := auth.uid();
  v_role := reve_private.current_app_role();

  IF v_role IS NULL OR v_profile_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF p_is_correction THEN
    IF NOT reve_private.is_owner() THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
    END IF;
  ELSE
    IF v_role = 'teacher'
      AND NOT reve_private.teacher_can_access_lesson(p_lesson_id) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
    ELSIF v_role NOT IN ('owner', 'teacher') THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
    END IF;
  END IF;

  SELECT *
  INTO v_lesson
  FROM public.lessons AS l
  WHERE l.id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  v_pass_id := v_lesson.pass_id;

  PERFORM 1
  FROM public.passes AS p
  WHERE p.id = v_pass_id
  FOR UPDATE;

  IF v_lesson.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  v_trimmed_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF p_is_correction THEN
    IF v_trimmed_reason IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
    END IF;
    IF NOT reve_private.is_correction_lesson_transition(v_lesson.status, p_new_status) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_TRANSITION';
    END IF;
  ELSE
    IF reve_private.lesson_status_is_deductible(v_lesson.status) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_TRANSITION';
    END IF;
    IF NOT reve_private.is_ordinary_lesson_transition(v_lesson.status, p_new_status) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_TRANSITION';
    END IF;
    IF reve_private.lesson_status_requires_reason(p_new_status)
      AND v_trimmed_reason IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
    END IF;
  END IF;

  IF p_new_status = 'completed' AND p_actual_started_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTUAL_START_REQUIRED';
  END IF;

  IF p_actual_started_at IS NOT NULL
    AND p_actual_ended_at IS NOT NULL
    AND p_actual_ended_at < p_actual_started_at THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_ACTUAL_TIMES';
  END IF;

  v_previous_lesson := jsonb_build_object(
    'status', v_lesson.status,
    'actual_start_at', v_lesson.actual_start_at,
    'actual_end_at', v_lesson.actual_end_at,
    'change_reason', v_lesson.change_reason
  );

  UPDATE public.lessons AS l
  SET
    status = p_new_status,
    change_reason = CASE
      WHEN v_trimmed_reason IS NOT NULL THEN v_trimmed_reason
      ELSE l.change_reason
    END,
    actual_start_at = CASE
      WHEN p_new_status = 'completed' THEN p_actual_started_at
      ELSE NULL
    END,
    actual_end_at = CASE
      WHEN p_new_status = 'completed' THEN p_actual_ended_at
      ELSE NULL
    END
  WHERE l.id = p_lesson_id
  RETURNING
    l.updated_at,
    l.status,
    l.actual_start_at,
    l.actual_end_at,
    l.change_reason
  INTO
    v_lesson_updated_at,
    v_new_status,
    v_new_actual_start,
    v_new_actual_end,
    v_new_change_reason;

  v_new_lesson := jsonb_build_object(
    'status', v_new_status,
    'actual_start_at', v_new_actual_start,
    'actual_end_at', v_new_actual_end,
    'change_reason', v_new_change_reason
  );

  PERFORM reve_private.append_audit_log(
    v_profile_id,
    v_role,
    CASE WHEN p_is_correction THEN 'lesson.status_correction' ELSE 'lesson.status_transition' END,
    'lessons',
    p_lesson_id,
    v_previous_lesson,
    v_new_lesson,
    v_new_change_reason,
    v_correlation_id
  );

  previous_status := v_lesson.status;
  lesson_id := p_lesson_id;
  new_status := v_new_status;
  lesson_updated_at := v_lesson_updated_at;

  SELECT u.registered_lesson_count, u.used_lesson_count, u.remaining_lesson_count
  INTO v_registered, v_used, v_remaining
  FROM reve_private.calculate_pass_usage(v_pass_id) AS u;

  SELECT s.pass_status, s.reserved_pass_activation_pending
  INTO v_pass_status, v_reserved_pending
  FROM reve_private.synchronize_pass_after_lesson_change(
    v_pass_id,
    v_registered,
    v_used,
    v_remaining,
    v_correlation_id,
    v_profile_id,
    v_role,
    p_is_correction
  ) AS s;

  pass_id := v_pass_id;
  pass_status := v_pass_status;
  registered_lesson_count := v_registered;
  used_lesson_count := v_used;
  remaining_lesson_count := v_remaining;
  reserved_pass_activation_pending := v_reserved_pending;

  PERFORM 1
  FROM public.sms_notifications AS n
  WHERE n.pass_id = v_pass_id
  FOR UPDATE;

  v_sms_status := reve_private.synchronize_sms_notification(
    v_pass_id,
    v_lesson.student_id,
    v_remaining,
    v_correlation_id,
    v_profile_id,
    v_role
  );

  v_next_at := reve_private.find_next_lesson_at(v_pass_id);
  sms_notification_status := v_sms_status;
  next_lesson_at := v_next_at;

  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Public trusted RPC functions
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_transition_lesson_status(
  p_lesson_id uuid,
  p_new_status text,
  p_expected_updated_at timestamptz,
  p_actual_started_at timestamptz DEFAULT NULL,
  p_actual_ended_at timestamptz DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS TABLE (
  lesson_id uuid,
  previous_status text,
  new_status text,
  lesson_updated_at timestamptz,
  pass_id uuid,
  pass_status text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_lesson_at timestamptz,
  sms_notification_status text,
  reserved_pass_activation_pending boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM reve_private.apply_lesson_status_change(
    p_lesson_id,
    p_new_status,
    p_expected_updated_at,
    p_reason,
    p_actual_started_at,
    p_actual_ended_at,
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.reve_correct_lesson_status(
  p_lesson_id uuid,
  p_new_status text,
  p_expected_updated_at timestamptz,
  p_reason text,
  p_actual_started_at timestamptz DEFAULT NULL,
  p_actual_ended_at timestamptz DEFAULT NULL
)
RETURNS TABLE (
  lesson_id uuid,
  previous_status text,
  new_status text,
  lesson_updated_at timestamptz,
  pass_id uuid,
  pass_status text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_lesson_at timestamptz,
  sms_notification_status text,
  reserved_pass_activation_pending boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM reve_private.apply_lesson_status_change(
    p_lesson_id,
    p_new_status,
    p_expected_updated_at,
    p_reason,
    p_actual_started_at,
    p_actual_ended_at,
    true
  );
$$;

-- ===========================================================================
-- Privileges
-- ===========================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE (n.nspname = 'reve_private' AND p.proname IN (
      'lesson_status_is_deductible',
      'is_ordinary_lesson_transition',
      'is_correction_lesson_transition',
      'lesson_status_requires_reason',
      'calculate_pass_usage',
      'find_next_lesson_at',
      'sms_renewal_message_body',
      'synchronize_sms_notification',
      'synchronize_pass_after_lesson_change',
      'append_audit_log',
      'apply_lesson_status_change'
    ))
    OR (n.nspname = 'public' AND p.proname IN (
      'reve_transition_lesson_status',
      'reve_correct_lesson_status'
    ))
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
  END LOOP;

  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'reve_private'
      AND p.proname IN (
        'lesson_status_is_deductible',
        'is_ordinary_lesson_transition',
        'is_correction_lesson_transition',
        'lesson_status_requires_reason',
        'calculate_pass_usage',
        'find_next_lesson_at',
        'sms_renewal_message_body',
        'synchronize_sms_notification',
        'synchronize_pass_after_lesson_change',
        'append_audit_log',
        'apply_lesson_status_change'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;

  GRANT EXECUTE ON FUNCTION public.reve_transition_lesson_status(
    uuid, text, timestamptz, timestamptz, timestamptz, text
  ) TO authenticated, service_role;

  GRANT EXECUTE ON FUNCTION public.reve_correct_lesson_status(
    uuid, text, timestamptz, text, timestamptz, timestamptz
  ) TO authenticated, service_role;
END $$;

COMMENT ON FUNCTION public.reve_transition_lesson_status IS
  'Phase 0B-3B-2B-1 trusted ordinary lesson status transition (owner or assigned teacher).';

COMMENT ON FUNCTION public.reve_correct_lesson_status IS
  'Phase 0B-3B-2B-1 owner-only deductible lesson status correction (OD-02).';

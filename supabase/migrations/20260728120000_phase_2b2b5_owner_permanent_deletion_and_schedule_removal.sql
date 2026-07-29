-- REVE ACADEMY OS Phase 2B-2B5 — Owner permanent deletion and fixed-schedule removal
-- Adds trusted, confirmation-gated physical deletion for students/teachers and fixed
-- pass-schedule removal. Historical-protection triggers stay in force for ordinary traffic
-- and are bypassed only inside these trusted internal functions via a local transaction GUC.

-- ===========================================================================
-- Historical protection trigger bypass (reve.trusted_deletion = 'on')
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_block_row_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('reve.trusted_deletion', true) = 'on' THEN
    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'Physical DELETE prohibited on % (REVE historical protection)', TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.reve_block_row_delete() IS
  'Prevents physical DELETE unless reve.trusted_deletion=on (Phase 2B-2B5 owner permanent deletion). Lifecycle changes otherwise use trusted operations.';

CREATE OR REPLACE FUNCTION public.reve_block_row_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('reve.trusted_deletion', true) = 'on' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'UPDATE prohibited on % (append-only / immutable)', TG_TABLE_NAME
      USING ERRCODE = 'restrict_violation';
  ELSIF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'DELETE prohibited on % (append-only / immutable)', TG_TABLE_NAME
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.reve_block_row_mutation() IS
  'Immutable row protection for refunds, schedule events, and audit logs unless reve.trusted_deletion=on (Phase 2B-2B5 owner permanent deletion).';

-- ===========================================================================
-- lessons: allow teacher un-assignment for permanently deleted teachers
-- ===========================================================================

ALTER TABLE public.lessons
  ADD COLUMN assigned_teacher_name_snapshot text;

ALTER TABLE public.lessons
  ALTER COLUMN assigned_teacher_id DROP NOT NULL;

-- ===========================================================================
-- Shared private helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.pass_schedule_removal_lesson_counts(
  p_pass_id uuid,
  p_effective_start timestamptz
)
RETURNS TABLE (
  future_timetable_lesson_count integer,
  manually_moved_future_lesson_count integer,
  preserved_past_lesson_count integer,
  preserved_completed_lesson_count integer
)
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND l.actual_start_at IS NULL
        AND l.actual_end_at IS NULL
        AND l.status IN ('scheduled', 'postponed')
        AND l.scheduled_at >= p_effective_start
    ), 0),
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND l.actual_start_at IS NULL
        AND l.actual_end_at IS NULL
        AND l.status IN ('scheduled', 'postponed')
        AND l.scheduled_at >= p_effective_start
        AND EXISTS (
          SELECT 1
          FROM public.lesson_schedule_changes AS lsc
          WHERE lsc.lesson_id = l.id
            AND lsc.change_origin = 'direct_user'
        )
    ), 0),
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND l.scheduled_at < p_effective_start
        AND NOT reve_private.lesson_status_is_deductible(l.status)
    ), 0),
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND reve_private.lesson_status_is_deductible(l.status)
    ), 0);
$$;

CREATE OR REPLACE FUNCTION reve_private.pass_schedule_removal_fingerprint(
  p_pass_id uuid,
  p_effective_from date
)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT md5(
    COALESCE(p.updated_at::text, '') || '|' ||
    COALESCE(p.status, '') || '|' ||
    p_effective_from::text || '|' ||
    reve_private.active_pass_schedule_fingerprint(p_pass_id) || '|' ||
    COALESCE((
      SELECT c.future_timetable_lesson_count::text
      FROM reve_private.pass_schedule_removal_lesson_counts(
        p_pass_id,
        (p_effective_from::text || ' 00:00:00+09')::timestamptz
      ) AS c
    ), '0')
  )
  FROM public.passes AS p
  WHERE p.id = p_pass_id;
$$;

CREATE OR REPLACE FUNCTION reve_private.student_deletion_fingerprint(p_student_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT md5(
    COALESCE(s.updated_at::text, '') || '|' ||
    COALESCE((SELECT count(*)::text FROM public.passes AS p WHERE p.student_id = s.id), '0') || '|' ||
    COALESCE((SELECT count(*)::text FROM public.lessons AS l WHERE l.student_id = s.id), '0') || '|' ||
    COALESCE((SELECT count(*)::text FROM public.payments AS pay WHERE pay.student_id = s.id), '0') || '|' ||
    COALESCE((SELECT count(*)::text FROM public.sms_notifications AS n WHERE n.student_id = s.id), '0') || '|' ||
    COALESCE((
      SELECT count(*)::text
      FROM public.schedule_slots AS ss
      INNER JOIN public.passes AS p ON p.id = ss.pass_id
      WHERE p.student_id = s.id
    ), '0') || '|' ||
    COALESCE((
      SELECT count(*)::text
      FROM public.payment_refunds AS pr
      INNER JOIN public.payments AS pay ON pay.id = pr.payment_id
      WHERE pay.student_id = s.id
    ), '0') || '|' ||
    COALESCE((SELECT count(*)::text FROM public.schedule_change_requests AS scr WHERE scr.student_id = s.id), '0') || '|' ||
    COALESCE((
      SELECT count(*)::text
      FROM public.lesson_notes AS ln
      INNER JOIN public.lessons AS l ON l.id = ln.lesson_id
      WHERE l.student_id = s.id
    ), '0') || '|' ||
    COALESCE((
      SELECT count(*)::text
      FROM public.lesson_schedule_changes AS lsc
      INNER JOIN public.lessons AS l ON l.id = lsc.lesson_id
      WHERE l.student_id = s.id
    ), '0')
  )
  FROM public.students AS s
  WHERE s.id = p_student_id;
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_deletion_fingerprint(p_teacher_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT md5(
    COALESCE(t.updated_at::text, '') || '|' ||
    COALESCE((SELECT count(*)::text FROM public.lessons AS l WHERE l.assigned_teacher_id = t.id), '0') || '|' ||
    COALESCE((SELECT count(*)::text FROM public.schedule_slots AS ss WHERE ss.teacher_id = t.id), '0') || '|' ||
    COALESCE((
      SELECT count(*)::text
      FROM public.schedule_slots AS ss
      WHERE ss.teacher_id = t.id AND ss.is_active = true
    ), '0') || '|' ||
    COALESCE((
      SELECT count(*)::text
      FROM public.lessons AS l
      WHERE l.assigned_teacher_id = t.id
        AND l.actual_start_at IS NULL
        AND l.actual_end_at IS NULL
        AND l.status IN ('scheduled', 'postponed')
        AND l.scheduled_at > now()
    ), '0')
  )
  FROM public.teachers AS t
  WHERE t.id = p_teacher_id;
$$;

-- ===========================================================================
-- Fixed pass-schedule removal (owner-only)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_preview_remove_fixed_pass_schedule(
  p_pass_id uuid,
  p_effective_from date
)
RETURNS TABLE (
  student_name text,
  student_code text,
  pass_code text,
  pass_status text,
  pass_updated_at timestamptz,
  active_slot_count integer,
  current_weekday_times text,
  future_timetable_lesson_count integer,
  manually_moved_future_lesson_count integer,
  preserved_past_lesson_count integer,
  preserved_completed_lesson_count integer,
  preflight_fingerprint text,
  blockers text[],
  warnings text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pass public.passes%ROWTYPE;
  v_student public.students%ROWTYPE;
  v_effective_from date;
  v_effective_start timestamptz;
  v_counts record;
  v_blockers text[] := '{}';
  v_warnings text[] := '{}';
BEGIN
  PERFORM reve_private.assert_active_owner_caller();

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_pass_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  SELECT *
  INTO v_student
  FROM public.students AS s
  WHERE s.id = v_pass.student_id;

  v_effective_from := COALESCE(p_effective_from, (now() AT TIME ZONE 'Asia/Seoul')::date);
  v_effective_start := (v_effective_from::text || ' 00:00:00+09')::timestamptz;

  SELECT count(*)::integer
  INTO active_slot_count
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true;

  SELECT COALESCE(
    string_agg(
      (ARRAY['일', '월', '화', '수', '목', '금', '토'])[ss.weekday + 1]
        || ' ' || to_char(ss.local_start_time, 'HH24:MI'),
      ', '
      ORDER BY ss.weekday, ss.local_start_time
    ),
    ''
  )
  INTO current_weekday_times
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true;

  SELECT *
  INTO v_counts
  FROM reve_private.pass_schedule_removal_lesson_counts(p_pass_id, v_effective_start);

  IF v_pass.status NOT IN ('active', 'reserved') THEN
    v_blockers := array_append(
      v_blockers,
      '완료되었거나 취소된 회차권은 고정 일정을 삭제할 수 없습니다.'
    );
  END IF;

  IF active_slot_count = 0 THEN
    v_warnings := array_append(
      v_warnings,
      '현재 활성 고정 일정이 없습니다. 실행해도 변경 사항이 없습니다.'
    );
  END IF;

  IF v_counts.manually_moved_future_lesson_count > 0 THEN
    v_warnings := array_append(
      v_warnings,
      format('수동으로 일정이 변경된 향후 수업 %s건이 포함되어 있습니다.', v_counts.manually_moved_future_lesson_count)
    );
  END IF;

  student_name := v_student.name;
  student_code := v_student.student_code;
  pass_code := v_pass.pass_code;
  pass_status := v_pass.status;
  pass_updated_at := v_pass.updated_at;
  future_timetable_lesson_count := v_counts.future_timetable_lesson_count;
  manually_moved_future_lesson_count := v_counts.manually_moved_future_lesson_count;
  preserved_past_lesson_count := v_counts.preserved_past_lesson_count;
  preserved_completed_lesson_count := v_counts.preserved_completed_lesson_count;
  preflight_fingerprint := reve_private.pass_schedule_removal_fingerprint(p_pass_id, v_effective_from);
  blockers := v_blockers;
  warnings := v_warnings;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_remove_fixed_pass_schedule(
  p_pass_id uuid,
  p_expected_pass_updated_at timestamptz,
  p_effective_from date,
  p_reason text,
  p_confirmation_code text,
  p_preflight_fingerprint text
)
RETURNS TABLE (
  pass_id uuid,
  removed_schedule_slot_count integer,
  removed_or_cancelled_future_lesson_count integer,
  preserved_past_lesson_count integer,
  preserved_completed_lesson_count integer,
  effective_from date,
  pass_updated_at timestamptz,
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
  v_effective_from date;
  v_effective_start timestamptz;
  v_fingerprint text;
  v_counts record;
  v_active_slot_count integer;
  v_removed_slot_count integer := 0;
  v_cancelled_count integer := 0;
  v_previous_fingerprint text;
  v_new_fingerprint text;
  v_lesson record;
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
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_DELETION_BLOCKED';
  END IF;

  IF v_pass.updated_at IS DISTINCT FROM p_expected_pass_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  IF p_confirmation_code IS DISTINCT FROM (v_pass.pass_code || ' 스케줄삭제') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CONFIRMATION_MISMATCH';
  END IF;

  v_effective_from := COALESCE(p_effective_from, (now() AT TIME ZONE 'Asia/Seoul')::date);
  v_effective_start := (v_effective_from::text || ' 00:00:00+09')::timestamptz;

  v_fingerprint := reve_private.pass_schedule_removal_fingerprint(p_pass_id, v_effective_from);

  IF v_fingerprint IS DISTINCT FROM p_preflight_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PREFLIGHT_MISMATCH';
  END IF;

  PERFORM 1
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true
  FOR UPDATE;

  SELECT count(*)::integer
  INTO v_active_slot_count
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true;

  SELECT *
  INTO v_counts
  FROM reve_private.pass_schedule_removal_lesson_counts(p_pass_id, v_effective_start);

  IF v_active_slot_count = 0 THEN
    pass_id := p_pass_id;
    removed_schedule_slot_count := 0;
    removed_or_cancelled_future_lesson_count := 0;
    preserved_past_lesson_count := v_counts.preserved_past_lesson_count;
    preserved_completed_lesson_count := v_counts.preserved_completed_lesson_count;
    effective_from := v_effective_from;
    pass_updated_at := v_pass.updated_at;
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  v_previous_fingerprint := reve_private.active_pass_schedule_fingerprint(p_pass_id);

  UPDATE public.schedule_slots AS ss
  SET
    is_active = false,
    effective_until = GREATEST(v_effective_from, ss.effective_from)
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true;

  GET DIAGNOSTICS v_removed_slot_count = ROW_COUNT;

  FOR v_lesson IN
    SELECT l.id, l.status, l.scheduled_at
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
      AND l.actual_start_at IS NULL
      AND l.actual_end_at IS NULL
      AND l.status IN ('scheduled', 'postponed')
      AND l.scheduled_at >= v_effective_start
    ORDER BY l.id
    FOR UPDATE
  LOOP
    UPDATE public.lessons AS l
    SET
      status = 'advance_cancelled',
      change_reason = v_reason
    WHERE l.id = v_lesson.id;

    PERFORM reve_private.append_audit_log(
      v_actor,
      v_actor_role,
      'lesson.status_transition',
      'lessons',
      v_lesson.id,
      jsonb_build_object('status', v_lesson.status, 'scheduled_at', v_lesson.scheduled_at),
      jsonb_build_object('status', 'advance_cancelled', 'scheduled_at', v_lesson.scheduled_at),
      v_reason,
      v_correlation_id
    );

    v_cancelled_count := v_cancelled_count + 1;
  END LOOP;

  v_new_fingerprint := reve_private.active_pass_schedule_fingerprint(p_pass_id);

  UPDATE public.passes AS p
  SET updated_at = now()
  WHERE p.id = p_pass_id
  RETURNING p.updated_at
  INTO pass_updated_at;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'pass.fixed_schedule_removed',
    'passes',
    p_pass_id,
    jsonb_build_object(
      'schedule_fingerprint', v_previous_fingerprint,
      'active_slot_count', v_active_slot_count
    ),
    jsonb_build_object(
      'schedule_fingerprint', v_new_fingerprint,
      'effective_from', v_effective_from,
      'removed_schedule_slot_count', v_removed_slot_count,
      'cancelled_future_lesson_count', v_cancelled_count
    ),
    v_reason,
    v_correlation_id
  );

  pass_id := p_pass_id;
  removed_schedule_slot_count := v_removed_slot_count;
  removed_or_cancelled_future_lesson_count := v_cancelled_count;
  preserved_past_lesson_count := v_counts.preserved_past_lesson_count;
  preserved_completed_lesson_count := v_counts.preserved_completed_lesson_count;
  effective_from := v_effective_from;
  no_change := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Student permanent deletion (owner-only)
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.permanently_delete_student_internal(
  p_student_id uuid,
  p_actor uuid,
  p_actor_role text,
  p_reason text,
  p_correlation_id uuid
)
RETURNS TABLE (
  deleted_lesson_count integer,
  deleted_pass_count integer,
  deleted_payment_count integer,
  deleted_payment_refund_count integer,
  deleted_sms_notification_count integer,
  deleted_schedule_slot_count integer,
  deleted_lesson_note_count integer,
  deleted_schedule_change_request_count integer,
  deleted_lesson_schedule_change_count integer,
  profile_deleted boolean,
  auth_user_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_student public.students%ROWTYPE;
  v_profile_id uuid;
  v_lsc_count integer := 0;
  v_scr_count integer := 0;
  v_note_count integer := 0;
  v_lesson_count integer := 0;
  v_slot_count integer := 0;
  v_sms_count integer := 0;
  v_refund_count integer := 0;
  v_payment_count integer := 0;
  v_pass_count integer := 0;
  v_profile_deleted_rows integer := 0;
BEGIN
  PERFORM set_config('reve.trusted_deletion', 'on', true);

  SELECT *
  INTO v_student
  FROM public.students AS s
  WHERE s.id = p_student_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ALREADY_DELETED';
  END IF;

  v_profile_id := v_student.profile_id;

  DELETE FROM public.lesson_schedule_changes AS lsc
  WHERE lsc.lesson_id IN (
    SELECT l.id FROM public.lessons AS l WHERE l.student_id = p_student_id
  );
  GET DIAGNOSTICS v_lsc_count = ROW_COUNT;

  DELETE FROM public.schedule_change_requests AS scr
  WHERE scr.student_id = p_student_id;
  GET DIAGNOSTICS v_scr_count = ROW_COUNT;

  DELETE FROM public.lesson_notes AS ln
  WHERE ln.lesson_id IN (
    SELECT l.id FROM public.lessons AS l WHERE l.student_id = p_student_id
  );
  GET DIAGNOSTICS v_note_count = ROW_COUNT;

  UPDATE public.lessons AS l
  SET makeup_source_lesson_id = NULL
  WHERE l.makeup_source_lesson_id IN (
    SELECT id FROM public.lessons WHERE student_id = p_student_id
  );

  DELETE FROM public.lessons AS l
  WHERE l.student_id = p_student_id;
  GET DIAGNOSTICS v_lesson_count = ROW_COUNT;

  DELETE FROM public.schedule_slots AS ss
  WHERE ss.pass_id IN (
    SELECT p.id FROM public.passes AS p WHERE p.student_id = p_student_id
  );
  GET DIAGNOSTICS v_slot_count = ROW_COUNT;

  DELETE FROM public.sms_notifications AS n
  WHERE n.student_id = p_student_id;
  GET DIAGNOSTICS v_sms_count = ROW_COUNT;

  DELETE FROM public.payment_refunds AS pr
  WHERE pr.payment_id IN (
    SELECT pay.id FROM public.payments AS pay WHERE pay.student_id = p_student_id
  );
  GET DIAGNOSTICS v_refund_count = ROW_COUNT;

  DELETE FROM public.payments AS pay
  WHERE pay.student_id = p_student_id;
  GET DIAGNOSTICS v_payment_count = ROW_COUNT;

  UPDATE public.passes AS p
  SET previous_pass_id = NULL, correction_source_pass_id = NULL
  WHERE p.student_id = p_student_id
    AND (p.previous_pass_id IS NOT NULL OR p.correction_source_pass_id IS NOT NULL);

  DELETE FROM public.passes AS p
  WHERE p.student_id = p_student_id;
  GET DIAGNOSTICS v_pass_count = ROW_COUNT;

  PERFORM reve_private.append_audit_log(
    p_actor,
    p_actor_role,
    'student.permanently_deleted',
    'students',
    p_student_id,
    jsonb_build_object(
      'student_code', v_student.student_code,
      'deleted_lesson_count', v_lesson_count,
      'deleted_pass_count', v_pass_count,
      'deleted_payment_count', v_payment_count,
      'deleted_payment_refund_count', v_refund_count,
      'deleted_sms_notification_count', v_sms_count,
      'deleted_schedule_slot_count', v_slot_count,
      'deleted_lesson_note_count', v_note_count,
      'deleted_schedule_change_request_count', v_scr_count,
      'deleted_lesson_schedule_change_count', v_lsc_count
    ),
    NULL,
    p_reason,
    p_correlation_id
  );

  DELETE FROM public.students AS s
  WHERE s.id = p_student_id;

  IF v_profile_id IS NOT NULL THEN
    PERFORM reve_private.append_audit_log(
      p_actor,
      p_actor_role,
      'profile.deleted_with_student',
      'profiles',
      v_profile_id,
      jsonb_build_object('student_id', p_student_id),
      NULL,
      p_reason,
      p_correlation_id
    );

    DELETE FROM public.profiles AS pr
    WHERE pr.id = v_profile_id;
    GET DIAGNOSTICS v_profile_deleted_rows = ROW_COUNT;
  END IF;

  deleted_lesson_count := v_lesson_count;
  deleted_pass_count := v_pass_count;
  deleted_payment_count := v_payment_count;
  deleted_payment_refund_count := v_refund_count;
  deleted_sms_notification_count := v_sms_count;
  deleted_schedule_slot_count := v_slot_count;
  deleted_lesson_note_count := v_note_count;
  deleted_schedule_change_request_count := v_scr_count;
  deleted_lesson_schedule_change_count := v_lsc_count;
  profile_deleted := v_profile_deleted_rows > 0;
  auth_user_id := v_profile_id;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_preview_delete_student(p_student_id uuid)
RETURNS TABLE (
  student_id uuid,
  student_code text,
  student_name text,
  operational_status text,
  updated_at timestamptz,
  linked_profile_id uuid,
  auth_user_exists boolean,
  lesson_count integer,
  pass_count integer,
  payment_count integer,
  payment_refund_count integer,
  sms_notification_count integer,
  schedule_slot_count integer,
  lesson_note_count integer,
  schedule_change_request_count integer,
  lesson_schedule_change_count integer,
  preflight_fingerprint text,
  blockers text[],
  warnings text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_student public.students%ROWTYPE;
  v_blockers text[] := '{}';
  v_warnings text[] := '{}';
  v_active_pass_count integer;
BEGIN
  PERFORM reve_private.assert_active_owner_caller();

  SELECT *
  INTO v_student
  FROM public.students AS s
  WHERE s.id = p_student_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  student_id := v_student.id;
  student_code := v_student.student_code;
  student_name := v_student.name;
  operational_status := v_student.operational_status;
  updated_at := v_student.updated_at;
  linked_profile_id := v_student.profile_id;
  auth_user_exists := v_student.profile_id IS NOT NULL
    AND reve_private.auth_user_exists(v_student.profile_id);

  SELECT count(*)::integer INTO lesson_count
  FROM public.lessons AS l WHERE l.student_id = p_student_id;

  SELECT count(*)::integer INTO pass_count
  FROM public.passes AS p WHERE p.student_id = p_student_id;

  SELECT count(*)::integer INTO v_active_pass_count
  FROM public.passes AS p
  WHERE p.student_id = p_student_id
    AND p.status IN ('active', 'reserved');

  SELECT count(*)::integer INTO payment_count
  FROM public.payments AS pay WHERE pay.student_id = p_student_id;

  SELECT count(*)::integer INTO payment_refund_count
  FROM public.payment_refunds AS pr
  INNER JOIN public.payments AS pay ON pay.id = pr.payment_id
  WHERE pay.student_id = p_student_id;

  SELECT count(*)::integer INTO sms_notification_count
  FROM public.sms_notifications AS n WHERE n.student_id = p_student_id;

  SELECT count(*)::integer INTO schedule_slot_count
  FROM public.schedule_slots AS ss
  INNER JOIN public.passes AS p ON p.id = ss.pass_id
  WHERE p.student_id = p_student_id;

  SELECT count(*)::integer INTO lesson_note_count
  FROM public.lesson_notes AS ln
  INNER JOIN public.lessons AS l ON l.id = ln.lesson_id
  WHERE l.student_id = p_student_id;

  SELECT count(*)::integer INTO schedule_change_request_count
  FROM public.schedule_change_requests AS scr
  WHERE scr.student_id = p_student_id;

  SELECT count(*)::integer INTO lesson_schedule_change_count
  FROM public.lesson_schedule_changes AS lsc
  INNER JOIN public.lessons AS l ON l.id = lsc.lesson_id
  WHERE l.student_id = p_student_id;

  IF v_active_pass_count > 0 THEN
    v_warnings := array_append(
      v_warnings,
      format('현재 활성/예약 회차권 %s건이 함께 영구 삭제됩니다.', v_active_pass_count)
    );
  END IF;

  IF payment_count > 0 THEN
    v_warnings := array_append(
      v_warnings,
      format('결제 이력 %s건이 함께 영구 삭제됩니다.', payment_count)
    );
  END IF;

  preflight_fingerprint := reve_private.student_deletion_fingerprint(p_student_id);
  blockers := v_blockers;
  warnings := v_warnings;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_permanently_delete_student(
  p_student_id uuid,
  p_expected_updated_at timestamptz,
  p_confirmation_code text,
  p_reason text,
  p_preflight_fingerprint text
)
RETURNS TABLE (
  student_id uuid,
  already_deleted boolean,
  deleted_lesson_count integer,
  deleted_pass_count integer,
  deleted_payment_count integer,
  deleted_payment_refund_count integer,
  deleted_sms_notification_count integer,
  deleted_schedule_slot_count integer,
  deleted_lesson_note_count integer,
  deleted_schedule_change_request_count integer,
  deleted_lesson_schedule_change_count integer,
  profile_deleted boolean,
  auth_user_id uuid,
  correlation_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_student public.students%ROWTYPE;
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_fingerprint text;
  v_result record;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  SELECT *
  INTO v_student
  FROM public.students AS s
  WHERE s.id = p_student_id
  FOR UPDATE;

  IF NOT FOUND THEN
    student_id := p_student_id;
    already_deleted := true;
    deleted_lesson_count := 0;
    deleted_pass_count := 0;
    deleted_payment_count := 0;
    deleted_payment_refund_count := 0;
    deleted_sms_notification_count := 0;
    deleted_schedule_slot_count := 0;
    deleted_lesson_note_count := 0;
    deleted_schedule_change_request_count := 0;
    deleted_lesson_schedule_change_count := 0;
    profile_deleted := false;
    auth_user_id := NULL;
    correlation_id := v_correlation_id;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_confirmation_code IS DISTINCT FROM (v_student.student_code || ' 영구삭제') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CONFIRMATION_MISMATCH';
  END IF;

  IF v_student.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  v_fingerprint := reve_private.student_deletion_fingerprint(p_student_id);

  IF v_fingerprint IS DISTINCT FROM p_preflight_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PREFLIGHT_MISMATCH';
  END IF;

  SELECT *
  INTO v_result
  FROM reve_private.permanently_delete_student_internal(
    p_student_id,
    v_actor,
    v_actor_role,
    v_reason,
    v_correlation_id
  );

  student_id := p_student_id;
  already_deleted := false;
  deleted_lesson_count := v_result.deleted_lesson_count;
  deleted_pass_count := v_result.deleted_pass_count;
  deleted_payment_count := v_result.deleted_payment_count;
  deleted_payment_refund_count := v_result.deleted_payment_refund_count;
  deleted_sms_notification_count := v_result.deleted_sms_notification_count;
  deleted_schedule_slot_count := v_result.deleted_schedule_slot_count;
  deleted_lesson_note_count := v_result.deleted_lesson_note_count;
  deleted_schedule_change_request_count := v_result.deleted_schedule_change_request_count;
  deleted_lesson_schedule_change_count := v_result.deleted_lesson_schedule_change_count;
  profile_deleted := v_result.profile_deleted;
  auth_user_id := v_result.auth_user_id;
  correlation_id := v_correlation_id;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Teacher permanent deletion (owner-only)
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.permanently_delete_teacher_internal(
  p_teacher_id uuid,
  p_link_handling_mode text,
  p_replacement_teacher_id uuid,
  p_actor uuid,
  p_actor_role text,
  p_reason text,
  p_correlation_id uuid
)
RETURNS TABLE (
  future_reassigned_lesson_count integer,
  future_cancelled_lesson_count integer,
  reassigned_active_slot_count integer,
  snapshotted_lesson_count integer,
  deleted_schedule_slot_count integer,
  profile_deleted boolean,
  auth_user_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_teacher public.teachers%ROWTYPE;
  v_now timestamptz := now();
  v_profile_id uuid;
  v_future_reassigned_count integer := 0;
  v_future_cancelled_count integer := 0;
  v_reassigned_slot_count integer := 0;
  v_snapshot_count integer := 0;
  v_deleted_slot_count integer := 0;
  v_lesson record;
BEGIN
  PERFORM set_config('reve.trusted_deletion', 'on', true);

  SELECT *
  INTO v_teacher
  FROM public.teachers AS t
  WHERE t.id = p_teacher_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ALREADY_DELETED';
  END IF;

  v_profile_id := v_teacher.profile_id;

  PERFORM 1 FROM public.lessons AS l WHERE l.assigned_teacher_id = p_teacher_id FOR UPDATE;
  PERFORM 1 FROM public.schedule_slots AS ss WHERE ss.teacher_id = p_teacher_id FOR UPDATE;

  IF p_link_handling_mode = 'reassign' THEN
    UPDATE public.lessons AS l
    SET assigned_teacher_id = p_replacement_teacher_id
    WHERE l.assigned_teacher_id = p_teacher_id
      AND l.actual_start_at IS NULL
      AND l.actual_end_at IS NULL
      AND l.status IN ('scheduled', 'postponed')
      AND l.scheduled_at > v_now;
    GET DIAGNOSTICS v_future_reassigned_count = ROW_COUNT;

    UPDATE public.schedule_slots AS ss
    SET teacher_id = p_replacement_teacher_id
    WHERE ss.teacher_id = p_teacher_id
      AND ss.is_active = true;
    GET DIAGNOSTICS v_reassigned_slot_count = ROW_COUNT;
  ELSE
    UPDATE public.schedule_slots AS ss
    SET is_active = false
    WHERE ss.teacher_id = p_teacher_id
      AND ss.is_active = true;

    FOR v_lesson IN
      SELECT l.id, l.status, l.scheduled_at
      FROM public.lessons AS l
      WHERE l.assigned_teacher_id = p_teacher_id
        AND l.actual_start_at IS NULL
        AND l.actual_end_at IS NULL
        AND l.status IN ('scheduled', 'postponed')
        AND l.scheduled_at > v_now
      ORDER BY l.id
      FOR UPDATE
    LOOP
      UPDATE public.lessons AS l
      SET status = 'advance_cancelled', change_reason = p_reason
      WHERE l.id = v_lesson.id;

      PERFORM reve_private.append_audit_log(
        p_actor,
        p_actor_role,
        'lesson.status_transition',
        'lessons',
        v_lesson.id,
        jsonb_build_object('status', v_lesson.status, 'scheduled_at', v_lesson.scheduled_at),
        jsonb_build_object('status', 'advance_cancelled', 'scheduled_at', v_lesson.scheduled_at),
        p_reason,
        p_correlation_id
      );

      v_future_cancelled_count := v_future_cancelled_count + 1;
    END LOOP;
  END IF;

  UPDATE public.lessons AS l
  SET
    assigned_teacher_name_snapshot = v_teacher.name,
    assigned_teacher_id = NULL
  WHERE l.assigned_teacher_id = p_teacher_id;
  GET DIAGNOSTICS v_snapshot_count = ROW_COUNT;

  DELETE FROM public.schedule_slots AS ss
  WHERE ss.teacher_id = p_teacher_id;
  GET DIAGNOSTICS v_deleted_slot_count = ROW_COUNT;

  PERFORM reve_private.append_audit_log(
    p_actor,
    p_actor_role,
    'teacher.permanently_deleted',
    'teachers',
    p_teacher_id,
    jsonb_build_object(
      'teacher_code', v_teacher.teacher_code,
      'link_handling_mode', p_link_handling_mode,
      'replacement_teacher_id', p_replacement_teacher_id
    ),
    jsonb_build_object(
      'future_reassigned_lesson_count', v_future_reassigned_count,
      'future_cancelled_lesson_count', v_future_cancelled_count,
      'reassigned_active_slot_count', v_reassigned_slot_count,
      'snapshotted_lesson_count', v_snapshot_count,
      'deleted_schedule_slot_count', v_deleted_slot_count
    ),
    p_reason,
    p_correlation_id
  );

  DELETE FROM public.teachers AS t
  WHERE t.id = p_teacher_id;

  -- Unlike student deletion, the linked profile (auth user) is intentionally kept: a teacher's
  -- profile may still be referenced by requesting_profile_id on other students' schedule_change_requests
  -- (ON DELETE RESTRICT), and access revocation for the underlying auth user is a separate owner action.
  future_reassigned_lesson_count := v_future_reassigned_count;
  future_cancelled_lesson_count := v_future_cancelled_count;
  reassigned_active_slot_count := v_reassigned_slot_count;
  snapshotted_lesson_count := v_snapshot_count;
  deleted_schedule_slot_count := v_deleted_slot_count;
  profile_deleted := false;
  auth_user_id := v_profile_id;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_preview_delete_teacher(p_teacher_id uuid)
RETURNS TABLE (
  teacher_id uuid,
  teacher_code text,
  teacher_name text,
  is_active boolean,
  updated_at timestamptz,
  linked_profile_id uuid,
  auth_user_exists boolean,
  total_lesson_count integer,
  future_eligible_lesson_count integer,
  past_deductible_lesson_count integer,
  active_schedule_slot_count integer,
  total_schedule_slot_count integer,
  preflight_fingerprint text,
  blockers text[],
  warnings text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_teacher public.teachers%ROWTYPE;
  v_blockers text[] := '{}';
  v_warnings text[] := '{}';
BEGIN
  PERFORM reve_private.assert_active_owner_caller();

  SELECT *
  INTO v_teacher
  FROM public.teachers AS t
  WHERE t.id = p_teacher_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  teacher_id := v_teacher.id;
  teacher_code := v_teacher.teacher_code;
  teacher_name := v_teacher.name;
  is_active := v_teacher.is_active;
  updated_at := v_teacher.updated_at;
  linked_profile_id := v_teacher.profile_id;
  auth_user_exists := v_teacher.profile_id IS NOT NULL
    AND reve_private.auth_user_exists(v_teacher.profile_id);

  SELECT count(*)::integer INTO total_lesson_count
  FROM public.lessons AS l WHERE l.assigned_teacher_id = p_teacher_id;

  SELECT count(*)::integer INTO future_eligible_lesson_count
  FROM public.lessons AS l
  WHERE l.assigned_teacher_id = p_teacher_id
    AND l.actual_start_at IS NULL
    AND l.actual_end_at IS NULL
    AND l.status IN ('scheduled', 'postponed')
    AND l.scheduled_at > now();

  SELECT count(*)::integer INTO past_deductible_lesson_count
  FROM public.lessons AS l
  WHERE l.assigned_teacher_id = p_teacher_id
    AND NOT (
      l.actual_start_at IS NULL
      AND l.actual_end_at IS NULL
      AND l.status IN ('scheduled', 'postponed')
      AND l.scheduled_at > now()
    );

  SELECT count(*)::integer INTO active_schedule_slot_count
  FROM public.schedule_slots AS ss
  WHERE ss.teacher_id = p_teacher_id AND ss.is_active = true;

  SELECT count(*)::integer INTO total_schedule_slot_count
  FROM public.schedule_slots AS ss
  WHERE ss.teacher_id = p_teacher_id;

  IF future_eligible_lesson_count > 0 THEN
    v_warnings := array_append(
      v_warnings,
      format(
        '향후 예정된 수업 %s건에 대한 처리 방식을 선택해야 합니다 (강사 재배정 또는 향후 일정 취소).',
        future_eligible_lesson_count
      )
    );
  END IF;

  IF active_schedule_slot_count > 0 THEN
    v_warnings := array_append(
      v_warnings,
      format('활성 고정 일정 %s건이 함께 정리됩니다.', active_schedule_slot_count)
    );
  END IF;

  preflight_fingerprint := reve_private.teacher_deletion_fingerprint(p_teacher_id);
  blockers := v_blockers;
  warnings := v_warnings;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_permanently_delete_teacher(
  p_teacher_id uuid,
  p_expected_updated_at timestamptz,
  p_link_handling_mode text,
  p_replacement_teacher_id uuid,
  p_confirmation_code text,
  p_reason text,
  p_preflight_fingerprint text
)
RETURNS TABLE (
  teacher_id uuid,
  already_deleted boolean,
  link_handling_mode text,
  future_reassigned_lesson_count integer,
  future_cancelled_lesson_count integer,
  reassigned_active_slot_count integer,
  snapshotted_lesson_count integer,
  deleted_schedule_slot_count integer,
  profile_deleted boolean,
  auth_user_id uuid,
  correlation_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_teacher public.teachers%ROWTYPE;
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_fingerprint text;
  v_result record;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  SELECT *
  INTO v_teacher
  FROM public.teachers AS t
  WHERE t.id = p_teacher_id
  FOR UPDATE;

  IF NOT FOUND THEN
    teacher_id := p_teacher_id;
    already_deleted := true;
    link_handling_mode := p_link_handling_mode;
    future_reassigned_lesson_count := 0;
    future_cancelled_lesson_count := 0;
    reassigned_active_slot_count := 0;
    snapshotted_lesson_count := 0;
    deleted_schedule_slot_count := 0;
    profile_deleted := false;
    auth_user_id := NULL;
    correlation_id := v_correlation_id;
    RETURN NEXT;
    RETURN;
  END IF;

  IF p_confirmation_code IS DISTINCT FROM (v_teacher.teacher_code || ' 영구삭제') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_CONFIRMATION_MISMATCH';
  END IF;

  IF v_teacher.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF p_link_handling_mode NOT IN ('reassign', 'remove_future_schedule') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_LINK_HANDLING';
  END IF;

  IF p_link_handling_mode = 'reassign' THEN
    IF p_replacement_teacher_id IS NULL OR p_replacement_teacher_id = p_teacher_id THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REPLACEMENT_TEACHER_INVALID';
    END IF;

    PERFORM 1
    FROM public.teachers AS t
    WHERE t.id = p_replacement_teacher_id
      AND t.is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REPLACEMENT_TEACHER_INVALID';
    END IF;
  ELSE
    IF p_replacement_teacher_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REPLACEMENT_TEACHER_INVALID';
    END IF;
  END IF;

  v_fingerprint := reve_private.teacher_deletion_fingerprint(p_teacher_id);

  IF v_fingerprint IS DISTINCT FROM p_preflight_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PREFLIGHT_MISMATCH';
  END IF;

  SELECT *
  INTO v_result
  FROM reve_private.permanently_delete_teacher_internal(
    p_teacher_id,
    p_link_handling_mode,
    p_replacement_teacher_id,
    v_actor,
    v_actor_role,
    v_reason,
    v_correlation_id
  );

  teacher_id := p_teacher_id;
  already_deleted := false;
  link_handling_mode := p_link_handling_mode;
  future_reassigned_lesson_count := v_result.future_reassigned_lesson_count;
  future_cancelled_lesson_count := v_result.future_cancelled_lesson_count;
  reassigned_active_slot_count := v_result.reassigned_active_slot_count;
  snapshotted_lesson_count := v_result.snapshotted_lesson_count;
  deleted_schedule_slot_count := v_result.deleted_schedule_slot_count;
  profile_deleted := v_result.profile_deleted;
  auth_user_id := v_result.auth_user_id;
  correlation_id := v_correlation_id;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Security grants
-- ===========================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'reve_private'
      AND p.proname IN (
        'pass_schedule_removal_lesson_counts',
        'pass_schedule_removal_fingerprint',
        'student_deletion_fingerprint',
        'teacher_deletion_fingerprint',
        'permanently_delete_student_internal',
        'permanently_delete_teacher_internal'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;

  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'reve_owner_preview_remove_fixed_pass_schedule',
        'reve_owner_remove_fixed_pass_schedule',
        'reve_owner_preview_delete_student',
        'reve_owner_permanently_delete_student',
        'reve_owner_preview_delete_teacher',
        'reve_owner_permanently_delete_teacher'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.reve_owner_preview_remove_fixed_pass_schedule IS
  'Phase 2B-2B5 owner-only read-only preview for fixed pass-schedule removal: counts, weekday/time summary, blockers/warnings, preflight fingerprint.';

COMMENT ON FUNCTION public.reve_owner_remove_fixed_pass_schedule IS
  'Phase 2B-2B5 owner-only fixed pass-schedule removal: confirmation-code + preflight-fingerprint gated; deactivates active slots and advance_cancels eligible future lessons (no physical delete); idempotent when no active slots remain.';

COMMENT ON FUNCTION public.reve_owner_preview_delete_student IS
  'Phase 2B-2B5 owner-only read-only preview for permanent student deletion: dependent-row counts, blockers/warnings, preflight fingerprint, auth user existence.';

COMMENT ON FUNCTION public.reve_owner_permanently_delete_student IS
  'Phase 2B-2B5 owner-only permanent student deletion: confirmation-code ("<student_code> 영구삭제") + preflight-fingerprint gated trusted physical delete of all dependent rows in FK-safe order; tombstone audit contains no PII; idempotent (already_deleted=true) if student is already gone; does not delete the auth.users row.';

COMMENT ON FUNCTION public.reve_owner_preview_delete_teacher IS
  'Phase 2B-2B5 owner-only read-only preview for permanent teacher deletion: lesson/slot counts, blockers/warnings, preflight fingerprint, auth user existence.';

COMMENT ON FUNCTION public.reve_owner_permanently_delete_teacher IS
  'Phase 2B-2B5 owner-only permanent teacher deletion: confirmation-code ("<teacher_code> 영구삭제") + preflight-fingerprint gated; link_handling_mode reassign|remove_future_schedule (no unassign mode; teacher_id is NOT NULL on schedule_slots); snapshots teacher name onto historical lessons before clearing assigned_teacher_id; does not delete students, passes, or payments; idempotent (already_deleted=true) if teacher is already gone; the linked profile/auth user is intentionally kept (may still be referenced by other students'' schedule_change_requests) and auth_user_id is returned for a separate owner access-revocation action.';

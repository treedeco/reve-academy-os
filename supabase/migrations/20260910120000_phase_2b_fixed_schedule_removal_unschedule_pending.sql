-- REVE ACADEMY OS Phase 2B — fixed-schedule removal unschedules pending lessons
-- Owner-approved: active passes may hold unscheduled pending shells (status=scheduled,
-- scheduled_at NULL, no actuals). Fixed-schedule deletion clears obsolete dates on
-- scheduled/postponed pending lessons only; historical statuses are preserved.
--
-- Postponed decision: eligible postponed lessons become status='scheduled' with
-- scheduled_at NULL when the fixed schedule is removed. Reason: lessons_unscheduled_shell_row_check
-- only permits NULL scheduled_at when status='scheduled'; existing reschedule contracts already
-- convert postponed → scheduled when a new date is assigned. Previous postponed status is
-- recorded in audit previous_value.

-- ===========================================================================
-- 1. Active-pass invariant: allow valid unscheduled pending shells
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.validate_pass_lesson_invariants(p_pass_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_pass public.passes%ROWTYPE;
  v_lesson_count integer;
BEGIN
  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_pass_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT count(*)::integer
  INTO v_lesson_count
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id;

  IF v_pass.status IN ('active', 'reserved') THEN
    IF v_lesson_count <> v_pass.registered_lesson_count_snapshot THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PASS_LESSON_COUNT_MISMATCH';
    END IF;
  END IF;

  -- Completed passes must not retain unresolved unscheduled shells.
  IF v_pass.status = 'completed' THEN
    IF EXISTS (
      SELECT 1
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND l.scheduled_at IS NULL
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVE_PASS_UNSCHEDULED_LESSON';
    END IF;
  END IF;

  -- Active/reserved: NULL scheduled_at only allowed for pending scheduled shells
  -- (status=scheduled, no actual timestamps). Invalid combinations remain rejected.
  IF EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
      AND l.scheduled_at IS NULL
      AND (
        l.actual_start_at IS NOT NULL
        OR l.actual_end_at IS NOT NULL
        OR l.status <> 'scheduled'
        OR reve_private.lesson_status_is_deductible(l.status)
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_RESERVED_SHELL';
  END IF;
END;
$$;

COMMENT ON FUNCTION reve_private.validate_pass_lesson_invariants(uuid) IS
  'Pass/lesson invariants: lesson-count match for active/reserved; completed rejects any NULL scheduled_at; active/reserved allow NULL scheduled_at only for status=scheduled shells with no actual timestamps.';

-- ===========================================================================
-- 2. Removal preview counts — eligible pending includes past unprocessed
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
    -- Column name retained for API compatibility; counts all eligible pending
    -- (scheduled/postponed, no actuals) regardless of past/future scheduled_at.
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND l.actual_start_at IS NULL
        AND l.actual_end_at IS NULL
        AND l.status IN ('scheduled', 'postponed')
    ), 0),
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND l.actual_start_at IS NULL
        AND l.actual_end_at IS NULL
        AND l.status IN ('scheduled', 'postponed')
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
        AND l.scheduled_at IS NOT NULL
        AND l.scheduled_at < p_effective_start
        AND NOT reve_private.lesson_status_is_deductible(l.status)
        AND NOT (
          l.actual_start_at IS NULL
          AND l.actual_end_at IS NULL
          AND l.status IN ('scheduled', 'postponed')
        )
    ), 0),
    COALESCE((
      SELECT count(*)::integer
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND reve_private.lesson_status_is_deductible(l.status)
    ), 0);
$$;

-- ===========================================================================
-- 3. Preview warnings for past pending that will be unscheduled
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
  v_past_pending integer := 0;
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

  SELECT count(*)::integer
  INTO v_past_pending
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.actual_start_at IS NULL
    AND l.actual_end_at IS NULL
    AND l.status IN ('scheduled', 'postponed')
    AND l.scheduled_at IS NOT NULL
    AND l.scheduled_at < v_effective_start;

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
      format('수동으로 일정이 변경된 예정 회차 %s건이 포함되어 있습니다.', v_counts.manually_moved_future_lesson_count)
    );
  END IF;

  IF v_past_pending > 0 THEN
    v_warnings := array_append(
      v_warnings,
      format('과거 일시로 남아 있는 미진행 예정 회차 %s건의 일정도 함께 해제됩니다.', v_past_pending)
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

-- ===========================================================================
-- 4. Remove fixed schedule — unschedule eligible pending (not advance_cancel)
-- ===========================================================================

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
  v_unscheduled_count integer := 0;
  v_previous_fingerprint text;
  v_new_fingerprint text;
  v_lesson record;
  v_prev_status text;
  v_new_status text;
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
    SELECT
      l.id,
      l.status,
      l.scheduled_at,
      l.schedule_slot_id,
      l.sequence_number
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
      AND l.actual_start_at IS NULL
      AND l.actual_end_at IS NULL
      AND l.status IN ('scheduled', 'postponed')
    ORDER BY l.sequence_number, l.id
    FOR UPDATE
  LOOP
    v_prev_status := v_lesson.status;
    -- postponed → scheduled required for NULL scheduled_at (row CHECK + invariant)
    v_new_status := 'scheduled';

    UPDATE public.lessons AS l
    SET
      scheduled_at = NULL,
      schedule_slot_id = NULL,
      status = v_new_status,
      change_reason = v_reason
    WHERE l.id = v_lesson.id;

    PERFORM reve_private.append_audit_log(
      v_actor,
      v_actor_role,
      'lesson.schedule_unscheduled',
      'lessons',
      v_lesson.id,
      jsonb_build_object(
        'status', v_prev_status,
        'scheduled_at', v_lesson.scheduled_at,
        'schedule_slot_id', v_lesson.schedule_slot_id,
        'sequence_number', v_lesson.sequence_number
      ),
      jsonb_build_object(
        'status', v_new_status,
        'scheduled_at', NULL,
        'schedule_slot_id', NULL,
        'sequence_number', v_lesson.sequence_number,
        'reason_code', 'fixed_schedule_removed'
      ),
      v_reason,
      v_correlation_id
    );

    v_unscheduled_count := v_unscheduled_count + 1;
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
      'unscheduled_pending_lesson_count', v_unscheduled_count
    ),
    v_reason,
    v_correlation_id
  );

  pass_id := p_pass_id;
  removed_schedule_slot_count := v_removed_slot_count;
  removed_or_cancelled_future_lesson_count := v_unscheduled_count;
  preserved_past_lesson_count := v_counts.preserved_past_lesson_count;
  preserved_completed_lesson_count := v_counts.preserved_completed_lesson_count;
  effective_from := v_effective_from;
  no_change := false;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.reve_owner_preview_remove_fixed_pass_schedule IS
  'Owner-only preview for fixed pass-schedule removal: counts eligible pending lessons (scheduled/postponed, including past unprocessed), preserved history, blockers/warnings, preflight fingerprint.';

COMMENT ON FUNCTION public.reve_owner_remove_fixed_pass_schedule IS
  'Owner-only fixed pass-schedule removal: deactivates active slots; clears scheduled_at/schedule_slot_id on eligible pending lessons (scheduled/postponed, no actuals) while preserving lesson rows and historical statuses; postponed becomes scheduled shell (CHECK-required); never advance_cancels; never deletes lessons.';

-- ===========================================================================
-- 5. Assign dates to existing unscheduled pending shells (no INSERT)
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.assign_dates_to_unscheduled_pending_lessons(
  p_pass_id uuid,
  p_boundary timestamptz,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text,
  p_reason text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cursor timestamptz;
  v_today_start timestamptz;
  v_assigned integer := 0;
  v_lesson record;
  v_best_at timestamptz;
  v_best_slot_id uuid;
  v_best_teacher uuid;
  v_best_order integer;
  r record;
  v_cand timestamptz;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p_pass_id
      AND ss.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  v_today_start := ((now() AT TIME ZONE 'Asia/Seoul')::date::text || ' 00:00:00+09')::timestamptz;
  v_cursor := GREATEST(p_boundary, v_today_start) - interval '1 minute';

  FOR v_lesson IN
    SELECT l.id, l.sequence_number, l.scheduled_at, l.schedule_slot_id, l.assigned_teacher_id, l.status
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
      AND l.scheduled_at IS NULL
      AND l.status = 'scheduled'
      AND l.actual_start_at IS NULL
      AND l.actual_end_at IS NULL
    ORDER BY l.sequence_number ASC
    FOR UPDATE
  LOOP
    v_best_at := NULL;
    v_best_slot_id := NULL;
    v_best_teacher := NULL;
    v_best_order := NULL;

    FOR r IN
      SELECT ss.id, ss.teacher_id, ss.weekday, ss.local_start_time, ss.slot_order
      FROM public.schedule_slots AS ss
      WHERE ss.pass_id = p_pass_id
        AND ss.is_active = true
      ORDER BY ss.slot_order, ss.weekday, ss.local_start_time
    LOOP
      v_cand := reve_private.next_slot_occurrence_after(
        v_cursor, r.weekday, r.local_start_time
      );
      IF v_best_at IS NULL
        OR v_cand < v_best_at
        OR (v_cand = v_best_at AND r.slot_order < v_best_order) THEN
        v_best_at := v_cand;
        v_best_slot_id := r.id;
        v_best_teacher := r.teacher_id;
        v_best_order := r.slot_order;
      END IF;
    END LOOP;

    IF v_best_at IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
    END IF;

    UPDATE public.lessons AS l
    SET
      scheduled_at = v_best_at,
      schedule_slot_id = v_best_slot_id,
      assigned_teacher_id = v_best_teacher
    WHERE l.id = v_lesson.id;

    PERFORM reve_private.append_audit_log(
      p_actor_profile_id,
      p_actor_role,
      'lesson.schedule_assigned',
      'lessons',
      v_lesson.id,
      jsonb_build_object(
        'status', v_lesson.status,
        'scheduled_at', NULL,
        'schedule_slot_id', v_lesson.schedule_slot_id,
        'sequence_number', v_lesson.sequence_number
      ),
      jsonb_build_object(
        'status', 'scheduled',
        'scheduled_at', v_best_at,
        'schedule_slot_id', v_best_slot_id,
        'assigned_teacher_id', v_best_teacher,
        'sequence_number', v_lesson.sequence_number,
        'reason_code', 'fixed_schedule_reassigned'
      ),
      p_reason,
      p_correlation_id
    );

    v_cursor := v_best_at;
    v_assigned := v_assigned + 1;
  END LOOP;

  RETURN v_assigned;
END;
$$;

REVOKE ALL ON FUNCTION reve_private.assign_dates_to_unscheduled_pending_lessons(
  uuid, timestamptz, uuid, uuid, text, text
) FROM PUBLIC;

-- ===========================================================================
-- 6. change_fixed_pass_schedule — cascade dated lessons, then fill shells
-- ===========================================================================

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
  v_dated_eligible_count integer := 0;
  v_unscheduled_count integer := 0;
  v_assigned integer := 0;
  v_actor uuid;
  v_actor_role text;
  v_correlation_id uuid := gen_random_uuid();
  v_reason text;
BEGIN
  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_EFFECTIVE_FROM_REQUIRED';
  END IF;

  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

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
  INTO v_unscheduled_count
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.scheduled_at IS NULL
    AND l.status = 'scheduled'
    AND l.actual_start_at IS NULL
    AND l.actual_end_at IS NULL;

  SELECT count(*)::integer
  INTO v_dated_eligible_count
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.scheduled_at IS NOT NULL
    AND l.scheduled_at >= v_effective_start
    AND reve_private.lesson_is_cascade_eligible(l);

  future_eligible_lesson_count := v_dated_eligible_count + v_unscheduled_count;

  -- Path A: remap existing dated eligible lessons when slots changed.
  IF NOT v_replace.no_change AND v_dated_eligible_count > 0 THEN
    SELECT *
    INTO v_anchor
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
      AND l.scheduled_at >= v_effective_start
      AND reve_private.lesson_is_cascade_eligible(l)
    ORDER BY l.sequence_number ASC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
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
      cascaded_lesson_count := cascaded_lesson_count + COALESCE(v_reschedule.cascaded_lesson_count, 0);
      pass_updated_at := v_reschedule.pass_updated_at;
    END IF;
  END IF;

  -- Path B: fill remaining unscheduled pending shells (after deletion / mixed state).
  -- Never inserts rows; never reuses completed/cancelled history rows.
  SELECT count(*)::integer
  INTO v_unscheduled_count
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
    AND l.scheduled_at IS NULL
    AND l.status = 'scheduled'
    AND l.actual_start_at IS NULL
    AND l.actual_end_at IS NULL;

  IF v_unscheduled_count > 0 THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.schedule_slots AS ss
      WHERE ss.pass_id = p_pass_id
        AND ss.is_active = true
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
    END IF;

    v_assigned := reve_private.assign_dates_to_unscheduled_pending_lessons(
      p_pass_id,
      v_effective_start,
      v_correlation_id,
      v_actor,
      v_actor_role,
      COALESCE(v_reason, 'fixed_schedule_reassigned')
    );
    cascaded_lesson_count := cascaded_lesson_count + v_assigned;
    no_change := false;

    SELECT p.updated_at, p.status
    INTO pass_updated_at, pass_status
    FROM public.passes AS p
    WHERE p.id = p_pass_id;
  END IF;

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.reve_owner_change_fixed_pass_schedule IS
  'Owner-only fixed schedule change: replaces active slots then either assigns dates to existing unscheduled pending shells (sequence order, no duplicate INSERT) or cascades remapping of dated eligible lessons from effective_from.';

COMMENT ON FUNCTION reve_private.assign_dates_to_unscheduled_pending_lessons IS
  'Assigns scheduled_at/schedule_slot_id/teacher to existing unscheduled pending shells in sequence_number order from max(boundary, Seoul today); never creates lesson rows; never reuses completed/cancelled history rows.';

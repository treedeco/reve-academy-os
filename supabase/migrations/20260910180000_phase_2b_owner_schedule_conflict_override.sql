-- REVE ACADEMY OS Phase 2B — Owner fixed-schedule re-register + conflict override
-- Adds collision preview, Owner-only allow_conflict_override on fixed-schedule change,
-- and keeps structural integrity constraints hard-enforced.

-- ===========================================================================
-- 1. List recurring schedule collisions (teacher active slots + internal)
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.list_recurring_schedule_collisions(
  p_target_pass_id uuid,
  p_target_student_id uuid,
  p_target_course_id uuid,
  p_target_status text,
  p_schedule_slots jsonb
)
RETURNS TABLE (
  conflict_type text,
  conflicting_schedule_slot_id uuid,
  conflicting_pass_id uuid,
  conflicting_pass_code text,
  student_name text,
  student_code text,
  teacher_id uuid,
  teacher_name text,
  course_name text,
  weekday integer,
  local_start_time time,
  duration_minutes integer
)
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  r_proposed record;
  r_other record;
BEGIN
  -- Internal proposed-slot self-collision (same teacher + weekday + overlapping times)
  FOR r_proposed IN
    SELECT
      (a.elem->>'teacher_id')::uuid AS teacher_id,
      (a.elem->>'weekday')::integer AS weekday,
      (a.elem->>'local_time')::time AS local_start_time,
      (a.elem->>'duration_minutes')::integer AS duration_minutes,
      a.i AS idx
    FROM jsonb_array_elements(p_schedule_slots) WITH ORDINALITY AS a(elem, i)
  LOOP
    FOR r_other IN
      SELECT
        (b.elem->>'teacher_id')::uuid AS teacher_id,
        (b.elem->>'weekday')::integer AS weekday,
        (b.elem->>'local_time')::time AS local_start_time,
        (b.elem->>'duration_minutes')::integer AS duration_minutes,
        b.j AS idx
      FROM jsonb_array_elements(p_schedule_slots) WITH ORDINALITY AS b(elem, j)
      WHERE b.j > r_proposed.idx
    LOOP
      IF r_proposed.teacher_id = r_other.teacher_id
        AND r_proposed.weekday = r_other.weekday
        AND reve_private.recurring_slot_times_overlap(
          r_proposed.local_start_time,
          r_proposed.duration_minutes,
          r_other.local_start_time,
          r_other.duration_minutes
        ) THEN
        conflict_type := 'proposed_internal';
        conflicting_schedule_slot_id := NULL;
        conflicting_pass_id := p_target_pass_id;
        conflicting_pass_code := NULL;
        student_name := NULL;
        student_code := NULL;
        teacher_id := r_proposed.teacher_id;
        SELECT t.name INTO teacher_name FROM public.teachers AS t WHERE t.id = r_proposed.teacher_id;
        course_name := NULL;
        weekday := r_proposed.weekday;
        local_start_time := r_other.local_start_time;
        duration_minutes := r_other.duration_minutes;
        RETURN NEXT;
      END IF;
    END LOOP;
  END LOOP;

  -- Same-teacher active schedule_slot overlaps on other passes
  FOR r_proposed IN
    SELECT
      (elem->>'teacher_id')::uuid AS teacher_id,
      (elem->>'weekday')::integer AS weekday,
      (elem->>'local_time')::time AS local_start_time,
      (elem->>'duration_minutes')::integer AS duration_minutes
    FROM jsonb_array_elements(p_schedule_slots) AS elem
  LOOP
    FOR r_other IN
      SELECT
        ss.id AS slot_id,
        ss.pass_id,
        p.pass_code,
        p.status AS pass_status,
        p.student_id,
        p.course_id,
        s.name AS student_name,
        s.student_code,
        ss.teacher_id,
        t.name AS teacher_name,
        c.name AS course_name,
        ss.weekday,
        ss.local_start_time,
        ss.duration_minutes
      FROM public.schedule_slots AS ss
      INNER JOIN public.passes AS p ON p.id = ss.pass_id
      INNER JOIN public.students AS s ON s.id = p.student_id
      INNER JOIN public.teachers AS t ON t.id = ss.teacher_id
      INNER JOIN public.courses AS c ON c.id = p.course_id
      WHERE ss.is_active = true
        AND ss.pass_id <> p_target_pass_id
        AND ss.teacher_id = r_proposed.teacher_id
        AND ss.weekday = r_proposed.weekday
        AND reve_private.recurring_slot_times_overlap(
          r_proposed.local_start_time,
          r_proposed.duration_minutes,
          ss.local_start_time,
          ss.duration_minutes
        )
    LOOP
      IF p_target_status = 'reserved'
        AND r_other.pass_status = 'active'
        AND r_other.student_id = p_target_student_id
        AND r_other.course_id = p_target_course_id THEN
        CONTINUE;
      END IF;

      conflict_type := 'same_teacher_slot';
      conflicting_schedule_slot_id := r_other.slot_id;
      conflicting_pass_id := r_other.pass_id;
      conflicting_pass_code := r_other.pass_code;
      student_name := r_other.student_name;
      student_code := r_other.student_code;
      teacher_id := r_other.teacher_id;
      teacher_name := r_other.teacher_name;
      course_name := r_other.course_name;
      weekday := r_other.weekday;
      local_start_time := r_other.local_start_time;
      duration_minutes := r_other.duration_minutes;
      RETURN NEXT;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.assert_recurring_schedule_no_collision(
  p_target_pass_id uuid,
  p_target_student_id uuid,
  p_target_course_id uuid,
  p_target_status text,
  p_schedule_slots jsonb
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM reve_private.list_recurring_schedule_collisions(
      p_target_pass_id,
      p_target_student_id,
      p_target_course_id,
      p_target_status,
      p_schedule_slots
    )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION reve_private.list_recurring_schedule_collisions(
  uuid, uuid, uuid, text, jsonb
) FROM PUBLIC;

-- ===========================================================================
-- 2. Owner preview collisions
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_preview_pass_schedule_collisions(
  p_pass_id uuid,
  p_schedule_slots jsonb
)
RETURNS TABLE (
  conflict_type text,
  conflicting_schedule_slot_id uuid,
  conflicting_pass_id uuid,
  conflicting_pass_code text,
  student_name text,
  student_code text,
  teacher_id uuid,
  teacher_name text,
  course_name text,
  weekday integer,
  local_start_time time,
  duration_minutes integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pass public.passes%ROWTYPE;
BEGIN
  PERFORM reve_private.assert_active_owner_caller();

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_pass_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_pass.status NOT IN ('active', 'reserved') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PASS_SCHEDULE_IMMUTABLE';
  END IF;

  RETURN QUERY
  SELECT *
  FROM reve_private.list_recurring_schedule_collisions(
    p_pass_id,
    v_pass.student_id,
    v_pass.course_id,
    v_pass.status,
    p_schedule_slots
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reve_owner_preview_pass_schedule_collisions(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_preview_pass_schedule_collisions(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_preview_pass_schedule_collisions(uuid, jsonb)
  TO authenticated, service_role;

-- ===========================================================================
-- 3. replace_pass_schedule_slots + allow_conflict_override
-- ===========================================================================

DROP FUNCTION IF EXISTS public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text, date
);

CREATE OR REPLACE FUNCTION public.reve_owner_replace_pass_schedule_slots(
  p_pass_id uuid,
  p_expected_pass_updated_at timestamptz,
  p_schedule_slots jsonb,
  p_reason text,
  p_effective_from date DEFAULT NULL,
  p_allow_conflict_override boolean DEFAULT false
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
  no_change boolean,
  conflict_override_applied boolean
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
  v_conflicts jsonb := '[]'::jsonb;
  v_override boolean := COALESCE(p_allow_conflict_override, false);
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
    conflict_override_applied := false;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
  INTO v_conflicts
  FROM reve_private.list_recurring_schedule_collisions(
    p_pass_id,
    v_pass.student_id,
    v_pass.course_id,
    v_pass.status,
    p_schedule_slots
  ) AS c;

  IF jsonb_array_length(v_conflicts) > 0 THEN
    IF NOT v_override THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
    END IF;

    IF v_actor_role IS DISTINCT FROM 'owner' THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
    END IF;
  ELSE
    v_override := false;
  END IF;

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
      'effective_from', v_effective_from,
      'conflict_override_applied', v_override
    ),
    v_reason,
    v_correlation_id
  );

  IF v_override THEN
    PERFORM reve_private.append_audit_log(
      v_actor,
      v_actor_role,
      'pass.schedule_conflict_overridden',
      'passes',
      p_pass_id,
      jsonb_build_object(
        'schedule_slots', p_schedule_slots,
        'conflict_count', jsonb_array_length(v_conflicts)
      ),
      jsonb_build_object(
        'conflicts', v_conflicts,
        'explicit_override', true,
        'effective_from', v_effective_from
      ),
      v_reason,
      v_correlation_id
    );
  END IF;

  pass_id := p_pass_id;
  previous_active_slot_count := v_previous_count;
  new_active_slot_count := v_created_count;
  deactivated_slot_count := v_deactivated_count;
  created_slot_count := v_created_count;
  lesson_rows_changed := 0;
  no_change := false;
  conflict_override_applied := v_override;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text, date, boolean
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text, date, boolean
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text, date, boolean
) TO authenticated, service_role;

-- ===========================================================================
-- 4. change_fixed_pass_schedule + allow_conflict_override passthrough
-- ===========================================================================

DROP FUNCTION IF EXISTS public.reve_owner_change_fixed_pass_schedule(
  uuid, timestamptz, date, jsonb, text
);

CREATE OR REPLACE FUNCTION public.reve_owner_change_fixed_pass_schedule(
  p_pass_id uuid,
  p_expected_pass_updated_at timestamptz,
  p_effective_from date,
  p_schedule_slots jsonb,
  p_reason text,
  p_allow_conflict_override boolean DEFAULT false
)
RETURNS TABLE (
  pass_id uuid,
  pass_status text,
  pass_updated_at timestamptz,
  anchor_lesson_id uuid,
  anchor_rescheduled boolean,
  cascaded_lesson_count integer,
  future_eligible_lesson_count integer,
  no_change boolean,
  conflict_override_applied boolean
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
    p_effective_from,
    p_allow_conflict_override
  )
  LIMIT 1;

  pass_id := v_replace.pass_id;
  pass_status := v_replace.pass_status;
  pass_updated_at := v_replace.pass_updated_at;
  no_change := v_replace.no_change;
  conflict_override_applied := v_replace.conflict_override_applied;
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

REVOKE ALL ON FUNCTION public.reve_owner_change_fixed_pass_schedule(
  uuid, timestamptz, date, jsonb, text, boolean
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_change_fixed_pass_schedule(
  uuid, timestamptz, date, jsonb, text, boolean
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_change_fixed_pass_schedule(
  uuid, timestamptz, date, jsonb, text, boolean
) TO authenticated, service_role;

COMMENT ON FUNCTION public.reve_owner_preview_pass_schedule_collisions IS
  'Owner-only preview of recurring fixed-schedule collisions (same-teacher active slots / proposed internal overlaps).';

COMMENT ON FUNCTION public.reve_owner_replace_pass_schedule_slots IS
  'Owner-only replace active schedule slots; p_allow_conflict_override permits Owner to save despite same-teacher recurring overlaps with audit.';

COMMENT ON FUNCTION public.reve_owner_change_fixed_pass_schedule IS
  'Owner-only fixed schedule change with optional conflict override; reuses unscheduled pending lesson shells without INSERT.';

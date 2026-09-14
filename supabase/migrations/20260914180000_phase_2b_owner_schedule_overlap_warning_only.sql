-- REVE ACADEMY OS Phase 2B — Owner schedule overlap is warning-only
-- Owner-originated scheduling may temporarily overlap; do not hard-block save.
-- Non-owner callers (if any shared helper is invoked outside Owner JWT) still raise.

-- ===========================================================================
-- 1. Operational lesson collision helpers — Owner soft
-- ===========================================================================

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
    IF COALESCE(reve_private.current_app_role(), '') = 'owner' THEN
      RETURN;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
  END IF;
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
    IF COALESCE(reve_private.current_app_role(), '') = 'owner' THEN
      RETURN;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
  END IF;
END;
$$;

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
    IF COALESCE(reve_private.current_app_role(), '') = 'owner' THEN
      RETURN;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_STUDENT_SCHEDULE_COLLISION';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.student_has_operational_lesson_collision_excluding(
  p_student_id uuid,
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
  WHERE l.student_id = p_student_id
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
    IF COALESCE(reve_private.current_app_role(), '') = 'owner' THEN
      RETURN;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_STUDENT_SCHEDULE_COLLISION';
  END IF;
END;
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
  v_is_owner boolean := COALESCE(reve_private.current_app_role(), '') = 'owner';
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
        IF v_is_owner THEN
          CONTINUE;
        END IF;
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
      END IF;
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
  IF COALESCE(reve_private.current_app_role(), '') = 'owner' THEN
    RETURN;
  END IF;

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

-- ===========================================================================
-- 2. Lesson generation / finalize — Owner may overlap exact teacher times
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.generate_pass_lessons(
  p_pass_id uuid,
  p_student_id uuid,
  p_course_id uuid,
  p_boundary timestamptz,
  p_lesson_count integer,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text
)
RETURNS TABLE (
  lessons_created integer,
  first_lesson_at timestamptz,
  last_lesson_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cursor timestamptz := p_boundary;
  v_seq integer := 0;
  v_created integer := 0;
  v_first timestamptz;
  v_last timestamptz;
  v_best_at timestamptz;
  v_best_slot_id uuid;
  v_best_teacher uuid;
  v_best_order integer;
  r record;
  v_cand timestamptz;
  v_allow_overlap boolean := COALESCE(p_actor_role, '') = 'owner';
BEGIN
  IF p_lesson_count <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_LESSON_COUNT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p_pass_id AND ss.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  WHILE v_created < p_lesson_count LOOP
    v_best_at := NULL;
    v_best_slot_id := NULL;
    v_best_teacher := NULL;
    v_best_order := NULL;

    FOR r IN
      SELECT ss.id, ss.teacher_id, ss.weekday, ss.local_start_time, ss.slot_order
      FROM public.schedule_slots AS ss
      WHERE ss.pass_id = p_pass_id AND ss.is_active = true
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
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_GENERATION_FAILED';
    END IF;

    IF (NOT v_allow_overlap)
      AND reve_private.teacher_has_schedule_collision(v_best_teacher, v_best_at, NULL) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
    END IF;

    v_seq := v_seq + 1;
    INSERT INTO public.lessons (
      pass_id, student_id, course_id, assigned_teacher_id,
      schedule_slot_id, sequence_number, scheduled_at, status
    ) VALUES (
      p_pass_id, p_student_id, p_course_id, v_best_teacher,
      v_best_slot_id, v_seq, v_best_at, 'scheduled'
    );

    v_created := v_created + 1;
    v_first := COALESCE(v_first, v_best_at);
    v_last := v_best_at;
    v_cursor := v_best_at;
  END LOOP;

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'pass.lessons_generated',
    'passes',
    p_pass_id,
    NULL,
    jsonb_build_object(
      'lessons_created', v_created,
      'first_lesson_at', v_first,
      'last_lesson_at', v_last,
      'owner_overlap_allowed', v_allow_overlap
    ),
    NULL,
    p_correlation_id
  );

  lessons_created := v_created;
  first_lesson_at := v_first;
  last_lesson_at := v_last;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.finalize_pass_lesson_schedules(
  p_pass_id uuid,
  p_boundary timestamptz,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text
)
RETURNS TABLE (
  lessons_scheduled integer,
  first_lesson_at timestamptz,
  last_lesson_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_registered integer;
  v_existing integer;
  v_scheduled integer;
  v_cursor timestamptz := p_boundary;
  v_seq integer := 0;
  v_lesson_id uuid;
  v_best_at timestamptz;
  v_best_slot_id uuid;
  v_best_teacher uuid;
  v_best_order integer;
  r record;
  v_cand timestamptz;
  v_first timestamptz;
  v_last timestamptz;
  v_allow_overlap boolean := COALESCE(p_actor_role, '') = 'owner';
BEGIN
  SELECT p.registered_lesson_count_snapshot
  INTO v_registered
  FROM public.passes AS p
  WHERE p.id = p_pass_id
  FOR UPDATE;

  SELECT count(*)::integer,
         count(l.scheduled_at)::integer
  INTO v_existing, v_scheduled
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id;

  PERFORM 1
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass_id
  FOR UPDATE;

  IF v_existing <> v_registered THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
  END IF;

  IF v_scheduled = v_existing THEN
    SELECT min(l.scheduled_at), max(l.scheduled_at)
    INTO v_first, v_last
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id;

    lessons_scheduled := v_existing;
    first_lesson_at := v_first;
    last_lesson_at := v_last;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_scheduled > 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p_pass_id AND ss.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  WHILE v_seq < v_registered LOOP
    v_seq := v_seq + 1;

    SELECT l.id
    INTO v_lesson_id
    FROM public.lessons AS l
    WHERE l.pass_id = p_pass_id
      AND l.sequence_number = v_seq
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
    END IF;

    v_best_at := NULL;
    v_best_slot_id := NULL;
    v_best_teacher := NULL;
    v_best_order := NULL;

    FOR r IN
      SELECT ss.id, ss.teacher_id, ss.weekday, ss.local_start_time, ss.slot_order
      FROM public.schedule_slots AS ss
      WHERE ss.pass_id = p_pass_id AND ss.is_active = true
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
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_GENERATION_FAILED';
    END IF;

    IF (NOT v_allow_overlap)
      AND reve_private.teacher_has_schedule_collision(v_best_teacher, v_best_at, v_lesson_id) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
    END IF;

    UPDATE public.lessons AS l
    SET
      scheduled_at = v_best_at,
      schedule_slot_id = v_best_slot_id,
      assigned_teacher_id = v_best_teacher
    WHERE l.id = v_lesson_id;

    v_first := COALESCE(v_first, v_best_at);
    v_last := v_best_at;
    v_cursor := v_best_at;
  END LOOP;

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'pass.lessons_scheduled',
    'passes',
    p_pass_id,
    jsonb_build_object('scheduled_at_pending', true),
    jsonb_build_object(
      'lessons_scheduled', v_registered,
      'first_lesson_at', v_first,
      'last_lesson_at', v_last,
      'owner_overlap_allowed', v_allow_overlap
    ),
    NULL,
    p_correlation_id
  );

  lessons_scheduled := v_registered;
  first_lesson_at := v_first;
  last_lesson_at := v_last;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- 3. Fixed-schedule replace — Owner auto-allows recurring overlap (warning-only)
-- ===========================================================================

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
    -- Owner: warning-only. Persist overlapping fixed schedules.
    IF v_actor_role = 'owner' THEN
      v_override := true;
    ELSIF NOT v_override THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
    ELSE
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
        'owner_warning_only', true,
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

-- ===========================================================================
-- 4. Enrollment-time slot collision preview (Owner soft warning)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_preview_schedule_slot_collisions(
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
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM reve_private.assert_active_owner_caller();

  RETURN QUERY
  SELECT *
  FROM reve_private.list_recurring_schedule_collisions(
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'active',
    p_schedule_slots
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reve_owner_preview_schedule_slot_collisions(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_preview_schedule_slot_collisions(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_preview_schedule_slot_collisions(jsonb)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.reve_owner_preview_schedule_slot_collisions IS
  'Owner-only soft-warning preview of recurring slot collisions before enrollment/schedule save.';

COMMENT ON FUNCTION public.reve_owner_replace_pass_schedule_slots IS
  'Owner-only replace active schedule slots; Owner overlaps are warning-only and persist with audit.';

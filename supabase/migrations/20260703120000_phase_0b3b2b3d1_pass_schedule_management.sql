-- REVE ACADEMY OS Phase 0B-3B-2B-3D-1 — pass schedule slot replacement (owner-only)
-- Deactivate prior active slots, insert new active set; no lesson row mutation in this phase

-- ===========================================================================
-- Internal helpers — recurring overlap and collision detection
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.recurring_slot_times_overlap(
  p_start time,
  p_duration_minutes integer,
  p_other_start time,
  p_other_duration_minutes integer
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT
    (timestamp '2000-01-01' + p_start)
    < (timestamp '2000-01-01' + p_other_start + (p_other_duration_minutes * interval '1 minute'))
    AND
    (timestamp '2000-01-01' + p_other_start)
    < (timestamp '2000-01-01' + p_start + (p_duration_minutes * interval '1 minute'));
$$;

CREATE OR REPLACE FUNCTION reve_private.active_pass_schedule_fingerprint(p_pass_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'teacher_id', ss.teacher_id::text,
          'weekday', ss.weekday,
          'local_time', to_char(ss.local_start_time, 'HH24:MI:SS'),
          'duration_minutes', ss.duration_minutes,
          'slot_order', ss.slot_order
        )
        ORDER BY
          ss.slot_order,
          ss.weekday,
          to_char(ss.local_start_time, 'HH24:MI:SS'),
          ss.teacher_id::text
      )::text
      FROM public.schedule_slots AS ss
      WHERE ss.pass_id = p_pass_id
        AND ss.is_active = true
    ),
    '[]'
  );
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
DECLARE
  r_proposed record;
  r_other record;
BEGIN
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
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
      END IF;
    END LOOP;
  END LOOP;

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
        ss.teacher_id,
        ss.weekday,
        ss.local_start_time,
        ss.duration_minutes,
        p.status AS pass_status,
        p.student_id,
        p.course_id
      FROM public.schedule_slots AS ss
      INNER JOIN public.passes AS p ON p.id = ss.pass_id
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

      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SCHEDULE_COLLISION';
    END LOOP;
  END LOOP;
END;
$$;

-- ===========================================================================
-- Public RPC — replace active schedule slots for a pass
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_replace_pass_schedule_slots(
  p_pass_id uuid,
  p_expected_pass_updated_at timestamptz,
  p_schedule_slots jsonb,
  p_reason text
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

  v_effective_from := (now() AT TIME ZONE 'Asia/Seoul')::date;

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
    jsonb_build_object('schedule_fingerprint', v_previous_fingerprint),
    jsonb_build_object('schedule_fingerprint', v_new_fingerprint),
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

-- ===========================================================================
-- Security grants
-- ===========================================================================

REVOKE ALL ON FUNCTION reve_private.recurring_slot_times_overlap(time, integer, time, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.active_pass_schedule_fingerprint(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.assert_recurring_schedule_no_collision(uuid, uuid, uuid, text, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_replace_pass_schedule_slots(
  uuid, timestamptz, jsonb, text
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
      'recurring_slot_times_overlap',
      'active_pass_schedule_fingerprint',
      'assert_recurring_schedule_no_collision'
    ))
    OR (n.nspname = 'public' AND p.proname = 'reve_owner_replace_pass_schedule_slots')
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.reve_owner_replace_pass_schedule_slots IS
  'Phase 0B-3B-2B-3D-1 owner-only pass schedule replacement: deactivate prior active slots, insert new set, audit; no lesson mutation.';

-- REVE ACADEMY OS Phase 0B-3B-2B-3C — initial enrollment (payment + pass + schedule + lessons)
-- Owner-only RPC; first pass for student+course with owner-defined schedule slots

-- ===========================================================================
-- Internal helpers — schedule validation and fingerprinting
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.validate_initial_enrollment_schedule(
  p_schedule_slots jsonb,
  p_weekly_frequency integer
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_len integer;
  r record;
  v_teacher_id uuid;
  v_weekday integer;
  v_duration integer;
  v_slot_order integer;
  v_local_time text;
BEGIN
  IF p_weekly_frequency IS NULL OR p_weekly_frequency <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
  END IF;

  IF p_schedule_slots IS NULL OR jsonb_typeof(p_schedule_slots) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
  END IF;

  v_len := jsonb_array_length(p_schedule_slots);

  IF v_len = 0 OR v_len <> p_weekly_frequency THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
  END IF;

  FOR r IN
    SELECT elem, ordinality AS idx
    FROM jsonb_array_elements(p_schedule_slots) WITH ORDINALITY AS t(elem, ordinality)
  LOOP
    IF jsonb_typeof(r.elem) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;

    IF (r.elem - 'teacher_id' - 'weekday' - 'local_time' - 'duration_minutes' - 'slot_order') <> '{}'::jsonb THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;

    IF NOT (r.elem ? 'teacher_id'
      AND r.elem ? 'weekday'
      AND r.elem ? 'local_time'
      AND r.elem ? 'duration_minutes'
      AND r.elem ? 'slot_order') THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;

    IF jsonb_typeof(r.elem->'teacher_id') <> 'string'
      OR jsonb_typeof(r.elem->'weekday') <> 'number'
      OR jsonb_typeof(r.elem->'local_time') <> 'string'
      OR jsonb_typeof(r.elem->'duration_minutes') <> 'number'
      OR jsonb_typeof(r.elem->'slot_order') <> 'number' THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;

    BEGIN
      v_teacher_id := (r.elem->>'teacher_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END;

    v_weekday := (r.elem->>'weekday')::integer;
    v_duration := (r.elem->>'duration_minutes')::integer;
    v_slot_order := (r.elem->>'slot_order')::integer;
    v_local_time := r.elem->>'local_time';

    IF v_weekday < 0 OR v_weekday > 6 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;

    IF v_duration IS NULL OR v_duration <= 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;

    IF v_slot_order IS NULL OR v_slot_order < 1 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;

    BEGIN
      PERFORM (v_local_time::time);
    EXCEPTION
      WHEN invalid_datetime_format THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END;

    IF NOT EXISTS (
      SELECT 1
      FROM public.teachers AS t
      WHERE t.id = v_teacher_id
        AND t.is_active = true
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
    END IF;
  END LOOP;

  IF (
    SELECT count(DISTINCT (elem->>'slot_order')::integer)
    FROM jsonb_array_elements(p_schedule_slots) AS elem
  ) <> v_len THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
  END IF;

  IF (
    SELECT count(DISTINCT (
      (elem->>'weekday')::integer,
      elem->>'local_time',
      elem->>'teacher_id'
    ))
    FROM jsonb_array_elements(p_schedule_slots) AS elem
  ) <> v_len THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.initial_schedule_fingerprint(p_schedule_slots jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'teacher_id', elem->>'teacher_id',
          'weekday', (elem->>'weekday')::integer,
          'local_time', to_char((elem->>'local_time')::time, 'HH24:MI:SS'),
          'duration_minutes', (elem->>'duration_minutes')::integer,
          'slot_order', (elem->>'slot_order')::integer
        )
        ORDER BY
          (elem->>'slot_order')::integer,
          (elem->>'weekday')::integer,
          to_char((elem->>'local_time')::time, 'HH24:MI:SS'),
          elem->>'teacher_id'
      )::text
      FROM jsonb_array_elements(p_schedule_slots) AS elem
    ),
    '[]'
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.pass_schedule_matches_fingerprint(
  p_pass_id uuid,
  p_schedule_slots jsonb
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT reve_private.initial_schedule_fingerprint(p_schedule_slots) = COALESCE(
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

CREATE OR REPLACE FUNCTION reve_private.create_initial_schedule_slots(
  p_pass_id uuid,
  p_effective_from date,
  p_schedule_slots jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  INSERT INTO public.schedule_slots (
    pass_id,
    teacher_id,
    weekday,
    local_start_time,
    duration_minutes,
    slot_order,
    is_active,
    effective_from
  )
  SELECT
    p_pass_id,
    (elem->>'teacher_id')::uuid,
    (elem->>'weekday')::smallint,
    (elem->>'local_time')::time,
    (elem->>'duration_minutes')::integer,
    (elem->>'slot_order')::integer,
    true,
    p_effective_from
  FROM jsonb_array_elements(p_schedule_slots) AS elem;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ===========================================================================
-- Public RPC — initial enrollment
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_create_initial_enrollment(
  p_student_id uuid,
  p_course_product_id uuid,
  p_schedule_start_date date,
  p_schedule_slots jsonb,
  p_paid_amount_krw integer,
  p_payment_method text,
  p_paid_at timestamptz,
  p_idempotency_key text,
  p_owner_reason text DEFAULT NULL
)
RETURNS TABLE (
  payment_id uuid,
  payment_status text,
  payment_updated_at timestamptz,
  pass_id uuid,
  pass_public_code text,
  pass_sequence_number integer,
  pass_status text,
  registered_lesson_count integer,
  schedule_slots_created integer,
  lesson_rows_created integer,
  first_lesson_at timestamptz,
  last_lesson_at timestamptz,
  sms_notification_status text,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_idempotency_key text;
  v_student public.students%ROWTYPE;
  v_product public.course_products%ROWTYPE;
  v_course public.courses%ROWTYPE;
  v_existing_payment public.payments%ROWTYPE;
  v_correlation_id uuid := gen_random_uuid();
  v_creation_reason text;
  v_pass_code text;
  v_registered integer;
  v_new_pass_id uuid;
  v_new_payment_id uuid;
  v_slots_created integer;
  v_boundary timestamptz;
  v_gen record;
  v_sms_id uuid;
  v_pass_new jsonb;
  v_payment_new jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_idempotency_key := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');

  IF v_idempotency_key IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
  END IF;

  IF p_payment_method IS NULL
    OR btrim(p_payment_method) = ''
    OR p_payment_method NOT IN ('cash', 'bank_transfer', 'card', 'other') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_PAYMENT_METHOD';
  END IF;

  IF p_paid_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  IF p_paid_amount_krw IS NULL OR p_paid_amount_krw < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  IF p_schedule_start_date IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_SCHEDULE';
  END IF;

  SELECT *
  INTO v_product
  FROM public.course_products AS cp
  WHERE cp.id = p_course_product_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PRODUCT_NOT_FOUND';
  END IF;

  IF NOT v_product.is_active THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ENTITY_INACTIVE';
  END IF;

  SELECT *
  INTO v_course
  FROM public.courses AS c
  WHERE c.id = v_product.course_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_NOT_FOUND';
  END IF;

  IF NOT v_course.is_active THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ENTITY_INACTIVE';
  END IF;

  SELECT *
  INTO v_student
  FROM public.students AS s
  WHERE s.id = p_student_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_student.operational_status <> 'active' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ENTITY_INACTIVE';
  END IF;

  IF p_paid_amount_krw <> v_product.default_tuition_krw THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  SELECT *
  INTO v_existing_payment
  FROM public.payments AS pay
  WHERE pay.idempotency_key = v_idempotency_key;

  IF FOUND THEN
    IF v_existing_payment.status = 'completed'
      AND v_existing_payment.renewed_pass_id IS NOT NULL THEN
      IF v_existing_payment.student_id IS DISTINCT FROM p_student_id
        OR v_existing_payment.course_id IS DISTINCT FROM v_product.course_id
        OR v_existing_payment.course_product_id IS DISTINCT FROM p_course_product_id
        OR v_existing_payment.paid_amount_krw IS DISTINCT FROM p_paid_amount_krw
        OR v_existing_payment.payment_method IS DISTINCT FROM p_payment_method THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
      END IF;

      IF NOT reve_private.pass_schedule_matches_fingerprint(
        v_existing_payment.renewed_pass_id,
        p_schedule_slots
      ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.schedule_slots AS ss
        WHERE ss.pass_id = v_existing_payment.renewed_pass_id
          AND ss.is_active = true
          AND ss.effective_from IS DISTINCT FROM p_schedule_start_date
      ) OR NOT EXISTS (
        SELECT 1
        FROM public.schedule_slots AS ss
        WHERE ss.pass_id = v_existing_payment.renewed_pass_id
          AND ss.is_active = true
      ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
      END IF;

      payment_id := v_existing_payment.id;
      payment_status := v_existing_payment.status;
      payment_updated_at := v_existing_payment.updated_at;
      pass_id := v_existing_payment.renewed_pass_id;

      SELECT
        p.pass_code,
        p.sequence_number,
        p.status,
        p.registered_lesson_count_snapshot
      INTO
        pass_public_code,
        pass_sequence_number,
        pass_status,
        registered_lesson_count
      FROM public.passes AS p
      WHERE p.id = v_existing_payment.renewed_pass_id;

      SELECT count(*)::integer
      INTO schedule_slots_created
      FROM public.schedule_slots AS ss
      WHERE ss.pass_id = v_existing_payment.renewed_pass_id
        AND ss.is_active = true;

      SELECT count(*)::integer
      INTO lesson_rows_created
      FROM public.lessons AS l
      WHERE l.pass_id = v_existing_payment.renewed_pass_id;

      SELECT min(l.scheduled_at), max(l.scheduled_at)
      INTO first_lesson_at, last_lesson_at
      FROM public.lessons AS l
      WHERE l.pass_id = v_existing_payment.renewed_pass_id;

      SELECT sn.status
      INTO sms_notification_status
      FROM public.sms_notifications AS sn
      WHERE sn.pass_id = v_existing_payment.renewed_pass_id
      ORDER BY sn.created_at DESC
      LIMIT 1;

      idempotent_replay := true;
      RETURN NEXT;
      RETURN;
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
  END IF;

  PERFORM reve_private.renewal_advisory_lock(p_student_id, v_product.course_id);

  IF EXISTS (
    SELECT 1
    FROM public.passes AS p
    WHERE p.student_id = p_student_id
      AND p.course_id = v_product.course_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NOT_INITIAL_ENROLLMENT';
  END IF;

  PERFORM reve_private.validate_initial_enrollment_schedule(
    p_schedule_slots,
    v_product.weekly_frequency
  );

  v_creation_reason := COALESCE(NULLIF(btrim(COALESCE(p_owner_reason, '')), ''), 'initial_enrollment');
  v_registered := v_product.default_lesson_count;
  v_pass_code := reve_private.build_pass_public_code(
    v_course.course_code,
    v_student.student_code,
    1
  );

  INSERT INTO public.payments AS ins (
    student_id,
    course_id,
    course_product_id,
    paid_amount_krw,
    payment_method,
    status,
    paid_at,
    idempotency_key,
    processed_at,
    created_by_profile_id
  ) VALUES (
    p_student_id,
    v_product.course_id,
    p_course_product_id,
    p_paid_amount_krw,
    p_payment_method,
    'completed',
    p_paid_at,
    v_idempotency_key,
    now(),
    v_actor
  )
  RETURNING ins.id, ins.status, ins.updated_at
  INTO v_new_payment_id, payment_status, payment_updated_at;

  INSERT INTO public.passes (
    pass_code,
    student_id,
    course_id,
    course_product_id,
    sequence_number,
    status,
    registered_lesson_count_snapshot,
    weekly_frequency_snapshot,
    product_name_snapshot,
    tuition_amount_krw_snapshot,
    start_date,
    activated_at,
    creation_reason
  ) VALUES (
    v_pass_code,
    p_student_id,
    v_product.course_id,
    p_course_product_id,
    1,
    'active',
    v_registered,
    v_product.weekly_frequency,
    v_product.product_name,
    v_product.default_tuition_krw,
    p_schedule_start_date,
    p_paid_at,
    v_creation_reason
  )
  RETURNING id INTO v_new_pass_id;

  v_pass_new := jsonb_build_object(
    'pass_code', v_pass_code,
    'status', 'active',
    'sequence_number', 1,
    'registered_lesson_count_snapshot', v_registered
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'pass.created',
    'passes',
    v_new_pass_id,
    NULL,
    v_pass_new,
    v_creation_reason,
    v_correlation_id
  );

  v_slots_created := reve_private.create_initial_schedule_slots(
    v_new_pass_id,
    p_schedule_start_date,
    p_schedule_slots
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'schedule_slots.created',
    'passes',
    v_new_pass_id,
    NULL,
    jsonb_build_object('schedule_slots_created', v_slots_created),
    NULL,
    v_correlation_id
  );

  -- Start boundary: owner-selected Seoul calendar date at local midnight (inclusive lower bound).
  -- next_slot_occurrence_after uses strict '>' so the first lesson may fall on this date when slot time is after midnight.
  v_boundary := (p_schedule_start_date::timestamp AT TIME ZONE 'Asia/Seoul');

  SELECT g.lessons_created, g.first_lesson_at, g.last_lesson_at
  INTO v_gen
  FROM reve_private.generate_pass_lessons(
    v_new_pass_id,
    p_student_id,
    v_product.course_id,
    v_boundary,
    v_registered,
    v_correlation_id,
    v_actor,
    v_actor_role
  ) AS g;

  UPDATE public.passes AS p
  SET start_date = (v_gen.first_lesson_at AT TIME ZONE 'Asia/Seoul')::date
  WHERE p.id = v_new_pass_id;

  UPDATE public.payments AS pay
  SET renewed_pass_id = v_new_pass_id
  WHERE pay.id = v_new_payment_id
  RETURNING pay.updated_at INTO payment_updated_at;

  v_payment_new := jsonb_build_object(
    'status', 'completed',
    'renewed_pass_id', v_new_pass_id,
    'payment_method', p_payment_method,
    'paid_at', p_paid_at
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'payment.completed',
    'payments',
    v_new_payment_id,
    NULL,
    v_payment_new,
    NULL,
    v_correlation_id
  );

  v_sms_id := reve_private.initialize_pass_sms_notification(
    v_new_pass_id,
    p_student_id,
    v_registered,
    v_correlation_id,
    v_actor,
    v_actor_role,
    false
  );

  SELECT sn.status
  INTO sms_notification_status
  FROM public.sms_notifications AS sn
  WHERE sn.id = v_sms_id;

  payment_id := v_new_payment_id;
  pass_id := v_new_pass_id;
  pass_public_code := v_pass_code;
  pass_sequence_number := 1;
  pass_status := 'active';
  registered_lesson_count := v_registered;
  schedule_slots_created := v_slots_created;
  lesson_rows_created := v_gen.lessons_created;
  first_lesson_at := v_gen.first_lesson_at;
  last_lesson_at := v_gen.last_lesson_at;
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Security grants
-- ===========================================================================

REVOKE ALL ON FUNCTION reve_private.validate_initial_enrollment_schedule(jsonb, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.initial_schedule_fingerprint(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.pass_schedule_matches_fingerprint(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.create_initial_schedule_slots(uuid, date, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reve_owner_create_initial_enrollment(
  uuid, uuid, date, jsonb, integer, text, timestamptz, text, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_create_initial_enrollment(
  uuid, uuid, date, jsonb, integer, text, timestamptz, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_create_initial_enrollment(
  uuid, uuid, date, jsonb, integer, text, timestamptz, text, text
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
      'validate_initial_enrollment_schedule',
      'initial_schedule_fingerprint',
      'pass_schedule_matches_fingerprint',
      'create_initial_schedule_slots'
    ))
    OR (n.nspname = 'public' AND p.proname = 'reve_owner_create_initial_enrollment')
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.reve_owner_create_initial_enrollment IS
  'Phase 0B-3B-2B-3C owner-only initial enrollment: completed payment, sequence-1 active pass, schedule slots, and lesson generation.';

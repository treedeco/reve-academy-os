-- REVE ACADEMY OS Phase 0B-3B-2B-2 — payment completion, pass renewal, reserved activation
-- OD-14~16 provisional; lessons.scheduled_at NOT NULL → reserved pass defers lesson INSERT until activation

-- ===========================================================================
-- Internal helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.renewal_advisory_lock(
  p_student_id uuid,
  p_course_id uuid
)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $$
  SELECT pg_advisory_xact_lock(
    hashtextextended(p_student_id::text || ':' || p_course_id::text, 0)
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.build_pass_public_code(
  p_course_code text,
  p_student_code text,
  p_sequence_number integer
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT upper(left(p_course_code, 1))
    || '-'
    || p_student_code
    || '-'
    || lpad(p_sequence_number::text, 3, '0');
$$;

CREATE OR REPLACE FUNCTION reve_private.next_pass_sequence(
  p_student_id uuid,
  p_course_id uuid
)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(max(p.sequence_number), 0) + 1
  FROM public.passes AS p
  WHERE p.student_id = p_student_id
    AND p.course_id = p_course_id;
$$;

CREATE OR REPLACE FUNCTION reve_private.find_schedule_source_pass_id(
  p_student_id uuid,
  p_course_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT p.id
  FROM public.passes AS p
  WHERE p.student_id = p_student_id
    AND p.course_id = p_course_id
    AND p.status = 'active'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION reve_private.find_schedule_source_pass_id_fallback(
  p_student_id uuid,
  p_course_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    reve_private.find_schedule_source_pass_id(p_student_id, p_course_id),
    (
      SELECT p.id
      FROM public.passes AS p
      WHERE p.student_id = p_student_id
        AND p.course_id = p_course_id
        AND p.status = 'completed'
      ORDER BY p.sequence_number DESC
      LIMIT 1
    )
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.next_slot_occurrence_after(
  p_after timestamptz,
  p_weekday smallint,
  p_local_start time
)
RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_local timestamp;
  v_date date;
  v_dow integer;
  v_days integer;
  v_target date;
  v_candidate timestamptz;
BEGIN
  v_local := p_after AT TIME ZONE 'Asia/Seoul';
  v_date := v_local::date;
  v_dow := extract(dow FROM v_local)::integer;
  v_days := (p_weekday - v_dow + 7) % 7;
  v_target := v_date + v_days;

  LOOP
    v_candidate := (v_target + p_local_start) AT TIME ZONE 'Asia/Seoul';
    IF v_candidate > p_after THEN
      RETURN v_candidate;
    END IF;
    v_target := v_target + 7;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_has_schedule_collision(
  p_teacher_id uuid,
  p_scheduled_at timestamptz,
  p_exclude_lesson_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.assigned_teacher_id = p_teacher_id
      AND l.scheduled_at = p_scheduled_at
      AND (p_exclude_lesson_id IS NULL OR l.id <> p_exclude_lesson_id)
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.copy_schedule_slots_from_pass(
  p_source_pass_id uuid,
  p_target_pass_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count integer := 0;
  r record;
BEGIN
  FOR r IN
    SELECT ss.*
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p_source_pass_id
      AND ss.is_active = true
      AND (ss.effective_until IS NULL OR ss.effective_until >= (now() AT TIME ZONE 'Asia/Seoul')::date)
    ORDER BY ss.slot_order, ss.weekday, ss.local_start_time
  LOOP
    INSERT INTO public.schedule_slots (
      pass_id, teacher_id, weekday, local_start_time,
      duration_minutes, slot_order, is_active, effective_from
    ) VALUES (
      p_target_pass_id,
      r.teacher_id,
      r.weekday,
      r.local_start_time,
      r.duration_minutes,
      r.slot_order,
      true,
      (now() AT TIME ZONE 'Asia/Seoul')::date
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.initialize_pass_sms_notification(
  p_pass_id uuid,
  p_student_id uuid,
  p_registered integer,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text,
  p_is_reserved boolean
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_sms_id uuid;
  v_body text;
  v_status text := 'normal';
BEGIN
  v_body := format('회차권 갱신 안내: 잔여 %s회', p_registered);

  INSERT INTO public.sms_notifications (
    student_id, pass_id, notification_type, status, message_body_snapshot
  ) VALUES (
    p_student_id,
    p_pass_id,
    'renewal_reminder',
    v_status,
    v_body
  )
  RETURNING id INTO v_sms_id;

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'sms_notification.initialized',
    'sms_notifications',
    v_sms_id,
    NULL,
    jsonb_build_object('status', v_status, 'message_body_snapshot', v_body),
    NULL,
    p_correlation_id
  );

  RETURN v_sms_id;
END;
$$;

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

    IF reve_private.teacher_has_schedule_collision(v_best_teacher, v_best_at, NULL) THEN
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
      'last_lesson_at', v_last
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

CREATE OR REPLACE FUNCTION reve_private.resolve_pass_completion_boundary(
  p_pass_id uuid
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT p.completed_at FROM public.passes AS p WHERE p.id = p_pass_id),
    (
      SELECT max(COALESCE(l.actual_end_at, l.actual_start_at, l.scheduled_at))
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND reve_private.lesson_status_is_deductible(l.status)
    ),
    now()
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.activate_reserved_pass_internal(
  p_reserved_pass_id uuid,
  p_previous_pass_id uuid,
  p_boundary timestamptz,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text,
  p_reason text,
  p_automatic boolean
)
RETURNS TABLE (
  pass_id uuid,
  pass_public_code text,
  previous_status text,
  new_status text,
  pass_updated_at timestamptz,
  activated_at timestamptz,
  lessons_scheduled integer,
  first_lesson_at timestamptz,
  last_lesson_at timestamptz,
  previous_pass_id uuid,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pass public.passes%ROWTYPE;
  v_previous jsonb;
  v_new jsonb;
  v_existing_lessons integer;
  v_registered integer;
  v_boundary timestamptz;
  v_gen record;
  v_activated timestamptz;
BEGIN
  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_reserved_pass_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_pass.status = 'active' THEN
    SELECT count(*)::integer
    INTO v_existing_lessons
    FROM public.lessons AS l
    WHERE l.pass_id = p_reserved_pass_id;

    pass_id := v_pass.id;
    pass_public_code := v_pass.pass_code;
    previous_status := 'active';
    new_status := 'active';
    pass_updated_at := v_pass.updated_at;
    activated_at := v_pass.activated_at;
    lessons_scheduled := v_existing_lessons;
    first_lesson_at := (
      SELECT min(l.scheduled_at) FROM public.lessons AS l WHERE l.pass_id = v_pass.id
    );
    last_lesson_at := (
      SELECT max(l.scheduled_at) FROM public.lessons AS l WHERE l.pass_id = v_pass.id
    );
    previous_pass_id := p_previous_pass_id;
    idempotent_replay := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_pass.status <> 'reserved' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.passes AS ap
    WHERE ap.student_id = v_pass.student_id
      AND ap.course_id = v_pass.course_id
      AND ap.status = 'active'
      AND ap.id <> p_reserved_pass_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
  END IF;

  IF p_previous_pass_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.passes AS pp
      WHERE pp.id = p_previous_pass_id
        AND pp.student_id = v_pass.student_id
        AND pp.course_id = v_pass.course_id
        AND pp.status = 'completed'
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
    END IF;
  END IF;

  v_registered := v_pass.registered_lesson_count_snapshot;
  v_boundary := COALESCE(
    p_boundary,
    reve_private.resolve_pass_completion_boundary(p_previous_pass_id)
  );

  SELECT count(*)::integer
  INTO v_existing_lessons
  FROM public.lessons AS l
  WHERE l.pass_id = p_reserved_pass_id;

  IF v_existing_lessons = 0 THEN
    SELECT g.lessons_created, g.first_lesson_at, g.last_lesson_at
    INTO v_gen
    FROM reve_private.generate_pass_lessons(
      p_reserved_pass_id,
      v_pass.student_id,
      v_pass.course_id,
      v_boundary,
      v_registered,
      p_correlation_id,
      p_actor_profile_id,
      p_actor_role
    ) AS g;
    v_existing_lessons := v_gen.lessons_created;
  ELSIF v_existing_lessons <> v_registered THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
  END IF;

  v_activated := COALESCE(v_pass.activated_at, now());
  v_previous := jsonb_build_object(
    'status', v_pass.status,
    'activated_at', v_pass.activated_at
  );

  UPDATE public.passes AS p
  SET
    status = 'active',
    activated_at = v_activated,
    start_date = COALESCE(
      (SELECT (min(l.scheduled_at) AT TIME ZONE 'Asia/Seoul')::date
       FROM public.lessons AS l WHERE l.pass_id = p_reserved_pass_id),
      p.start_date
    )
  WHERE p.id = p_reserved_pass_id;

  v_new := jsonb_build_object(
    'status', 'active',
    'activated_at', v_activated,
    'automatic', p_automatic
  );

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    CASE WHEN p_automatic THEN 'pass.reserved_auto_activated' ELSE 'pass.reserved_activated' END,
    'passes',
    p_reserved_pass_id,
    v_previous,
    v_new,
    p_reason,
    p_correlation_id
  );

  PERFORM reve_private.synchronize_sms_notification(
    p_reserved_pass_id,
    v_pass.student_id,
    v_registered,
    p_correlation_id,
    p_actor_profile_id,
    p_actor_role
  );

  pass_id := p_reserved_pass_id;
  pass_public_code := v_pass.pass_code;
  previous_status := 'reserved';
  new_status := 'active';
  pass_updated_at := (SELECT p.updated_at FROM public.passes AS p WHERE p.id = p_reserved_pass_id);
  activated_at := v_activated;
  lessons_scheduled := v_existing_lessons;
  first_lesson_at := (
    SELECT min(l.scheduled_at) FROM public.lessons AS l WHERE l.pass_id = p_reserved_pass_id
  );
  last_lesson_at := (
    SELECT max(l.scheduled_at) FROM public.lessons AS l WHERE l.pass_id = p_reserved_pass_id
  );
  previous_pass_id := p_previous_pass_id;
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.complete_payment_and_renew_pass_internal(
  p_payment_id uuid,
  p_expected_payment_updated_at timestamptz,
  p_paid_amount_krw integer,
  p_payment_method text,
  p_paid_at timestamptz,
  p_idempotency_key text,
  p_actor_profile_id uuid,
  p_actor_role text
)
RETURNS TABLE (
  payment_id uuid,
  payment_status text,
  payment_updated_at timestamptz,
  new_pass_id uuid,
  new_pass_public_code text,
  new_pass_sequence integer,
  new_pass_status text,
  registered_lesson_count integer,
  lesson_rows_created integer,
  schedule_slots_copied integer,
  activation_required boolean,
  activated_at timestamptz,
  first_lesson_at timestamptz,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_student public.students%ROWTYPE;
  v_course public.courses%ROWTYPE;
  v_product public.course_products%ROWTYPE;
  v_correlation_id uuid := gen_random_uuid();
  v_active_pass public.passes%ROWTYPE;
  v_source_pass_id uuid;
  v_slots_copied integer;
  v_new_pass_id uuid;
  v_sequence integer;
  v_pass_code text;
  v_new_status text;
  v_previous_pass_id uuid;
  v_registered integer;
  v_lessons_created integer := 0;
  v_first_lesson timestamptz;
  v_activated timestamptz;
  v_remaining integer;
  v_gen record;
  v_pass_previous jsonb;
  v_pass_new jsonb;
  v_payment_previous jsonb;
  v_payment_new jsonb;
BEGIN
  IF NOT reve_private.is_owner() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.payments AS pay
  WHERE pay.id = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_payment.idempotency_key IS DISTINCT FROM p_idempotency_key THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
  END IF;

  IF v_payment.status = 'completed' AND v_payment.renewed_pass_id IS NOT NULL THEN
    IF v_payment.paid_amount_krw IS DISTINCT FROM p_paid_amount_krw
      OR v_payment.payment_method IS DISTINCT FROM p_payment_method THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
    END IF;

    payment_id := v_payment.id;
    payment_status := v_payment.status;
    payment_updated_at := v_payment.updated_at;
    new_pass_id := v_payment.renewed_pass_id;
    SELECT p.pass_code, p.sequence_number, p.status, p.registered_lesson_count_snapshot,
           p.activated_at
    INTO new_pass_public_code, new_pass_sequence, new_pass_status, registered_lesson_count,
         v_activated
    FROM public.passes AS p
    WHERE p.id = v_payment.renewed_pass_id;
    SELECT count(*)::integer INTO lesson_rows_created
    FROM public.lessons AS l WHERE l.pass_id = v_payment.renewed_pass_id;
    SELECT count(*)::integer INTO schedule_slots_copied
    FROM public.schedule_slots AS ss WHERE ss.pass_id = v_payment.renewed_pass_id;
    activation_required := (new_pass_status = 'reserved');
    activated_at := v_activated;
    first_lesson_at := (
      SELECT min(l.scheduled_at) FROM public.lessons AS l WHERE l.pass_id = v_payment.renewed_pass_id
    );
    idempotent_replay := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_payment.status NOT IN ('pending') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
  END IF;

  IF v_payment.updated_at IS DISTINCT FROM p_expected_payment_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF p_paid_amount_krw IS NULL OR p_paid_amount_krw < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  IF p_paid_amount_krw IS DISTINCT FROM v_payment.paid_amount_krw THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  IF p_payment_method IS NULL
    OR btrim(p_payment_method) = ''
    OR p_payment_method NOT IN ('cash', 'bank_transfer', 'card', 'other') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_PAYMENT_METHOD';
  END IF;

  IF p_paid_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
  END IF;

  SELECT * INTO v_student FROM public.students AS s WHERE s.id = v_payment.student_id;
  SELECT * INTO v_course FROM public.courses AS c WHERE c.id = v_payment.course_id;
  SELECT * INTO v_product
  FROM public.course_products AS cp
  WHERE cp.id = v_payment.course_product_id;

  IF v_product.course_id <> v_payment.course_id OR NOT v_product.is_active THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
  END IF;

  IF p_paid_amount_krw <> v_product.default_tuition_krw THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  PERFORM reve_private.renewal_advisory_lock(v_payment.student_id, v_payment.course_id);

  PERFORM 1
  FROM public.passes AS p
  WHERE p.student_id = v_payment.student_id
    AND p.course_id = v_payment.course_id
    AND p.status IN ('active', 'reserved')
  FOR UPDATE;

  SELECT *
  INTO v_active_pass
  FROM public.passes AS p
  WHERE p.student_id = v_payment.student_id
    AND p.course_id = v_payment.course_id
    AND p.status = 'active'
  FOR UPDATE;

  IF FOUND THEN
    SELECT u.remaining_lesson_count
    INTO v_remaining
    FROM reve_private.calculate_pass_usage(v_active_pass.id) AS u;

    IF v_remaining > 0 THEN
      v_new_status := 'reserved';
      v_previous_pass_id := v_active_pass.id;
    ELSIF v_remaining = 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVE_PASS_NOT_COMPLETE';
    ELSE
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_USAGE_EXCEEDED';
    END IF;
  ELSE
    v_new_status := 'active';
    v_previous_pass_id := (
      SELECT p.id
      FROM public.passes AS p
      WHERE p.student_id = v_payment.student_id
        AND p.course_id = v_payment.course_id
        AND p.status = 'completed'
      ORDER BY p.sequence_number DESC
      LIMIT 1
    );
  END IF;

  IF v_new_status = 'reserved' AND EXISTS (
    SELECT 1
    FROM public.passes AS rp
    WHERE rp.student_id = v_payment.student_id
      AND rp.course_id = v_payment.course_id
      AND rp.status = 'reserved'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_RESERVED_EXISTS';
  END IF;

  v_source_pass_id := reve_private.find_schedule_source_pass_id_fallback(
    v_payment.student_id, v_payment.course_id
  );

  IF v_source_pass_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.schedule_slots AS ss
    WHERE ss.pass_id = v_source_pass_id AND ss.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  v_sequence := reve_private.next_pass_sequence(v_payment.student_id, v_payment.course_id);
  v_pass_code := reve_private.build_pass_public_code(
    v_course.course_code, v_student.student_code, v_sequence
  );
  v_registered := v_product.default_lesson_count;

  INSERT INTO public.passes (
    pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, previous_pass_id, creation_reason
  ) VALUES (
    v_pass_code,
    v_payment.student_id,
    v_payment.course_id,
    v_payment.course_product_id,
    v_sequence,
    v_new_status,
    v_registered,
    v_product.weekly_frequency,
    v_product.product_name,
    v_product.default_tuition_krw,
    (p_paid_at AT TIME ZONE 'Asia/Seoul')::date,
    v_previous_pass_id,
    'payment_renewal'
  )
  RETURNING id INTO v_new_pass_id;

  v_pass_new := jsonb_build_object(
    'pass_code', v_pass_code,
    'status', v_new_status,
    'sequence_number', v_sequence,
    'registered_lesson_count_snapshot', v_registered
  );

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'pass.created_by_payment',
    'passes',
    v_new_pass_id,
    NULL,
    v_pass_new,
    NULL,
    v_correlation_id
  );

  v_slots_copied := reve_private.copy_schedule_slots_from_pass(v_source_pass_id, v_new_pass_id);

  IF v_slots_copied = 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'schedule_slots.copied_to_pass',
    'passes',
    v_new_pass_id,
    NULL,
    jsonb_build_object('schedule_slots_copied', v_slots_copied, 'source_pass_id', v_source_pass_id),
    NULL,
    v_correlation_id
  );

  IF v_new_status = 'active' THEN
    v_activated := p_paid_at;
    UPDATE public.passes AS p
    SET activated_at = v_activated
    WHERE p.id = v_new_pass_id;

    SELECT g.lessons_created, g.first_lesson_at
    INTO v_gen
    FROM reve_private.generate_pass_lessons(
      v_new_pass_id,
      v_payment.student_id,
      v_payment.course_id,
      p_paid_at,
      v_registered,
      v_correlation_id,
      p_actor_profile_id,
      p_actor_role
    ) AS g;

    v_lessons_created := v_gen.lessons_created;
    v_first_lesson := v_gen.first_lesson_at;

    UPDATE public.passes AS p
    SET start_date = (v_first_lesson AT TIME ZONE 'Asia/Seoul')::date
    WHERE p.id = v_new_pass_id;
  ELSE
    v_activated := NULL;
    v_first_lesson := NULL;
  END IF;

  PERFORM reve_private.initialize_pass_sms_notification(
    v_new_pass_id,
    v_payment.student_id,
    v_registered,
    v_correlation_id,
    p_actor_profile_id,
    p_actor_role,
    v_new_status = 'reserved'
  );

  v_payment_previous := jsonb_build_object(
    'status', v_payment.status,
    'renewed_pass_id', v_payment.renewed_pass_id,
    'payment_method', v_payment.payment_method,
    'paid_at', v_payment.paid_at
  );

  UPDATE public.payments AS pay
  SET
    status = 'completed',
    payment_method = p_payment_method,
    paid_at = p_paid_at,
    processed_at = now(),
    renewed_pass_id = v_new_pass_id,
    related_pass_id = COALESCE(pay.related_pass_id, v_previous_pass_id)
  WHERE pay.id = p_payment_id
  RETURNING pay.updated_at INTO payment_updated_at;

  v_payment_new := jsonb_build_object(
    'status', 'completed',
    'renewed_pass_id', v_new_pass_id,
    'payment_method', p_payment_method,
    'paid_at', p_paid_at
  );

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'payment.completed',
    'payments',
    p_payment_id,
    v_payment_previous,
    v_payment_new,
    NULL,
    v_correlation_id
  );

  payment_id := p_payment_id;
  payment_status := 'completed';
  new_pass_id := v_new_pass_id;
  new_pass_public_code := v_pass_code;
  new_pass_sequence := v_sequence;
  new_pass_status := v_new_status;
  registered_lesson_count := v_registered;
  lesson_rows_created := v_lessons_created;
  schedule_slots_copied := v_slots_copied;
  activation_required := (v_new_status = 'reserved');
  activated_at := v_activated;
  first_lesson_at := v_first_lesson;
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Extend pass sync: automatic reserved activation (replaces pending flag path)
-- ===========================================================================

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
  v_reserved_id uuid;
  v_boundary timestamptz;
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

    SELECT rp.id
    INTO v_reserved_id
    FROM public.passes AS rp
    WHERE rp.student_id = v_pass.student_id
      AND rp.course_id = v_pass.course_id
      AND rp.status = 'reserved'
    FOR UPDATE;

    IF v_reserved_id IS NOT NULL THEN
      v_boundary := reve_private.resolve_pass_completion_boundary(p_pass_id);
      PERFORM reve_private.activate_reserved_pass_internal(
        v_reserved_id,
        p_pass_id,
        v_boundary,
        p_correlation_id,
        p_actor_profile_id,
        p_actor_role,
        NULL,
        true
      );
      v_pending := false;
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

-- ===========================================================================
-- Public trusted RPCs
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_complete_payment_and_renew_pass(
  p_payment_id uuid,
  p_expected_payment_updated_at timestamptz,
  p_paid_amount_krw integer,
  p_payment_method text,
  p_paid_at timestamptz,
  p_idempotency_key text
)
RETURNS TABLE (
  payment_id uuid,
  payment_status text,
  payment_updated_at timestamptz,
  new_pass_id uuid,
  new_pass_public_code text,
  new_pass_sequence integer,
  new_pass_status text,
  registered_lesson_count integer,
  lesson_rows_created integer,
  schedule_slots_copied integer,
  activation_required boolean,
  activated_at timestamptz,
  first_lesson_at timestamptz,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_profile_id uuid;
  v_role text;
BEGIN
  v_profile_id := auth.uid();
  v_role := reve_private.current_app_role();

  IF v_role IS NULL OR v_profile_id IS NULL OR NOT reve_private.is_owner() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT *
  FROM reve_private.complete_payment_and_renew_pass_internal(
    p_payment_id,
    p_expected_payment_updated_at,
    p_paid_amount_krw,
    p_payment_method,
    p_paid_at,
    p_idempotency_key,
    v_profile_id,
    v_role
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_activate_reserved_pass(
  p_reserved_pass_id uuid,
  p_expected_pass_updated_at timestamptz,
  p_reason text DEFAULT NULL
)
RETURNS TABLE (
  pass_id uuid,
  pass_public_code text,
  previous_status text,
  new_status text,
  pass_updated_at timestamptz,
  activated_at timestamptz,
  lessons_scheduled integer,
  first_lesson_at timestamptz,
  last_lesson_at timestamptz,
  previous_pass_id uuid,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_profile_id uuid;
  v_role text;
  v_pass public.passes%ROWTYPE;
  v_previous_pass_id uuid;
  v_boundary timestamptz;
  v_correlation_id uuid := gen_random_uuid();
BEGIN
  v_profile_id := auth.uid();
  v_role := reve_private.current_app_role();

  IF v_role IS NULL OR v_profile_id IS NULL OR NOT reve_private.is_owner() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_reserved_pass_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_pass.updated_at IS DISTINCT FROM p_expected_pass_updated_at
    AND v_pass.status = 'reserved' THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  v_previous_pass_id := v_pass.previous_pass_id;
  IF v_previous_pass_id IS NULL THEN
    v_previous_pass_id := (
      SELECT p.id
      FROM public.passes AS p
      WHERE p.student_id = v_pass.student_id
        AND p.course_id = v_pass.course_id
        AND p.status = 'completed'
      ORDER BY p.sequence_number DESC
      LIMIT 1
    );
  END IF;

  v_boundary := reve_private.resolve_pass_completion_boundary(v_previous_pass_id);

  RETURN QUERY
  SELECT *
  FROM reve_private.activate_reserved_pass_internal(
    p_reserved_pass_id,
    v_previous_pass_id,
    v_boundary,
    v_correlation_id,
    v_profile_id,
    v_role,
    NULLIF(btrim(COALESCE(p_reason, '')), ''),
    false
  );
END;
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
      'renewal_advisory_lock',
      'build_pass_public_code',
      'next_pass_sequence',
      'find_schedule_source_pass_id',
      'find_schedule_source_pass_id_fallback',
      'next_slot_occurrence_after',
      'teacher_has_schedule_collision',
      'copy_schedule_slots_from_pass',
      'initialize_pass_sms_notification',
      'generate_pass_lessons',
      'resolve_pass_completion_boundary',
      'activate_reserved_pass_internal',
      'complete_payment_and_renew_pass_internal'
    ))
    OR (n.nspname = 'public' AND p.proname IN (
      'reve_complete_payment_and_renew_pass',
      'reve_activate_reserved_pass'
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
        'renewal_advisory_lock',
        'build_pass_public_code',
        'next_pass_sequence',
        'find_schedule_source_pass_id',
        'find_schedule_source_pass_id_fallback',
        'next_slot_occurrence_after',
        'teacher_has_schedule_collision',
        'copy_schedule_slots_from_pass',
        'initialize_pass_sms_notification',
        'generate_pass_lessons',
        'resolve_pass_completion_boundary',
        'activate_reserved_pass_internal',
        'complete_payment_and_renew_pass_internal'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;

  GRANT EXECUTE ON FUNCTION public.reve_complete_payment_and_renew_pass(
    uuid, timestamptz, integer, text, timestamptz, text
  ) TO authenticated, service_role;

  GRANT EXECUTE ON FUNCTION public.reve_activate_reserved_pass(
    uuid, timestamptz, text
  ) TO authenticated, service_role;
END $$;

COMMENT ON FUNCTION public.reve_complete_payment_and_renew_pass IS
  'Phase 0B-3B-2B-2 owner-only idempotent payment completion and pass renewal.';

COMMENT ON FUNCTION public.reve_activate_reserved_pass IS
  'Phase 0B-3B-2B-2 owner-only manual reserved-pass activation (OD-14 provisional).';

-- REVE ACADEMY OS Phase 0B-3B-2B-2A — reserved-pass lesson shells (forward hotfix)
-- Payment completion creates all lesson rows; reserved shells have pending scheduled_at.
-- Activation finalizes scheduled_at on existing rows (no second INSERT set).

-- ===========================================================================
-- 1. Nullable scheduled_at + row-level shell constraint
-- ===========================================================================

ALTER TABLE public.lessons
  ALTER COLUMN scheduled_at DROP NOT NULL;

ALTER TABLE public.lessons
  ADD CONSTRAINT lessons_unscheduled_shell_row_check
    CHECK (
      scheduled_at IS NOT NULL
      OR (
        status = 'scheduled'
        AND actual_start_at IS NULL
        AND actual_end_at IS NULL
      )
    );

-- ===========================================================================
-- 2. Deferred pass/lesson invariant validation
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

  IF v_pass.status IN ('active', 'completed') THEN
    IF EXISTS (
      SELECT 1
      FROM public.lessons AS l
      WHERE l.pass_id = p_pass_id
        AND l.scheduled_at IS NULL
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVE_PASS_UNSCHEDULED_LESSON';
    END IF;
  END IF;

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

CREATE OR REPLACE FUNCTION reve_private.trg_deferred_validate_lessons()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  PERFORM reve_private.validate_pass_lesson_invariants(COALESCE(NEW.pass_id, OLD.pass_id));
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.trg_deferred_validate_pass_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM reve_private.validate_pass_lesson_invariants(NEW.id);
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_lessons_validate_pass_invariants
  AFTER INSERT OR UPDATE OR DELETE ON public.lessons
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION reve_private.trg_deferred_validate_lessons();

CREATE CONSTRAINT TRIGGER trg_passes_validate_lesson_invariants
  AFTER INSERT OR UPDATE OF status ON public.passes
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION reve_private.trg_deferred_validate_pass_status();

-- ===========================================================================
-- 3. Reserved lesson shells (payment completion)
-- Ordinal-to-slot: round-robin by slot_order, weekday, local_start_time.
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.create_pass_lesson_shells(
  p_pass_id uuid,
  p_student_id uuid,
  p_course_id uuid,
  p_lesson_count integer,
  p_correlation_id uuid,
  p_actor_profile_id uuid,
  p_actor_role text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_seq integer := 0;
  v_slot_id uuid;
  v_teacher_id uuid;
  v_slot_count integer;
BEGIN
  IF p_lesson_count <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_LESSON_COUNT';
  END IF;

  SELECT count(*)::integer
  INTO v_slot_count
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass_id
    AND ss.is_active = true;

  IF v_slot_count = 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  WHILE v_seq < p_lesson_count LOOP
    v_seq := v_seq + 1;

    SELECT ss.id, ss.teacher_id
    INTO v_slot_id, v_teacher_id
    FROM (
      SELECT
        s.id,
        s.teacher_id,
        row_number() OVER (
          ORDER BY s.slot_order, s.weekday, s.local_start_time
        ) AS rn,
        count(*) OVER () AS cnt
      FROM public.schedule_slots AS s
      WHERE s.pass_id = p_pass_id
        AND s.is_active = true
    ) AS ss
    WHERE ss.rn = ((v_seq - 1) % ss.cnt) + 1;

    INSERT INTO public.lessons (
      pass_id, student_id, course_id, assigned_teacher_id,
      schedule_slot_id, sequence_number, scheduled_at, status
    ) VALUES (
      p_pass_id, p_student_id, p_course_id, v_teacher_id,
      v_slot_id, v_seq, NULL, 'scheduled'
    );
  END LOOP;

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'pass.lesson_shells_created',
    'passes',
    p_pass_id,
    NULL,
    jsonb_build_object(
      'lesson_shells_created', p_lesson_count,
      'scheduled_at_pending', true
    ),
    NULL,
    p_correlation_id
  );

  RETURN p_lesson_count;
END;
$$;

-- ===========================================================================
-- 4. Finalize schedules on existing lesson rows (activation)
-- ===========================================================================

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

    IF reve_private.teacher_has_schedule_collision(v_best_teacher, v_best_at, v_lesson_id) THEN
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
      'last_lesson_at', v_last
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
-- 5. Payment completion — create shells for reserved passes
-- ===========================================================================

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
  v_active_pass public.passes%ROWTYPE;
  v_correlation_id uuid := gen_random_uuid();
  v_new_pass_id uuid;
  v_source_pass_id uuid;
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
  v_pass_new jsonb;
  v_payment_previous jsonb;
  v_payment_new jsonb;
  v_slots_copied integer;
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
    v_lessons_created := reve_private.create_pass_lesson_shells(
      v_new_pass_id,
      v_payment.student_id,
      v_payment.course_id,
      v_registered,
      v_correlation_id,
      p_actor_profile_id,
      p_actor_role
    );
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
-- 6. Activation — finalize existing shells (no INSERT)
-- ===========================================================================

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
  v_registered integer;
  v_boundary timestamptz;
  v_gen record;
  v_activated timestamptz;
  v_existing_lessons integer;
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

  IF v_existing_lessons = 0 OR v_existing_lessons <> v_registered THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVATION_DENIED';
  END IF;

  SELECT g.lessons_scheduled, g.first_lesson_at, g.last_lesson_at
  INTO v_gen
  FROM reve_private.finalize_pass_lesson_schedules(
    p_reserved_pass_id,
    v_boundary,
    p_correlation_id,
    p_actor_profile_id,
    p_actor_role
  ) AS g;

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
  lessons_scheduled := v_gen.lessons_scheduled;
  first_lesson_at := v_gen.first_lesson_at;
  last_lesson_at := v_gen.last_lesson_at;
  previous_pass_id := p_previous_pass_id;
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- 7. Dependent helpers — null-safe scheduled_at handling
-- ===========================================================================

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
      AND l.scheduled_at IS NOT NULL
      AND l.scheduled_at = p_scheduled_at
      AND (p_exclude_lesson_id IS NULL OR l.id <> p_exclude_lesson_id)
  );
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
    AND l.scheduled_at IS NOT NULL
    AND l.scheduled_at > now()
  ORDER BY l.scheduled_at ASC
  LIMIT 1;
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
        AND (
          l.scheduled_at IS NOT NULL
          OR l.actual_start_at IS NOT NULL
          OR l.actual_end_at IS NOT NULL
        )
    ),
    now()
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

  IF v_lesson.scheduled_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_LESSON_NOT_SCHEDULED';
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
-- 8. Safe read RPCs — exclude null-dated shells from calendar projections
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_get_my_pass_summary()
RETURNS TABLE (
  pass_id uuid,
  pass_code text,
  pass_status text,
  course_id uuid,
  course_code text,
  course_name text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_scheduled_at timestamptz,
  start_date date,
  expires_on date,
  assigned_teacher_display_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.id AS pass_id,
    p.pass_code,
    p.status AS pass_status,
    c.id AS course_id,
    c.course_code,
    c.name AS course_name,
    p.registered_lesson_count_snapshot AS registered_lesson_count,
    COALESCE(usage.used_lesson_count, 0) AS used_lesson_count,
    p.registered_lesson_count_snapshot - COALESCE(usage.used_lesson_count, 0) AS remaining_lesson_count,
    next_lesson.next_scheduled_at,
    p.start_date,
    p.expires_on,
    COALESCE(next_lesson.teacher_name, slot_teacher.teacher_name) AS assigned_teacher_display_name
  FROM public.passes AS p
  INNER JOIN public.courses AS c ON c.id = p.course_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS used_lesson_count
    FROM public.lessons AS l
    WHERE l.pass_id = p.id
      AND l.status IN ('completed', 'same_day_cancelled', 'makeup_completed')
  ) AS usage ON true
  LEFT JOIN LATERAL (
    SELECT
      l.scheduled_at AS next_scheduled_at,
      t.name AS teacher_name
    FROM public.lessons AS l
    INNER JOIN public.teachers AS t ON t.id = l.assigned_teacher_id
    WHERE l.pass_id = p.id
      AND l.status = 'scheduled'
      AND l.scheduled_at IS NOT NULL
      AND l.scheduled_at > now()
    ORDER BY l.scheduled_at ASC
    LIMIT 1
  ) AS next_lesson ON true
  LEFT JOIN LATERAL (
    SELECT t.name AS teacher_name
    FROM public.schedule_slots AS ss
    INNER JOIN public.teachers AS t ON t.id = ss.teacher_id
    WHERE ss.pass_id = p.id
      AND ss.is_active = true
    ORDER BY ss.slot_order ASC, ss.weekday ASC, ss.local_start_time ASC
    LIMIT 1
  ) AS slot_teacher ON true
  WHERE reve_private.current_app_role() = 'student'
    AND p.student_id = reve_private.current_student_id()
    AND p.status IN ('active', 'reserved')
  ORDER BY
    CASE p.status WHEN 'active' THEN 0 WHEN 'reserved' THEN 1 ELSE 2 END,
    c.course_code,
    p.pass_code;
$$;

CREATE OR REPLACE FUNCTION public.reve_get_my_assigned_student_summaries()
RETURNS TABLE (
  student_id uuid,
  student_code text,
  student_name text,
  course_id uuid,
  course_code text,
  course_name text,
  pass_id uuid,
  pass_code text,
  pass_status text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_assigned_lesson_at timestamptz,
  schedule_weekday smallint,
  schedule_local_start_time time
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    s.id AS student_id,
    s.student_code,
    s.name AS student_name,
    c.id AS course_id,
    c.course_code,
    c.name AS course_name,
    p.id AS pass_id,
    p.pass_code,
    p.status AS pass_status,
    p.registered_lesson_count_snapshot AS registered_lesson_count,
    COALESCE(usage.used_lesson_count, 0) AS used_lesson_count,
    p.registered_lesson_count_snapshot - COALESCE(usage.used_lesson_count, 0) AS remaining_lesson_count,
    next_lesson.next_assigned_lesson_at,
    slot_info.schedule_weekday,
    slot_info.schedule_local_start_time
  FROM public.passes AS p
  INNER JOIN public.students AS s ON s.id = p.student_id
  INNER JOIN public.courses AS c ON c.id = p.course_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS used_lesson_count
    FROM public.lessons AS l
    WHERE l.pass_id = p.id
      AND l.status IN ('completed', 'same_day_cancelled', 'makeup_completed')
  ) AS usage ON true
  LEFT JOIN LATERAL (
    SELECT l.scheduled_at AS next_assigned_lesson_at
    FROM public.lessons AS l
    WHERE l.pass_id = p.id
      AND l.assigned_teacher_id = reve_private.current_teacher_id()
      AND l.status = 'scheduled'
      AND l.scheduled_at IS NOT NULL
      AND l.scheduled_at > now()
    ORDER BY l.scheduled_at ASC
    LIMIT 1
  ) AS next_lesson ON true
  LEFT JOIN LATERAL (
    SELECT ss.weekday AS schedule_weekday, ss.local_start_time AS schedule_local_start_time
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p.id
      AND ss.teacher_id = reve_private.current_teacher_id()
      AND ss.is_active = true
    ORDER BY ss.slot_order ASC, ss.weekday ASC, ss.local_start_time ASC
    LIMIT 1
  ) AS slot_info ON true
  WHERE reve_private.current_app_role() = 'teacher'
    AND p.status IN ('active', 'reserved')
    AND (
      EXISTS (
        SELECT 1
        FROM public.schedule_slots AS ss
        WHERE ss.pass_id = p.id
          AND ss.teacher_id = reve_private.current_teacher_id()
          AND ss.is_active = true
      )
      OR EXISTS (
        SELECT 1
        FROM public.lessons AS l
        WHERE l.pass_id = p.id
          AND l.assigned_teacher_id = reve_private.current_teacher_id()
      )
    )
  ORDER BY s.student_code, c.course_code;
$$;

-- ===========================================================================
-- 10. Teacher display — exclude null-dated shells from upcoming lesson link
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_get_my_teacher_display()
RETURNS TABLE (
  teacher_id uuid,
  teacher_code text,
  teacher_name text,
  course_id uuid,
  course_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT DISTINCT
    t.id AS teacher_id,
    t.teacher_code,
    t.name AS teacher_name,
    c.id AS course_id,
    c.name AS course_name
  FROM public.passes AS p
  INNER JOIN public.courses AS c ON c.id = p.course_id
  INNER JOIN (
    SELECT ss.pass_id, ss.teacher_id
    FROM public.schedule_slots AS ss
    WHERE ss.is_active = true
    UNION
    SELECT l.pass_id, l.assigned_teacher_id AS teacher_id
    FROM public.lessons AS l
    WHERE l.status = 'scheduled'
      AND l.scheduled_at IS NOT NULL
      AND l.scheduled_at > now()
  ) AS link ON link.pass_id = p.id
  INNER JOIN public.teachers AS t ON t.id = link.teacher_id
  WHERE reve_private.current_app_role() = 'student'
    AND p.student_id = reve_private.current_student_id()
    AND p.status IN ('active', 'reserved')
  ORDER BY t.teacher_code, c.name;
$$;

-- ===========================================================================
-- 9. Revoke direct execution of new internal helpers
-- ===========================================================================

REVOKE ALL ON FUNCTION reve_private.validate_pass_lesson_invariants(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.create_pass_lesson_shells(uuid, uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.finalize_pass_lesson_schedules(uuid, timestamptz, uuid, uuid, text) FROM PUBLIC;

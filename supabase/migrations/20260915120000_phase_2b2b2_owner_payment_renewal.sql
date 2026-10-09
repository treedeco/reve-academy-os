-- REVE ACADEMY OS Phase 2B-2B2 — Owner payment + pass renewal UI entrypoint
-- Reuses reve_private.complete_payment_and_renew_pass_internal (no duplicate renewal logic).
-- Creates the pending payment row Owners cannot INSERT via RLS, then completes atomically.

CREATE OR REPLACE FUNCTION public.reve_owner_record_payment_and_renew_pass(
  p_student_id uuid,
  p_course_product_id uuid,
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
  v_actor uuid;
  v_actor_role text;
  v_idempotency_key text;
  v_student public.students%ROWTYPE;
  v_product public.course_products%ROWTYPE;
  v_course public.courses%ROWTYPE;
  v_existing public.payments%ROWTYPE;
  v_payment_id uuid;
  v_payment_updated_at timestamptz;
  v_has_prior_pass boolean;
  v_has_schedule boolean;
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
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
  END IF;

  IF p_paid_amount_krw IS NULL OR p_paid_amount_krw < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
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

  IF p_paid_amount_krw <> v_product.default_tuition_krw THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
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
  WHERE s.id = p_student_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_STUDENT_NOT_FOUND';
  END IF;

  IF v_student.operational_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ENTITY_INACTIVE';
  END IF;

  SELECT *
  INTO v_existing
  FROM public.payments AS pay
  WHERE pay.idempotency_key = v_idempotency_key
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing.student_id IS DISTINCT FROM p_student_id
      OR v_existing.course_product_id IS DISTINCT FROM p_course_product_id
      OR v_existing.paid_amount_krw IS DISTINCT FROM p_paid_amount_krw THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
    END IF;

    IF v_existing.status = 'completed' AND v_existing.renewed_pass_id IS NOT NULL THEN
      RETURN QUERY
      SELECT *
      FROM reve_private.complete_payment_and_renew_pass_internal(
        v_existing.id,
        v_existing.updated_at,
        p_paid_amount_krw,
        COALESCE(v_existing.payment_method, p_payment_method),
        COALESCE(v_existing.paid_at, p_paid_at),
        v_idempotency_key,
        v_actor,
        v_actor_role
      );
      RETURN;
    END IF;

    IF v_existing.status = 'pending' THEN
      v_payment_id := v_existing.id;
      v_payment_updated_at := v_existing.updated_at;
    ELSE
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
    END IF;
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public.passes AS p
      WHERE p.student_id = p_student_id
        AND p.course_id = v_product.course_id
    )
    INTO v_has_prior_pass;

    IF NOT v_has_prior_pass THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_PREVIOUS_PASS';
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.schedule_slots AS ss
      JOIN public.passes AS p ON p.id = ss.pass_id
      WHERE p.student_id = p_student_id
        AND p.course_id = v_product.course_id
        AND ss.is_active = true
        AND (
          p.status = 'active'
          OR (
            p.status = 'completed'
            AND NOT EXISTS (
              SELECT 1
              FROM public.passes AS ap
              WHERE ap.student_id = p_student_id
                AND ap.course_id = v_product.course_id
                AND ap.status = 'active'
            )
          )
        )
    )
    INTO v_has_schedule;

    IF NOT v_has_schedule THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
    END IF;

    INSERT INTO public.payments AS ins (
      student_id,
      course_id,
      course_product_id,
      related_pass_id,
      paid_amount_krw,
      payment_method,
      status,
      paid_at,
      idempotency_key,
      created_by_profile_id
    ) VALUES (
      p_student_id,
      v_product.course_id,
      p_course_product_id,
      (
        SELECT p.id
        FROM public.passes AS p
        WHERE p.student_id = p_student_id
          AND p.course_id = v_product.course_id
          AND p.status IN ('active', 'completed')
        ORDER BY
          CASE p.status WHEN 'active' THEN 0 ELSE 1 END,
          p.sequence_number DESC
        LIMIT 1
      ),
      p_paid_amount_krw,
      p_payment_method,
      'pending',
      NULL,
      v_idempotency_key,
      v_actor
    )
    RETURNING ins.id, ins.updated_at
    INTO v_payment_id, v_payment_updated_at;
  END IF;

  RETURN QUERY
  SELECT *
  FROM reve_private.complete_payment_and_renew_pass_internal(
    v_payment_id,
    v_payment_updated_at,
    p_paid_amount_krw,
    p_payment_method,
    p_paid_at,
    v_idempotency_key,
    v_actor,
    v_actor_role
  );
END;
$$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'reve_owner_record_payment_and_renew_pass'
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
  END LOOP;

  GRANT EXECUTE ON FUNCTION public.reve_owner_record_payment_and_renew_pass(
    uuid, uuid, integer, text, timestamptz, text
  ) TO authenticated, service_role;
END $$;

COMMENT ON FUNCTION public.reve_owner_record_payment_and_renew_pass IS
  'Phase 2B-2B2 owner-only: create pending payment and renew pass via complete_payment_and_renew_pass_internal.';

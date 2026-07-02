-- REVE ACADEMY OS Phase 0B-3B-2B-3E — Owner payment refund trusted operation
-- OD-06, OD-11, OD-12, OD-13; contract process_payment_refund → reve_process_payment_refund

CREATE OR REPLACE FUNCTION public.reve_process_payment_refund(
  p_payment_id uuid,
  p_refunded_amount_krw integer,
  p_reason text
)
RETURNS TABLE (
  refund_id uuid,
  payment_id uuid,
  pass_id uuid,
  payment_status text,
  pass_status text,
  pass_disposition text,
  refunded_amount_krw integer,
  lessons_advanced_cancelled integer,
  correlation_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_payment public.payments%ROWTYPE;
  v_pass public.passes%ROWTYPE;
  v_pass_id uuid;
  v_correlation_id uuid := gen_random_uuid();
  v_trimmed_reason text;
  v_refund_id uuid;
  v_disposition text;
  v_cancelled_at timestamptz := now();
  v_lessons_cancelled integer := 0;
  v_lesson record;
  v_previous_lesson jsonb;
  v_new_lesson jsonb;
  v_previous_payment jsonb;
  v_new_payment jsonb;
  v_previous_pass jsonb;
  v_new_pass jsonb;
  v_new_refund jsonb;
  v_remaining integer;
  v_sms_status text;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_trimmed_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_trimmed_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  IF p_refunded_amount_krw IS NULL OR p_refunded_amount_krw <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REFUND_AMOUNT_MISMATCH';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.payments AS pay
  WHERE pay.id = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.payment_refunds AS pr
    WHERE pr.payment_id = p_payment_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REFUND_ALREADY_EXISTS';
  END IF;

  IF v_payment.status <> 'completed' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_REFUNDABLE';
  END IF;

  IF p_refunded_amount_krw IS DISTINCT FROM v_payment.paid_amount_krw THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REFUND_AMOUNT_MISMATCH';
  END IF;

  v_pass_id := v_payment.renewed_pass_id;

  IF v_pass_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_REFUNDABLE';
  END IF;

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = v_pass_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_REFUNDABLE';
  END IF;

  IF v_pass.status NOT IN ('active', 'reserved') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_REFUNDABLE';
  END IF;

  IF v_pass.student_id IS DISTINCT FROM v_payment.student_id
    OR v_pass.course_id IS DISTINCT FROM v_payment.course_id THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_REFUNDABLE';
  END IF;

  IF v_pass.status = 'reserved' THEN
    v_disposition := 'reserved_cancelled';
  ELSE
    v_disposition := 'active_cancelled_future_advance_cancelled';
  END IF;

  PERFORM 1
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_id
  ORDER BY l.id
  FOR UPDATE;

  IF v_pass.status = 'active' THEN
    FOR v_lesson IN
      SELECT l.id, l.status, l.scheduled_at, l.change_reason
      FROM public.lessons AS l
      WHERE l.pass_id = v_pass_id
        AND NOT reve_private.lesson_status_is_deductible(l.status)
        AND l.status <> 'advance_cancelled'
        AND l.scheduled_at > now()
      ORDER BY l.id
      FOR UPDATE
    LOOP
      v_previous_lesson := jsonb_build_object(
        'status', v_lesson.status,
        'scheduled_at', v_lesson.scheduled_at,
        'change_reason', v_lesson.change_reason
      );

      UPDATE public.lessons AS l
      SET
        status = 'advance_cancelled',
        change_reason = v_trimmed_reason
      WHERE l.id = v_lesson.id;

      v_new_lesson := jsonb_build_object(
        'status', 'advance_cancelled',
        'scheduled_at', v_lesson.scheduled_at,
        'change_reason', v_trimmed_reason
      );

      PERFORM reve_private.append_audit_log(
        v_actor,
        v_actor_role,
        'lesson.status_transition',
        'lessons',
        v_lesson.id,
        v_previous_lesson,
        v_new_lesson,
        v_trimmed_reason,
        v_correlation_id
      );

      v_lessons_cancelled := v_lessons_cancelled + 1;
    END LOOP;
  END IF;

  v_previous_pass := jsonb_build_object(
    'status', v_pass.status,
    'cancelled_at', v_pass.cancelled_at
  );

  UPDATE public.passes AS p
  SET
    status = 'cancelled',
    cancelled_at = v_cancelled_at
  WHERE p.id = v_pass_id;

  v_new_pass := jsonb_build_object(
    'status', 'cancelled',
    'cancelled_at', v_cancelled_at
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'pass.cancelled_by_refund',
    'passes',
    v_pass_id,
    v_previous_pass,
    v_new_pass,
    v_trimmed_reason,
    v_correlation_id
  );

  v_previous_payment := jsonb_build_object(
    'status', v_payment.status
  );

  UPDATE public.payments AS pay
  SET status = 'refunded'
  WHERE pay.id = p_payment_id;

  v_new_payment := jsonb_build_object(
    'status', 'refunded'
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'payment.refunded',
    'payments',
    p_payment_id,
    v_previous_payment,
    v_new_payment,
    v_trimmed_reason,
    v_correlation_id
  );

  INSERT INTO public.payment_refunds (
    payment_id,
    refunded_amount_krw,
    reason,
    actor_profile_id,
    pass_disposition
  ) VALUES (
    p_payment_id,
    p_refunded_amount_krw,
    v_trimmed_reason,
    v_actor,
    v_disposition
  )
  RETURNING id INTO v_refund_id;

  v_new_refund := jsonb_build_object(
    'payment_id', p_payment_id,
    'refunded_amount_krw', p_refunded_amount_krw,
    'pass_disposition', v_disposition,
    'actor_profile_id', v_actor
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'payment_refund.created',
    'payment_refunds',
    v_refund_id,
    NULL,
    v_new_refund,
    v_trimmed_reason,
    v_correlation_id
  );

  SELECT u.remaining_lesson_count
  INTO v_remaining
  FROM reve_private.calculate_pass_usage(v_pass_id) AS u;

  v_sms_status := reve_private.synchronize_sms_notification(
    v_pass_id,
    v_pass.student_id,
    v_remaining,
    v_correlation_id,
    v_actor,
    v_actor_role
  );

  IF v_sms_status IS NOT NULL THEN
    PERFORM reve_private.append_audit_log(
      v_actor,
      v_actor_role,
      'sms_notification.recalculated',
      'sms_notifications',
      (
        SELECT n.id
        FROM public.sms_notifications AS n
        WHERE n.pass_id = v_pass_id
          AND n.notification_type = 'renewal_reminder'
        LIMIT 1
      ),
      NULL,
      jsonb_build_object('status', v_sms_status),
      v_trimmed_reason,
      v_correlation_id
    );
  END IF;

  refund_id := v_refund_id;
  payment_id := p_payment_id;
  pass_id := v_pass_id;
  payment_status := 'refunded';
  pass_status := 'cancelled';
  pass_disposition := v_disposition;
  refunded_amount_krw := p_refunded_amount_krw;
  lessons_advanced_cancelled := v_lessons_cancelled;
  correlation_id := v_correlation_id;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.reve_process_payment_refund(uuid, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_process_payment_refund(uuid, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_process_payment_refund(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reve_process_payment_refund(uuid, integer, text) TO service_role;

COMMENT ON FUNCTION public.reve_process_payment_refund IS
  'Owner-only trusted full refund for completed payments on active or reserved passes (OD-06/12/13). Duplicate attempts reject with REVE_REFUND_ALREADY_EXISTS.';

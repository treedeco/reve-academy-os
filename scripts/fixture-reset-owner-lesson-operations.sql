-- Reset Owner lesson-operation integration fixtures from seed-owner-alpha.sql
-- Local integration tests only.

DO $$
DECLARE
  v_today timestamptz := date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') AT TIME ZONE 'Asia/Seoul' + interval '15 hours';
BEGIN
  UPDATE public.lessons
  SET
    status = 'scheduled',
    updated_at = now(),
    actual_start_at = NULL,
    actual_end_at = NULL,
    change_reason = NULL
  WHERE id IN (
    '99999999-9999-9999-9999-999999999101',
    '99999999-9999-9999-9999-999999999102',
    '99999999-9999-9999-9999-999999999103',
    '99999999-9999-9999-9999-999999999104'
  );

  UPDATE public.lessons
  SET
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE pass_id IN (
    '66666666-6666-6666-6666-666666666103',
    '66666666-6666-6666-6666-666666666105'
  );

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '1 day',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999201';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '2 days',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999202';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '8 days',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999203';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '9 days',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999204';

  UPDATE public.passes
  SET status = 'active', cancelled_at = NULL, updated_at = now()
  WHERE id = '66666666-6666-6666-6666-666666666105';

  DELETE FROM public.payment_refunds
  WHERE payment_id = '12121212-1212-1212-1212-121212121102';

  UPDATE public.payments
  SET status = 'completed', updated_at = now()
  WHERE id = '12121212-1212-1212-1212-121212121102';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '17 days',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999213';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '24 days',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999214';
END $$;

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

  UPDATE public.payments
  SET status = 'completed', updated_at = now()
  WHERE id = '12121212-1212-1212-1212-121212121102'
    AND NOT EXISTS (
      SELECT 1
      FROM public.payment_refunds AS pr
      WHERE pr.payment_id = '12121212-1212-1212-1212-121212121102'
    );

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

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '3 days',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999211';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '10 days',
    status = 'scheduled',
    change_reason = NULL,
    actual_start_at = NULL,
    actual_end_at = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999212';

  -- Restore Delta pass recurring pattern after direct schedule edits in prior test runs.
  UPDATE public.schedule_slots
  SET is_active = false, effective_until = CURRENT_DATE - 1, updated_at = now()
  WHERE pass_id = '66666666-6666-6666-6666-666666666103'
    AND id <> '77777777-7777-7777-7777-777777777103'
    AND is_active = true;

  UPDATE public.schedule_slots
  SET
    teacher_id = '22222222-2222-2222-2222-222222222102',
    weekday = 5,
    local_start_time = TIME '11:00',
    duration_minutes = 60,
    slot_order = 1,
    is_active = true,
    effective_from = CURRENT_DATE - 7,
    effective_until = NULL,
    updated_at = now()
  WHERE id = '77777777-7777-7777-7777-777777777103';

  UPDATE public.passes
  SET status = 'active', cancelled_at = NULL, updated_at = now()
  WHERE id = '66666666-6666-6666-6666-666666666103';
END $$;

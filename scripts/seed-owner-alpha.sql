-- REVE ACADEMY OS Phase 1A — Owner Alpha local dev and Playwright E2E seed data
-- Run after `npx supabase db reset` (not during pgTAP verification).

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa101';
  v_teacher_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd101';
  v_student_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb101';
  v_teacher uuid := '22222222-2222-2222-2222-222222222101';
  v_teacher_b uuid := '22222222-2222-2222-2222-222222222102';
  v_teacher_b_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd102';
  v_student uuid := '44444444-4444-4444-4444-444444444101';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee101';
  v_course_piano uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee102';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff101';
  v_product_piano8 uuid := 'ffffffff-ffff-ffff-ffff-fffffffff102';
  v_pass uuid := '66666666-6666-6666-6666-666666666101';
  v_slot uuid := '77777777-7777-7777-7777-777777777101';
  v_lesson uuid := '99999999-9999-9999-9999-999999999101';
  v_today timestamptz := date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') AT TIME ZONE 'Asia/Seoul' + interval '15 hours';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, reauthentication_token,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner-alpha@test.local', crypt('OwnerAlphaTest123!', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
     '', '', '', '', '', '', now(), now()),
    (v_teacher_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-alpha@test.local', crypt('TeacherAlpha123!', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
     '', '', '', '', '', '', now(), now()),
    (v_student_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-alpha@test.local', crypt('StudentAlpha123!', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
     '', '', '', '', '', '', now(), now())
  ON CONFLICT (id) DO UPDATE SET
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = EXCLUDED.email_confirmed_at,
    raw_app_meta_data = EXCLUDED.raw_app_meta_data,
    confirmation_token = '',
    recovery_token = '',
    email_change_token_new = '',
    email_change = '',
    email_change_token_current = '',
    reauthentication_token = '',
    updated_at = now();

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_owner, 'owner', 'Alpha Owner', 'active'),
    (v_teacher_profile, 'teacher', 'Alpha Teacher', 'active'),
    (v_student_profile, 'student', 'Alpha Student', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, is_active) VALUES
    (v_teacher, 'T-A1', v_teacher_profile, 'Alpha Teacher', true)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student, 'S1A1', v_student_profile, 'Alpha Student', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOC-A1', 'Alpha Vocal Course', true),
    (v_course_piano, 'PIA-A1', 'Alpha Piano Course', true)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES
    (v_product, v_course, 'VOC-4-A1', 'Alpha 4 Lessons', 4, 1, 200000, true),
    (v_product_piano8, v_course_piano, 'PIA-8-A1', 'Alpha 8 Lessons', 8, 2, 400000, true)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at
  ) VALUES (
    v_pass, 'V-S1A1-001', v_student, v_course, v_product,
    1, 'active', 4, 1, 'Alpha 4 Lessons', 200000,
    CURRENT_DATE - 14, now() - interval '14 days'
  ) ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES (
    v_slot, v_pass, v_teacher, 1, TIME '10:00', 60, 1, true, CURRENT_DATE - 14
  ) ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
    sequence_number, scheduled_at, status
  ) VALUES
    (v_lesson, v_pass, v_student, v_course, v_teacher, v_slot, 1, v_today, 'scheduled'),
    ('99999999-9999-9999-9999-999999999102', v_pass, v_student, v_course, v_teacher, v_slot, 2, v_today + interval '7 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999103', v_pass, v_student, v_course, v_teacher, v_slot, 3, v_today + interval '14 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999104', v_pass, v_student, v_course, v_teacher, v_slot, 4, v_today + interval '21 days', 'scheduled')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status, message_body_snapshot, target_date
  ) VALUES (
    '88888888-8888-8888-8888-888888888101', v_student, v_pass, 'renewal_reminder', 'normal',
    'Alpha SMS reminder', CURRENT_DATE + 14
  ) ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.lesson_notes (
    id, lesson_id, author_profile_id, body, visibility
  ) VALUES (
    'abababab-abab-abab-abab-ababababa101', v_lesson, v_owner, 'Alpha seed memo', 'internal'
  ) ON CONFLICT (id) DO NOTHING;

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

  -- Phase 1B-1 weekly schedule fixtures
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, reauthentication_token,
    created_at, updated_at
  ) VALUES (
    v_teacher_b_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'teacher-beta@test.local', crypt('TeacherBeta123!', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', now(), now()
  ) ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_teacher_b_profile, 'teacher', 'Beta Teacher', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, is_active) VALUES
    (v_teacher_b, 'T-A2', v_teacher_b_profile, 'Beta Teacher', true)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    ('44444444-4444-4444-4444-444444444102', 'S1B1', NULL, 'Beta Student', 'active'),
    ('44444444-4444-4444-4444-444444444103', 'S1G1', NULL, 'Gamma Student', 'active'),
    ('44444444-4444-4444-4444-444444444104', 'S1D1', NULL, 'Delta Student', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at
  ) VALUES
    ('66666666-6666-6666-6666-666666666102', 'V-S1G1-001', '44444444-4444-4444-4444-444444444103', v_course, v_product,
     1, 'completed', 4, 1, 'Alpha 4 Lessons', 200000, CURRENT_DATE - 90, now() - interval '90 days'),
    ('66666666-6666-6666-6666-666666666103', 'V-S1D1-001', '44444444-4444-4444-4444-444444444104', v_course, v_product,
     1, 'active', 4, 1, 'Alpha 4 Lessons', 200000, CURRENT_DATE - 7, now() - interval '7 days'),
    ('66666666-6666-6666-6666-666666666105', 'V-S1B1-001', '44444444-4444-4444-4444-444444444102', v_course, v_product,
     1, 'active', 4, 2, 'Alpha 4 Lessons', 200000, CURRENT_DATE - 14, now() - interval '14 days')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES
    ('77777777-7777-7777-7777-777777777102', '66666666-6666-6666-6666-666666666102', v_teacher, 3, TIME '10:00', 60, 1, false, CURRENT_DATE - 90),
    ('77777777-7777-7777-7777-777777777103', '66666666-6666-6666-6666-666666666103', v_teacher_b, 5, TIME '11:00', 60, 1, true, CURRENT_DATE - 7),
    ('77777777-7777-7777-7777-777777777105', '66666666-6666-6666-6666-666666666105', v_teacher_b, 3, TIME '10:00', 60, 1, true, CURRENT_DATE - 14),
    ('77777777-7777-7777-7777-777777777106', '66666666-6666-6666-6666-666666666105', v_teacher, 3, TIME '15:00', 60, 2, true, CURRENT_DATE - 14)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
    sequence_number, scheduled_at, status
  ) VALUES
    ('99999999-9999-9999-9999-999999999201', '66666666-6666-6666-6666-666666666105', '44444444-4444-4444-4444-444444444102', v_course, v_teacher_b, '77777777-7777-7777-7777-777777777105', 1, v_today + interval '1 day', 'scheduled'),
    ('99999999-9999-9999-9999-999999999202', '66666666-6666-6666-6666-666666666105', '44444444-4444-4444-4444-444444444102', v_course, v_teacher, '77777777-7777-7777-7777-777777777106', 2, v_today + interval '2 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999203', '66666666-6666-6666-6666-666666666105', '44444444-4444-4444-4444-444444444102', v_course, v_teacher_b, '77777777-7777-7777-7777-777777777105', 3, v_today + interval '8 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999204', '66666666-6666-6666-6666-666666666105', '44444444-4444-4444-4444-444444444102', v_course, v_teacher, '77777777-7777-7777-7777-777777777106', 4, v_today + interval '9 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999211', '66666666-6666-6666-6666-666666666103', '44444444-4444-4444-4444-444444444104', v_course, v_teacher_b, '77777777-7777-7777-7777-777777777103', 1, v_today + interval '3 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999212', '66666666-6666-6666-6666-666666666103', '44444444-4444-4444-4444-444444444104', v_course, v_teacher_b, '77777777-7777-7777-7777-777777777103', 2, v_today + interval '10 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999213', '66666666-6666-6666-6666-666666666103', '44444444-4444-4444-4444-444444444104', v_course, v_teacher_b, '77777777-7777-7777-7777-777777777103', 3, v_today + interval '17 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999214', '66666666-6666-6666-6666-666666666103', '44444444-4444-4444-4444-444444444104', v_course, v_teacher_b, '77777777-7777-7777-7777-777777777103', 4, v_today + interval '24 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999301', '66666666-6666-6666-6666-666666666102', '44444444-4444-4444-4444-444444444103', v_course, v_teacher, '77777777-7777-7777-7777-777777777102', 1, v_today - interval '80 days', 'completed'),
    ('99999999-9999-9999-9999-999999999302', '66666666-6666-6666-6666-666666666102', '44444444-4444-4444-4444-444444444103', v_course, v_teacher, '77777777-7777-7777-7777-777777777102', 2, v_today - interval '73 days', 'completed'),
    ('99999999-9999-9999-9999-999999999303', '66666666-6666-6666-6666-666666666102', '44444444-4444-4444-4444-444444444103', v_course, v_teacher, '77777777-7777-7777-7777-777777777102', 3, v_today - interval '66 days', 'completed'),
    ('99999999-9999-9999-9999-999999999304', '66666666-6666-6666-6666-666666666102', '44444444-4444-4444-4444-444444444103', v_course, v_teacher, '77777777-7777-7777-7777-777777777102', 4, v_today - interval '59 days', 'completed')
  ON CONFLICT (id) DO NOTHING;

  -- Phase 1B-2 SMS sent confirmation fixtures
  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status, message_body_snapshot, target_date,
    sent_at, sent_confirmed_by_profile_id
  ) VALUES
    ('88888888-8888-8888-8888-888888888102', '44444444-4444-4444-4444-444444444102', '66666666-6666-6666-6666-666666666105', 'renewal_reminder', 'scheduled',
     '[Beta] Alpha 4 Lessons 수강권 갱신 안내 SMS', CURRENT_DATE + 3, NULL, NULL),
    ('88888888-8888-8888-8888-888888888103', '44444444-4444-4444-4444-444444444104', '66666666-6666-6666-6666-666666666103', 'renewal_reminder', 'target',
     '[Delta] Alpha 4 Lessons 수강권 갱신 안내 SMS', CURRENT_DATE, NULL, NULL),
    ('88888888-8888-8888-8888-888888888104', '44444444-4444-4444-4444-444444444103', '66666666-6666-6666-6666-666666666102', 'renewal_reminder', 'exhausted_unsent',
     '[Gamma] Alpha 4 Lessons 수강권 갱신 안내 SMS (미발송 소진)', CURRENT_DATE - 1, NULL, NULL)
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.sms_notifications
  SET
    status = 'normal',
    message_body_snapshot = 'Alpha SMS reminder',
    target_date = CURRENT_DATE + 14,
    sent_at = NULL,
    sent_confirmed_by_profile_id = NULL,
    updated_at = now()
  WHERE id = '88888888-8888-8888-8888-888888888101';

  UPDATE public.sms_notifications
  SET
    status = 'scheduled',
    message_body_snapshot = '[Beta] Alpha 4 Lessons 수강권 갱신 안내 SMS',
    target_date = CURRENT_DATE + 3,
    sent_at = NULL,
    sent_confirmed_by_profile_id = NULL,
    updated_at = now()
  WHERE id = '88888888-8888-8888-8888-888888888102';

  UPDATE public.sms_notifications
  SET
    status = 'target',
    message_body_snapshot = '[Delta] Alpha 4 Lessons 수강권 갱신 안내 SMS',
    target_date = CURRENT_DATE,
    sent_at = NULL,
    sent_confirmed_by_profile_id = NULL,
    updated_at = now()
  WHERE id = '88888888-8888-8888-8888-888888888103';

  UPDATE public.sms_notifications
  SET
    status = 'exhausted_unsent',
    message_body_snapshot = '[Gamma] Alpha 4 Lessons 수강권 갱신 안내 SMS (미발송 소진)',
    target_date = CURRENT_DATE - 1,
    sent_at = NULL,
    sent_confirmed_by_profile_id = NULL,
    updated_at = now()
  WHERE id = '88888888-8888-8888-8888-888888888104';

  -- Phase 1B-3 payment refund fixtures
  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    ('44444444-4444-4444-4444-444444444105', 'S1E1', NULL, 'Epsilon Student', 'active'),
    ('44444444-4444-4444-4444-444444444106', 'S1Z1', NULL, 'Zeta Student', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at
  ) VALUES
    ('66666666-6666-6666-6666-666666666109', 'V-S1E1-001', '44444444-4444-4444-4444-444444444105', v_course, v_product,
     1, 'reserved', 4, 1, 'Alpha 4 Lessons', 200000, CURRENT_DATE + 30, NULL),
    ('66666666-6666-6666-6666-666666666110', 'V-S1Z1-001', '44444444-4444-4444-4444-444444444106', v_course, v_product,
     1, 'cancelled', 4, 1, 'Alpha 4 Lessons', 200000, CURRENT_DATE - 30, now() - interval '30 days')
  ON CONFLICT (id) DO NOTHING;

  DELETE FROM public.schedule_slots
  WHERE id = '77777777-7777-7777-7777-777777777109';

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
    sequence_number, scheduled_at, status
  ) VALUES
    ('99999999-9999-9999-9999-999999999401', '66666666-6666-6666-6666-666666666109', '44444444-4444-4444-4444-444444444105', v_course, v_teacher, NULL, 1, v_today + interval '30 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999402', '66666666-6666-6666-6666-666666666109', '44444444-4444-4444-4444-444444444105', v_course, v_teacher, NULL, 2, v_today + interval '37 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999403', '66666666-6666-6666-6666-666666666109', '44444444-4444-4444-4444-444444444105', v_course, v_teacher, NULL, 3, v_today + interval '44 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999404', '66666666-6666-6666-6666-666666666109', '44444444-4444-4444-4444-444444444105', v_course, v_teacher, NULL, 4, v_today + interval '51 days', 'scheduled'),
    ('99999999-9999-9999-9999-999999999501', '66666666-6666-6666-6666-666666666110', '44444444-4444-4444-4444-444444444106', v_course, v_teacher, v_slot, 1, v_today - interval '20 days', 'advance_cancelled'),
    ('99999999-9999-9999-9999-999999999502', '66666666-6666-6666-6666-666666666110', '44444444-4444-4444-4444-444444444106', v_course, v_teacher, v_slot, 2, v_today - interval '13 days', 'advance_cancelled'),
    ('99999999-9999-9999-9999-999999999503', '66666666-6666-6666-6666-666666666110', '44444444-4444-4444-4444-444444444106', v_course, v_teacher, v_slot, 3, v_today - interval '6 days', 'advance_cancelled'),
    ('99999999-9999-9999-9999-999999999504', '66666666-6666-6666-6666-666666666110', '44444444-4444-4444-4444-444444444106', v_course, v_teacher, v_slot, 4, v_today + interval '1 day', 'advance_cancelled')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id, renewed_pass_id,
    paid_amount_krw, payment_method, status, paid_at, idempotency_key, processed_at, created_by_profile_id
  ) VALUES
    ('12121212-1212-1212-1212-121212121101', '44444444-4444-4444-4444-444444444104', v_course, v_product, NULL, '66666666-6666-6666-6666-666666666103',
     200000, 'card', 'completed', now() - interval '7 days', 'alpha-seed-refund-delta-101', now() - interval '7 days', v_owner),
    ('12121212-1212-1212-1212-121212121102', '44444444-4444-4444-4444-444444444102', v_course, v_product, NULL, '66666666-6666-6666-6666-666666666105',
     200000, 'bank_transfer', 'completed', now() - interval '14 days', 'alpha-seed-refund-beta-102', now() - interval '14 days', v_owner),
    ('12121212-1212-1212-1212-121212121103', v_student, v_course, v_product, NULL, v_pass,
     200000, NULL, 'pending', NULL, 'alpha-seed-refund-pending-103', NULL, v_owner),
    ('12121212-1212-1212-1212-121212121104', '44444444-4444-4444-4444-444444444106', v_course, v_product, NULL, '66666666-6666-6666-6666-666666666110',
     200000, 'card', 'refunded', now() - interval '25 days', 'alpha-seed-refund-done-104', now() - interval '25 days', v_owner),
    ('12121212-1212-1212-1212-121212121105', '44444444-4444-4444-4444-444444444105', v_course, v_product, NULL, '66666666-6666-6666-6666-666666666109',
     200000, 'cash', 'completed', now() - interval '3 days', 'alpha-seed-refund-reserved-105', now() - interval '3 days', v_owner)
  ON CONFLICT (id) DO NOTHING;

  ALTER TABLE public.payment_refunds DISABLE TRIGGER trg_payment_refunds_block_mutation;
  DELETE FROM public.payment_refunds
  WHERE payment_id IN (
    '12121212-1212-1212-1212-121212121101',
    '12121212-1212-1212-1212-121212121102',
    '12121212-1212-1212-1212-121212121105'
  );
  DELETE FROM public.payment_refunds
  WHERE id = 'abababab-abab-abab-abab-ababababa201';
  INSERT INTO public.payment_refunds (
    id, payment_id, refunded_amount_krw, refunded_at, reason, actor_profile_id, pass_disposition
  ) VALUES (
    'abababab-abab-abab-abab-ababababa201', '12121212-1212-1212-1212-121212121104', 200000,
    now() - interval '20 days', 'Alpha seed already refunded payment', v_owner,
    'active_cancelled_future_advance_cancelled'
  );
  ALTER TABLE public.payment_refunds ENABLE TRIGGER trg_payment_refunds_block_mutation;

  UPDATE public.payments
  SET
    status = 'completed',
    paid_amount_krw = 200000,
    paid_at = now() - interval '7 days',
    processed_at = now() - interval '7 days',
    updated_at = now()
  WHERE id = '12121212-1212-1212-1212-121212121101';

  UPDATE public.payments
  SET
    status = 'completed',
    paid_amount_krw = 200000,
    paid_at = now() - interval '14 days',
    processed_at = now() - interval '14 days',
    updated_at = now()
  WHERE id = '12121212-1212-1212-1212-121212121102';

  UPDATE public.payments
  SET
    status = 'pending',
    paid_at = NULL,
    processed_at = NULL,
    payment_method = NULL,
    updated_at = now()
  WHERE id = '12121212-1212-1212-1212-121212121103';

  UPDATE public.payments
  SET
    status = 'completed',
    paid_amount_krw = 200000,
    paid_at = now() - interval '3 days',
    processed_at = now() - interval '3 days',
    updated_at = now()
  WHERE id = '12121212-1212-1212-1212-121212121105';

  UPDATE public.passes
  SET status = 'active', cancelled_at = NULL, updated_at = now()
  WHERE id = '66666666-6666-6666-6666-666666666103';

  UPDATE public.passes
  SET status = 'active', cancelled_at = NULL, updated_at = now()
  WHERE id = '66666666-6666-6666-6666-666666666105';

  UPDATE public.passes
  SET status = 'reserved', cancelled_at = NULL, activated_at = NULL, updated_at = now()
  WHERE id = '66666666-6666-6666-6666-666666666109';

  UPDATE public.lessons
  SET status = 'scheduled', change_reason = NULL, updated_at = now()
  WHERE pass_id IN ('66666666-6666-6666-6666-666666666103', '66666666-6666-6666-6666-666666666105');

  UPDATE public.lessons
  SET status = 'scheduled', change_reason = NULL, updated_at = now()
  WHERE pass_id = '66666666-6666-6666-6666-666666666109';

  UPDATE public.lessons
  SET
    status = 'postponed',
    scheduled_at = v_today + interval '5 days',
    change_reason = 'Alpha seed postponed lesson',
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999102';

  -- Phase 1B-4 schedule change request fixtures
  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '3 days',
    status = 'scheduled',
    change_reason = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999211';

  INSERT INTO public.schedule_change_requests (
    id, student_id, target_lesson_id, requesting_profile_id, request_source_role,
    status, requested_reason, proposed_scheduled_at,
    approved_scheduled_at, owner_decision_note, decided_by_profile_id, decided_at, applied_at
  ) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa301', '44444444-4444-4444-4444-444444444102',
     '99999999-9999-9999-9999-999999999201', v_teacher_b_profile, 'teacher',
     'submitted', 'Alpha seed Beta lesson reschedule request', v_today + interval '6 days',
     NULL, NULL, NULL, NULL, NULL),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa302', '44444444-4444-4444-4444-444444444104',
     '99999999-9999-9999-9999-999999999211', v_teacher_b_profile, 'teacher',
     'approved', 'Alpha seed Delta pre-approved request', v_today + interval '11 days',
     v_today + interval '40 days', 'Alpha seed pre-approved schedule time', v_owner, now() - interval '1 day', NULL),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa303', '44444444-4444-4444-4444-444444444102',
     '99999999-9999-9999-9999-999999999202', v_teacher_b_profile, 'teacher',
     'rejected', 'Alpha seed rejected request', v_today + interval '7 days',
     NULL, 'Alpha seed rejected', v_owner, now() - interval '2 days', NULL),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa304', '44444444-4444-4444-4444-444444444104',
     '99999999-9999-9999-9999-999999999214', v_teacher_b_profile, 'teacher',
     'applied', 'Alpha seed already applied request', v_today + interval '15 days',
     v_today + interval '24 days', 'Alpha seed applied', v_owner, now() - interval '3 days', now() - interval '2 days'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa305', '44444444-4444-4444-4444-444444444104',
     '99999999-9999-9999-9999-999999999212', v_teacher_b_profile, 'teacher',
     'applied', 'Alpha seed cascade pending request', v_today + interval '12 days',
     v_today + interval '38 days', 'Alpha seed cascade pending apply', v_owner, now() - interval '2 days', now() - interval '1 day')
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.schedule_change_requests
  SET
    status = 'submitted',
    proposed_scheduled_at = v_today + interval '6 days',
    approved_scheduled_at = NULL,
    owner_decision_note = NULL,
    decided_by_profile_id = NULL,
    decided_at = NULL,
    applied_at = NULL,
    requested_reason = 'Alpha seed Beta lesson reschedule request',
    updated_at = now()
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa301';

  UPDATE public.schedule_change_requests
  SET
    status = 'approved',
    proposed_scheduled_at = v_today + interval '11 days',
    approved_scheduled_at = v_today + interval '40 days',
    owner_decision_note = 'Alpha seed pre-approved schedule time',
    decided_by_profile_id = v_owner,
    decided_at = now() - interval '1 day',
    applied_at = NULL,
    requested_reason = 'Alpha seed Delta pre-approved request',
    updated_at = now()
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa302';

  UPDATE public.schedule_change_requests
  SET
    status = 'rejected',
    proposed_scheduled_at = v_today + interval '7 days',
    approved_scheduled_at = NULL,
    owner_decision_note = 'Alpha seed rejected',
    decided_by_profile_id = v_owner,
    decided_at = now() - interval '2 days',
    applied_at = NULL,
    requested_reason = 'Alpha seed rejected request',
    updated_at = now()
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa303';

  UPDATE public.schedule_change_requests
  SET
    status = 'applied',
    proposed_scheduled_at = v_today + interval '15 days',
    approved_scheduled_at = v_today + interval '24 days',
    owner_decision_note = 'Alpha seed applied',
    decided_by_profile_id = v_owner,
    decided_at = now() - interval '3 days',
    applied_at = now() - interval '2 days',
    requested_reason = 'Alpha seed already applied request',
    cascade_completed_at = now() - interval '1 day',
    cascaded_lesson_count = 0,
    cascade_reason = 'Alpha seed completed cascade',
    updated_at = now()
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa304';

  UPDATE public.schedule_change_requests
  SET
    status = 'applied',
    proposed_scheduled_at = v_today + interval '12 days',
    approved_scheduled_at = v_today + interval '38 days',
    owner_decision_note = 'Alpha seed cascade pending apply',
    decided_by_profile_id = v_owner,
    decided_at = now() - interval '2 days',
    applied_at = now() - interval '1 day',
    requested_reason = 'Alpha seed cascade pending request',
    cascade_completed_at = NULL,
    cascaded_lesson_count = NULL,
    cascade_reason = NULL,
    updated_at = now()
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa305';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '24 days',
    status = 'scheduled',
    change_reason = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999214';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '38 days',
    status = 'scheduled',
    change_reason = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999212';

  UPDATE public.lessons
  SET
    scheduled_at = v_today + interval '17 days',
    status = 'scheduled',
    change_reason = NULL,
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999213';

  ALTER TABLE public.lesson_schedule_changes DISABLE TRIGGER trg_lesson_schedule_changes_block_mutation;
  DELETE FROM public.lesson_schedule_changes
  WHERE id IN (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb304',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb305'
  );
  INSERT INTO public.lesson_schedule_changes (
    id, lesson_id, schedule_change_request_id, change_origin,
    previous_scheduled_at, new_scheduled_at, reason, actor_profile_id
  ) VALUES
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb304', '99999999-9999-9999-9999-999999999214',
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa304', 'direct_user',
     v_today + interval '23 days', v_today + interval '24 days', 'Alpha seed applied direct move', v_owner),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb305', '99999999-9999-9999-9999-999999999212',
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa305', 'direct_user',
     v_today + interval '10 days', v_today + interval '38 days', 'Alpha seed cascade pending direct move', v_owner);
  ALTER TABLE public.lesson_schedule_changes ENABLE TRIGGER trg_lesson_schedule_changes_block_mutation;
END $$;

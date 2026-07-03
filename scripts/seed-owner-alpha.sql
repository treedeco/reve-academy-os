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
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff101';
  v_pass uuid := '66666666-6666-6666-6666-666666666101';
  v_slot uuid := '77777777-7777-7777-7777-777777777101';
  v_lesson uuid := '99999999-9999-9999-9999-999999999101';
  v_today timestamptz := date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') AT TIME ZONE 'Asia/Seoul' + interval '10 hours';
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
    (v_course, 'VOC-A1', 'Alpha Vocal Course', true)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES (
    v_product, v_course, 'VOC-4-A1', 'Alpha 4 Lessons', 4, 1, 200000, true
  ) ON CONFLICT (id) DO NOTHING;

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

  UPDATE public.lessons
  SET
    status = 'postponed',
    scheduled_at = v_today + interval '5 days',
    change_reason = 'Alpha seed postponed lesson',
    updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999102';
END $$;

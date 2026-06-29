-- REVE ACADEMY OS Phase 0B-3B-2B-2 — payment renewal and reserved activation pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(48);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_teacher_a uuid := 'dddddddd-dddd-dddd-dddd-ddddddddddda';
  v_teacher_b uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddb';
  v_student_a uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_student_b uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_student_c uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc01';
  v_student_d uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc02';
  v_student_e uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc03';
  v_student_f uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc04';
  v_student_g uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc05';
  v_student_h uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc06';
  v_teacher_a_row uuid := '22222222-2222-2222-2222-222222222222';
  v_teacher_b_row uuid := '33333333-3333-3333-3333-333333333333';
  v_student_s001 uuid := '44444444-4444-4444-4444-444444444444';
  v_student_s002 uuid := '44444444-4444-4444-4444-444444444401';
  v_student_s003 uuid := '44444444-4444-4444-4444-444444444402';
  v_student_s004 uuid := '44444444-4444-4444-4444-444444444403';
  v_student_s005 uuid := '44444444-4444-4444-4444-444444444404';
  v_student_s006 uuid := '44444444-4444-4444-4444-444444444405';
  v_student_s007 uuid := '44444444-4444-4444-4444-444444444406';
  v_student_s008 uuid := '44444444-4444-4444-4444-444444444407';
  v_course_vocal uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_course_piano uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01';
  v_product_4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_product_8 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff01';
  v_pass_err_base uuid := '66666666-6666-6666-6666-666666666601';
  v_pass_s002_001 uuid := '66666666-6666-6666-6666-666666666602';
  v_pass_s002_002 uuid := '66666666-6666-6666-6666-666666666603';
  v_pass_s003_001 uuid := '66666666-6666-6666-6666-666666666604';
  v_pass_s004_001 uuid := '66666666-6666-6666-6666-666666666605';
  v_pass_s005_active uuid := '66666666-6666-6666-6666-666666666606';
  v_pass_s005_reserved uuid := '67676767-6767-6767-6767-676767676767';
  v_pass_s006_done uuid := '66666666-6666-6666-6666-666666666607';
  v_pass_s006_active uuid := '66666666-6666-6666-6666-666666666608';
  v_pass_s007_001 uuid := '66666666-6666-6666-6666-666666666609';
  v_pass_s008_001 uuid := '66666666-6666-6666-6666-666666666610';
  v_pass_s009_done uuid := '66666666-6666-6666-6666-666666666611';
  v_pass_s009_reserved uuid := '67676767-6767-6767-6767-676767676768';
  v_slot_err uuid := '77777777-7777-7777-7777-777777777701';
  v_slot_s002 uuid := '77777777-7777-7777-7777-777777777702';
  v_slot_s003 uuid := '77777777-7777-7777-7777-777777777703';
  v_slot_s004 uuid := '77777777-7777-7777-7777-777777777704';
  v_slot_s005 uuid := '77777777-7777-7777-7777-777777777705';
  v_slot_s005_r uuid := '77777777-7777-7777-7777-777777777706';
  v_slot_s006 uuid := '77777777-7777-7777-7777-777777777707';
  v_slot_s007 uuid := '77777777-7777-7777-7777-777777777708';
  v_slot_s008 uuid := '77777777-7777-7777-7777-777777777709';
  v_slot_s009_done uuid := '77777777-7777-7777-7777-777777777710';
  v_slot_s009_reserved uuid := '77777777-7777-7777-7777-777777777711';
  v_lesson_s002_1 uuid := '99999999-9999-9999-9999-999999999901';
  v_lesson_s002_2 uuid := '99999999-9999-9999-9999-999999999902';
  v_lesson_s002_3 uuid := '99999999-9999-9999-9999-999999999903';
  v_lesson_s002_4 uuid := '99999999-9999-9999-9999-999999999904';
  v_lesson_s006_1 uuid := '99999999-9999-9999-9999-999999999911';
  v_lesson_s006_2 uuid := '99999999-9999-9999-9999-999999999912';
  v_lesson_s006_3 uuid := '99999999-9999-9999-9999-999999999913';
  v_lesson_s006_last uuid := '99999999-9999-9999-9999-999999999914';
  v_lesson_s009_1 uuid := 'abababab-abab-abab-abab-ababababab01';
  v_lesson_s009_2 uuid := 'abababab-abab-abab-abab-ababababab02';
  v_lesson_s009_3 uuid := 'abababab-abab-abab-abab-ababababab03';
  v_lesson_s009_4 uuid := 'abababab-abab-abab-abab-ababababab04';
  v_payment_stale uuid := '12121212-1212-1212-1212-121212121201';
  v_payment_bad_amt uuid := '12121212-1212-1212-1212-121212121202';
  v_payment_bad_method uuid := '12121212-1212-1212-1212-121212121203';
  v_payment_cancel uuid := '12121212-1212-1212-1212-121212121204';
  v_payment_s002 uuid := '12121212-1212-1212-1212-121212121205';
  v_payment_s003 uuid := '12121212-1212-1212-1212-121212121206';
  v_payment_s004 uuid := '12121212-1212-1212-1212-121212121207';
  v_payment_s005 uuid := '12121212-1212-1212-1212-121212121208';
  v_payment_s006 uuid := '12121212-1212-1212-1212-121212121209';
  v_payment_s007 uuid := '12121212-1212-1212-1212-121212121210';
  v_payment_s008_a uuid := '12121212-1212-1212-1212-121212121211';
  v_payment_s008_b uuid := '12121212-1212-1212-1212-121212121212';
  v_sms_s006_sent uuid := '14141414-1414-1414-1414-141414141401';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-a@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now()),
    (v_teacher_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-b@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-a@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-b@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-c@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_d, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-d@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_e, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-e@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_f, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-f@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_g, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-g@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_h, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-h@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Test Owner'),
    (v_teacher_a, 'teacher', 'Teacher A'),
    (v_teacher_b, 'teacher', 'Teacher B'),
    (v_student_a, 'student', 'Student A'),
    (v_student_b, 'student', 'Student B'),
    (v_student_c, 'student', 'Student C'),
    (v_student_d, 'student', 'Student D'),
    (v_student_e, 'student', 'Student E'),
    (v_student_f, 'student', 'Student F'),
    (v_student_g, 'student', 'Student G'),
    (v_student_h, 'student', 'Student H');

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student_s001, 'S001', v_student_a, 'Student S001'),
    (v_student_s002, 'S002', v_student_b, 'Student S002'),
    (v_student_s003, 'S003', v_student_c, 'Student S003'),
    (v_student_s004, 'S004', v_student_d, 'Student S004'),
    (v_student_s005, 'S005', v_student_e, 'Student S005'),
    (v_student_s006, 'S006', v_student_f, 'Student S006'),
    (v_student_s007, 'S007', v_student_g, 'Student S007'),
    (v_student_s008, 'S008', v_student_h, 'Student S008');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email) VALUES
    (v_teacher_a_row, 'T-A001', v_teacher_a, 'Teacher A', '010-0000-0001', 'ta@test.local'),
    (v_teacher_b_row, 'T-B001', v_teacher_b, 'Teacher B', '010-0000-0002', 'tb@test.local');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course_vocal, 'VOCAL', 'Vocal Course', true),
    (v_course_piano, 'PIANO', 'Piano Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES
    (v_product_4, v_course_vocal, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000),
    (v_product_8, v_course_piano, 'PIANO-8', 'Piano 8 Lessons', 8, 1, 400000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at, previous_pass_id
  ) VALUES
    (v_pass_err_base, 'V-S001-001', v_student_s001, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 90, now() - interval '30 days', NULL),
    (v_pass_s002_001, 'V-S002-001', v_student_s002, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 90, now() - interval '30 days', NULL),
    (v_pass_s002_002, 'V-S002-002', v_student_s002, v_course_vocal, v_product_4,
     2, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE, NULL, NULL),
    (v_pass_s003_001, 'V-S003-001', v_student_s003, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 60, now() - interval '20 days', NULL),
    (v_pass_s004_001, 'P-S004-001', v_student_s004, v_course_piano, v_product_8,
     1, 'completed', 8, 1, 'Piano 8 Lessons', 400000, CURRENT_DATE - 60, now() - interval '20 days', NULL),
    (v_pass_s005_active, 'V-S005-001', v_student_s005, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE, NULL, NULL),
    (v_pass_s005_reserved, 'V-S005-002', v_student_s005, v_course_vocal, v_product_4,
     2, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE + 30, NULL, v_pass_s005_active),
    (v_pass_s006_done, 'V-S006-001', v_student_s006, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 120, now() - interval '60 days', NULL),
    (v_pass_s006_active, 'V-S006-002', v_student_s006, v_course_vocal, v_product_4,
     2, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE, NULL, NULL),
    (v_pass_s007_001, 'V-S007-001', v_student_s007, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 60, now() - interval '20 days', NULL),
    (v_pass_s008_001, 'V-S008-001', v_student_s008, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 90, now() - interval '30 days', NULL),
    (v_pass_s009_done, 'V-S001-002', v_student_s001, v_course_vocal, v_product_4,
     2, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 30, now() - interval '5 days', v_pass_err_base),
    (v_pass_s009_reserved, 'V-S001-003', v_student_s001, v_course_vocal, v_product_4,
     3, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE + 30, NULL, v_pass_s009_done);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot_err, v_pass_err_base, v_teacher_a_row, 1, '10:00', 60, CURRENT_DATE - 90),
    (v_slot_s002, v_pass_s002_002, v_teacher_a_row, 2, '11:00', 60, CURRENT_DATE),
    (v_slot_s003, v_pass_s003_001, v_teacher_a_row, 3, '12:00', 60, CURRENT_DATE - 60),
    (v_slot_s004, v_pass_s004_001, v_teacher_a_row, 4, '13:00', 60, CURRENT_DATE - 60),
    (v_slot_s005, v_pass_s005_active, v_teacher_a_row, 1, '14:00', 60, CURRENT_DATE),
    (v_slot_s005_r, v_pass_s005_reserved, v_teacher_a_row, 1, '14:00', 60, CURRENT_DATE),
    (v_slot_s006, v_pass_s006_active, v_teacher_a_row, 5, '15:00', 60, CURRENT_DATE),
    (v_slot_s007, v_pass_s007_001, v_teacher_a_row, 1, '16:00', 60, CURRENT_DATE - 60),
    (v_slot_s008, v_pass_s008_001, v_teacher_b_row, 6, '09:00', 60, CURRENT_DATE - 90),
    (v_slot_s009_done, v_pass_s009_done, v_teacher_a_row, 1, '18:00', 60, CURRENT_DATE - 30),
    (v_slot_s009_reserved, v_pass_s009_reserved, v_teacher_a_row, 1, '18:00', 60, CURRENT_DATE);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    actual_start_at, actual_end_at
  ) VALUES
    (v_lesson_s002_1, v_pass_s002_002, v_student_s002, v_course_vocal, v_teacher_a_row,
     v_slot_s002, 1, now() - interval '14 days', 'completed',
     now() - interval '14 days', now() - interval '14 days' + interval '1 hour'),
    (v_lesson_s002_2, v_pass_s002_002, v_student_s002, v_course_vocal, v_teacher_a_row,
     v_slot_s002, 2, now() - interval '7 days', 'completed',
     now() - interval '7 days', now() - interval '7 days' + interval '1 hour'),
    (v_lesson_s002_3, v_pass_s002_002, v_student_s002, v_course_vocal, v_teacher_a_row,
     v_slot_s002, 3, now() + interval '2 days', 'scheduled', NULL, NULL),
    (v_lesson_s002_4, v_pass_s002_002, v_student_s002, v_course_vocal, v_teacher_a_row,
     v_slot_s002, 4, now() + interval '9 days', 'scheduled', NULL, NULL),
    (v_lesson_s006_1, v_pass_s006_active, v_student_s006, v_course_vocal, v_teacher_a_row,
     v_slot_s006, 1, now() - interval '21 days', 'completed',
     now() - interval '21 days', now() - interval '21 days' + interval '1 hour'),
    (v_lesson_s006_2, v_pass_s006_active, v_student_s006, v_course_vocal, v_teacher_a_row,
     v_slot_s006, 2, now() - interval '14 days', 'completed',
     now() - interval '14 days', now() - interval '14 days' + interval '1 hour'),
    (v_lesson_s006_3, v_pass_s006_active, v_student_s006, v_course_vocal, v_teacher_a_row,
     v_slot_s006, 3, now() - interval '7 days', 'completed',
     now() - interval '7 days', now() - interval '7 days' + interval '1 hour'),
    (v_lesson_s006_last, v_pass_s006_active, v_student_s006, v_course_vocal, v_teacher_a_row,
     v_slot_s006, 4, now() + interval '1 day', 'scheduled', NULL, NULL),
    (v_lesson_s009_1, v_pass_s009_reserved, v_student_s001, v_course_vocal, v_teacher_a_row,
     v_slot_s009_reserved, 1, NULL, 'scheduled', NULL, NULL),
    (v_lesson_s009_2, v_pass_s009_reserved, v_student_s001, v_course_vocal, v_teacher_a_row,
     v_slot_s009_reserved, 2, NULL, 'scheduled', NULL, NULL),
    (v_lesson_s009_3, v_pass_s009_reserved, v_student_s001, v_course_vocal, v_teacher_a_row,
     v_slot_s009_reserved, 3, NULL, 'scheduled', NULL, NULL),
    (v_lesson_s009_4, v_pass_s009_reserved, v_student_s001, v_course_vocal, v_teacher_a_row,
     v_slot_s009_reserved, 4, NULL, 'scheduled', NULL, NULL);

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, payment_method, status, paid_at, idempotency_key,
    created_by_profile_id
  ) VALUES
    (v_payment_stale, v_student_s001, v_course_vocal, v_product_4, v_pass_err_base,
     200000, NULL, 'pending', NULL, 'idem-pay-stale', v_owner),
    (v_payment_bad_amt, v_student_s001, v_course_vocal, v_product_4, v_pass_err_base,
     200000, NULL, 'pending', NULL, 'idem-pay-bad-amt', v_owner),
    (v_payment_bad_method, v_student_s001, v_course_vocal, v_product_4, v_pass_err_base,
     200000, NULL, 'pending', NULL, 'idem-pay-bad-method', v_owner),
    (v_payment_cancel, v_student_s001, v_course_vocal, v_product_4, v_pass_err_base,
     200000, NULL, 'cancelled', NULL, 'idem-pay-cancel', v_owner),
    (v_payment_s002, v_student_s002, v_course_vocal, v_product_4, v_pass_s002_002,
     200000, NULL, 'pending', NULL, 'idem-pay-s002', v_owner),
    (v_payment_s003, v_student_s003, v_course_vocal, v_product_4, v_pass_s003_001,
     200000, NULL, 'pending', NULL, 'idem-pay-s003', v_owner),
    (v_payment_s004, v_student_s004, v_course_piano, v_product_8, v_pass_s004_001,
     400000, NULL, 'pending', NULL, 'idem-pay-s004', v_owner),
    (v_payment_s005, v_student_s005, v_course_vocal, v_product_4, v_pass_s005_active,
     200000, NULL, 'pending', NULL, 'idem-pay-s005', v_owner),
    (v_payment_s006, v_student_s006, v_course_vocal, v_product_4, v_pass_s006_active,
     200000, NULL, 'pending', NULL, 'idem-pay-s006', v_owner),
    (v_payment_s007, v_student_s007, v_course_vocal, v_product_4, v_pass_s007_001,
     200000, NULL, 'pending', NULL, 'idem-pay-s007', v_owner),
    (v_payment_s008_a, v_student_s008, v_course_vocal, v_product_4, v_pass_s008_001,
     200000, NULL, 'pending', NULL, 'idem-pay-s008-a', v_owner),
    (v_payment_s008_b, v_student_s008, v_course_vocal, v_product_4, NULL,
     200000, NULL, 'pending', NULL, 'idem-pay-s008-b', v_owner);

  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status,
    message_body_snapshot, target_date, sent_at
  ) VALUES
    (v_sms_s006_sent, v_student_s006, v_pass_s006_done, 'renewal_reminder', 'sent',
     'Prior pass renewal notice', CURRENT_DATE - 90, now() - interval '90 days');

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, false);
  PERFORM set_config('test.student_a', v_student_a::text, false);
  PERFORM set_config('test.payment_stale', v_payment_stale::text, false);
  PERFORM set_config('test.payment_bad_amt', v_payment_bad_amt::text, false);
  PERFORM set_config('test.payment_bad_method', v_payment_bad_method::text, false);
  PERFORM set_config('test.payment_cancel', v_payment_cancel::text, false);
  PERFORM set_config('test.payment_s002', v_payment_s002::text, false);
  PERFORM set_config('test.payment_s003', v_payment_s003::text, false);
  PERFORM set_config('test.payment_s004', v_payment_s004::text, false);
  PERFORM set_config('test.payment_s005', v_payment_s005::text, false);
  PERFORM set_config('test.payment_s006', v_payment_s006::text, false);
  PERFORM set_config('test.payment_s007', v_payment_s007::text, false);
  PERFORM set_config('test.payment_s008_a', v_payment_s008_a::text, false);
  PERFORM set_config('test.payment_s008_b', v_payment_s008_b::text, false);
  PERFORM set_config('test.pass_s002_002', v_pass_s002_002::text, false);
  PERFORM set_config('test.pass_s003_001', v_pass_s003_001::text, false);
  PERFORM set_config('test.pass_s005_active', v_pass_s005_active::text, false);
  PERFORM set_config('test.lesson_s006_last', v_lesson_s006_last::text, false);
  PERFORM set_config('test.sms_s006_sent', v_sms_s006_sent::text, false);
  PERFORM set_config('test.slot_s003', v_slot_s003::text, false);
  PERFORM set_config('test.student_s007', v_student_s007::text, false);
  PERFORM set_config('test.pass_s009_reserved', v_pass_s009_reserved::text, false);
  PERFORM set_config('test.lesson_s009_1', v_lesson_s009_1::text, false);
  PERFORM set_config('test.lesson_s009_2', v_lesson_s009_2::text, false);
  PERFORM set_config('test.lesson_s009_3', v_lesson_s009_3::text, false);
  PERFORM set_config('test.lesson_s009_4', v_lesson_s009_4::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.test_auth_as(p_user uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  SET ROLE authenticated;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.test_reset_role()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM set_config('request.jwt.claim.role', '', false);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.reve_payment_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_complete_payment_and_renew_pass(uuid,timestamptz,integer,text,timestamptz,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.reve_activate_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_activate_reserved_pass(uuid,timestamptz,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.payment_updated_at(p_payment uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.payments WHERE id = p_payment;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count()
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs;
$$;

-- ---------------------------------------------------------------------------
-- Function existence, contracts, security
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_complete_payment_and_renew_pass',
  ARRAY['uuid', 'timestamptz', 'integer', 'text', 'timestamptz', 'text']
);
SELECT has_function(
  'public', 'reve_activate_reserved_pass',
  ARRAY['uuid', 'timestamptz', 'text']
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_complete_payment_and_renew_pass'
      AND p.proargnames @> ARRAY[
        'p_payment_id', 'p_expected_payment_updated_at', 'p_paid_amount_krw',
        'p_payment_method', 'p_paid_at', 'p_idempotency_key'
      ]
  ),
  'reve_complete_payment_and_renew_pass has explicit argument contract'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_activate_reserved_pass'
      AND p.proargnames @> ARRAY[
        'p_reserved_pass_id', 'p_expected_pass_updated_at', 'p_reason'
      ]
  ),
  'reve_activate_reserved_pass has explicit argument contract'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname IN (
        'reve_complete_payment_and_renew_pass',
        'reve_activate_reserved_pass'
      )
      AND (
        pg_get_function_result(p.oid) LIKE '%payments%'
        OR pg_get_function_result(p.oid) LIKE '%passes%'
      )
  ),
  'payment renewal RPC functions do not return base-table row types'
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname IN (
        'reve_complete_payment_and_renew_pass',
        'reve_activate_reserved_pass'
      )
  ),
  'payment renewal RPC functions use fixed empty search_path'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.reve_payment_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_complete_payment_and_renew_pass'
);
SELECT ok(
  NOT has_function_privilege('public', pg_temp.reve_activate_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_activate_reserved_pass'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_s003')::uuid,
       now(), 200000, 'cash', now(), 'anon-key') $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_activate_reserved_pass(
       '66666666-6666-6666-6666-666666666603'::uuid, now(), NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;
SELECT ok(
  has_function_privilege('authenticated', pg_temp.reve_payment_sig(), 'EXECUTE'),
  'authenticated may execute reve_complete_payment_and_renew_pass'
);
SELECT ok(
  has_function_privilege('authenticated', pg_temp.reve_activate_sig(), 'EXECUTE'),
  'authenticated may execute reve_activate_reserved_pass'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_s003')::uuid,
       now(), 200000, 'cash', now(), 'student-key') $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_activate_reserved_pass(
       '66666666-6666-6666-6666-666666666603'::uuid, now(), NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_s003')::uuid,
       now(), 200000, 'cash', now(), 'teacher-key') $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_activate_reserved_pass(
       '66666666-6666-6666-6666-666666666603'::uuid, now(), NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ---------------------------------------------------------------------------
-- Payment completion validation failures
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_stale')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       200000, 'cash', now(), 'idem-pay-stale') $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_bad_amt')::uuid,
       pg_temp.payment_updated_at(current_setting('test.payment_bad_amt')::uuid),
       199999, 'cash', now(), 'idem-pay-bad-amt') $$,
  'P0001',
  'REVE_PAYMENT_AMOUNT_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_bad_method')::uuid,
       pg_temp.payment_updated_at(current_setting('test.payment_bad_method')::uuid),
       200000, 'wire', now(), 'idem-pay-bad-method') $$,
  'P0001',
  'REVE_INVALID_PAYMENT_METHOD'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_cancel')::uuid,
       pg_temp.payment_updated_at(current_setting('test.payment_cancel')::uuid),
       200000, 'cash', now(), 'idem-pay-cancel') $$,
  'P0001',
  'REVE_PAYMENT_NOT_COMPLETABLE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_s005')::uuid,
       pg_temp.payment_updated_at(current_setting('test.payment_s005')::uuid),
       200000, 'bank_transfer', now(), 'idem-pay-s005') $$,
  'P0001',
  'REVE_RESERVED_EXISTS'
);

-- ---------------------------------------------------------------------------
-- No active pass → active immediately (S003, 4-lesson product)
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT payment_status = 'completed'
      AND new_pass_status = 'active'
      AND new_pass_public_code = 'V-S003-002'
      AND new_pass_sequence = 2
      AND registered_lesson_count = 4
      AND lesson_rows_created = 4
      AND activation_required = false
      AND idempotent_replay = false
    FROM public.reve_complete_payment_and_renew_pass(
      current_setting('test.payment_s003')::uuid,
      pg_temp.payment_updated_at(current_setting('test.payment_s003')::uuid),
      200000, 'card', now() - interval '1 hour', 'idem-pay-s003'
    )
    LIMIT 1
  ),
  'owner completes payment and creates active pass when no active pass exists'
);

SELECT ok(
  (
    SELECT status = 'completed'
      AND renewed_pass_id IS NOT NULL
      AND payment_method = 'card'
    FROM public.payments
    WHERE id = current_setting('test.payment_s003')::uuid
  ),
  'payment row marked completed and linked to renewed pass'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = (
     SELECT renewed_pass_id FROM public.payments
     WHERE id = current_setting('test.payment_s003')::uuid
   )) = 4,
  'four-lesson product creates four scheduled lessons on active pass'
);

-- ---------------------------------------------------------------------------
-- Schedule slots copied; source pass unchanged
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT count(*)::integer FROM public.schedule_slots
    WHERE pass_id = (
      SELECT renewed_pass_id FROM public.payments
      WHERE id = current_setting('test.payment_s003')::uuid
    )
  ) >= 1,
  'renewed pass receives copied schedule slots'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.schedule_slots AS src
    JOIN public.schedule_slots AS copied
      ON src.weekday = copied.weekday
     AND src.local_start_time = copied.local_start_time
     AND src.duration_minutes = copied.duration_minutes
     AND src.teacher_id = copied.teacher_id
    WHERE src.id = current_setting('test.slot_s003')::uuid
      AND copied.pass_id = (
        SELECT renewed_pass_id FROM public.payments
        WHERE id = current_setting('test.payment_s003')::uuid
      )
  ),
  'copied schedule slot matches source weekday time and teacher'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.schedule_slots
   WHERE pass_id = current_setting('test.pass_s003_001')::uuid) = 1,
  'source pass schedule slots remain unchanged after renewal'
);

-- ---------------------------------------------------------------------------
-- Active with remaining → reserved; lesson shells at payment time
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_new_pass uuid;
BEGIN
  SELECT new_pass_id
  INTO v_new_pass
  FROM public.reve_complete_payment_and_renew_pass(
    current_setting('test.payment_s002')::uuid,
    pg_temp.payment_updated_at(current_setting('test.payment_s002')::uuid),
    200000, 'cash', now(), 'idem-pay-s002'
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s002_reserved', v_new_pass::text, false);
END $$;

SELECT ok(
  (
    SELECT p.status = 'reserved'
      AND p.pass_code = 'V-S002-003'
      AND p.sequence_number = 3
      AND (SELECT count(*)::integer FROM public.lessons AS l
           WHERE l.pass_id = p.id) = 4
      AND (SELECT count(*)::integer FROM public.lessons AS l
           WHERE l.pass_id = p.id AND l.scheduled_at IS NULL) = 4
      AND (SELECT count(*)::integer FROM public.schedule_slots AS ss
           WHERE ss.pass_id = p.id) >= 1
    FROM public.passes AS p
    WHERE p.id = current_setting('test.pass_s002_reserved')::uuid
  ),
  'active pass with remaining lessons yields reserved next pass with four lesson shells'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_s002_reserved')::uuid
     AND scheduled_at IS NULL) = 4,
  'reserved pass lesson shells have pending scheduled_at after payment completion'
);

-- ---------------------------------------------------------------------------
-- Manual reserved activation (no active pass; simulates post-payment reserved)
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT new_status = 'active'
      AND previous_status = 'reserved'
      AND lessons_scheduled = 4
      AND idempotent_replay = false
    FROM public.reve_activate_reserved_pass(
      current_setting('test.pass_s009_reserved')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_s009_reserved')::uuid),
      'Owner manual activation'
    )
    LIMIT 1
  ),
  'owner manual activation finalizes schedules on existing reserved lesson shells'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_s009_reserved')::uuid
     AND scheduled_at IS NOT NULL) = 4,
  'manual activation assigns scheduled_at to four existing reserved lesson shells'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lessons
    WHERE pass_id = current_setting('test.pass_s009_reserved')::uuid
      AND id NOT IN (
        current_setting('test.lesson_s009_1')::uuid,
        current_setting('test.lesson_s009_2')::uuid,
        current_setting('test.lesson_s009_3')::uuid,
        current_setting('test.lesson_s009_4')::uuid
      )
  ),
  'manual activation inserts no additional lesson rows'
);

-- ---------------------------------------------------------------------------
-- Eight-lesson product
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT lesson_rows_created = 8
      AND registered_lesson_count = 8
      AND new_pass_public_code = 'P-S004-002'
    FROM public.reve_complete_payment_and_renew_pass(
      current_setting('test.payment_s004')::uuid,
      pg_temp.payment_updated_at(current_setting('test.payment_s004')::uuid),
      400000, 'bank_transfer', now(), 'idem-pay-s004'
    )
    LIMIT 1
  ),
  'eight-lesson piano product creates eight lessons on active pass'
);

-- ---------------------------------------------------------------------------
-- Pass sequence increment V-S008-001 → 002 → 003
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_pass_002 uuid;
  r record;
BEGIN
  SELECT new_pass_id
  INTO v_pass_002
  FROM public.reve_complete_payment_and_renew_pass(
    current_setting('test.payment_s008_a')::uuid,
    pg_temp.payment_updated_at(current_setting('test.payment_s008_a')::uuid),
    200000, 'cash', now() - interval '2 days', 'idem-pay-s008-a'
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s008_002', v_pass_002::text, false);

  FOR r IN
    SELECT l.id, l.updated_at
    FROM public.lessons AS l
    WHERE l.pass_id = v_pass_002 AND l.status = 'scheduled'
    ORDER BY l.sequence_number
  LOOP
    PERFORM public.reve_transition_lesson_status(
      r.id, 'completed', r.updated_at,
      now() - interval '1 hour', now(), NULL
    );
  END LOOP;
END $$;

SELECT ok(
  (SELECT pass_code FROM public.passes
   WHERE id = current_setting('test.pass_s008_002')::uuid) = 'V-S008-002',
  'first renewal increments pass sequence to V-S008-002'
);

SELECT ok(
  (
    SELECT new_pass_public_code = 'V-S008-003'
      AND new_pass_sequence = 3
      AND new_pass_status = 'active'
    FROM public.reve_complete_payment_and_renew_pass(
      current_setting('test.payment_s008_b')::uuid,
      pg_temp.payment_updated_at(current_setting('test.payment_s008_b')::uuid),
      200000, 'other', now() + interval '60 days', 'idem-pay-s008-b'
    )
    LIMIT 1
  ),
  'second renewal increments pass sequence to V-S008-003'
);

-- ---------------------------------------------------------------------------
-- Idempotency replay
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_before_passes bigint;
  v_before_lessons bigint;
  v_before_sms bigint;
  v_before_audit bigint;
  v_new_pass uuid;
BEGIN
  SELECT new_pass_id INTO v_new_pass
  FROM public.reve_complete_payment_and_renew_pass(
    current_setting('test.payment_s007')::uuid,
    pg_temp.payment_updated_at(current_setting('test.payment_s007')::uuid),
    200000, 'cash', now(), 'idem-pay-s007'
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s007_new', v_new_pass::text, false);

  SELECT count(*) INTO v_before_passes FROM public.passes
  WHERE student_id = current_setting('test.student_s007')::uuid;
  SELECT count(*) INTO v_before_lessons FROM public.lessons
  WHERE pass_id = v_new_pass;
  SELECT count(*) INTO v_before_sms FROM public.sms_notifications
  WHERE pass_id = v_new_pass;
  v_before_audit := pg_temp.audit_count();

  PERFORM set_config('test.idem_passes', v_before_passes::text, false);
  PERFORM set_config('test.idem_lessons', v_before_lessons::text, false);
  PERFORM set_config('test.idem_sms', v_before_sms::text, false);
  PERFORM set_config('test.idem_audit', v_before_audit::text, false);
END $$;

SELECT ok(
  (
    SELECT idempotent_replay = true
      AND payment_status = 'completed'
    FROM public.reve_complete_payment_and_renew_pass(
      current_setting('test.payment_s007')::uuid,
      pg_temp.payment_updated_at(current_setting('test.payment_s007')::uuid),
      200000, 'cash', now(), 'idem-pay-s007'
    )
    LIMIT 1
  ),
  'idempotent payment replay returns replay indicator'
);

SELECT ok(
  (SELECT count(*) FROM public.passes
   WHERE student_id = current_setting('test.student_s007')::uuid)
   = current_setting('test.idem_passes')::bigint,
  'idempotent replay creates no duplicate pass'
);

SELECT ok(
  (SELECT count(*) FROM public.lessons
   WHERE pass_id = current_setting('test.pass_s007_new')::uuid)
   = current_setting('test.idem_lessons')::bigint,
  'idempotent replay creates no duplicate lessons'
);

SELECT ok(
  (SELECT count(*) FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_s007_new')::uuid)
   = current_setting('test.idem_sms')::bigint,
  'idempotent replay creates no duplicate SMS row'
);

SELECT ok(
  pg_temp.audit_count() = current_setting('test.idem_audit')::bigint,
  'idempotent replay adds no new audit rows'
);

-- ---------------------------------------------------------------------------
-- SMS initialization and sent history preservation
-- ---------------------------------------------------------------------------
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.sms_notifications AS sn
    WHERE sn.pass_id = current_setting('test.pass_s007_new')::uuid
      AND sn.status = 'normal'
      AND sn.message_body_snapshot LIKE '회차권 갱신 안내: 잔여 4회'
  ),
  'new pass SMS initialized with renewal template for registered count'
);

SELECT ok(
  (SELECT status FROM public.sms_notifications
   WHERE id = current_setting('test.sms_s006_sent')::uuid) = 'sent',
  'prior sent SMS history remains sent after unrelated renewals'
);

-- ---------------------------------------------------------------------------
-- Auto activation on final lesson transition
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_reserved uuid;
BEGIN
  SELECT new_pass_id INTO v_reserved
  FROM public.reve_complete_payment_and_renew_pass(
    current_setting('test.payment_s006')::uuid,
    pg_temp.payment_updated_at(current_setting('test.payment_s006')::uuid),
    200000, 'cash', now(), 'idem-pay-s006'
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s006_reserved', v_reserved::text, false);
END $$;

SELECT ok(
  (SELECT status FROM public.passes
   WHERE id = current_setting('test.pass_s006_reserved')::uuid) = 'reserved',
  'renewal while active pass remains creates reserved pass for auto activation'
);

SELECT ok(
  (
    SELECT pass_status = 'completed'
      AND reserved_pass_activation_pending = false
    FROM public.reve_transition_lesson_status(
      current_setting('test.lesson_s006_last')::uuid,
      'completed',
      pg_temp.lesson_updated_at(current_setting('test.lesson_s006_last')::uuid),
      now() - interval '1 hour',
      now(),
      NULL
    )
    LIMIT 1
  ),
  'final deductible lesson completes active pass and auto-activates reserved pass'
);

SELECT ok(
  (SELECT status FROM public.passes
   WHERE id = current_setting('test.pass_s006_reserved')::uuid) = 'active',
  'reserved pass becomes active after automatic activation'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_s006_reserved')::uuid
     AND scheduled_at IS NOT NULL) = 4,
  'automatic activation finalizes scheduled_at on four existing reserved lesson shells'
);

-- ---------------------------------------------------------------------------
-- Audit correlation on payment completion
-- ---------------------------------------------------------------------------
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'payment.completed'
      AND resource_table = 'payments'
      AND resource_id = current_setting('test.payment_s003')::uuid
      AND correlation_id IS NOT NULL
  ),
  'payment completion writes audit row with correlation identifier'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.audit_logs AS pay
    JOIN public.audit_logs AS pass
      ON pass.correlation_id = pay.correlation_id
    WHERE pay.action = 'payment.completed'
      AND pay.resource_id = current_setting('test.payment_s003')::uuid
      AND pass.action = 'pass.created_by_payment'
  ),
  'pass creation audit shares correlation with payment completion audit'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();
ROLLBACK;

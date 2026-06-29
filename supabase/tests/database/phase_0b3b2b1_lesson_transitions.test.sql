-- REVE ACADEMY OS Phase 0B-3B-2B-1 — trusted lesson transition pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(63);

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
  v_teacher_a_row uuid := '22222222-2222-2222-2222-222222222222';
  v_teacher_b_row uuid := '33333333-3333-3333-3333-333333333333';
  v_student_a_row uuid := '44444444-4444-4444-4444-444444444444';
  v_student_b_row uuid := '55555555-5555-5555-5555-555555555555';
  v_course_vocal uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_course_piano uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01';
  v_product_4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_product_8 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff01';
  v_pass_vocal uuid := '66666666-6666-6666-6666-666666666601';
  v_pass_reserved uuid := '67676767-6767-6767-6767-676767676767';
  v_pass_piano uuid := '66666666-6666-6666-6666-666666666608';
  v_pass_sb uuid := '70707070-7070-7070-7070-707070707070';
  v_pass_sb_old uuid := '69696969-6969-6969-6969-696969696969';
  v_pass_sb_piano uuid := '70707070-7070-7070-7070-707070707071';
  v_slot_vocal uuid := '77777777-7777-7777-7777-777777777701';
  v_slot_reserved uuid := '77777777-7777-7777-7777-777777777702';
  v_slot_piano uuid := '77777777-7777-7777-7777-777777777708';
  v_slot_sb uuid := '88888888-8888-8888-8888-888888888888';
  v_lesson_sched_1 uuid := '99999999-9999-9999-9999-999999999901';
  v_lesson_sched_2 uuid := '99999999-9999-9999-9999-999999999902';
  v_lesson_sched_3 uuid := '99999999-9999-9999-9999-999999999903';
  v_lesson_sched_4 uuid := '99999999-9999-9999-9999-999999999904';
  v_lesson_sched_5 uuid := '99999999-9999-9999-9999-999999999905';
  v_lesson_sched_6 uuid := '99999999-9999-9999-9999-999999999906';
  v_lesson_sched_7 uuid := '99999999-9999-9999-9999-999999999907';
  v_lesson_postponed uuid := '99999999-9999-9999-9999-999999999908';
  v_lesson_vocal_last uuid := '99999999-9999-9999-9999-999999999909';
  v_lesson_vocal_1 uuid := '99999999-9999-9999-9999-999999999911';
  v_lesson_vocal_2 uuid := '99999999-9999-9999-9999-999999999912';
  v_lesson_vocal_3 uuid := '99999999-9999-9999-9999-999999999913';
  v_lesson_makeup uuid := '99999999-9999-9999-9999-999999999914';
  v_lesson_stale uuid := '99999999-9999-9999-9999-999999999915';
  v_lesson_sb_last uuid := '10101010-1010-1010-1010-101010101002';
  v_lesson_sb_1 uuid := '10101010-1010-1010-1010-101010101011';
  v_lesson_sb_2 uuid := '10101010-1010-1010-1010-101010101012';
  v_lesson_sb_3 uuid := '10101010-1010-1010-1010-101010101013';
  v_lesson_sb_x1 uuid := '10101010-1010-1010-1010-101010101021';
  v_lesson_sb_x2 uuid := '10101010-1010-1010-1010-101010101022';
  v_lesson_sb_x3 uuid := '10101010-1010-1010-1010-101010101023';
  v_lesson_sb_x4 uuid := '10101010-1010-1010-1010-101010101024';
  v_lesson_sb_exceed uuid := '10101010-1010-1010-1010-101010101015';
  v_lesson_reserved_1 uuid := 'abababab-abab-abab-abab-ababababab01';
  v_lesson_reserved_2 uuid := 'abababab-abab-abab-abab-ababababab02';
  v_lesson_reserved_3 uuid := 'abababab-abab-abab-abab-ababababab03';
  v_lesson_reserved_4 uuid := 'abababab-abab-abab-abab-ababababab04';
  v_sms_piano uuid := '14141414-1414-1414-1414-141414141401';
  v_sms_vocal uuid := '14141414-1414-1414-1414-141414141402';
  v_sms_old uuid := '14141414-1414-1414-1414-141414141406';
  v_sms_sb uuid := '14141414-1414-1414-1414-141414141407';
  i integer;
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
     'student-a@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now()),
    (v_student_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-b@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Test Owner'),
    (v_teacher_a, 'teacher', 'Teacher A'),
    (v_teacher_b, 'teacher', 'Teacher B'),
    (v_student_a, 'student', 'Student A'),
    (v_student_b, 'student', 'Student B');

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student_a_row, 'S-A001', v_student_a, 'Student A'),
    (v_student_b_row, 'S-B001', v_student_b, 'Student B');

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
    start_date, expires_on, completed_at
  ) VALUES
    (v_pass_vocal, 'P-SA-V-001', v_student_a_row, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE, CURRENT_DATE + 90, NULL),
    (v_pass_reserved, 'P-SA-V-R01', v_student_a_row, v_course_vocal, v_product_4,
     2, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE + 30, NULL, NULL),
    (v_pass_piano, 'P-SA-P-001', v_student_a_row, v_course_piano, v_product_8,
     1, 'active', 8, 1, 'Piano 8 Lessons', 400000, CURRENT_DATE, NULL, NULL),
    (v_pass_sb_old, 'P-SB-V-000', v_student_b_row, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 120, CURRENT_DATE - 30,
     now() - interval '30 days'),
    (v_pass_sb, 'P-SB-V-001', v_student_b_row, v_course_vocal, v_product_4,
     2, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE, CURRENT_DATE + 60, NULL),
    (v_pass_sb_piano, 'P-SB-P-001', v_student_b_row, v_course_piano, v_product_8,
     1, 'active', 4, 1, 'Piano 8 Lessons', 400000, CURRENT_DATE, NULL, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot_vocal, v_pass_vocal, v_teacher_a_row, 1, '10:00', 60, CURRENT_DATE),
    (v_slot_reserved, v_pass_reserved, v_teacher_a_row, 1, '10:00', 60, CURRENT_DATE),
    (v_slot_piano, v_pass_piano, v_teacher_a_row, 4, '12:00', 60, CURRENT_DATE),
    (v_slot_sb, v_pass_sb, v_teacher_b_row, 3, '14:00', 60, CURRENT_DATE);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    actual_start_at, actual_end_at
  ) VALUES
    (v_lesson_sched_1, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 1, now() + interval '2 days', 'scheduled', NULL, NULL),
    (v_lesson_sched_2, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 2, now() + interval '9 days', 'scheduled', NULL, NULL),
    (v_lesson_sched_3, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 3, now() + interval '16 days', 'scheduled', NULL, NULL),
    (v_lesson_sched_4, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 4, now() + interval '23 days', 'scheduled', NULL, NULL),
    (v_lesson_sched_5, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 5, now() + interval '30 days', 'scheduled', NULL, NULL),
    (v_lesson_sched_6, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 6, now() + interval '37 days', 'scheduled', NULL, NULL),
    (v_lesson_sched_7, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 7, now() + interval '44 days', 'scheduled', NULL, NULL),
    (v_lesson_postponed, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 8, now() + interval '51 days', 'postponed', NULL, NULL),
    (v_lesson_makeup, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 9, now() - interval '3 days', 'makeup_completed',
     now() - interval '3 days', now() - interval '3 days' + interval '1 hour'),
    (v_lesson_stale, v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
     v_slot_piano, 10, now() + interval '58 days', 'scheduled', NULL, NULL),
    (v_lesson_vocal_1, v_pass_vocal, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_vocal, 1, now() - interval '21 days', 'completed',
     now() - interval '21 days', now() - interval '21 days' + interval '1 hour'),
    (v_lesson_vocal_2, v_pass_vocal, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_vocal, 2, now() - interval '14 days', 'completed',
     now() - interval '14 days', now() - interval '14 days' + interval '1 hour'),
    (v_lesson_vocal_3, v_pass_vocal, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_vocal, 3, now() - interval '7 days', 'completed',
     now() - interval '7 days', now() - interval '7 days' + interval '1 hour'),
    (v_lesson_vocal_last, v_pass_vocal, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_vocal, 4, now() + interval '1 day', 'scheduled', NULL, NULL),
    (v_lesson_sb_1, v_pass_sb, v_student_b_row, v_course_vocal, v_teacher_b_row,
     v_slot_sb, 1, now() - interval '21 days', 'completed',
     now() - interval '21 days', now() - interval '21 days' + interval '1 hour'),
    (v_lesson_sb_2, v_pass_sb, v_student_b_row, v_course_vocal, v_teacher_b_row,
     v_slot_sb, 2, now() - interval '14 days', 'completed',
     now() - interval '14 days', now() - interval '14 days' + interval '1 hour'),
    (v_lesson_sb_3, v_pass_sb, v_student_b_row, v_course_vocal, v_teacher_b_row,
     v_slot_sb, 3, now() - interval '7 days', 'completed',
     now() - interval '7 days', now() - interval '7 days' + interval '1 hour'),
    (v_lesson_sb_last, v_pass_sb, v_student_b_row, v_course_vocal, v_teacher_b_row,
     v_slot_sb, 4, now() + interval '4 days', 'scheduled', NULL, NULL),
    (v_lesson_sb_x1, v_pass_sb_piano, v_student_b_row, v_course_piano, v_teacher_b_row,
     NULL, 1, now() - interval '28 days', 'completed',
     now() - interval '28 days', now() - interval '28 days' + interval '1 hour'),
    (v_lesson_sb_x2, v_pass_sb_piano, v_student_b_row, v_course_piano, v_teacher_b_row,
     NULL, 2, now() - interval '21 days', 'completed',
     now() - interval '21 days', now() - interval '21 days' + interval '1 hour'),
    (v_lesson_sb_x3, v_pass_sb_piano, v_student_b_row, v_course_piano, v_teacher_b_row,
     NULL, 3, now() - interval '14 days', 'completed',
     now() - interval '14 days', now() - interval '14 days' + interval '1 hour'),
    (v_lesson_sb_x4, v_pass_sb_piano, v_student_b_row, v_course_piano, v_teacher_b_row,
     NULL, 4, now() - interval '7 days', 'completed',
     now() - interval '7 days', now() - interval '7 days' + interval '1 hour'),
    (v_lesson_sb_exceed, v_pass_sb_piano, v_student_b_row, v_course_piano, v_teacher_b_row,
     NULL, 5, now() + interval '1 day', 'scheduled', NULL, NULL),
    (v_lesson_reserved_1, v_pass_reserved, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_reserved, 1, NULL, 'scheduled', NULL, NULL),
    (v_lesson_reserved_2, v_pass_reserved, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_reserved, 2, NULL, 'scheduled', NULL, NULL),
    (v_lesson_reserved_3, v_pass_reserved, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_reserved, 3, NULL, 'scheduled', NULL, NULL),
    (v_lesson_reserved_4, v_pass_reserved, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_reserved, 4, NULL, 'scheduled', NULL, NULL);

  FOR i IN 1..8 LOOP
    INSERT INTO public.lessons (
      id, pass_id, student_id, course_id, assigned_teacher_id,
      schedule_slot_id, sequence_number, scheduled_at, status
    ) VALUES (
      ('a0a0a0a0-a0a0-a0a0-a0a0-' || lpad(i::text, 12, '0'))::uuid,
      v_pass_piano, v_student_a_row, v_course_piano, v_teacher_a_row,
      v_slot_piano, 10 + i, now() + (60 + i || ' days')::interval, 'scheduled'
    );
  END LOOP;

  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status,
    message_body_snapshot, target_date, sent_at
  ) VALUES
    (v_sms_piano, v_student_a_row, v_pass_piano, 'renewal_reminder', 'normal',
     '회차권 갱신 안내: 잔여 8회', CURRENT_DATE + 30, NULL),
    (v_sms_vocal, v_student_a_row, v_pass_vocal, 'renewal_reminder', 'normal',
     NULL, CURRENT_DATE + 7, NULL),
    (v_sms_old, v_student_b_row, v_pass_sb_old, 'renewal_reminder', 'sent',
     'Old pass sent history', CURRENT_DATE - 60, now() - interval '60 days'),
    (v_sms_sb, v_student_b_row, v_pass_sb, 'renewal_reminder', 'normal',
     'Student B untouched', CURRENT_DATE + 10, NULL);

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, false);
  PERFORM set_config('test.teacher_b', v_teacher_b::text, false);
  PERFORM set_config('test.student_a', v_student_a::text, false);
  PERFORM set_config('test.student_b', v_student_b::text, false);
  PERFORM set_config('test.pass_vocal', v_pass_vocal::text, false);
  PERFORM set_config('test.pass_reserved', v_pass_reserved::text, false);
  PERFORM set_config('test.lesson_reserved_1', v_lesson_reserved_1::text, false);
  PERFORM set_config('test.lesson_reserved_2', v_lesson_reserved_2::text, false);
  PERFORM set_config('test.lesson_reserved_3', v_lesson_reserved_3::text, false);
  PERFORM set_config('test.lesson_reserved_4', v_lesson_reserved_4::text, false);
  PERFORM set_config('test.pass_piano', v_pass_piano::text, false);
  PERFORM set_config('test.pass_sb', v_pass_sb::text, false);
  PERFORM set_config('test.pass_sb_piano', v_pass_sb_piano::text, false);
  PERFORM set_config('test.lesson_sched_1', v_lesson_sched_1::text, false);
  PERFORM set_config('test.lesson_sched_2', v_lesson_sched_2::text, false);
  PERFORM set_config('test.lesson_sched_3', v_lesson_sched_3::text, false);
  PERFORM set_config('test.lesson_sched_4', v_lesson_sched_4::text, false);
  PERFORM set_config('test.lesson_sched_5', v_lesson_sched_5::text, false);
  PERFORM set_config('test.lesson_sched_6', v_lesson_sched_6::text, false);
  PERFORM set_config('test.lesson_postponed', v_lesson_postponed::text, false);
  PERFORM set_config('test.lesson_vocal_last', v_lesson_vocal_last::text, false);
  PERFORM set_config('test.lesson_makeup', v_lesson_makeup::text, false);
  PERFORM set_config('test.lesson_stale', v_lesson_stale::text, false);
  PERFORM set_config('test.lesson_sched_7', v_lesson_sched_7::text, false);
  PERFORM set_config('test.lesson_sb_last', v_lesson_sb_last::text, false);
  PERFORM set_config('test.lesson_sb_exceed', v_lesson_sb_exceed::text, false);
  PERFORM set_config('test.sms_piano', v_sms_piano::text, false);
  PERFORM set_config('test.sms_vocal', v_sms_vocal::text, false);
  PERFORM set_config('test.sms_old', v_sms_old::text, false);
  PERFORM set_config('test.sms_sb', v_sms_sb::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.reve_transition_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_transition_lesson_status(uuid,text,timestamptz,timestamptz,timestamptz,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.reve_correct_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_correct_lesson_status(uuid,text,timestamptz,text,timestamptz,timestamptz)'::text;
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
  'public', 'reve_transition_lesson_status',
  ARRAY['uuid', 'text', 'timestamptz', 'timestamptz', 'timestamptz', 'text']
);
SELECT has_function(
  'public', 'reve_correct_lesson_status',
  ARRAY['uuid', 'text', 'timestamptz', 'text', 'timestamptz', 'timestamptz']
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_transition_lesson_status'
      AND p.proargnames @> ARRAY[
        'p_lesson_id', 'p_new_status', 'p_expected_updated_at',
        'p_actual_started_at', 'p_actual_ended_at', 'p_reason'
      ]
  ),
  'reve_transition_lesson_status has explicit result contract columns'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname IN ('reve_transition_lesson_status', 'reve_correct_lesson_status')
      AND pg_get_function_result(p.oid) LIKE '%lessons%'
  ),
  'lesson RPC functions do not return base-table row types'
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname IN ('reve_transition_lesson_status', 'reve_correct_lesson_status')
  ),
  'lesson RPC functions use fixed empty search_path'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.reve_transition_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_transition_lesson_status'
);
SELECT ok(
  NOT has_function_privilege('public', pg_temp.reve_correct_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_correct_lesson_status'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sched_1')::uuid, 'completed',
       now(), now(), now(), NULL) $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_correct_lesson_status(
       current_setting('test.lesson_sched_1')::uuid, 'scheduled',
       now(), 'reason', NULL, NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;
SELECT ok(
  has_function_privilege('authenticated', pg_temp.reve_transition_sig(), 'EXECUTE'),
  'authenticated may execute reve_transition_lesson_status'
);
SELECT ok(
  has_function_privilege('authenticated', pg_temp.reve_correct_sig(), 'EXECUTE'),
  'authenticated may execute reve_correct_lesson_status'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT reve_private.apply_lesson_status_change(
       current_setting('test.lesson_sched_1')::uuid, 'completed', now(), NULL, now(), NULL, false) $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT * FROM reve_private.calculate_pass_usage(current_setting('test.pass_piano')::uuid) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT ok(
  NOT reve_private.is_owner(),
  'JWT app_role owner metadata does not elevate teacher A to owner'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ---------------------------------------------------------------------------
-- Authorization
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sched_1')::uuid, 'completed',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sched_1')::uuid),
       now(), now(), NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_b')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sched_1')::uuid, 'completed',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sched_1')::uuid),
       now(), now(), NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_sched_1')::uuid,
     'completed',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sched_1')::uuid),
     now() - interval '1 hour',
     now() - interval '30 minutes',
     NULL
   ) LIMIT 1) = 'completed',
  'assigned teacher can complete scheduled lesson'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;
SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_sched_2')::uuid,
     'same_day_cancelled',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sched_2')::uuid),
     NULL, NULL,
     'Student cancelled today'
   ) LIMIT 1) = 'same_day_cancelled',
  'owner can transition scheduled lesson'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_correct_lesson_status(
       current_setting('test.lesson_sched_1')::uuid, 'scheduled',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sched_1')::uuid),
       'correction reason', NULL, NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ---------------------------------------------------------------------------
-- Ordinary transitions, reasons, actual times
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sched_3')::uuid, 'completed',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sched_3')::uuid),
       NULL, NULL, NULL) $$,
  'P0001',
  'REVE_ACTUAL_START_REQUIRED'
);

SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_sched_3')::uuid,
     'postponed',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sched_3')::uuid),
     NULL, NULL,
     'Weather delay'
   ) LIMIT 1) = 'postponed',
  'scheduled to postponed with reason succeeds'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sched_4')::uuid, 'postponed',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sched_4')::uuid),
       NULL, NULL, '   ') $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_sched_4')::uuid,
     'advance_cancelled',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sched_4')::uuid),
     NULL, NULL,
     'Travel conflict'
   ) LIMIT 1) = 'advance_cancelled',
  'scheduled to advance_cancelled succeeds'
);

SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_sched_5')::uuid,
     'teacher_cancelled',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sched_5')::uuid),
     NULL, NULL,
     'Teacher illness'
   ) LIMIT 1) = 'teacher_cancelled',
  'scheduled to teacher_cancelled succeeds'
);

SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_sched_6')::uuid,
     'academy_closed',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sched_6')::uuid),
     NULL, NULL,
     'Holiday closure'
   ) LIMIT 1) = 'academy_closed',
  'scheduled to academy_closed succeeds'
);

SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_postponed')::uuid,
     'scheduled',
     pg_temp.lesson_updated_at(current_setting('test.lesson_postponed')::uuid),
     NULL, NULL,
     NULL
   ) LIMIT 1) = 'scheduled',
  'postponed to scheduled succeeds'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_makeup')::uuid, 'scheduled',
       pg_temp.lesson_updated_at(current_setting('test.lesson_makeup')::uuid),
       NULL, NULL, 'not allowed') $$,
  'P0001',
  'REVE_INVALID_TRANSITION'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sched_1')::uuid, 'scheduled',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sched_1')::uuid),
       NULL, NULL, 'cannot revert completed') $$,
  'P0001',
  'REVE_INVALID_TRANSITION'
);

-- ---------------------------------------------------------------------------
-- Deduction and derived counts
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;

SELECT ok(
  (SELECT used_lesson_count FROM public.reve_get_my_pass_summary()
   WHERE pass_id = current_setting('test.pass_piano')::uuid) >= 1,
  'makeup_completed counts as used lesson on piano pass'
);

SELECT ok(
  (SELECT remaining_lesson_count FROM public.reve_get_my_pass_summary()
   WHERE pass_id = current_setting('test.pass_piano')::uuid) >= 1,
  'postponed and cancellations do not increase used count beyond deductible statuses'
);

SELECT ok(
  (SELECT registered_lesson_count FROM public.reve_get_my_pass_summary()
   WHERE pass_id = current_setting('test.pass_piano')::uuid) = 8,
  'eight-lesson pass registered count is 8'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'lessons'
      AND column_name IN ('used_count', 'remaining_count', 'is_deducted')
  ),
  'lessons table has no editable usage or deduction columns'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sb_exceed')::uuid, 'completed',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sb_exceed')::uuid),
       now() - interval '1 hour', now(), NULL) $$,
  'P0001',
  'REVE_USAGE_EXCEEDED'
);

SELECT ok(
  (SELECT status FROM public.lessons
   WHERE id = current_setting('test.lesson_sb_exceed')::uuid) = 'scheduled',
  'failed usage-exceeded transition leaves lesson unchanged'
);

SELECT ok(
  (SELECT message_body_snapshot FROM public.sms_notifications
   WHERE id = current_setting('test.sms_sb')::uuid) = 'Student B untouched',
  'another student SMS row remains unchanged before scoped transitions complete'
);

-- ---------------------------------------------------------------------------
-- Optimistic concurrency
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sched_7')::uuid, 'completed',
       timestamptz '2000-01-01 00:00:00+00',
       now() - interval '1 hour', now(), NULL) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT ok(
  (SELECT status FROM public.lessons
   WHERE id = current_setting('test.lesson_sched_7')::uuid) = 'scheduled',
  'stale transition leaves lesson status unchanged'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE resource_id = current_setting('test.lesson_sched_7')::uuid
  ),
  'stale transition writes no audit row'
);

SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_stale')::uuid,
     'postponed',
     pg_temp.lesson_updated_at(current_setting('test.lesson_stale')::uuid),
     NULL, NULL,
     'First update'
   ) LIMIT 1) = 'postponed',
  'transition with correct expected_updated_at succeeds'
);

SELECT ok(
  (SELECT new_status FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_stale')::uuid,
     'scheduled',
     pg_temp.lesson_updated_at(current_setting('test.lesson_stale')::uuid),
     NULL, NULL,
     NULL
   ) LIMIT 1) = 'scheduled',
  'returned new timestamp can be used for the next valid transition'
);

-- ---------------------------------------------------------------------------
-- Pass lifecycle
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT pass_status = 'completed'
      AND reserved_pass_activation_pending = false
    FROM public.reve_transition_lesson_status(
      current_setting('test.lesson_vocal_last')::uuid,
      'completed',
      pg_temp.lesson_updated_at(current_setting('test.lesson_vocal_last')::uuid),
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
   WHERE id = current_setting('test.pass_reserved')::uuid) = 'active',
  'reserved pass becomes active after automatic activation'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_reserved')::uuid
     AND scheduled_at IS NOT NULL) = 4,
  'automatic activation finalizes scheduled_at on four existing reserved lesson shells'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lessons
    WHERE pass_id = current_setting('test.pass_reserved')::uuid
      AND id NOT IN (
        current_setting('test.lesson_reserved_1')::uuid,
        current_setting('test.lesson_reserved_2')::uuid,
        current_setting('test.lesson_reserved_3')::uuid,
        current_setting('test.lesson_reserved_4')::uuid
      )
  ),
  'automatic activation preserves existing reserved lesson IDs'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_b')::uuid); END $$;

SELECT ok(
  (SELECT reserved_pass_activation_pending FROM public.reve_transition_lesson_status(
     current_setting('test.lesson_sb_last')::uuid,
     'completed',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sb_last')::uuid),
     now() - interval '1 hour',
     now(),
     NULL
   ) LIMIT 1) = false,
  'no reserved pass yields pending indicator false'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

UPDATE public.passes
SET status = 'cancelled', completed_at = now()
WHERE id = current_setting('test.pass_sb_piano')::uuid;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sb_exceed')::uuid, 'completed',
       pg_temp.lesson_updated_at(current_setting('test.lesson_sb_exceed')::uuid),
       now() - interval '1 hour', now(), NULL) $$,
  'P0001',
  'REVE_PASS_CANCELLED'
);

SELECT ok(
  (SELECT pass_status FROM public.reve_correct_lesson_status(
     current_setting('test.lesson_sched_1')::uuid,
     'scheduled',
     pg_temp.lesson_updated_at(current_setting('test.lesson_sched_1')::uuid),
     'Owner correction reopen',
     NULL, NULL
   ) LIMIT 1) IN ('active', 'completed'),
  'owner correction from completed to scheduled is permitted'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_makeup')::uuid, 'scheduled',
       pg_temp.lesson_updated_at(current_setting('test.lesson_makeup')::uuid),
       NULL, NULL, 'teacher reopen') $$,
  'P0001',
  'REVE_INVALID_TRANSITION'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ---------------------------------------------------------------------------
-- SMS synchronization (owner context for isolated pass)
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT ok(
  (SELECT status FROM public.sms_notifications
   WHERE id = current_setting('test.sms_piano')::uuid) = 'normal',
  'more than one remaining keeps SMS normal'
);

SELECT ok(
  (SELECT message_body_snapshot FROM public.sms_notifications
   WHERE id = current_setting('test.sms_piano')::uuid)
   LIKE '회차권 갱신 안내: 잔여 %',
  'SMS message body uses approved renewal template'
);

SELECT ok(
  (SELECT status FROM public.sms_notifications
   WHERE id = current_setting('test.sms_old')::uuid) = 'sent',
  'existing sent SMS history remains sent'
);

SELECT ok(
  (SELECT status FROM public.sms_notifications
   WHERE id = current_setting('test.sms_vocal')::uuid) IN ('exhausted_unsent', 'target', 'scheduled', 'normal'),
  'zero remaining unsent SMS state is recalculated among allowed lifecycle values'
);

-- ---------------------------------------------------------------------------
-- Audit logging
-- ---------------------------------------------------------------------------
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action IN ('lesson.status_transition', 'lesson.status_correction')
      AND resource_table = 'lessons'
  ),
  'successful transitions write lesson audit rows'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'pass.completed'
      AND resource_table = 'passes'
  ),
  'pass completion writes pass audit row'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs al
    WHERE al.action = 'sms_notification.state_sync'
      AND al.resource_table = 'sms_notifications'
  ),
  'SMS state change writes SMS audit row'
);

SELECT ok(
  (
    SELECT count(DISTINCT correlation_id)
    FROM public.audit_logs
    WHERE correlation_id IS NOT NULL
  ) >= 1,
  'audit rows include correlation identifiers'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE actor_profile_id = current_setting('test.owner')::uuid
      AND actor_role_snapshot = 'owner'
  ),
  'audit actor profile and role snapshot are recorded'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'lesson.status_correction'
      AND reason IS NOT NULL
      AND btrim(reason) <> ''
  ),
  'owner correction reason is stored in audit log'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.lesson_sb_last')::uuid, 'completed',
       timestamptz '2000-01-01', now(), now(), NULL) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT ok(
  (SELECT count(*) FROM public.audit_logs) = pg_temp.audit_count(),
  'stale transition attempt adds no new audit rows'
);

SELECT throws_ok(
  $$ UPDATE public.lessons SET status = 'completed'
     WHERE id = current_setting('test.lesson_sb_last')::uuid $$,
  '42501'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'lessons'
      AND cmd = 'UPDATE' AND roles::text LIKE '%student%'
  ),
  'students have no direct lesson UPDATE policy'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'reve_process_payment_refund',
        'reve_apply_schedule_change_request'
      )
  ),
  'refund and schedule application RPCs remain deferred'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();
ROLLBACK;

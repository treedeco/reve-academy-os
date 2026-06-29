-- REVE ACADEMY OS Phase 0B-3B-2B-3C — initial enrollment pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(85);

-- ---------------------------------------------------------------------------
-- Fixture: auth users, courses/products, students, teachers, pass-history seeds
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_owner2 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
  v_teacher_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddddda';
  v_teacher_b_auth uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddc';
  v_student_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_spoof_auth uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddb';
  v_teacher_a uuid := '22222222-2222-2222-2222-222222222221';
  v_teacher_b uuid := '33333333-3333-3333-3333-333333333331';
  v_teacher_inactive uuid := '33333333-3333-3333-3333-333333333332';
  v_course_vocal uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_course_piano uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01';
  v_product_4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_product_8 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff01';
  v_student_s001 uuid := '44444444-4444-4444-4444-444444444401';
  v_student_s002 uuid := '44444444-4444-4444-4444-444444444402';
  v_student_s003 uuid := '44444444-4444-4444-4444-444444444403';
  v_student_s004 uuid := '44444444-4444-4444-4444-444444444404';
  v_student_s005 uuid := '44444444-4444-4444-4444-444444444405';
  v_student_s006 uuid := '44444444-4444-4444-4444-444444444406';
  v_student_s007 uuid := '44444444-4444-4444-4444-444444444407';
  v_student_s008 uuid := '44444444-4444-4444-4444-444444444408';
  v_student_s009 uuid := '44444444-4444-4444-4444-444444444409';
  v_student_s010 uuid := '44444444-4444-4444-4444-444444444410';
  v_student_s011 uuid := '44444444-4444-4444-4444-444444444411';
  v_pass_s003 uuid := '66666666-6666-6666-6666-666666666603';
  v_pass_s004_active uuid := '66666666-6666-6666-6666-666666666604';
  v_pass_s004_reserved uuid := '67676767-6767-6767-6767-676767676704';
  v_pass_s005 uuid := '66666666-6666-6666-6666-666666666605';
  v_pass_s006 uuid := '66666666-6666-6666-6666-666666666606';
  v_pass_s007 uuid := '66666666-6666-6666-6666-666666666607';
  v_slot_hist uuid := '77777777-7777-7777-7777-777777777701';
  v_collision_lesson uuid := '99999999-9999-9999-9999-999999999901';
  v_collision_pass uuid := '66666666-6666-6666-6666-666666666699';
  v_collision_slot uuid := '77777777-7777-7777-7777-777777777799';
  v_collision_student uuid := '44444444-4444-4444-4444-444444444499';
  v_start_date date := '2026-07-06';
  v_enroll_date date := '2026-07-13';
  v_boundary_date date := '2026-09-08';
  v_boundary timestamptz := (v_enroll_date::timestamp AT TIME ZONE 'Asia/Seoul');
  v_collision_at timestamptz := (v_start_date::timestamp + time '10:00') AT TIME ZONE 'Asia/Seoul';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner1@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner2@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-a@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_b_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-b@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_spoof_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'spoof@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now());

  INSERT INTO public.teachers (id, teacher_code, name, phone, email, is_active) VALUES
    (v_teacher_a, 'T-ENR-A', 'Enrollment Teacher A', '010-0000-0001', 'ta-enr@test.local', true),
    (v_teacher_b, 'T-ENR-B', 'Enrollment Teacher B', '010-0000-0002', 'tb-enr@test.local', true),
    (v_teacher_inactive, 'T-INACT', 'Inactive Teacher', '010-0000-0003', 'ti-enr@test.local', false);

  INSERT INTO public.students (id, student_code, name, operational_status) VALUES
    (v_student_s001, 'S001', 'Enrollment Student S001', 'active'),
    (v_student_s002, 'S002', 'Enrollment Student S002', 'active'),
    (v_student_s003, 'S003', 'Enrollment Student S003', 'active'),
    (v_student_s004, 'S004', 'Enrollment Student S004', 'active'),
    (v_student_s005, 'S005', 'Enrollment Student S005', 'active'),
    (v_student_s006, 'S006', 'Enrollment Student S006', 'active'),
    (v_student_s007, 'S007', 'Enrollment Student S007', 'active'),
    (v_student_s008, 'S008', 'Enrollment Student S008', 'active'),
    (v_student_s009, 'S009', 'Enrollment Student S009', 'active'),
    (v_student_s010, 'S010', 'Enrollment Student S010', 'active'),
    (v_student_s011, 'S011', 'Enrollment Student S011', 'active'),
    (v_collision_student, 'S099', 'Collision Fixture Student', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course_vocal, 'VOCAL', 'Vocal Course', true),
    (v_course_piano, 'PIANO', 'Piano Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES
    (v_product_4, v_course_vocal, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000, true),
    (v_product_8, v_course_piano, 'PIANO-8', 'Piano 8 Lessons', 8, 2, 400000, true);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at, completed_at, cancelled_at
  ) VALUES
    (v_pass_s003, 'V-S003-001', v_student_s003, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date, now(), NULL, NULL),
    (v_pass_s004_active, 'V-S004-001', v_student_s004, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date, now(), NULL, NULL),
    (v_pass_s004_reserved, 'V-S004-002', v_student_s004, v_course_vocal, v_product_4,
     2, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date + 30, now(), NULL, NULL),
    (v_pass_s005, 'V-S005-001', v_student_s005, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date - 90, now() - interval '30 days',
     now() - interval '30 days', NULL),
    (v_pass_s006, 'V-S006-001', v_student_s006, v_course_vocal, v_product_4,
     1, 'cancelled', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date - 60, now() - interval '20 days',
     NULL, now() - interval '10 days'),
    (v_pass_s007, 'V-S007-001', v_student_s007, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date - 90, now() - interval '30 days',
     now() - interval '30 days', NULL),
    (v_collision_pass, 'V-S099-001', v_collision_student, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date - 30, now(), NULL, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES
    (v_slot_hist, v_pass_s005, v_teacher_a, 1, '10:00', 60, 1, true, v_start_date - 90),
    (v_collision_slot, v_collision_pass, v_teacher_a, 1, '10:00', 60, 1, true, v_start_date - 30);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    v_collision_lesson, v_collision_pass, v_collision_student, v_course_vocal, v_teacher_a,
    v_collision_slot, 1, v_collision_at, 'scheduled'
  );

  PERFORM set_config('test.owner1', v_owner1::text, false);
  PERFORM set_config('test.owner2', v_owner2::text, false);
  PERFORM set_config('test.teacher_auth', v_teacher_auth::text, false);
  PERFORM set_config('test.student_auth', v_student_auth::text, false);
  PERFORM set_config('test.spoof_auth', v_spoof_auth::text, false);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, false);
  PERFORM set_config('test.teacher_b', v_teacher_b::text, false);
  PERFORM set_config('test.teacher_inactive', v_teacher_inactive::text, false);
  PERFORM set_config('test.course_vocal', v_course_vocal::text, false);
  PERFORM set_config('test.course_piano', v_course_piano::text, false);
  PERFORM set_config('test.product_4', v_product_4::text, false);
  PERFORM set_config('test.product_8', v_product_8::text, false);
  PERFORM set_config('test.student_s001', v_student_s001::text, false);
  PERFORM set_config('test.student_s002', v_student_s002::text, false);
  PERFORM set_config('test.student_s003', v_student_s003::text, false);
  PERFORM set_config('test.student_s004', v_student_s004::text, false);
  PERFORM set_config('test.student_s005', v_student_s005::text, false);
  PERFORM set_config('test.student_s006', v_student_s006::text, false);
  PERFORM set_config('test.student_s007', v_student_s007::text, false);
  PERFORM set_config('test.student_s008', v_student_s008::text, false);
  PERFORM set_config('test.student_s009', v_student_s009::text, false);
  PERFORM set_config('test.student_s010', v_student_s010::text, false);
  PERFORM set_config('test.student_s011', v_student_s011::text, false);
  PERFORM set_config('test.collision_lesson', v_collision_lesson::text, false);
  PERFORM set_config('test.start_date', v_start_date::text, false);
  PERFORM set_config('test.enroll_date', v_enroll_date::text, false);
  PERFORM set_config('test.boundary_date', v_boundary_date::text, false);
  PERFORM set_config('test.boundary', v_boundary::text, false);
  PERFORM set_config('test.collision_at', v_collision_at::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.enroll_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_create_initial_enrollment(uuid,uuid,date,jsonb,integer,text,timestamptz,text,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count()
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_count(p_student uuid, p_course uuid DEFAULT NULL)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*)
  FROM public.passes AS p
  WHERE p.student_id = p_student
    AND (p_course IS NULL OR p.course_id = p_course);
$$;

CREATE OR REPLACE FUNCTION pg_temp.payment_count(p_student uuid)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.payments AS pay WHERE pay.student_id = p_student;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_count(p_student uuid)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.lessons AS l WHERE l.student_id = p_student;
$$;

CREATE OR REPLACE FUNCTION pg_temp.vocal_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '11:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.vocal_collision_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '10:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.isolated_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 4,
    'local_time', '15:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.boundary_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 2,
    'local_time', '09:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.piano_slots_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_a')::uuid,
      'weekday', 1,
      'local_time', '10:00',
      'duration_minutes', 60,
      'slot_order', 1
    ),
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_b')::uuid,
      'weekday', 3,
      'local_time', '14:00',
      'duration_minutes', 60,
      'slot_order', 2
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Bootstrap owner and provision second owner for inactive-owner security test
-- ---------------------------------------------------------------------------
SET ROLE service_role;
SELECT ok(
  (SELECT role FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner1')::uuid, 'First Owner'
   ) LIMIT 1) = 'owner',
  'bootstrap creates first owner profile'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT ok(
  (SELECT role FROM public.reve_owner_provision_profile(
     current_setting('test.owner2')::uuid, 'owner', 'Second Owner', NULL, NULL
   ) LIMIT 1) = 'owner',
  'second owner provisioned for inactive-owner security test'
);

-- ---------------------------------------------------------------------------
-- Security (~12)
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_owner_create_initial_enrollment',
  ARRAY['uuid', 'uuid', 'date', 'jsonb', 'integer', 'text', 'timestamptz', 'text', 'text']
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_create_initial_enrollment'
  ),
  'initial enrollment RPC uses fixed empty search_path'
);

SELECT ok(
  (
    SELECT r.rolname = 'postgres'
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_create_initial_enrollment'
  ),
  'initial enrollment RPC owned by postgres'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.enroll_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_create_initial_enrollment'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'anon-enroll-key', NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'teacher-enroll-key', NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'student-enroll-key', NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.spoof_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'spoof-enroll-key', NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner1')::uuid,
     'inactive', 'step down for inactive owner test',
     (SELECT updated_at FROM public.profiles WHERE id = current_setting('test.owner1')::uuid)
   ) LIMIT 1) = 'inactive',
  'deactivate first owner when second owner exists'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'inactive-owner-key', NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;
SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner1')::uuid,
     'active', 'reactivate first owner for remaining tests',
     (SELECT updated_at FROM public.profiles WHERE id = current_setting('test.owner1')::uuid)
   ) LIMIT 1) = 'active',
  'reactivate first owner after inactive-owner denial test'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT throws_ok(
  $$ INSERT INTO public.payments (
       student_id, course_id, course_product_id, paid_amount_krw,
       status, idempotency_key, created_by_profile_id
     ) VALUES (
       current_setting('test.student_s001')::uuid,
       current_setting('test.course_vocal')::uuid,
       current_setting('test.product_4')::uuid,
       200000, 'completed', 'direct-pay', current_setting('test.owner1')::uuid) $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.passes (
       pass_code, student_id, course_id, course_product_id,
       sequence_number, status, registered_lesson_count_snapshot,
       weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
       start_date, activated_at
     ) VALUES (
       'V-DIR-001',
       current_setting('test.student_s001')::uuid,
       current_setting('test.course_vocal')::uuid,
       current_setting('test.product_4')::uuid,
       1, 'active', 4, 1, 'Vocal 4 Lessons', 200000,
       current_date, now()) $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.schedule_slots (
       pass_id, teacher_id, weekday, local_start_time, duration_minutes,
       slot_order, is_active, effective_from
     ) VALUES (
       '66666666-6666-6666-6666-666666666603'::uuid,
       current_setting('test.teacher_a')::uuid,
       1, '10:00', 60, 1, true, current_date) $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.lessons (
       pass_id, student_id, course_id, assigned_teacher_id,
       sequence_number, scheduled_at, status
     ) VALUES (
       '66666666-6666-6666-6666-666666666603'::uuid,
       current_setting('test.student_s003')::uuid,
       current_setting('test.course_vocal')::uuid,
       current_setting('test.teacher_a')::uuid,
       99, now(), 'scheduled') $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.sms_notifications (
       student_id, pass_id, notification_type, status
     ) VALUES (
       current_setting('test.student_s003')::uuid,
       '66666666-6666-6666-6666-666666666603'::uuid,
       'renewal_reminder', 'normal') $$,
  '42501'
);

-- ---------------------------------------------------------------------------
-- Schedule validation (~12)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       '[]'::jsonb,
       200000, 'cash', now(), 'sched-empty', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_object('teacher_id', current_setting('test.teacher_a')::uuid),
       200000, 'cash', now(), 'sched-not-array', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60,
         'slot_order', 1, 'extra_field', true)),
       200000, 'cash', now(), 'sched-unknown-field', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(jsonb_build_object(
         'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1)),
       200000, 'cash', now(), 'sched-missing-teacher', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_inactive')::uuid,
         'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1)),
       200000, 'cash', now(), 'sched-inactive-teacher', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 7, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1)),
       200000, 'cash', now(), 'sched-bad-weekday', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 1, 'local_time', '10:00', 'duration_minutes', 0, 'slot_order', 1)),
       200000, 'cash', now(), 'sched-bad-duration', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 1, 'local_time', 'bad', 'duration_minutes', 60, 'slot_order', 1)),
       200000, 'cash', now(), 'sched-bad-time', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_a')::uuid,
           'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1),
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_b')::uuid,
           'weekday', 3, 'local_time', '14:00', 'duration_minutes', 60, 'slot_order', 1)),
       200000, 'cash', now(), 'sched-dup-order', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_a')::uuid,
           'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1),
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_a')::uuid,
           'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 2)),
       200000, 'cash', now(), 'sched-dup-definition', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       jsonb_build_array(
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_a')::uuid,
           'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1),
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_b')::uuid,
           'weekday', 3, 'local_time', '14:00', 'duration_minutes', 60, 'slot_order', 2)),
       200000, 'cash', now(), 'sched-count-mismatch', NULL) $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       199999, 'cash', now(), 'sched-bad-amount', NULL) $$,
  'P0001',
  'REVE_PAYMENT_AMOUNT_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s001')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'wire', now(), 'sched-bad-method', NULL) $$,
  'P0001',
  'REVE_INVALID_PAYMENT_METHOD'
);

-- ---------------------------------------------------------------------------
-- Initial enrollment success and policy (~12)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_audit_before bigint;
  v_pass_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  v_pass_before := pg_temp.pass_count(
    current_setting('test.student_s001')::uuid,
    current_setting('test.course_vocal')::uuid
  );
  PERFORM set_config('test.audit_before_s001', v_audit_before::text, false);
  PERFORM set_config('test.pass_before_s001', v_pass_before::text, false);
END $$;

DO $$
DECLARE
  v_pass_id uuid;
  v_payment_id uuid;
BEGIN
  SELECT pass_id, payment_id
  INTO v_pass_id, v_payment_id
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_s001')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.vocal_slot_json(),
    200000, 'card',
    timestamptz '2026-06-01 09:00:00+09',
    'idem-s001-initial', 'First vocal enrollment'
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s001', v_pass_id::text, false);
  PERFORM set_config('test.payment_s001', v_payment_id::text, false);
END $$;

SELECT ok(
  (
    SELECT pay.status = 'completed'
      AND p.status = 'active'
      AND p.sequence_number = 1
      AND p.pass_code = 'V-S001-001'
      AND p.registered_lesson_count_snapshot = 4
      AND (SELECT count(*)::integer FROM public.schedule_slots AS ss
           WHERE ss.pass_id = p.id AND ss.is_active = true) = 1
      AND (SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p.id) = 4
    FROM public.payments AS pay
    JOIN public.passes AS p ON p.id = pay.renewed_pass_id
    WHERE pay.id = current_setting('test.payment_s001')::uuid
  ),
  'initial enrollment creates active first pass with completed payment'
);

SELECT is(
  (SELECT pass_code FROM public.passes WHERE id = current_setting('test.pass_s001')::uuid),
  'V-S001-001',
  'initial pass public code ends with sequence 001'
);

SELECT ok(
  (
    SELECT pay.status = 'completed'
      AND pay.renewed_pass_id = current_setting('test.pass_s001')::uuid
      AND pay.payment_method = 'card'
      AND pay.paid_amount_krw = 200000
    FROM public.payments AS pay
    WHERE pay.id = current_setting('test.payment_s001')::uuid
  ),
  'completed payment linked to initial pass via renewed_pass_id'
);

SELECT ok(
  (
    SELECT p.registered_lesson_count_snapshot = 4
      AND p.weekly_frequency_snapshot = 1
      AND p.product_name_snapshot = 'Vocal 4 Lessons'
      AND p.tuition_amount_krw_snapshot = 200000
      AND p.creation_reason = 'First vocal enrollment'
    FROM public.passes AS p
    WHERE p.id = current_setting('test.pass_s001')::uuid
  ),
  'initial pass stores immutable product snapshots and creation reason'
);

SELECT is(
  (SELECT count(*)::integer FROM public.passes
   WHERE student_id = current_setting('test.student_s001')::uuid
     AND course_id = current_setting('test.course_vocal')::uuid
     AND status = 'reserved'),
  0,
  'initial enrollment creates no reserved pass'
);

SELECT ok(
  pg_temp.audit_count() > current_setting('test.audit_before_s001')::bigint,
  'initial enrollment writes audit logs'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s003')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'block-active', NULL) $$,
  'P0001',
  'REVE_NOT_INITIAL_ENROLLMENT'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s004')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'block-reserved', NULL) $$,
  'P0001',
  'REVE_NOT_INITIAL_ENROLLMENT'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s005')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'block-completed', NULL) $$,
  'P0001',
  'REVE_NOT_INITIAL_ENROLLMENT'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s006')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'block-cancelled', NULL) $$,
  'P0001',
  'REVE_NOT_INITIAL_ENROLLMENT'
);

-- ---------------------------------------------------------------------------
-- Four-lesson product (~8)
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::integer FROM public.schedule_slots
   WHERE pass_id = current_setting('test.pass_s001')::uuid AND is_active = true),
  1,
  'four-lesson product creates one schedule slot'
);

SELECT is(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_s001')::uuid),
  4,
  'four-lesson product creates four lessons'
);

SELECT ok(
  (
    SELECT array_agg(l.sequence_number ORDER BY l.sequence_number)
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s001')::uuid
  ) = ARRAY[1, 2, 3, 4],
  'four-lesson pass lesson ordinals are 1 through 4'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s001')::uuid
      AND EXISTS (
        SELECT 1
        FROM public.lessons AS l2
        WHERE l2.pass_id = l.pass_id
          AND l2.sequence_number < l.sequence_number
          AND l2.scheduled_at > l.scheduled_at
      )
  ),
  'four-lesson pass lessons are chronological by sequence'
);

SELECT ok(
  (
    SELECT bool_and(
      extract(dow FROM l.scheduled_at AT TIME ZONE 'Asia/Seoul')::integer = ss.weekday
    )
    FROM public.lessons AS l
    JOIN public.schedule_slots AS ss ON ss.id = l.schedule_slot_id
    WHERE l.pass_id = current_setting('test.pass_s001')::uuid
  ),
  'four-lesson pass lesson weekdays match slot weekday'
);

SELECT ok(
  (
    SELECT bool_and(l.scheduled_at IS NOT NULL)
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s001')::uuid
  ),
  'four-lesson active pass lessons have non-null scheduled_at'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
SET ROLE service_role;
SELECT is(
  (
    SELECT used_lesson_count
    FROM reve_private.calculate_pass_usage(current_setting('test.pass_s001')::uuid)
  ),
  0,
  'four-lesson initial pass used count is zero'
);
SELECT is(
  (
    SELECT remaining_lesson_count
    FROM reve_private.calculate_pass_usage(current_setting('test.pass_s001')::uuid)
  ),
  4,
  'four-lesson initial pass remaining count is four via calculate_pass_usage'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

-- ---------------------------------------------------------------------------
-- Eight-lesson product (~8)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_pass_id uuid;
BEGIN
  SELECT pass_id
  INTO v_pass_id
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_s002')::uuid,
    current_setting('test.product_8')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.piano_slots_json(),
    400000, 'cash', now(), 'idem-s002-piano', NULL
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s002', v_pass_id::text, false);
END $$;

SELECT is(
  (SELECT count(*)::integer FROM public.schedule_slots
   WHERE pass_id = current_setting('test.pass_s002')::uuid AND is_active = true),
  2,
  'eight-lesson product creates two schedule slots'
);

SELECT is(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_s002')::uuid),
  8,
  'eight-lesson product creates eight lessons'
);

SELECT ok(
  (
    SELECT count(DISTINCT l.schedule_slot_id)::integer
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s002')::uuid
  ) = 2,
  'eight-lesson pass uses both schedule slots'
);

SELECT ok(
  (
    SELECT count(*)::integer
    FROM public.lessons AS l
    JOIN public.schedule_slots AS ss ON ss.id = l.schedule_slot_id
    WHERE l.pass_id = current_setting('test.pass_s002')::uuid
      AND ss.teacher_id = current_setting('test.teacher_a')::uuid
  ) >= 1,
  'eight-lesson pass preserves teacher A on slot one lessons'
);

SELECT ok(
  (
    SELECT count(*)::integer
    FROM public.lessons AS l
    JOIN public.schedule_slots AS ss ON ss.id = l.schedule_slot_id
    WHERE l.pass_id = current_setting('test.pass_s002')::uuid
      AND ss.teacher_id = current_setting('test.teacher_b')::uuid
  ) >= 1,
  'eight-lesson pass preserves teacher B on slot two lessons'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.lessons AS l
    JOIN public.schedule_slots AS ss ON ss.id = l.schedule_slot_id
    WHERE l.pass_id = current_setting('test.pass_s002')::uuid
      AND l.scheduled_at = (
        SELECT min(l2.scheduled_at)
        FROM public.lessons AS l2
        WHERE l2.pass_id = current_setting('test.pass_s002')::uuid
          AND l2.schedule_slot_id <> l.schedule_slot_id
      )
      AND ss.slot_order > (
        SELECT ss2.slot_order
        FROM public.schedule_slots AS ss2
        WHERE ss2.id = l.schedule_slot_id
      )
  ),
  'eight-lesson pass chronological ordering respects slot_order tie-break'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s002')::uuid
      AND EXISTS (
        SELECT 1
        FROM public.lessons AS l2
        WHERE l2.pass_id = l.pass_id
          AND l2.sequence_number < l.sequence_number
          AND l2.scheduled_at > l.scheduled_at
      )
  ),
  'eight-lesson pass lessons are chronological by sequence'
);

SELECT is(
  (SELECT pass_code FROM public.passes WHERE id = current_setting('test.pass_s002')::uuid),
  'P-S002-001',
  'eight-lesson initial pass uses piano course code prefix'
);

DO $$
DECLARE
  v_pass_id uuid;
BEGIN
  SELECT pass_id
  INTO v_pass_id
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_s007')::uuid,
    current_setting('test.product_8')::uuid,
    current_setting('test.enroll_date')::date + 28,
    pg_temp.piano_slots_json(),
    400000, 'bank_transfer', now(), 'idem-s007-piano', NULL
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s007_piano', v_pass_id::text, false);
END $$;

SELECT ok(
  pg_temp.pass_count(
    current_setting('test.student_s007')::uuid,
    current_setting('test.course_piano')::uuid
  ) = 1,
  'student with vocal pass history may still enroll another course'
);

-- ---------------------------------------------------------------------------
-- Start boundary (~5)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_pass_id uuid;
BEGIN
  SELECT pass_id
  INTO v_pass_id
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_s011')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.boundary_date')::date,
    pg_temp.boundary_slot_json(),
    200000, 'cash',
    timestamptz '2026-05-15 08:30:00+09',
    'idem-s011-boundary', NULL
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s011', v_pass_id::text, false);
END $$;

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s011')::uuid
      AND l.scheduled_at < (current_setting('test.boundary_date')::date::timestamp AT TIME ZONE 'Asia/Seoul')
  ),
  'no lesson scheduled before Seoul start boundary'
);

SELECT ok(
  (
    SELECT min(l.scheduled_at)
      >= (current_setting('test.boundary_date')::date::timestamp AT TIME ZONE 'Asia/Seoul')
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s011')::uuid
  ),
  'first lesson occurs on or after Seoul start boundary'
);

SELECT is(
  (
    SELECT min(l.scheduled_at)
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_s011')::uuid
  ),
  (current_setting('test.boundary_date')::date::timestamp + time '09:00') AT TIME ZONE 'Asia/Seoul',
  'first lesson scheduled_at uses Asia/Seoul slot time'
);

SELECT ok(
  (
    SELECT pay.paid_at <>
      (SELECT min(l.scheduled_at) FROM public.lessons AS l
       WHERE l.pass_id = current_setting('test.pass_s011')::uuid)
    FROM public.payments AS pay
    WHERE pay.renewed_pass_id = current_setting('test.pass_s011')::uuid
  ),
  'payment paid_at timestamp differs from first lesson scheduled_at'
);

SELECT is(
  (SELECT start_date FROM public.passes WHERE id = current_setting('test.pass_s011')::uuid),
  current_setting('test.boundary_date')::date,
  'pass start_date reflects first lesson Seoul calendar date'
);

-- ---------------------------------------------------------------------------
-- Collision (~6)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_audit_before bigint;
  v_pass_before bigint;
  v_pay_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  v_pass_before := pg_temp.pass_count(
    current_setting('test.student_s009')::uuid,
    current_setting('test.course_vocal')::uuid
  );
  v_pay_before := pg_temp.payment_count(current_setting('test.student_s009')::uuid);
  PERFORM set_config('test.audit_before_collision', v_audit_before::text, false);
  PERFORM set_config('test.pass_before_collision', v_pass_before::text, false);
  PERFORM set_config('test.pay_before_collision', v_pay_before::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s009')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.start_date')::date,
       pg_temp.vocal_collision_slot_json(),
       200000, 'cash', now(), 'idem-s009-collision', NULL) $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

SELECT is(
  pg_temp.pass_count(
    current_setting('test.student_s009')::uuid,
    current_setting('test.course_vocal')::uuid
  ),
  current_setting('test.pass_before_collision')::bigint,
  'schedule collision rolls back pass creation'
);

SELECT is(
  pg_temp.payment_count(current_setting('test.student_s009')::uuid),
  current_setting('test.pay_before_collision')::bigint,
  'schedule collision rolls back payment creation'
);

SELECT is(
  pg_temp.audit_count(),
  current_setting('test.audit_before_collision')::bigint,
  'schedule collision writes no audit log'
);

SELECT ok(
  (
    SELECT scheduled_at = current_setting('test.collision_at')::timestamptz
      AND status = 'scheduled'
    FROM public.lessons
    WHERE id = current_setting('test.collision_lesson')::uuid
  ),
  'pre-existing conflicting lesson remains unchanged after collision abort'
);

SELECT ok(
  pg_temp.lesson_count(current_setting('test.student_s009')::uuid) = 0,
  'collision abort leaves enrolling student without lesson rows'
);

-- ---------------------------------------------------------------------------
-- Idempotency (~10)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_pass_id uuid;
  v_payment_id uuid;
  v_audit_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  PERFORM set_config('test.audit_before_s010', v_audit_before::text, false);

  SELECT pass_id, payment_id
  INTO v_pass_id, v_payment_id
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_s010')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date + 42,
    pg_temp.vocal_slot_json(),
    200000, 'cash', now(), 'idem-s010-replay', NULL
  )
  LIMIT 1;

  PERFORM set_config('test.pass_s010', v_pass_id::text, false);
  PERFORM set_config('test.payment_s010', v_payment_id::text, false);
  PERFORM set_config('test.audit_after_s010', pg_temp.audit_count()::text, false);
END $$;

SELECT ok(
  (
    SELECT idempotent_replay = true
      AND pass_id = current_setting('test.pass_s010')::uuid
      AND payment_id = current_setting('test.payment_s010')::uuid
    FROM public.reve_owner_create_initial_enrollment(
      current_setting('test.student_s010')::uuid,
      current_setting('test.product_4')::uuid,
      current_setting('test.enroll_date')::date + 42,
      pg_temp.vocal_slot_json(),
      200000, 'cash', now(), 'idem-s010-replay', NULL
    )
    LIMIT 1
  ),
  'exact idempotency replay returns idempotent_replay true'
);

SELECT is(
  pg_temp.pass_count(
    current_setting('test.student_s010')::uuid,
    current_setting('test.course_vocal')::uuid
  ),
  1::bigint,
  'idempotent replay does not create duplicate pass'
);

SELECT is(
  pg_temp.payment_count(current_setting('test.student_s010')::uuid),
  1::bigint,
  'idempotent replay does not create duplicate payment'
);

SELECT is(
  pg_temp.audit_count(),
  current_setting('test.audit_after_s010')::bigint,
  'idempotent replay writes no additional audit log'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s008')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date + 42,
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'idem-s010-replay', NULL) $$,
  'P0001',
  'REVE_IDEMPOTENCY_CONFLICT'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s010')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date + 42,
       pg_temp.vocal_slot_json(),
       199999, 'cash', now(), 'idem-s010-replay', NULL) $$,
  'P0001',
  'REVE_PAYMENT_AMOUNT_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s010')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date + 42,
       pg_temp.vocal_slot_json(),
       200000, 'card', now(), 'idem-s010-replay', NULL) $$,
  'P0001',
  'REVE_IDEMPOTENCY_CONFLICT'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s010')::uuid,
       current_setting('test.product_4')::uuid,
       current_setting('test.enroll_date')::date + 42,
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 2, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1)),
       200000, 'cash', now(), 'idem-s010-replay', NULL) $$,
  'P0001',
  'REVE_IDEMPOTENCY_CONFLICT'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s010')::uuid,
       current_setting('test.product_4')::uuid,
       (current_setting('test.enroll_date')::date + 49),
       pg_temp.vocal_slot_json(),
       200000, 'cash', now(), 'idem-s010-replay', NULL) $$,
  'P0001',
  'REVE_IDEMPOTENCY_CONFLICT'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_s010')::uuid,
       current_setting('test.product_8')::uuid,
       current_setting('test.enroll_date')::date + 42,
       pg_temp.piano_slots_json(),
       400000, 'cash', now(), 'idem-s010-replay', NULL) $$,
  'P0001',
  'REVE_IDEMPOTENCY_CONFLICT'
);

-- ---------------------------------------------------------------------------
-- Transaction isolation (~4)
-- ---------------------------------------------------------------------------
SELECT is(
  pg_temp.pass_count(current_setting('test.student_s008')::uuid),
  0::bigint,
  'unrelated student pass count unchanged after other enrollments'
);

SELECT is(
  pg_temp.payment_count(current_setting('test.student_s008')::uuid),
  0::bigint,
  'unrelated student payment count unchanged after other enrollments'
);

SELECT is(
  pg_temp.lesson_count(current_setting('test.student_s008')::uuid),
  0::bigint,
  'unrelated student lesson count unchanged after other enrollments'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.reve_owner_create_initial_enrollment(
      current_setting('test.student_s008')::uuid,
      current_setting('test.product_4')::uuid,
      current_setting('test.enroll_date')::date + 49,
      pg_temp.isolated_slot_json(),
      200000, 'cash', now(), 'idem-s008-isolated', NULL
    )
    WHERE pass_status = 'active' AND idempotent_replay = false
  ),
  'unrelated student can still enroll after concurrent enrollment activity'
);

-- ---------------------------------------------------------------------------
-- Regression (~2)
-- ---------------------------------------------------------------------------
SELECT has_function('public', 'reve_owner_create_student', ARRAY['text', 'text', 'text', 'text']);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.reve_owner_create_student('S-LINT-ENR', 'Lint Enrollment Student', NULL, NULL)
    WHERE student_code = 'S-LINT-ENR' AND student_name = 'Lint Enrollment Student'
  ),
  'reve_owner_create_student still works after initial enrollment migration'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();
ROLLBACK;

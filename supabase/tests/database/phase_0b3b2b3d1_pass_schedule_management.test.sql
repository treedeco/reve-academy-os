-- REVE ACADEMY OS Phase 0B-3B-2B-3D-1 — pass schedule slot replacement pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(85);

-- ---------------------------------------------------------------------------
-- Fixture: auth users, courses/products, teachers, students, pass seeds
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
  v_student_main uuid := '44444444-4444-4444-4444-444444444420';
  v_student_2slot uuid := '44444444-4444-4444-4444-444444444421';
  v_student_res uuid := '44444444-4444-4444-4444-444444444422';
  v_student_int uuid := '44444444-4444-4444-4444-444444444423';
  v_student_col uuid := '44444444-4444-4444-4444-444444444424';
  v_student_free uuid := '44444444-4444-4444-4444-444444444425';
  v_student_immutable uuid := '44444444-4444-4444-4444-444444444426';
  v_pass_completed uuid := '66666666-6666-6666-6666-666666666605';
  v_pass_cancelled uuid := '66666666-6666-6666-6666-666666666606';
  v_pass_res_active uuid := '66666666-6666-6666-6666-666666666607';
  v_pass_res_reserved uuid := '67676767-6767-6767-6767-676767676707';
  v_collision_pass uuid := '66666666-6666-6666-6666-666666666699';
  v_collision_slot uuid := '77777777-7777-7777-7777-777777777799';
  v_collision_inact_slot uuid := '77777777-7777-7777-7777-777777777798';
  v_slot_res_active uuid := '77777777-7777-7777-7777-777777777701';
  v_slot_res_reserved uuid := '77777777-7777-7777-7777-777777777702';
  v_slot_completed uuid := '77777777-7777-7777-7777-777777777703';
  v_slot_cancelled uuid := '77777777-7777-7777-7777-777777777704';
  v_shell_1 uuid := 'abababab-abab-abab-abab-ababababab01';
  v_shell_2 uuid := 'abababab-abab-abab-abab-ababababab02';
  v_shell_3 uuid := 'abababab-abab-abab-abab-ababababab03';
  v_shell_4 uuid := 'abababab-abab-abab-abab-ababababab04';
  v_start_date date := '2026-07-06';
  v_enroll_date date := '2026-07-13';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner1-psm@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner2-psm@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-a-psm@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_b_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-b-psm@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-psm@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_spoof_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'spoof-psm@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_student_auth, 'student', 'Schedule Main Student Profile', 'active');

  INSERT INTO public.teachers (id, teacher_code, name, phone, email, is_active) VALUES
    (v_teacher_a, 'T-PSM-A', 'Schedule Teacher A', '010-0000-0001', 'ta-psm@test.local', true),
    (v_teacher_b, 'T-PSM-B', 'Schedule Teacher B', '010-0000-0002', 'tb-psm@test.local', true),
    (v_teacher_inactive, 'T-PSM-C', 'Inactive Teacher C', '010-0000-0003', 'ti-psm@test.local', false);

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student_main, 'S020', v_student_auth, 'Schedule Main Student', 'active'),
    (v_student_2slot, 'S021', NULL, 'Schedule Two Slot Student', 'active'),
    (v_student_res, 'S022', NULL, 'Schedule Reserved Student', 'active'),
    (v_student_int, 'S023', NULL, 'Schedule Integration Student', 'active'),
    (v_student_col, 'S024', NULL, 'Schedule Collision Student', 'active'),
    (v_student_free, 'S025', NULL, 'Schedule Free Collision Student', 'active'),
    (v_student_immutable, 'S026', NULL, 'Schedule Immutable Student', 'active');

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
    start_date, activated_at, completed_at, cancelled_at, previous_pass_id
  ) VALUES
    (v_pass_completed, 'V-S005-001', v_student_immutable, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date - 90,
     now() - interval '30 days', now() - interval '30 days', NULL, NULL),
    (v_pass_cancelled, 'V-S006-001', v_student_immutable, v_course_vocal, v_product_4,
     2, 'cancelled', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date - 60,
     now() - interval '20 days', NULL, now() - interval '10 days', NULL),
    (v_pass_res_active, 'V-S022-001', v_student_res, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date, now(), NULL, NULL, NULL),
    (v_pass_res_reserved, 'V-S022-002', v_student_res, v_course_vocal, v_product_4,
     2, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date + 30, now(), NULL, NULL,
     v_pass_res_active),
    (v_collision_pass, 'V-S024-001', v_student_col, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, v_start_date - 30, now(), NULL, NULL, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES
    (v_slot_completed, v_pass_completed, v_teacher_a, 1, '10:00', 60, 1, true, v_start_date - 90),
    (v_slot_cancelled, v_pass_cancelled, v_teacher_a, 1, '10:00', 60, 1, true, v_start_date - 60),
    (v_slot_res_active, v_pass_res_active, v_teacher_a, 1, '14:00', 60, 1, true, v_start_date),
    (v_slot_res_reserved, v_pass_res_reserved, v_teacher_a, 3, '16:00', 60, 1, true, v_start_date),
    (v_collision_slot, v_collision_pass, v_teacher_a, 1, '10:00', 60, 1, true, v_start_date - 30),
    (v_collision_inact_slot, v_collision_pass, v_teacher_a, 1, '09:00', 60, 1, false, v_start_date - 30);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (v_shell_1, v_pass_res_reserved, v_student_res, v_course_vocal, v_teacher_a,
     v_slot_res_reserved, 1, NULL, 'scheduled'),
    (v_shell_2, v_pass_res_reserved, v_student_res, v_course_vocal, v_teacher_a,
     v_slot_res_reserved, 2, NULL, 'scheduled'),
    (v_shell_3, v_pass_res_reserved, v_student_res, v_course_vocal, v_teacher_a,
     v_slot_res_reserved, 3, NULL, 'scheduled'),
    (v_shell_4, v_pass_res_reserved, v_student_res, v_course_vocal, v_teacher_a,
     v_slot_res_reserved, 4, NULL, 'scheduled');

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
  PERFORM set_config('test.student_main', v_student_main::text, false);
  PERFORM set_config('test.student_2slot', v_student_2slot::text, false);
  PERFORM set_config('test.student_res', v_student_res::text, false);
  PERFORM set_config('test.student_int', v_student_int::text, false);
  PERFORM set_config('test.student_col', v_student_col::text, false);
  PERFORM set_config('test.student_free', v_student_free::text, false);
  PERFORM set_config('test.student_immutable', v_student_immutable::text, false);
  PERFORM set_config('test.pass_completed', v_pass_completed::text, false);
  PERFORM set_config('test.pass_cancelled', v_pass_cancelled::text, false);
  PERFORM set_config('test.pass_res_active', v_pass_res_active::text, false);
  PERFORM set_config('test.pass_res_reserved', v_pass_res_reserved::text, false);
  PERFORM set_config('test.collision_pass', v_collision_pass::text, false);
  PERFORM set_config('test.collision_slot', v_collision_slot::text, false);
  PERFORM set_config('test.collision_inact_slot', v_collision_inact_slot::text, false);
  PERFORM set_config('test.shell_1', v_shell_1::text, false);
  PERFORM set_config('test.shell_2', v_shell_2::text, false);
  PERFORM set_config('test.shell_3', v_shell_3::text, false);
  PERFORM set_config('test.shell_4', v_shell_4::text, false);
  PERFORM set_config('test.slot_res_reserved', v_slot_res_reserved::text, false);
  PERFORM set_config('test.start_date', v_start_date::text, false);
  PERFORM set_config('test.enroll_date', v_enroll_date::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.replace_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_replace_pass_schedule_slots(uuid,timestamptz,jsonb,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count()
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count_for(p_action text)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs WHERE action = p_action;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.active_slot_count(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass AND ss.is_active = true;
$$;

CREATE OR REPLACE FUNCTION pg_temp.total_slot_count(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM public.schedule_slots AS ss WHERE ss.pass_id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_count_for_pass(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.main_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '11:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.replacement_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 2,
    'local_time', '15:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.collision_exact_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '10:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.collision_partial_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '10:30',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.collision_adjacent_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '12:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.collision_other_weekday_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 3,
    'local_time', '10:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.collision_other_teacher_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 1,
    'local_time', '10:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.collision_inactive_overlap_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '09:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.self_overlap_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '11:30',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.reserved_replacement_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 3,
    'local_time', '16:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.reserved_predecessor_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '14:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.two_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_a')::uuid,
      'weekday', 2, 'local_time', '09:00', 'duration_minutes', 60, 'slot_order', 1),
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_b')::uuid,
      'weekday', 4, 'local_time', '13:00', 'duration_minutes', 60, 'slot_order', 2)
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.two_slot_replacement_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_a')::uuid,
      'weekday', 3, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1),
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_b')::uuid,
      'weekday', 5, 'local_time', '15:00', 'duration_minutes', 60, 'slot_order', 2)
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.int_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 3,
    'local_time', '12:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.free_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 4,
    'local_time', '08:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.used_count_for_pass(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass
    AND l.status IN ('completed', 'same_day_cancelled', 'makeup_completed');
$$;

-- ---------------------------------------------------------------------------
-- Bootstrap owner and enroll primary passes via initial enrollment RPC
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

DO $$
DECLARE
  v_pass_main uuid;
  v_pass_2slot uuid;
  v_pass_free uuid;
  v_pass_int uuid;
  v_old_slot uuid;
  v_lesson_1 uuid;
  v_lesson_2 uuid;
  v_lesson_3 uuid;
  v_lesson_4 uuid;
BEGIN
  SELECT pass_id INTO v_pass_main
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_main')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.main_slot_json(),
    200000, 'cash', now(), 'psm-main-enroll', 'Main schedule fixture'
  )
  LIMIT 1;

  SELECT pass_id INTO v_pass_2slot
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_2slot')::uuid,
    current_setting('test.product_8')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.two_slot_json(),
    400000, 'card', now(), 'psm-2slot-enroll', 'Two slot fixture'
  )
  LIMIT 1;

  SELECT pass_id INTO v_pass_free
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_free')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.free_slot_json(),
    200000, 'cash', now(), 'psm-free-enroll', 'Collision-free fixture'
  )
  LIMIT 1;

  SELECT pass_id INTO v_pass_int
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_int')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.int_slot_json(),
    200000, 'cash', now(), 'psm-int-enroll', 'Integration fixture'
  )
  LIMIT 1;

  SELECT id INTO v_old_slot
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass_main AND ss.is_active = true
  ORDER BY ss.slot_order
  LIMIT 1;

  SELECT l.id INTO v_lesson_1
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_main AND l.sequence_number = 1;

  SELECT l.id INTO v_lesson_2
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_main AND l.sequence_number = 2;

  SELECT l.id INTO v_lesson_3
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_main AND l.sequence_number = 3;

  SELECT l.id INTO v_lesson_4
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_main AND l.sequence_number = 4;

  PERFORM public.reve_transition_lesson_status(
    v_lesson_1, 'completed',
    pg_temp.lesson_updated_at(v_lesson_1),
    now() - interval '2 days', now() - interval '2 days' + interval '1 hour',
    'Fixture completed lesson'
  );

  PERFORM public.reve_transition_lesson_status(
    v_lesson_3, 'postponed',
    pg_temp.lesson_updated_at(v_lesson_3),
    NULL, NULL,
    'Fixture postponed lesson'
  );

  PERFORM public.reve_transition_lesson_status(
    v_lesson_4, 'advance_cancelled',
    pg_temp.lesson_updated_at(v_lesson_4),
    NULL, NULL,
    'Fixture cancelled lesson'
  );

  PERFORM set_config('test.pass_main', v_pass_main::text, false);
  PERFORM set_config('test.pass_2slot', v_pass_2slot::text, false);
  PERFORM set_config('test.pass_free', v_pass_free::text, false);
  PERFORM set_config('test.pass_int', v_pass_int::text, false);
  PERFORM set_config('test.old_slot_main', v_old_slot::text, false);
  PERFORM set_config('test.lesson_1', v_lesson_1::text, false);
  PERFORM set_config('test.lesson_2', v_lesson_2::text, false);
  PERFORM set_config('test.lesson_3', v_lesson_3::text, false);
  PERFORM set_config('test.lesson_4', v_lesson_4::text, false);
  PERFORM set_config('test.lesson_1_scheduled_at',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_lesson_1), false);
  PERFORM set_config('test.lesson_2_scheduled_at',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_lesson_2), false);
  PERFORM set_config('test.lesson_3_scheduled_at',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_lesson_3), false);
  PERFORM set_config('test.lesson_4_scheduled_at',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_lesson_4), false);
  PERFORM set_config('test.lesson_1_slot',
    (SELECT schedule_slot_id::text FROM public.lessons WHERE id = v_lesson_1), false);
  PERFORM set_config('test.lesson_2_slot',
    (SELECT schedule_slot_id::text FROM public.lessons WHERE id = v_lesson_2), false);
  PERFORM set_config('test.lesson_3_slot',
    (SELECT schedule_slot_id::text FROM public.lessons WHERE id = v_lesson_3), false);
  PERFORM set_config('test.lesson_4_slot',
    (SELECT schedule_slot_id::text FROM public.lessons WHERE id = v_lesson_4), false);
  PERFORM set_config('test.lesson_count_main', pg_temp.lesson_count_for_pass(v_pass_main)::text, false);
  PERFORM set_config('test.used_before_main', pg_temp.used_count_for_pass(v_pass_main)::text, false);
  PERFORM set_config('test.sms_before_main',
    (SELECT status FROM public.sms_notifications WHERE pass_id = v_pass_main LIMIT 1), false);
  PERFORM set_config('test.payment_before_main',
    (SELECT paid_amount_krw::text FROM public.payments WHERE renewed_pass_id = v_pass_main LIMIT 1), false);
END $$;

-- ---------------------------------------------------------------------------
-- Security (~12)
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_owner_replace_pass_schedule_slots',
  ARRAY['uuid', 'timestamptz', 'jsonb', 'text']
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_replace_pass_schedule_slots'
  ),
  'replace pass schedule RPC uses fixed empty search_path'
);

SELECT ok(
  (
    SELECT r.rolname = 'postgres'
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_replace_pass_schedule_slots'
  ),
  'replace pass schedule RPC owned by postgres'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.replace_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_replace_pass_schedule_slots'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.replacement_slot_json(), 'anon replace') $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.replacement_slot_json(), 'teacher replace') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.replacement_slot_json(), 'student replace') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.spoof_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.replacement_slot_json(), 'spoof replace') $$,
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
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.replacement_slot_json(), 'inactive owner replace') $$,
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
  $$ INSERT INTO public.schedule_slots (
       pass_id, teacher_id, weekday, local_start_time, duration_minutes,
       slot_order, is_active, effective_from
     ) VALUES (
       current_setting('test.pass_main')::uuid,
       current_setting('test.teacher_a')::uuid,
       1, '10:00', 60, 1, true, current_date) $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.lessons (
       pass_id, student_id, course_id, assigned_teacher_id,
       sequence_number, scheduled_at, status
     ) VALUES (
       current_setting('test.pass_main')::uuid,
       current_setting('test.student_main')::uuid,
       current_setting('test.course_vocal')::uuid,
       current_setting('test.teacher_a')::uuid,
       99, now(), 'scheduled') $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.audit_logs (
       actor_profile_id, actor_role_snapshot, action, resource_table, resource_id
     ) VALUES (
       current_setting('test.owner1')::uuid, 'owner', 'test.direct', 'passes',
       current_setting('test.pass_main')::uuid) $$,
  '42501'
);

-- ---------------------------------------------------------------------------
-- Input validation (~14)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       '[]'::jsonb, 'empty array') $$,
  'P0001',
  'REVE_SCHEDULE_FREQUENCY_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_object('teacher_id', current_setting('test.teacher_a')::uuid),
       'non-array') $$,
  'P0001',
  'REVE_SCHEDULE_FREQUENCY_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 1, 'local_time', '11:00', 'duration_minutes', 60,
         'slot_order', 1, 'extra', true)),
       'unknown field') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 1, 'local_time', '11:00', 'duration_minutes', 60)),
       'missing field') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_inactive')::uuid,
         'weekday', 1, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1)),
       'inactive teacher') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 7, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1)),
       'bad weekday') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 1, 'local_time', 'bad', 'duration_minutes', 60, 'slot_order', 1)),
       'bad time') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_array(jsonb_build_object(
         'teacher_id', current_setting('test.teacher_a')::uuid,
         'weekday', 1, 'local_time', '11:00', 'duration_minutes', 0, 'slot_order', 1)),
       'bad duration') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_2slot')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_2slot')::uuid),
       jsonb_build_array(
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_a')::uuid,
           'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1),
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_b')::uuid,
           'weekday', 3, 'local_time', '14:00', 'duration_minutes', 60, 'slot_order', 1)),
       'duplicate slot_order') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_2slot')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_2slot')::uuid),
       jsonb_build_array(
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_a')::uuid,
           'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 1),
         jsonb_build_object(
           'teacher_id', current_setting('test.teacher_a')::uuid,
           'weekday', 1, 'local_time', '10:00', 'duration_minutes', 60, 'slot_order', 2)),
       'duplicate definition') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.two_slot_json(), 'frequency mismatch') $$,
  'P0001',
  'REVE_SCHEDULE_FREQUENCY_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.replacement_slot_json(), '') $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.replacement_slot_json(), '   ') $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       jsonb_build_array(jsonb_build_object(
         'teacher_id', 'not-a-uuid',
         'weekday', 1, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1)),
       'bad teacher uuid') $$,
  'P0001',
  'REVE_INVALID_SCHEDULE'
);

-- ---------------------------------------------------------------------------
-- Immutable (~4)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_completed')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_completed')::uuid),
       pg_temp.replacement_slot_json(), 'completed pass replace') $$,
  'P0001',
  'REVE_PASS_SCHEDULE_IMMUTABLE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_cancelled')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_cancelled')::uuid),
       pg_temp.replacement_slot_json(), 'cancelled pass replace') $$,
  'P0001',
  'REVE_PASS_SCHEDULE_IMMUTABLE'
);

SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_completed')::uuid),
  1,
  'completed pass active slot count unchanged after immutable rejection'
);

SELECT is(
  pg_temp.audit_count_for('pass.schedule_slots_replaced'),
  0::bigint,
  'immutable rejection writes no schedule replacement audit'
);

-- ---------------------------------------------------------------------------
-- No-op (~6)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.audit_before_noop',
    pg_temp.audit_count_for('pass.schedule_slots_replaced')::text, false);
  PERFORM set_config('test.pass_ts_before_noop',
    pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid)::text, false);
  PERFORM set_config('test.active_slots_before_noop',
    pg_temp.active_slot_count(current_setting('test.pass_main')::uuid)::text, false);
  PERFORM set_config('test.total_slots_before_noop',
    pg_temp.total_slot_count(current_setting('test.pass_main')::uuid)::text, false);
END $$;

SELECT ok(
  (
    SELECT no_change = true
      AND deactivated_slot_count = 0
      AND created_slot_count = 0
      AND lesson_rows_changed = 0
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_main')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
      pg_temp.main_slot_json(),
      'same schedule no-op'
    )
    LIMIT 1
  ),
  'identical schedule returns no_change true without mutation'
);

SELECT ok(
  (
    SELECT no_change = true
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_main')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
      jsonb_build_array(jsonb_build_object(
        'slot_order', 1,
        'weekday', 1,
        'local_time', '11:00',
        'duration_minutes', 60,
        'teacher_id', current_setting('test.teacher_a')::uuid)),
      'reordered json no-op'
    )
    LIMIT 1
  ),
  'reordered json with same fingerprint returns no_change true'
);

SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_main')::uuid),
  current_setting('test.active_slots_before_noop')::integer,
  'no-op leaves active slot count unchanged'
);

SELECT is(
  pg_temp.total_slot_count(current_setting('test.pass_main')::uuid),
  current_setting('test.total_slots_before_noop')::integer,
  'no-op inserts no additional schedule slot rows'
);

SELECT is(
  pg_temp.audit_count_for('pass.schedule_slots_replaced'),
  current_setting('test.audit_before_noop')::bigint,
  'no-op writes no schedule replacement audit'
);

SELECT is(
  pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
  current_setting('test.pass_ts_before_noop')::timestamptz,
  'no-op leaves pass updated_at unchanged'
);

-- ---------------------------------------------------------------------------
-- Stale (~4)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.active_before_stale',
    pg_temp.active_slot_count(current_setting('test.pass_main')::uuid)::text, false);
  PERFORM set_config('test.audit_before_stale',
    pg_temp.audit_count_for('pass.schedule_slots_replaced')::text, false);
  PERFORM set_config('test.pass_ts_before_stale',
    pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid)::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       pg_temp.replacement_slot_json(), 'stale replace') $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_main')::uuid),
  current_setting('test.active_before_stale')::integer,
  'stale rejection leaves active slot count unchanged'
);

SELECT is(
  pg_temp.audit_count_for('pass.schedule_slots_replaced'),
  current_setting('test.audit_before_stale')::bigint,
  'stale rejection writes no schedule replacement audit'
);

SELECT is(
  pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
  current_setting('test.pass_ts_before_stale')::timestamptz,
  'stale rejection leaves pass updated_at unchanged'
);

-- ---------------------------------------------------------------------------
-- Collision (~10)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.active_before_collision',
    pg_temp.active_slot_count(current_setting('test.pass_main')::uuid)::text, false);
  PERFORM set_config('test.audit_before_collision',
    pg_temp.audit_count_for('pass.schedule_slots_replaced')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.collision_exact_json(), 'exact overlap') $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_main')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
       pg_temp.collision_partial_json(), 'partial overlap') $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_main')::uuid),
  current_setting('test.active_before_collision')::integer,
  'failed collision rolls back active slot count on target pass'
);

SELECT is(
  pg_temp.audit_count_for('pass.schedule_slots_replaced'),
  current_setting('test.audit_before_collision')::bigint,
  'failed collision writes no schedule replacement audit'
);

SELECT ok(
  (
    SELECT no_change = false
      AND created_slot_count = 1
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_free')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_free')::uuid),
      pg_temp.collision_adjacent_json(),
      'adjacent non-overlap replace'
    )
    LIMIT 1
  ),
  'adjacent non-overlapping slot passes collision check'
);

SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_free')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_free')::uuid),
      pg_temp.collision_other_weekday_json(),
      'different weekday replace'
    )
    LIMIT 1
  ),
  'different weekday avoids collision with Monday blocker'
);

SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_free')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_free')::uuid),
      pg_temp.collision_other_teacher_json(),
      'different teacher replace'
    )
    LIMIT 1
  ),
  'different teacher avoids collision with same-time blocker'
);

DO $$
BEGIN
  PERFORM set_config('test.pass_ts_before_replace',
    pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid)::text, false);
END $$;

SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_main')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
      pg_temp.collision_inactive_overlap_json(),
      'inactive slot overlap allowed'
    )
    LIMIT 1
  ),
  'inactive foreign slot does not block replacement'
);

SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_main')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_main')::uuid),
      pg_temp.self_overlap_json(),
      'self old slot excluded'
    )
    LIMIT 1
  ),
  'target pass own prior active slots excluded from collision check'
);

SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_res_reserved')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_res_reserved')::uuid),
      pg_temp.reserved_predecessor_json(),
      'reserved overlaps active predecessor'
    )
    LIMIT 1
  ),
  'reserved pass may reuse active predecessor recurring slot'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_replace_pass_schedule_slots(
       current_setting('test.pass_res_reserved')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_res_reserved')::uuid),
       pg_temp.collision_exact_json(), 'unrelated reserved conflict') $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

-- ---------------------------------------------------------------------------
-- Replacement (~10) — main pass replaced via self-overlap collision test above
-- ---------------------------------------------------------------------------
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.schedule_slots AS ss
    WHERE ss.pass_id = current_setting('test.pass_main')::uuid
      AND ss.is_active = false
      AND ss.id = current_setting('test.old_slot_main')::uuid
  ),
  'prior active slot row deactivated after replacement'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.schedule_slots AS ss
    WHERE ss.pass_id = current_setting('test.pass_main')::uuid
      AND ss.is_active = true
      AND ss.id <> current_setting('test.old_slot_main')::uuid
      AND ss.weekday = 1
      AND ss.local_start_time = time '11:30'
  ),
  'replacement inserts new active slot row'
);

SELECT ok(
  (
    SELECT count(*)::integer FROM public.schedule_slots AS ss
    WHERE ss.pass_id = current_setting('test.pass_main')::uuid
      AND ss.is_active = true
      AND ss.id <> current_setting('test.old_slot_main')::uuid
  ) = 1,
  'new active slot id differs from deactivated slot id'
);

SELECT ok(
  pg_temp.audit_count_for('pass.schedule_slots_replaced') > 0,
  'successful replacement writes pass.schedule_slots_replaced audit'
);

SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_main')::uuid),
  1,
  'replacement leaves exactly one active slot on frequency-1 pass'
);

SELECT ok(
  (
    SELECT lesson_rows_changed = 0
      AND no_change = false
      AND deactivated_slot_count = 2
      AND created_slot_count = 2
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_2slot')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_2slot')::uuid),
      pg_temp.two_slot_replacement_json(),
      'two slot replacement'
    )
    LIMIT 1
  ),
  'two-slot pass replacement succeeds with zero lesson mutation'
);

SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_2slot')::uuid),
  2,
  'two-slot replacement leaves two active slots'
);

-- ---------------------------------------------------------------------------
-- Lesson preservation (~12)
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT id::text FROM public.lessons WHERE id = current_setting('test.lesson_1')::uuid),
  current_setting('test.lesson_1'),
  'completed lesson id unchanged after schedule replacement'
);

SELECT is(
  (SELECT scheduled_at::text FROM public.lessons WHERE id = current_setting('test.lesson_1')::uuid),
  current_setting('test.lesson_1_scheduled_at'),
  'completed lesson scheduled_at unchanged after schedule replacement'
);

SELECT is(
  (SELECT schedule_slot_id::text FROM public.lessons WHERE id = current_setting('test.lesson_1')::uuid),
  current_setting('test.lesson_1_slot'),
  'completed lesson schedule_slot_id unchanged after schedule replacement'
);

SELECT is(
  (SELECT scheduled_at::text FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid),
  current_setting('test.lesson_2_scheduled_at'),
  'future scheduled lesson scheduled_at unchanged after schedule replacement'
);

SELECT is(
  (SELECT schedule_slot_id::text FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid),
  current_setting('test.lesson_2_slot'),
  'future scheduled lesson schedule_slot_id unchanged after schedule replacement'
);

SELECT is(
  (SELECT scheduled_at::text FROM public.lessons WHERE id = current_setting('test.lesson_3')::uuid),
  current_setting('test.lesson_3_scheduled_at'),
  'postponed lesson scheduled_at unchanged after schedule replacement'
);

SELECT is(
  (SELECT schedule_slot_id::text FROM public.lessons WHERE id = current_setting('test.lesson_3')::uuid),
  current_setting('test.lesson_3_slot'),
  'postponed lesson schedule_slot_id unchanged after schedule replacement'
);

SELECT ok(
  (
    SELECT status = 'advance_cancelled'
      AND scheduled_at::text = current_setting('test.lesson_4_scheduled_at')
      AND schedule_slot_id::text = current_setting('test.lesson_4_slot')
    FROM public.lessons
    WHERE id = current_setting('test.lesson_4')::uuid
  ),
  'cancelled lesson row unchanged after schedule replacement'
);

SELECT is(
  pg_temp.lesson_count_for_pass(current_setting('test.pass_main')::uuid),
  current_setting('test.lesson_count_main')::integer,
  'lesson row count unchanged after schedule replacement'
);

SELECT is(
  pg_temp.used_count_for_pass(current_setting('test.pass_main')::uuid),
  current_setting('test.used_before_main')::integer,
  'deductible usage count unchanged after schedule replacement'
);

SELECT is(
  (SELECT status FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_main')::uuid
   LIMIT 1),
  current_setting('test.sms_before_main'),
  'SMS notification status unchanged after schedule replacement'
);

SELECT is(
  (SELECT paid_amount_krw::text FROM public.payments
   WHERE renewed_pass_id = current_setting('test.pass_main')::uuid
   LIMIT 1),
  current_setting('test.payment_before_main'),
  'linked payment amount unchanged after schedule replacement'
);

-- ---------------------------------------------------------------------------
-- Reserved (~8)
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_replace_pass_schedule_slots(
      current_setting('test.pass_res_reserved')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_res_reserved')::uuid),
      pg_temp.reserved_replacement_json(),
      'replace reserved timetable'
    )
    LIMIT 1
  ),
  'reserved pass schedule replacement succeeds'
);

SELECT is(
  (SELECT id::text FROM public.lessons WHERE id = current_setting('test.shell_1')::uuid),
  current_setting('test.shell_1'),
  'reserved shell lesson id unchanged after schedule replacement'
);

SELECT is(
  (SELECT sequence_number FROM public.lessons WHERE id = current_setting('test.shell_2')::uuid),
  2,
  'reserved shell sequence_number unchanged after schedule replacement'
);

SELECT is(
  pg_temp.lesson_count_for_pass(current_setting('test.pass_res_reserved')::uuid),
  4,
  'reserved pass lesson shell count unchanged after schedule replacement'
);

SELECT ok(
  (
    SELECT count(*)::integer FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_res_reserved')::uuid
      AND l.scheduled_at IS NULL
  ) = 4,
  'reserved shells remain scheduled_at null after schedule replacement'
);

SELECT is(
  (SELECT schedule_slot_id::text FROM public.lessons
   WHERE id = current_setting('test.shell_1')::uuid),
  current_setting('test.slot_res_reserved'),
  'reserved shell schedule_slot_id unchanged before activation'
);

DO $$
DECLARE
  v_new_slot uuid;
BEGIN
  SELECT ss.id INTO v_new_slot
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = current_setting('test.pass_res_reserved')::uuid
    AND ss.is_active = true
  LIMIT 1;

  PERFORM set_config('test.reserved_new_slot', v_new_slot::text, false);
END $$;

SET LOCAL ROLE postgres;
UPDATE public.passes
SET status = 'completed',
    completed_at = now(),
    updated_at = now()
WHERE id = current_setting('test.pass_res_active')::uuid;
RESET ROLE;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT ok(
  (
    SELECT new_status = 'active'
      AND lessons_scheduled = 4
    FROM public.reve_activate_reserved_pass(
      current_setting('test.pass_res_reserved')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_res_reserved')::uuid),
      'activate after reserved schedule replace'
    )
    LIMIT 1
  ),
  'reserved activation after schedule replace schedules existing shells'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_res_reserved')::uuid
      AND l.schedule_slot_id = current_setting('test.reserved_new_slot')::uuid
      AND l.scheduled_at IS NOT NULL
  ),
  'activation binds reserved shells to newly active schedule slots'
);

-- ---------------------------------------------------------------------------
-- Integration (~4)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_payment uuid;
  v_payment_updated timestamptz;
  v_new_pass uuid;
BEGIN
  PERFORM public.reve_owner_replace_pass_schedule_slots(
    current_setting('test.pass_int')::uuid,
    pg_temp.pass_updated_at(current_setting('test.pass_int')::uuid),
    pg_temp.replacement_slot_json(),
    'integration replace before renewal'
  );

  SELECT id, updated_at INTO v_payment, v_payment_updated
  FROM public.payments
  WHERE renewed_pass_id = current_setting('test.pass_int')::uuid
  LIMIT 1;

  SET LOCAL ROLE postgres;
  UPDATE public.payments AS pay
  SET status = 'pending',
      renewed_pass_id = NULL,
      related_pass_id = current_setting('test.pass_int')::uuid,
      idempotency_key = 'psm-int-renewal',
      updated_at = now()
  WHERE pay.id = v_payment;
  RESET ROLE;

  SELECT updated_at INTO v_payment_updated
  FROM public.payments
  WHERE id = v_payment;

  SELECT new_pass_id INTO v_new_pass
  FROM public.reve_complete_payment_and_renew_pass(
    v_payment,
    v_payment_updated,
    200000, 'cash', now(), 'psm-int-renewal'
  )
  LIMIT 1;

  PERFORM set_config('test.pass_int_renewed', v_new_pass::text, false);
END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = current_setting('test.pass_int_renewed')::uuid
      AND ss.is_active = true
      AND ss.weekday = 2
      AND ss.local_start_time = time '15:00'
      AND ss.teacher_id = current_setting('test.teacher_b')::uuid
  ),
  'renewal copies only current active slots after schedule replacement'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = current_setting('test.pass_int_renewed')::uuid
      AND ss.is_active = true
      AND ss.weekday = 1
      AND ss.local_start_time = time '11:00'
  ),
  'renewal does not copy deactivated pre-replacement slots'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT ok(
  (
    SELECT count(*)::integer FROM public.reve_get_my_pass_summary()
  ) >= 1,
  'student safe read pass summary still works after schedule replacement elsewhere'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT * FROM finish();

ROLLBACK;

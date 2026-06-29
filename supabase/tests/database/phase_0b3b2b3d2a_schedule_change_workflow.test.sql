-- REVE ACADEMY OS Phase 0B-3B-2B-3D-2A — schedule change review/apply pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(86);

-- ---------------------------------------------------------------------------
-- Fixture: auth users, courses/products, teachers, students, pass seeds
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa011';
  v_owner2 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa012';
  v_teacher_a_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd011';
  v_teacher_b_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd012';
  v_student_a_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb011';
  v_student_b_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb012';
  v_spoof_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd013';
  v_teacher_a uuid := '22222222-2222-2222-2222-222222222011';
  v_teacher_b uuid := '33333333-3333-3333-3333-333333333011';
  v_course_vocal uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee11';
  v_product_4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff11';
  v_student_a uuid := '44444444-4444-4444-4444-444444444011';
  v_student_b uuid := '44444444-4444-4444-4444-444444444012';
  v_student_col uuid := '44444444-4444-4444-4444-444444444013';
  v_pass_cancelled uuid := '66666666-6666-6666-6666-666666666011';
  v_pass_res_shell uuid := '66666666-6666-6666-6666-666666666012';
  v_slot_cancelled uuid := '77777777-7777-7777-7777-777777777011';
  v_slot_res_shell uuid := '77777777-7777-7777-7777-777777777012';
  v_lesson_cancelled uuid := '99999999-9999-9999-9999-999999999011';
  v_lesson_shell uuid := 'abababab-abab-abab-abab-ababababab11';
  v_lesson_collision_block uuid := '99999999-9999-9999-9999-999999999012';
  v_lesson_collision_teacher_b uuid := '99999999-9999-9999-9999-999999999013';
  v_lesson_actual_times uuid := '99999999-9999-9999-9999-999999999014';
  v_lesson_makeup uuid := '99999999-9999-9999-9999-999999999015';
  v_lesson_makeup_source uuid := '99999999-9999-9999-9999-999999999016';
  v_lesson_collision_target uuid := '99999999-9999-9999-9999-999999999017';
  v_enroll_date date := '2026-07-13';
  v_collision_anchor timestamptz := timestamptz '2026-08-10 11:00:00+09';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner1-scw@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner2-scw@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_a_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-a-scw@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_b_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-b-scw@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_a_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-a-scw@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_b_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-b-scw@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_spoof_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'spoof-scw@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_student_a_auth, 'student', 'SCW Student A Profile', 'active'),
    (v_student_b_auth, 'student', 'SCW Student B Profile', 'active'),
    (v_teacher_a_auth, 'teacher', 'SCW Teacher A Profile', 'active'),
    (v_teacher_b_auth, 'teacher', 'SCW Teacher B Profile', 'active');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher_a, 'T-SCW-A', v_teacher_a_auth, 'SCW Teacher A', '010-0000-0011', 'ta-scw@test.local', true),
    (v_teacher_b, 'T-SCW-B', v_teacher_b_auth, 'SCW Teacher B', '010-0000-0012', 'tb-scw@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student_a, 'S011', v_student_a_auth, 'SCW Student A', 'active'),
    (v_student_b, 'S012', v_student_b_auth, 'SCW Student B', 'active'),
    (v_student_col, 'S013', NULL, 'SCW Collision Student', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course_vocal, 'VOCAL', 'Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES
    (v_product_4, v_course_vocal, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000, true);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at, completed_at, cancelled_at, previous_pass_id
  ) VALUES
    (v_pass_cancelled, 'V-S013-001', v_student_col, v_course_vocal, v_product_4,
     1, 'cancelled', 4, 1, 'Vocal 4 Lessons', 200000, v_enroll_date - 60,
     now() - interval '20 days', NULL, now() - interval '10 days', NULL),
    (v_pass_res_shell, 'V-S013-002', v_student_col, v_course_vocal, v_product_4,
     2, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000, v_enroll_date + 30,
     now(), NULL, NULL, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES
    (v_slot_cancelled, v_pass_cancelled, v_teacher_a, 1, '11:00', 60, 1, true, v_enroll_date - 60),
    (v_slot_res_shell, v_pass_res_shell, v_teacher_a, 1, '11:00', 60, 1, true, v_enroll_date);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (v_lesson_cancelled, v_pass_cancelled, v_student_col, v_course_vocal, v_teacher_a,
     v_slot_cancelled, 1, v_collision_anchor, 'scheduled'),
    (v_lesson_shell, v_pass_res_shell, v_student_col, v_course_vocal, v_teacher_a,
     v_slot_res_shell, 1, NULL, 'scheduled');

  PERFORM set_config('test.owner1', v_owner1::text, false);
  PERFORM set_config('test.owner2', v_owner2::text, false);
  PERFORM set_config('test.teacher_a_auth', v_teacher_a_auth::text, false);
  PERFORM set_config('test.teacher_b_auth', v_teacher_b_auth::text, false);
  PERFORM set_config('test.student_a_auth', v_student_a_auth::text, false);
  PERFORM set_config('test.student_b_auth', v_student_b_auth::text, false);
  PERFORM set_config('test.spoof_auth', v_spoof_auth::text, false);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, false);
  PERFORM set_config('test.teacher_b', v_teacher_b::text, false);
  PERFORM set_config('test.course_vocal', v_course_vocal::text, false);
  PERFORM set_config('test.product_4', v_product_4::text, false);
  PERFORM set_config('test.student_a', v_student_a::text, false);
  PERFORM set_config('test.student_b', v_student_b::text, false);
  PERFORM set_config('test.student_col', v_student_col::text, false);
  PERFORM set_config('test.pass_cancelled', v_pass_cancelled::text, false);
  PERFORM set_config('test.pass_res_shell', v_pass_res_shell::text, false);
  PERFORM set_config('test.lesson_cancelled', v_lesson_cancelled::text, false);
  PERFORM set_config('test.lesson_shell', v_lesson_shell::text, false);
  PERFORM set_config('test.lesson_collision_block', v_lesson_collision_block::text, false);
  PERFORM set_config('test.lesson_collision_teacher_b', v_lesson_collision_teacher_b::text, false);
  PERFORM set_config('test.lesson_actual_times', v_lesson_actual_times::text, false);
  PERFORM set_config('test.lesson_makeup', v_lesson_makeup::text, false);
  PERFORM set_config('test.lesson_makeup_source', v_lesson_makeup_source::text, false);
  PERFORM set_config('test.lesson_collision_target', v_lesson_collision_target::text, false);
  PERFORM set_config('test.enroll_date', v_enroll_date::text, false);
  PERFORM set_config('test.collision_anchor', v_collision_anchor::text, false);
  PERFORM set_config('test.collision_partial', (v_collision_anchor + interval '30 minutes')::text, false);
  PERFORM set_config('test.collision_adjacent', (v_collision_anchor + interval '1 hour')::text, false);
  PERFORM set_config('test.approved_new_time', timestamptz '2026-08-17 11:00:00+09'::text, false);
  PERFORM set_config('test.approved_postponed_time', timestamptz '2026-08-24 11:00:00+09'::text, false);
  PERFORM set_config('test.diff_teacher_time', timestamptz '2026-10-06 11:00:00+09'::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.review_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_review_schedule_change_request(uuid,text,timestamptz,text,timestamptz)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.apply_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_apply_schedule_change_request(uuid,timestamptz,timestamptz)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count()
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count_for(p_action text)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs WHERE action = p_action;
$$;

CREATE OR REPLACE FUNCTION pg_temp.request_updated_at(p_request uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.schedule_change_requests WHERE id = p_request;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_count_for_pass(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.active_slot_count(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass AND ss.is_active = true;
$$;

CREATE OR REPLACE FUNCTION pg_temp.used_count_for_pass(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass
    AND l.status IN ('completed', 'same_day_cancelled', 'makeup_completed');
$$;

CREATE OR REPLACE FUNCTION pg_temp.schedule_change_event_count(p_request uuid DEFAULT NULL)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*)
  FROM public.lesson_schedule_changes AS lsc
  WHERE p_request IS NULL OR lsc.schedule_change_request_id = p_request;
$$;

CREATE OR REPLACE FUNCTION pg_temp.seed_request(
  p_student uuid,
  p_lesson uuid,
  p_profile uuid,
  p_source_role text,
  p_reason text,
  p_proposed timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  RESET ROLE;
  INSERT INTO public.schedule_change_requests (
    student_id, target_lesson_id, requesting_profile_id,
    request_source_role, requested_reason, proposed_scheduled_at
  ) VALUES (
    p_student, p_lesson, p_profile, p_source_role, p_reason, p_proposed
  )
  RETURNING id INTO v_id;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '11:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.student_b_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 3,
    'local_time', '14:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

-- ---------------------------------------------------------------------------
-- Bootstrap owner and enroll primary passes via initial enrollment RPC
-- ---------------------------------------------------------------------------
SET ROLE service_role;
SELECT ok(
  (SELECT role FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner1')::uuid, 'SCW First Owner'
   ) LIMIT 1) = 'owner',
  'bootstrap creates first owner profile'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT ok(
  (SELECT role FROM public.reve_owner_provision_profile(
     current_setting('test.owner2')::uuid, 'owner', 'SCW Second Owner', NULL, NULL
   ) LIMIT 1) = 'owner',
  'second owner provisioned for inactive-owner security test'
);

DO $$
DECLARE
  v_pass_a uuid;
  v_pass_b uuid;
  v_lesson_1 uuid;
  v_lesson_2 uuid;
  v_lesson_3 uuid;
  v_lesson_4 uuid;
  v_slot_a uuid;
BEGIN
  SELECT pass_id INTO v_pass_a
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_a')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json(),
    200000, 'cash', now(), 'scw-a-enroll', 'SCW student A fixture'
  )
  LIMIT 1;

  SELECT pass_id INTO v_pass_b
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_b')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.student_b_slot_json(),
    200000, 'card', now(), 'scw-b-enroll', 'SCW student B fixture'
  )
  LIMIT 1;

  SELECT l.id INTO v_lesson_1
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_a AND l.sequence_number = 1;

  SELECT l.id INTO v_lesson_2
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_a AND l.sequence_number = 2;

  SELECT l.id INTO v_lesson_3
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_a AND l.sequence_number = 3;

  SELECT l.id INTO v_lesson_4
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_a AND l.sequence_number = 4;

  SELECT ss.id INTO v_slot_a
  FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass_a AND ss.is_active = true
  ORDER BY ss.slot_order
  LIMIT 1;

  PERFORM public.reve_transition_lesson_status(
    v_lesson_1, 'completed',
    pg_temp.lesson_updated_at(v_lesson_1),
    now() - interval '2 days', now() - interval '2 days' + interval '1 hour',
    'SCW fixture completed lesson'
  );

  PERFORM public.reve_transition_lesson_status(
    v_lesson_3, 'postponed',
    pg_temp.lesson_updated_at(v_lesson_3),
    NULL, NULL,
    'SCW fixture postponed lesson'
  );

  PERFORM public.reve_transition_lesson_status(
    v_lesson_4, 'same_day_cancelled',
    pg_temp.lesson_updated_at(v_lesson_4),
    NULL, NULL,
    'SCW fixture same-day cancelled lesson'
  );

  PERFORM set_config('test.pass_a', v_pass_a::text, false);
  PERFORM set_config('test.pass_b', v_pass_b::text, false);
  PERFORM set_config('test.slot_a', v_slot_a::text, false);
  PERFORM set_config('test.lesson_1', v_lesson_1::text, false);
  PERFORM set_config('test.lesson_2', v_lesson_2::text, false);
  PERFORM set_config('test.lesson_3', v_lesson_3::text, false);
  PERFORM set_config('test.lesson_4', v_lesson_4::text, false);
  PERFORM set_config('test.lesson_2_scheduled_at',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_lesson_2), false);
  PERFORM set_config('test.lesson_3_scheduled_at',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_lesson_3), false);
END $$;

RESET ROLE;
DO $$
DECLARE
  v_pass_a uuid := current_setting('test.pass_a')::uuid;
  v_pass_b uuid := current_setting('test.pass_b')::uuid;
  v_slot_a uuid := current_setting('test.slot_a')::uuid;
BEGIN
  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    actual_start_at, actual_end_at
  ) VALUES (
    current_setting('test.lesson_actual_times')::uuid,
    v_pass_a, current_setting('test.student_a')::uuid, current_setting('test.course_vocal')::uuid,
    current_setting('test.teacher_a')::uuid, v_slot_a, 5,
    timestamptz '2026-09-07 11:00:00+09', 'scheduled',
    timestamptz '2026-09-07 11:00:00+09', timestamptz '2026-09-07 12:00:00+09'
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    current_setting('test.lesson_makeup_source')::uuid,
    v_pass_a, current_setting('test.student_a')::uuid, current_setting('test.course_vocal')::uuid,
    current_setting('test.teacher_a')::uuid, v_slot_a, 6,
    timestamptz '2026-09-14 11:00:00+09', 'completed'
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    makeup_source_lesson_id
  ) VALUES (
    current_setting('test.lesson_makeup')::uuid,
    v_pass_a, current_setting('test.student_a')::uuid, current_setting('test.course_vocal')::uuid,
    current_setting('test.teacher_a')::uuid, v_slot_a, 7,
    timestamptz '2026-09-21 11:00:00+09', 'makeup_completed',
    current_setting('test.lesson_makeup_source')::uuid
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    current_setting('test.lesson_collision_block')::uuid,
    v_pass_a, current_setting('test.student_a')::uuid, current_setting('test.course_vocal')::uuid,
    current_setting('test.teacher_a')::uuid, v_slot_a, 8,
    current_setting('test.collision_anchor')::timestamptz, 'scheduled'
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    current_setting('test.lesson_collision_teacher_b')::uuid,
    v_pass_b, current_setting('test.student_b')::uuid, current_setting('test.course_vocal')::uuid,
    current_setting('test.teacher_b')::uuid, NULL, 5,
    current_setting('test.diff_teacher_time')::timestamptz, 'scheduled'
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    current_setting('test.lesson_collision_target')::uuid,
    v_pass_a, current_setting('test.student_a')::uuid, current_setting('test.course_vocal')::uuid,
    current_setting('test.teacher_a')::uuid, v_slot_a, 9,
    timestamptz '2026-10-05 11:00:00+09', 'scheduled'
  );

  PERFORM set_config('test.lesson_count_a', pg_temp.lesson_count_for_pass(v_pass_a)::text, false);
  PERFORM set_config('test.used_before_a', pg_temp.used_count_for_pass(v_pass_a)::text, false);
  PERFORM set_config('test.active_slots_before_a', pg_temp.active_slot_count(v_pass_a)::text, false);
  PERFORM set_config('test.sms_before_a',
    (SELECT status FROM public.sms_notifications WHERE pass_id = v_pass_a LIMIT 1), false);
  PERFORM set_config('test.payment_before_a',
    (SELECT paid_amount_krw::text FROM public.payments WHERE renewed_pass_id = v_pass_a LIMIT 1), false);
END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

-- ---------------------------------------------------------------------------
-- Security (12)
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_owner_review_schedule_change_request',
  ARRAY['uuid', 'text', 'timestamptz', 'text', 'timestamptz']
);

SELECT has_function(
  'public', 'reve_owner_apply_schedule_change_request',
  ARRAY['uuid', 'timestamptz', 'timestamptz']
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname IN (
        'reve_owner_review_schedule_change_request',
        'reve_owner_apply_schedule_change_request'
      )
  ),
  'schedule change RPCs use fixed empty search_path'
);

SELECT ok(
  (
    SELECT bool_and(r.rolname = 'postgres')
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE ns.nspname = 'public'
      AND p.proname IN (
        'reve_owner_review_schedule_change_request',
        'reve_owner_apply_schedule_change_request'
      )
  ),
  'schedule change RPCs owned by postgres'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.review_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_review_schedule_change_request'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       gen_random_uuid(), 'approve', now(), 'anon review', now()) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       gen_random_uuid(), 'approve', now(), 'teacher review', now()) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       gen_random_uuid(), 'approve', now(), 'student review', now()) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.spoof_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       gen_random_uuid(), 'approve', now(), 'spoof review', now()) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

DO $$
BEGIN
  PERFORM public.reve_owner_set_profile_active(
    current_setting('test.owner1')::uuid,
    'inactive', 'SCW inactive owner test',
    (SELECT updated_at FROM public.profiles WHERE id = current_setting('test.owner1')::uuid)
  );
END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       gen_random_uuid(), 'approve', now(), 'inactive review', now()) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;
SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner1')::uuid,
     'active', 'reactivate first owner for remaining SCW tests',
     (SELECT updated_at FROM public.profiles WHERE id = current_setting('test.owner1')::uuid)
   ) LIMIT 1) = 'active',
  'reactivate first owner after inactive-owner denial test'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

DO $$
BEGIN
  PERFORM set_config('test.req_security',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_2')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Security direct update probe')::text, false);
END $$;

SELECT throws_ok(
  $$ UPDATE public.schedule_change_requests
     SET status = 'approved'
     WHERE id = current_setting('test.req_security')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ UPDATE public.lessons
     SET scheduled_at = now()
     WHERE id = current_setting('test.lesson_2')::uuid $$,
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

-- ---------------------------------------------------------------------------
-- Requester isolation (6)
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a_auth')::uuid); END $$;

SELECT lives_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason
     ) VALUES (
       current_setting('test.student_a')::uuid,
       current_setting('test.lesson_2')::uuid,
       current_setting('test.student_a_auth')::uuid,
       'student', 'Student A own lesson request'
     ) $$,
  'student A can insert schedule change request for own lesson'
);

SELECT throws_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason
     ) VALUES (
       current_setting('test.student_a')::uuid,
       (SELECT l.id FROM public.lessons AS l
        WHERE l.pass_id = current_setting('test.pass_b')::uuid
        ORDER BY l.sequence_number LIMIT 1),
       current_setting('test.student_a_auth')::uuid,
       'student', 'Student A cross-student attempt'
     ) $$,
  '42501'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a_auth')::uuid); END $$;

SELECT lives_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason
     ) VALUES (
       current_setting('test.student_a')::uuid,
       current_setting('test.lesson_2')::uuid,
       current_setting('test.teacher_a_auth')::uuid,
       'teacher', 'Assigned teacher request'
     ) $$,
  'assigned teacher can insert schedule change request'
);

SELECT throws_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason
     ) VALUES (
       current_setting('test.student_b')::uuid,
       (SELECT l.id FROM public.lessons AS l
        WHERE l.pass_id = current_setting('test.pass_b')::uuid
        ORDER BY l.sequence_number LIMIT 1),
       current_setting('test.teacher_a_auth')::uuid,
       'teacher', 'Unassigned teacher attempt'
     ) $$,
  '42501'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a_auth')::uuid); END $$;
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.schedule_change_requests AS scr
    WHERE scr.requesting_profile_id = current_setting('test.student_a_auth')::uuid
      AND scr.target_lesson_id = current_setting('test.lesson_2')::uuid
  ),
  'student A can read own submitted schedule change requests'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a_auth')::uuid); END $$;
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.schedule_change_requests AS scr
    WHERE scr.request_source_role = 'teacher'
      AND scr.requesting_profile_id = current_setting('test.teacher_a_auth')::uuid
  ),
  'assigned teacher can read own submitted schedule change requests'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

-- ---------------------------------------------------------------------------
-- Regression (4)
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a_auth')::uuid); END $$;
SELECT lives_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason, proposed_scheduled_at
     ) VALUES (
       current_setting('test.student_a')::uuid,
       current_setting('test.lesson_2')::uuid,
       current_setting('test.student_a_auth')::uuid,
       'student', 'Regression student insert',
       current_setting('test.approved_new_time')::timestamptz
     ) $$,
  'regression: student schedule change request INSERT still works'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a_auth')::uuid); END $$;
SELECT lives_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason, proposed_scheduled_at
     ) VALUES (
       current_setting('test.student_a')::uuid,
       current_setting('test.lesson_2')::uuid,
       current_setting('test.teacher_a_auth')::uuid,
       'teacher', 'Regression teacher insert',
       current_setting('test.approved_new_time')::timestamptz
     ) $$,
  'regression: teacher schedule change request INSERT still works'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a_auth')::uuid); END $$;
SELECT throws_ok(
  $$ UPDATE public.schedule_change_requests
     SET status = 'approved'
     WHERE target_lesson_id = current_setting('test.lesson_2')::uuid $$,
  '42501'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a_auth')::uuid); END $$;
SELECT throws_ok(
  $$ UPDATE public.schedule_change_requests
     SET owner_decision_note = 'teacher override'
     WHERE request_source_role = 'teacher' $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

-- ---------------------------------------------------------------------------
-- Review (12)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.req_review_approve',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_2')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Review approve submitted',
      current_setting('test.approved_new_time')::timestamptz)::text, false);
END $$;

SELECT ok(
  (
    SELECT new_request_status = 'approved'
      AND previous_request_status = 'submitted'
      AND decision = 'approve'
      AND no_change = false
      AND approved_scheduled_at = current_setting('test.approved_new_time')::timestamptz
    FROM public.reve_owner_review_schedule_change_request(
      current_setting('test.req_review_approve')::uuid,
      'approve',
      pg_temp.request_updated_at(current_setting('test.req_review_approve')::uuid),
      'Owner approved new time',
      current_setting('test.approved_new_time')::timestamptz
    )
    LIMIT 1
  ),
  'owner approve moves submitted request to approved'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid),
  current_setting('test.lesson_2_scheduled_at')::timestamptz,
  'approval does not change target lesson scheduled_at'
);

SELECT is(
  (SELECT approved_scheduled_at FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_review_approve')::uuid),
  current_setting('test.approved_new_time')::timestamptz,
  'approval stores approved_scheduled_at on request row'
);

DO $$
BEGIN
  PERFORM set_config('test.req_review_reject',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_2')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Review reject submitted')::text, false);
END $$;

SELECT ok(
  (
    SELECT new_request_status = 'rejected'
      AND previous_request_status = 'submitted'
      AND decision = 'reject'
      AND no_change = false
    FROM public.reve_owner_review_schedule_change_request(
      current_setting('test.req_review_reject')::uuid,
      'reject',
      pg_temp.request_updated_at(current_setting('test.req_review_reject')::uuid),
      'Owner rejected request',
      NULL
    )
    LIMIT 1
  ),
  'owner reject moves submitted request to rejected'
);

DO $$
BEGIN
  PERFORM set_config('test.req_review_reason',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_2')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Review reason required probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_review_reason')::uuid,
       'reject',
       pg_temp.request_updated_at(current_setting('test.req_review_reason')::uuid),
       '   ',
       NULL) $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_review_approve')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_review_approve')::uuid),
       'Cannot review applied',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'P0001',
  'REVE_REQUEST_NOT_REVIEWABLE'
);

DO $$
BEGIN
  PERFORM set_config('test.req_review_stale',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_2')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Review stale probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_review_stale')::uuid,
       'approve',
       timestamptz '2000-01-01 00:00:00+00',
       'Stale review',
       current_setting('test.approved_new_time')::timestamptz) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT ok(
  (
    SELECT no_change = true
      AND new_request_status = 'approved'
      AND approved_scheduled_at = current_setting('test.approved_new_time')::timestamptz
    FROM public.reve_owner_review_schedule_change_request(
      current_setting('test.req_review_approve')::uuid,
      'approve',
      pg_temp.request_updated_at(current_setting('test.req_review_approve')::uuid),
      'Owner approved new time',
      current_setting('test.approved_new_time')::timestamptz
    )
    LIMIT 1
  ),
  'identical approve replay returns no_change true'
);

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_2')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Review idempotent reject');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'reject',
    pg_temp.request_updated_at(v_request),
    'Owner rejected once', NULL
  );
  PERFORM set_config('test.req_idempotent_reject', v_request::text, false);
END $$;

SELECT ok(
  (
    SELECT no_change = true AND new_request_status = 'rejected'
    FROM public.reve_owner_review_schedule_change_request(
      current_setting('test.req_idempotent_reject')::uuid,
      'reject',
      pg_temp.request_updated_at(current_setting('test.req_idempotent_reject')::uuid),
      'Owner rejected once',
      NULL
    )
    LIMIT 1
  ),
  'identical reject replay returns no_change true'
);

DO $$
BEGIN
  PERFORM set_config('test.audit_before_review',
    pg_temp.audit_count_for('schedule_change_request.reviewed')::text, false);
END $$;

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_2')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Review audit probe');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Audit on approve',
    current_setting('test.approved_new_time')::timestamptz
  );
  PERFORM set_config('test.req_review_audit', v_request::text, false);
END $$;

SELECT ok(
  pg_temp.audit_count_for('schedule_change_request.reviewed')
    > current_setting('test.audit_before_review')::bigint,
  'successful review writes schedule_change_request.reviewed audit'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_review_stale')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_review_stale')::uuid),
       'Missing approved time',
       NULL) $$,
  'P0001',
  'REVE_APPROVED_TIME_REQUIRED'
);

-- ---------------------------------------------------------------------------
-- Lesson state (10)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.req_lesson_scheduled',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_2')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Scheduled lesson ok')::text, false);
END $$;

SELECT lives_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_lesson_scheduled')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_lesson_scheduled')::uuid),
       'Scheduled lesson approve ok',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'scheduled lesson can be approved for schedule change'
);

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_3')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Postponed lesson approve');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Postponed lesson approved',
    current_setting('test.approved_postponed_time')::timestamptz
  );
  PERFORM set_config('test.req_lesson_postponed', v_request::text, false);
END $$;

SELECT ok(
  (
    SELECT new_lesson_status = 'scheduled'
      AND previous_lesson_status = 'postponed'
      AND new_scheduled_at = current_setting('test.approved_postponed_time')::timestamptz
    FROM public.reve_owner_apply_schedule_change_request(
      current_setting('test.req_lesson_postponed')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_lesson_postponed')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.lesson_3')::uuid)
    )
    LIMIT 1
  ),
  'apply on postponed lesson restores status to scheduled'
);

DO $$
BEGIN
  PERFORM set_config('test.req_lesson_completed',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_1')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Completed lesson probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_lesson_completed')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_lesson_completed')::uuid),
       'Completed lesson',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'P0001',
  'REVE_LESSON_NOT_CHANGEABLE'
);

DO $$
BEGIN
  PERFORM set_config('test.req_lesson_sdc',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_4')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Same-day cancelled probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_lesson_sdc')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_lesson_sdc')::uuid),
       'Same-day cancelled lesson',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'P0001',
  'REVE_LESSON_NOT_CHANGEABLE'
);

DO $$
BEGIN
  PERFORM set_config('test.req_lesson_makeup',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_makeup')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Makeup completed probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_lesson_makeup')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_lesson_makeup')::uuid),
       'Makeup completed lesson',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'P0001',
  'REVE_LESSON_NOT_CHANGEABLE'
);

DO $$
BEGIN
  PERFORM set_config('test.req_lesson_actual',
    pg_temp.seed_request(
      current_setting('test.student_a')::uuid,
      current_setting('test.lesson_actual_times')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Actual times probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_lesson_actual')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_lesson_actual')::uuid),
       'Actual times lesson',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'P0001',
  'REVE_SCHEDULE_CHANGE_DENIED'
);

DO $$
BEGIN
  PERFORM set_config('test.req_lesson_shell',
    pg_temp.seed_request(
      current_setting('test.student_col')::uuid,
      current_setting('test.lesson_shell')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Shell lesson probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_lesson_shell')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_lesson_shell')::uuid),
       'Null scheduled_at shell',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'P0001',
  'REVE_LESSON_NOT_CHANGEABLE'
);

DO $$
BEGIN
  PERFORM set_config('test.req_lesson_cancelled_pass',
    pg_temp.seed_request(
      current_setting('test.student_col')::uuid,
      current_setting('test.lesson_cancelled')::uuid,
      current_setting('test.student_a_auth')::uuid,
      'student', 'Cancelled pass probe')::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_lesson_cancelled_pass')::uuid,
       'approve',
       pg_temp.request_updated_at(current_setting('test.req_lesson_cancelled_pass')::uuid),
       'Cancelled pass lesson',
       current_setting('test.approved_new_time')::timestamptz) $$,
  'P0001',
  'REVE_SCHEDULE_CHANGE_DENIED'
);

-- ---------------------------------------------------------------------------
-- Concurrency (6)
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT status FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_review_stale')::uuid),
  'submitted',
  'stale review leaves request in submitted status'
);

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_collision_target')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Apply stale request probe');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Approved for stale apply',
    timestamptz '2026-10-12 11:00:00+09'
  );
  PERFORM set_config('test.req_apply_stale_request', v_request::text, false);
  PERFORM set_config('test.collision_target_before_stale_apply',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.lesson_collision_target')::uuid), false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_apply_stale_request')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       pg_temp.lesson_updated_at(current_setting('test.lesson_collision_target')::uuid)) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT is(
  (SELECT status FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_apply_stale_request')::uuid),
  'approved',
  'stale apply leaves request approved but unapplied'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons
   WHERE id = current_setting('test.lesson_collision_target')::uuid),
  current_setting('test.collision_target_before_stale_apply')::timestamptz,
  'stale apply leaves lesson scheduled_at unchanged'
);

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_2')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Apply stale lesson probe');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Approved for stale lesson apply',
    current_setting('test.approved_new_time')::timestamptz
  );
  PERFORM set_config('test.req_apply_stale_lesson', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_apply_stale_lesson')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_apply_stale_lesson')::uuid),
       timestamptz '2000-01-01 00:00:00+00') $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_review_schedule_change_request(
       current_setting('test.req_review_stale')::uuid,
       'reject',
       timestamptz '2000-01-01 00:00:00+00',
       'Stale reject attempt',
       NULL) $$,
  '22000',
  'REVE_STALE_STATE'
);

-- ---------------------------------------------------------------------------
-- Collision (10)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_request uuid;
  v_before_events bigint;
  v_before_apply_audit bigint;
  v_before_reschedule_audit bigint;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_collision_target')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Collision exact overlap');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Exact collision approve',
    current_setting('test.collision_anchor')::timestamptz
  );

  v_before_events := pg_temp.schedule_change_event_count(v_request);
  v_before_apply_audit := pg_temp.audit_count_for('schedule_change_request.applied');
  v_before_reschedule_audit := pg_temp.audit_count_for('lesson.rescheduled');

  PERFORM set_config('test.req_collision_exact', v_request::text, false);
  PERFORM set_config('test.events_before_collision', v_before_events::text, false);
  PERFORM set_config('test.apply_audit_before_collision', v_before_apply_audit::text, false);
  PERFORM set_config('test.reschedule_audit_before_collision', v_before_reschedule_audit::text, false);
  PERFORM set_config('test.collision_target_before',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.lesson_collision_target')::uuid), false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_collision_exact')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_collision_exact')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_collision_target')::uuid)) $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

SELECT is(
  (SELECT status FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_collision_exact')::uuid),
  'approved',
  'collision abort leaves request approved and unapplied'
);

SELECT is(
  pg_temp.schedule_change_event_count(current_setting('test.req_collision_exact')::uuid),
  current_setting('test.events_before_collision')::bigint,
  'collision abort writes no lesson_schedule_changes event'
);

SELECT is(
  pg_temp.audit_count_for('schedule_change_request.applied'),
  current_setting('test.apply_audit_before_collision')::bigint,
  'collision abort writes no schedule_change_request.applied audit'
);

SELECT is(
  pg_temp.audit_count_for('lesson.rescheduled'),
  current_setting('test.reschedule_audit_before_collision')::bigint,
  'collision abort writes no lesson.rescheduled audit'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons
   WHERE id = current_setting('test.lesson_collision_target')::uuid),
  current_setting('test.collision_target_before')::timestamptz,
  'collision abort leaves target lesson scheduled_at unchanged'
);

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_collision_target')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Collision partial overlap');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Partial collision approve',
    current_setting('test.collision_partial')::timestamptz
  );
  PERFORM set_config('test.req_collision_partial', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_collision_partial')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_collision_partial')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_collision_target')::uuid)) $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_collision_target')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Collision adjacent ok');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Adjacent slot approve',
    current_setting('test.collision_adjacent')::timestamptz
  );
  PERFORM set_config('test.req_collision_adjacent', v_request::text, false);
END $$;

SELECT lives_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_collision_adjacent')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_collision_adjacent')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_collision_target')::uuid)) $$,
  'adjacent teacher slot does not collide'
);

DO $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_collision_target')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Different teacher collision ok');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Different teacher overlap ok',
    current_setting('test.diff_teacher_time')::timestamptz
  );
  PERFORM set_config('test.req_collision_diff_teacher', v_request::text, false);
END $$;

SELECT lives_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_collision_diff_teacher')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_collision_diff_teacher')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_collision_target')::uuid)) $$,
  'overlapping time on different teacher does not block apply'
);

-- ---------------------------------------------------------------------------
-- Apply (14)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_request uuid;
  v_other_sched timestamptz;
  v_before_sched timestamptz;
BEGIN
  SELECT scheduled_at INTO v_other_sched
  FROM public.lessons
  WHERE id = current_setting('test.lesson_1')::uuid;

  SELECT scheduled_at INTO v_before_sched
  FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid;

  v_request := pg_temp.seed_request(
    current_setting('test.student_a')::uuid,
    current_setting('test.lesson_2')::uuid,
    current_setting('test.student_a_auth')::uuid,
    'student', 'Apply happy path');

  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'approve',
    pg_temp.request_updated_at(v_request),
    'Apply happy path approved',
    current_setting('test.approved_new_time')::timestamptz
  );

  PERFORM set_config('test.req_apply_main', v_request::text, false);
  PERFORM set_config('test.other_lesson_sched_before', v_other_sched::text, false);
  PERFORM set_config('test.lesson_2_before_apply', v_before_sched::text, false);
  PERFORM set_config('test.audit_before_apply',
    pg_temp.audit_count_for('schedule_change_request.applied')::text, false);
  PERFORM set_config('test.reschedule_audit_before_apply',
    pg_temp.audit_count_for('lesson.rescheduled')::text, false);
  PERFORM set_config('test.events_before_apply',
    pg_temp.schedule_change_event_count(v_request)::text, false);
END $$;

SELECT ok(
  (
    SELECT request_status = 'applied'
      AND new_scheduled_at = current_setting('test.approved_new_time')::timestamptz
      AND previous_scheduled_at = current_setting('test.lesson_2_before_apply')::timestamptz
      AND cascaded_lesson_count = 0
      AND no_change = false
      AND schedule_change_event_id IS NOT NULL
    FROM public.reve_owner_apply_schedule_change_request(
      current_setting('test.req_apply_main')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_apply_main')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.lesson_2')::uuid)
    )
    LIMIT 1
  ),
  'approved request apply updates lesson and marks request applied'
);

DO $$
BEGIN
  PERFORM set_config('test.events_after_first_apply',
    pg_temp.schedule_change_event_count(current_setting('test.req_apply_main')::uuid)::text, false);
END $$;

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid),
  current_setting('test.approved_new_time')::timestamptz,
  'apply sets lesson scheduled_at to approved_scheduled_at'
);

SELECT ok(
  (
    SELECT lsc.change_origin = 'direct_user'
      AND lsc.previous_scheduled_at = current_setting('test.lesson_2_before_apply')::timestamptz
      AND lsc.new_scheduled_at = current_setting('test.approved_new_time')::timestamptz
    FROM public.lesson_schedule_changes AS lsc
    WHERE lsc.schedule_change_request_id = current_setting('test.req_apply_main')::uuid
    ORDER BY lsc.created_at ASC
    LIMIT 1
  ),
  'apply inserts direct_user lesson_schedule_changes event'
);

SELECT ok(
  (
    SELECT status = 'applied' AND applied_at IS NOT NULL
    FROM public.schedule_change_requests
    WHERE id = current_setting('test.req_apply_main')::uuid
  ),
  'apply sets request status applied with applied_at timestamp'
);

SELECT is(
  (SELECT schedule_slot_id FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid),
  current_setting('test.slot_a')::uuid,
  'apply leaves schedule_slot_id unchanged'
);

SELECT is(
  (SELECT assigned_teacher_id FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid),
  current_setting('test.teacher_a')::uuid,
  'apply leaves assigned_teacher_id unchanged'
);

SELECT is(
  (SELECT sequence_number FROM public.lessons WHERE id = current_setting('test.lesson_2')::uuid),
  2,
  'apply leaves lesson sequence_number unchanged'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_1')::uuid),
  current_setting('test.other_lesson_sched_before')::timestamptz,
  'apply changes only the target lesson row'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_review_reject')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_review_reject')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_2')::uuid)) $$,
  'P0001',
  'REVE_REQUEST_NOT_APPLICABLE'
);

SELECT ok(
  (
    SELECT no_change = true
      AND request_status = 'applied'
    FROM public.reve_owner_apply_schedule_change_request(
      current_setting('test.req_apply_main')::uuid,
      timestamptz '2000-01-01 00:00:00+00',
      pg_temp.lesson_updated_at(current_setting('test.lesson_2')::uuid)
    )
    LIMIT 1
  ),
  'already applied request with stale timestamp returns idempotent no_change'
);

SELECT ok(
  (
    SELECT no_change = true
      AND request_status = 'applied'
      AND new_scheduled_at = current_setting('test.approved_new_time')::timestamptz
    FROM public.reve_owner_apply_schedule_change_request(
      current_setting('test.req_apply_main')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_apply_main')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.lesson_2')::uuid)
    )
    LIMIT 1
  ),
  'identical apply replay returns no_change true'
);

DO $$
BEGIN
  PERFORM set_config('test.events_after_idempotent_apply',
    pg_temp.schedule_change_event_count(current_setting('test.req_apply_main')::uuid)::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_apply_schedule_change_request(
       current_setting('test.req_review_stale')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_review_stale')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_2')::uuid)) $$,
  'P0001',
  'REVE_REQUEST_NOT_APPLICABLE'
);

SELECT ok(
  pg_temp.audit_count_for('schedule_change_request.applied')
    > current_setting('test.audit_before_apply')::bigint,
  'successful apply writes schedule_change_request.applied audit'
);

SELECT ok(
  pg_temp.audit_count_for('lesson.rescheduled')
    > current_setting('test.reschedule_audit_before_apply')::bigint,
  'successful apply writes lesson.rescheduled audit'
);

-- ---------------------------------------------------------------------------
-- Fixed timetable (6)
-- ---------------------------------------------------------------------------
SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_a')::uuid),
  current_setting('test.active_slots_before_a')::integer,
  'apply does not change active schedule slot count'
);

SELECT is(
  pg_temp.lesson_count_for_pass(current_setting('test.pass_a')::uuid),
  current_setting('test.lesson_count_a')::integer,
  'apply does not add or remove lesson rows'
);

SELECT is(
  (SELECT target_date FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_a')::uuid
   ORDER BY created_at DESC LIMIT 1),
  (
    SELECT ((max(l.scheduled_at) AT TIME ZONE 'Asia/Seoul')::date - 1)
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_a')::uuid
  ),
  'apply keeps SMS target_date aligned with final lesson when max scheduled_at is unchanged'
);

SELECT is(
  (SELECT paid_amount_krw FROM public.payments
   WHERE renewed_pass_id = current_setting('test.pass_a')::uuid
   LIMIT 1),
  current_setting('test.payment_before_a')::integer,
  'apply leaves linked payment amount unchanged'
);

SELECT is(
  pg_temp.used_count_for_pass(current_setting('test.pass_a')::uuid),
  current_setting('test.used_before_a')::integer,
  'apply leaves deductible used lesson count unchanged'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = current_setting('test.pass_a')::uuid
      AND ss.created_at > (
        SELECT min(lsc.created_at)
        FROM public.lesson_schedule_changes AS lsc
        WHERE lsc.schedule_change_request_id = current_setting('test.req_apply_main')::uuid
      )
  ),
  'apply creates no new schedule_slots rows'
);

-- ---------------------------------------------------------------------------
-- Append-only (6)
-- ---------------------------------------------------------------------------
SELECT is(
  pg_temp.schedule_change_event_count(current_setting('test.req_apply_main')::uuid),
  1::bigint,
  'exactly one lesson_schedule_changes event per successful apply'
);

SELECT is(
  pg_temp.schedule_change_event_count(current_setting('test.req_review_reject')::uuid),
  0::bigint,
  'reject review creates no lesson_schedule_changes event'
);

SELECT is(
  pg_temp.schedule_change_event_count(current_setting('test.req_review_approve')::uuid),
  0::bigint,
  'approve review alone creates no lesson_schedule_changes event'
);

SELECT throws_ok(
  $$ UPDATE public.lesson_schedule_changes
     SET reason = 'mutated'
     WHERE schedule_change_request_id = current_setting('test.req_apply_main')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ DELETE FROM public.lesson_schedule_changes
     WHERE schedule_change_request_id = current_setting('test.req_apply_main')::uuid $$,
  '42501'
);

SELECT is(
  current_setting('test.events_after_idempotent_apply')::bigint,
  current_setting('test.events_after_first_apply')::bigint,
  'idempotent apply replay does not append a second schedule change event'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();

ROLLBACK;

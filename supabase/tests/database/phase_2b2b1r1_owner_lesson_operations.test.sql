-- REVE ACADEMY OS Phase 2B-2B1R1 — owner direct lesson reschedule pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(26);

-- ---------------------------------------------------------------------------
-- Fixture: auth users, courses/products, teachers, students
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa031';
  v_owner2 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa032';
  v_teacher_a_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd031';
  v_student_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb031';
  v_spoof_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd033';
  v_teacher_a uuid := '22222222-2222-2222-2222-222222222031';
  v_course_vocal uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee31';
  v_product_4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff31';
  v_student_w1 uuid := '44444444-4444-4444-4444-444444444031';
  v_student_completed uuid := '44444444-4444-4444-4444-444444444032';
  v_enroll_date date := '2026-09-07';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner1-olo@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner2-olo@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_a_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-a-olo@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-olo@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_spoof_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'spoof-olo@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_student_auth, 'student', 'OLO Student Profile', 'active'),
    (v_teacher_a_auth, 'teacher', 'OLO Teacher A Profile', 'active');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher_a, 'T-OLO-A', v_teacher_a_auth, 'OLO Teacher A', '010-0000-0031', 'ta-olo@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student_w1, 'S031', v_student_auth, 'OLO Weekly Once Student', 'active'),
    (v_student_completed, 'S032', NULL, 'OLO Completed Lesson Student', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course_vocal, 'VOCAL', 'Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES
    (v_product_4, v_course_vocal, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000, true);

  PERFORM set_config('test.owner1', v_owner1::text, false);
  PERFORM set_config('test.owner2', v_owner2::text, false);
  PERFORM set_config('test.teacher_a_auth', v_teacher_a_auth::text, false);
  PERFORM set_config('test.student_auth', v_student_auth::text, false);
  PERFORM set_config('test.spoof_auth', v_spoof_auth::text, false);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, false);
  PERFORM set_config('test.course_vocal', v_course_vocal::text, false);
  PERFORM set_config('test.product_4', v_product_4::text, false);
  PERFORM set_config('test.student_w1', v_student_w1::text, false);
  PERFORM set_config('test.student_completed', v_student_completed::text, false);
  PERFORM set_config('test.enroll_date', v_enroll_date::text, false);
  PERFORM set_config('test.valid_new_time', timestamptz '2026-09-21 14:00:00+09'::text, false);
  PERFORM set_config('test.hours_before_open', timestamptz '2026-09-21 12:00:00+09'::text, false);
  PERFORM set_config('test.hours_at_close', timestamptz '2026-09-21 22:00:00+09'::text, false);
  PERFORM set_config('test.hours_end_after_close', timestamptz '2026-09-21 21:30:00+09'::text, false);
  PERFORM set_config('test.hours_last_window', timestamptz '2026-09-21 21:00:00+09'::text, false);
  PERFORM set_config('test.l3_cascade_expected', timestamptz '2026-09-28 11:00:00+09'::text, false);
  PERFORM set_config('test.l4_cascade_expected', timestamptz '2026-10-05 11:00:00+09'::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.direct_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_direct_reschedule_lesson(uuid,timestamptz,timestamptz,text,boolean,timestamptz)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count_for(p_action text)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs WHERE action = p_action;
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_once()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '11:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_wed()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 3,
    'local_time', '14:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.direct_reschedule(
  p_lesson uuid,
  p_new_time timestamptz,
  p_reason text DEFAULT 'Owner direct reschedule',
  p_cascade boolean DEFAULT false,
  p_pass uuid DEFAULT NULL
)
RETURNS TABLE (
  no_change boolean,
  cascaded_lesson_count integer,
  schedule_change_event_id uuid
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_pass uuid;
BEGIN
  IF p_pass IS NULL THEN
    SELECT pass_id INTO v_pass FROM public.lessons WHERE id = p_lesson;
  ELSE
    v_pass := p_pass;
  END IF;

  RETURN QUERY
  SELECT
    r.no_change,
    r.cascaded_lesson_count,
    r.schedule_change_event_id
  FROM public.reve_owner_direct_reschedule_lesson(
    p_lesson,
    p_new_time,
    pg_temp.lesson_updated_at(p_lesson),
    p_reason,
    p_cascade,
    CASE WHEN p_cascade THEN pg_temp.pass_updated_at(v_pass) ELSE NULL END
  ) AS r;
END;
$$;

-- ---------------------------------------------------------------------------
-- Bootstrap owner and enroll fixture pass
-- ---------------------------------------------------------------------------
SET ROLE service_role;
SELECT ok(
  (SELECT role FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner1')::uuid, 'OLO First Owner'
   ) LIMIT 1) = 'owner',
  'bootstrap creates first owner profile'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

DO $$
DECLARE
  v_pass_w1 uuid;
  v_pass_completed uuid;
  v_l1 uuid;
  v_l2 uuid;
  v_l3 uuid;
  v_l4 uuid;
  v_l2_completed uuid;
  v_slot_w1 uuid;
BEGIN
  SELECT pass_id INTO v_pass_w1
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_w1')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_once(), 200000, 'cash', now(), 'olo-w1-enroll', 'Weekly once fixture'
  ) LIMIT 1;

  SELECT pass_id INTO v_pass_completed
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_completed')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_wed(), 200000, 'cash', now(), 'olo-completed-enroll', 'Completed lesson fixture'
  ) LIMIT 1;

  SELECT l.id INTO v_l1 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 1;
  SELECT l.id INTO v_l2 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 2;
  SELECT l.id INTO v_l3 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 3;
  SELECT l.id INTO v_l4 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 4;

  PERFORM public.reve_transition_lesson_status(
    v_l1, 'completed', pg_temp.lesson_updated_at(v_l1),
    now() - interval '3 days', now() - interval '3 days' + interval '1 hour',
    'OLO weekly-once L1 completed'
  );

  SELECT l.id INTO v_l2_completed
  FROM public.lessons AS l
  WHERE l.pass_id = v_pass_completed AND l.sequence_number = 2;

  PERFORM public.reve_transition_lesson_status(
    (SELECT l.id FROM public.lessons AS l WHERE l.pass_id = v_pass_completed AND l.sequence_number = 1),
    'completed', pg_temp.lesson_updated_at(
      (SELECT l.id FROM public.lessons AS l WHERE l.pass_id = v_pass_completed AND l.sequence_number = 1)
    ),
    now() - interval '4 days', now() - interval '4 days' + interval '1 hour',
    'OLO completed fixture L1 completed'
  );
  PERFORM public.reve_transition_lesson_status(
    v_l2_completed, 'completed', pg_temp.lesson_updated_at(v_l2_completed),
    now() - interval '2 days', now() - interval '2 days' + interval '1 hour',
    'OLO completed fixture L2 completed'
  );

  SELECT ss.id INTO v_slot_w1 FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass_w1 AND ss.is_active = true LIMIT 1;

  PERFORM set_config('test.pass_w1', v_pass_w1::text, false);
  PERFORM set_config('test.pass_completed', v_pass_completed::text, false);
  PERFORM set_config('test.slot_w1', v_slot_w1::text, false);
  PERFORM set_config('test.l1_w1', v_l1::text, false);
  PERFORM set_config('test.l2_w1', v_l2::text, false);
  PERFORM set_config('test.l3_w1', v_l3::text, false);
  PERFORM set_config('test.l4_w1', v_l4::text, false);
  PERFORM set_config('test.l2_completed', v_l2_completed::text, false);
  PERFORM set_config('test.l2_w1_before',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l2), false);
  PERFORM set_config('test.l2_slot_before',
    (SELECT schedule_slot_id::text FROM public.lessons WHERE id = v_l2), false);
  PERFORM set_config('test.l2_teacher_before',
    (SELECT assigned_teacher_id::text FROM public.lessons WHERE id = v_l2), false);
  PERFORM set_config('test.l3_w1_before',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l3), false);
  PERFORM set_config('test.l4_w1_before',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l4), false);
  PERFORM set_config('test.reschedule_audit_before',
    pg_temp.audit_count_for('lesson.rescheduled')::text, false);
  PERFORM set_config('test.cascade_audit_before',
    pg_temp.audit_count_for('lesson.cascade_rescheduled')::text, false);
END $$;

-- ---------------------------------------------------------------------------
-- Security (6)
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_owner_direct_reschedule_lesson',
  ARRAY['uuid', 'timestamptz', 'timestamptz', 'text', 'boolean', 'timestamptz']
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_direct_reschedule_lesson'
  ),
  'direct reschedule RPC uses fixed empty search_path'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.direct_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_direct_reschedule_lesson'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
       gen_random_uuid(), now(), now(), 'anon direct', false, NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
       current_setting('test.l2_w1')::uuid,
       current_setting('test.valid_new_time')::timestamptz,
       pg_temp.lesson_updated_at(current_setting('test.l2_w1')::uuid),
       'teacher direct', false, NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
       current_setting('test.l2_w1')::uuid,
       current_setting('test.valid_new_time')::timestamptz,
       pg_temp.lesson_updated_at(current_setting('test.l2_w1')::uuid),
       'student direct', false, NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.spoof_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
       current_setting('test.l2_w1')::uuid,
       current_setting('test.valid_new_time')::timestamptz,
       pg_temp.lesson_updated_at(current_setting('test.l2_w1')::uuid),
       'spoof direct', false, NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

-- ---------------------------------------------------------------------------
-- Academy operating hours (4)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM pg_temp.direct_reschedule(
       current_setting('test.l2_w1')::uuid,
       current_setting('test.hours_before_open')::timestamptz,
       'Before open probe') $$,
  'P0001',
  'REVE_ACADEMY_HOURS_BEFORE_OPEN'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM pg_temp.direct_reschedule(
       current_setting('test.l2_w1')::uuid,
       current_setting('test.hours_at_close')::timestamptz,
       'At close probe') $$,
  'P0001',
  'REVE_ACADEMY_HOURS_AFTER_CLOSE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM pg_temp.direct_reschedule(
       current_setting('test.l2_w1')::uuid,
       current_setting('test.hours_end_after_close')::timestamptz,
       'End after close probe') $$,
  'P0001',
  'REVE_ACADEMY_HOURS_END_AFTER_CLOSE'
);

SELECT lives_ok(
  $$ SELECT count(*) FROM pg_temp.direct_reschedule(
       current_setting('test.l2_w1')::uuid,
       current_setting('test.hours_last_window')::timestamptz,
       'Last window probe') $$,
  '21:00 start with 60-minute duration ending exactly at 22:00 is accepted'
);

-- ---------------------------------------------------------------------------
-- Owner direct reschedule — single lesson (6)
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT no_change = false AND cascaded_lesson_count = 0
    FROM pg_temp.direct_reschedule(
      current_setting('test.l2_w1')::uuid,
      current_setting('test.valid_new_time')::timestamptz,
      'Owner single direct move'
    ) LIMIT 1
  ),
  'owner direct reschedule moves anchor lesson to approved time'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l2_w1')::uuid),
  current_setting('test.valid_new_time')::timestamptz,
  'anchor lesson scheduled_at updated in lessons table'
);

SELECT is(
  (SELECT schedule_slot_id::text FROM public.lessons WHERE id = current_setting('test.l2_w1')::uuid),
  current_setting('test.l2_slot_before'),
  'anchor direct move leaves schedule_slot_id unchanged'
);

SELECT is(
  (SELECT assigned_teacher_id::text FROM public.lessons WHERE id = current_setting('test.l2_w1')::uuid),
  current_setting('test.l2_teacher_before'),
  'anchor direct move leaves assigned_teacher_id unchanged'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.lesson_schedule_changes AS lsc
    WHERE lsc.lesson_id = current_setting('test.l2_w1')::uuid
      AND lsc.schedule_change_request_id IS NULL
      AND lsc.change_origin = 'direct_user'
      AND lsc.new_scheduled_at = current_setting('test.valid_new_time')::timestamptz
  ),
  'direct reschedule writes direct_user event without schedule_change_request_id'
);

SELECT ok(
  pg_temp.audit_count_for('lesson.rescheduled')
    > current_setting('test.reschedule_audit_before')::bigint,
  'direct reschedule writes lesson.rescheduled audit'
);

-- ---------------------------------------------------------------------------
-- Optional cascade (4)
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT no_change = false
      AND cascaded_lesson_count = 2
    FROM pg_temp.direct_reschedule(
      current_setting('test.l2_w1')::uuid,
      timestamptz '2026-09-21 15:00:00+09',
      'Owner direct cascade move',
      true,
      current_setting('test.pass_w1')::uuid
    ) LIMIT 1
  ),
  'optional cascade moves two eligible later lessons'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l3_w1')::uuid),
  current_setting('test.l3_cascade_expected')::timestamptz,
  'cascade moves L3 to next Monday slot after anchor end'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l4_w1')::uuid),
  current_setting('test.l4_cascade_expected')::timestamptz,
  'cascade moves L4 to following Monday slot'
);

SELECT is(
  (
    SELECT count(*)::bigint
    FROM public.lesson_schedule_changes AS lsc
    WHERE lsc.lesson_id IN (
      current_setting('test.l3_w1')::uuid,
      current_setting('test.l4_w1')::uuid
    )
      AND lsc.schedule_change_request_id IS NULL
      AND lsc.change_origin = 'cascade_auto'
  ),
  2::bigint,
  'cascade writes cascade_auto events without schedule_change_request_id'
);

-- ---------------------------------------------------------------------------
-- Validation guards (4)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM pg_temp.direct_reschedule(
       current_setting('test.l2_w1')::uuid,
       timestamptz '2026-09-21 16:00:00+09',
       '   ') $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM pg_temp.direct_reschedule(
       current_setting('test.l2_completed')::uuid,
       current_setting('test.valid_new_time')::timestamptz,
       'Completed lesson probe') $$,
  'P0001',
  'REVE_LESSON_NOT_CHANGEABLE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
       current_setting('test.l2_w1')::uuid,
       timestamptz '2026-09-21 17:00:00+09',
       timestamptz '2000-01-01 00:00:00+00',
       'Stale lesson token', false, NULL) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT ok(
  (
    SELECT no_change = true
    FROM pg_temp.direct_reschedule(
      current_setting('test.l2_w1')::uuid,
      timestamptz '2026-09-21 15:00:00+09',
      'Idempotent replay'
    ) LIMIT 1
  ),
  'direct reschedule idempotent replay returns no_change when already at target'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();

ROLLBACK;

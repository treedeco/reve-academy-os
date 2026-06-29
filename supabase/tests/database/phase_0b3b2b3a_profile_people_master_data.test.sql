-- REVE ACADEMY OS Phase 0B-3B-2B-3A — profile provisioning and people master data pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(55);

-- ---------------------------------------------------------------------------
-- Fixture: auth users and minimal course graph (no profiles until bootstrap)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_owner2 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
  v_bootstrap_fail uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02';
  v_teacher_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddddda';
  v_teacher_provision uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddc';
  v_spoof_auth uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddb';
  v_student_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_student_role uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner1@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner2@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_bootstrap_fail, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'bootstrap-fail@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-auth@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_provision, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-provision@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_spoof_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'spoof@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-auth@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_role, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-role@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOCAL', 'Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES
    (v_product, v_course, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000);

  PERFORM set_config('test.owner1', v_owner1::text, false);
  PERFORM set_config('test.owner2', v_owner2::text, false);
  PERFORM set_config('test.bootstrap_fail', v_bootstrap_fail::text, false);
  PERFORM set_config('test.teacher_auth', v_teacher_auth::text, false);
  PERFORM set_config('test.teacher_provision', v_teacher_provision::text, false);
  PERFORM set_config('test.spoof_auth', v_spoof_auth::text, false);
  PERFORM set_config('test.student_auth', v_student_auth::text, false);
  PERFORM set_config('test.student_role', v_student_role::text, false);
  PERFORM set_config('test.course', v_course::text, false);
  PERFORM set_config('test.product', v_product::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.profile_updated_at(p_profile uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.profiles WHERE id = p_profile;
$$;

CREATE OR REPLACE FUNCTION pg_temp.student_updated_at(p_student uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.students WHERE id = p_student;
$$;

CREATE OR REPLACE FUNCTION pg_temp.teacher_updated_at(p_teacher uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.teachers WHERE id = p_teacher;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count()
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs;
$$;

CREATE OR REPLACE FUNCTION pg_temp.bootstrap_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_bootstrap_first_owner(uuid,text)'::text;
$$;

-- ---------------------------------------------------------------------------
-- Function contracts and bootstrap security
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_bootstrap_first_owner',
  ARRAY['uuid', 'text']
);
SELECT has_function(
  'public', 'reve_owner_provision_profile',
  ARRAY['uuid', 'text', 'text', 'uuid', 'uuid']
);

SELECT ok(
  has_function_privilege('service_role', pg_temp.bootstrap_sig(), 'EXECUTE'),
  'service_role may execute reve_bootstrap_first_owner'
);
SELECT ok(
  NOT has_function_privilege('authenticated', pg_temp.bootstrap_sig(), 'EXECUTE'),
  'authenticated may not execute reve_bootstrap_first_owner'
);

DO $$
DECLARE
  v_before bigint;
  v_after bigint;
BEGIN
  PERFORM set_config('test.audit_before_bootstrap', pg_temp.audit_count()::text, false);
END $$;

SET ROLE service_role;
SELECT ok(
  (SELECT role FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner1')::uuid, 'First Owner'
   ) LIMIT 1) = 'owner',
  'bootstrap creates first owner profile'
);
SELECT ok(
  (SELECT idempotent_replay FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner1')::uuid, 'First Owner'
   ) LIMIT 1),
  'bootstrap idempotent retry returns idempotent_replay true'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_bootstrap_first_owner(
       current_setting('test.bootstrap_fail')::uuid, 'Second Owner'
     ) $$,
  'P0001',
  'REVE_BOOTSTRAP_ALREADY_COMPLETED'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_bootstrap_first_owner(
       '00000000-0000-0000-0000-000000000099'::uuid, 'Missing User'
     ) $$,
  'P0001',
  'REVE_AUTH_USER_NOT_FOUND'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT ok(
  pg_temp.audit_count() > current_setting('test.audit_before_bootstrap')::bigint,
  'bootstrap creates audit log entry'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'profile.bootstrap_first_owner'
      AND resource_table = 'profiles'
      AND resource_id = current_setting('test.owner1')::uuid
  ),
  'bootstrap audit action is profile.bootstrap_first_owner'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_bootstrap_first_owner(
       current_setting('test.owner2')::uuid, 'Blocked Owner'
     ) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ---------------------------------------------------------------------------
-- Owner provisioning
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

-- Profile role/state: solo last-owner guard (before second owner exists)
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_profile_active(
       current_setting('test.owner1')::uuid,
       'inactive', 'cannot deactivate last owner',
       pg_temp.profile_updated_at(current_setting('test.owner1')::uuid)
     ) $$,
  'P0001',
  'REVE_LAST_OWNER'
);

SELECT ok(
  (SELECT role FROM public.reve_owner_provision_profile(
     current_setting('test.owner2')::uuid, 'owner', 'Second Owner', NULL, NULL
   ) LIMIT 1) = 'owner',
  'owner provisions additional owner profile'
);

DO $$
DECLARE
  v_teacher_id uuid;
BEGIN
  SELECT teacher_id
  INTO v_teacher_id
  FROM public.reve_owner_create_teacher('T-PROV', 'Provision Teacher', '010-1111-1111', NULL)
  LIMIT 1;
  PERFORM set_config('test.teacher_entity', v_teacher_id::text, false);
END $$;

SELECT ok(
  (SELECT teacher_id FROM public.reve_owner_provision_profile(
     current_setting('test.teacher_provision')::uuid,
     'teacher', 'Teacher Provisioned', NULL,
     current_setting('test.teacher_entity')::uuid
   ) LIMIT 1) = current_setting('test.teacher_entity')::uuid,
  'owner provisions teacher profile with entity link'
);

DO $$
DECLARE
  v_student_id uuid;
BEGIN
  SELECT student_id
  INTO v_student_id
  FROM public.reve_owner_create_student('S-PROV', 'Provision Student', NULL, NULL)
  LIMIT 1;
  PERFORM set_config('test.student_entity', v_student_id::text, false);
END $$;

SELECT ok(
  (SELECT student_id FROM public.reve_owner_provision_profile(
     current_setting('test.student_auth')::uuid,
     'student', 'Student Provisioned',
     current_setting('test.student_entity')::uuid, NULL
   ) LIMIT 1) = current_setting('test.student_entity')::uuid,
  'owner provisions student profile with entity link'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_provision_profile(
       current_setting('test.owner2')::uuid, 'owner', 'Duplicate Owner', NULL, NULL
     ) $$,
  'P0001',
  'REVE_PROFILE_EXISTS'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.spoof_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_student('S-SPOOF', 'Spoof Student') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_provision')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_student('S-TEACH-DENY', 'Denied') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_student('S-STUD-DENY', 'Denied') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_provision_profile(
       current_setting('test.bootstrap_fail')::uuid,
       'teacher', 'No Entity Teacher', NULL, NULL
     ) $$,
  'P0001',
  'REVE_ROLE_LINK_MISMATCH'
);

DO $$
DECLARE
  v_orphan_teacher uuid;
BEGIN
  SELECT teacher_id
  INTO v_orphan_teacher
  FROM public.reve_owner_create_teacher('T-ORPHAN', 'Orphan Teacher')
  LIMIT 1;
  PERFORM set_config('test.orphan_teacher', v_orphan_teacher::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_provision_profile(
       current_setting('test.bootstrap_fail')::uuid,
       'teacher', 'Missing Teacher Row', NULL,
       'cccccccc-cccc-cccc-cccc-cccccccccc02'::uuid
     ) $$,
  'P0001',
  'REVE_PROFILE_LINK_CONFLICT'
);

-- ---------------------------------------------------------------------------
-- Profile role and account state
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_profile_active(
       current_setting('test.owner1')::uuid,
       'inactive', '', pg_temp.profile_updated_at(current_setting('test.owner1')::uuid)
     ) $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner1')::uuid,
     'inactive', 'first owner stepping down',
     pg_temp.profile_updated_at(current_setting('test.owner1')::uuid)
   ) LIMIT 1) = 'inactive',
  'second owner allows deactivating first owner'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_profile_active(
       current_setting('test.owner2')::uuid,
       'inactive', 'cannot deactivate last owner',
       pg_temp.profile_updated_at(current_setting('test.owner2')::uuid)
     ) $$,
  'P0001',
  'REVE_LAST_OWNER'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_profile_role(
       current_setting('test.owner2')::uuid,
       'teacher', 'cannot demote last owner',
       pg_temp.profile_updated_at(current_setting('test.owner2')::uuid),
       NULL, current_setting('test.orphan_teacher')::uuid
     ) $$,
  'P0001',
  'REVE_LAST_OWNER'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT ok(
  NOT reve_private.is_owner(),
  'inactive owner profile loses is_owner access'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;

SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner1')::uuid,
     'active', 'reactivate first owner for multi-owner state test',
     pg_temp.profile_updated_at(current_setting('test.owner1')::uuid)
   ) LIMIT 1) = 'active',
  'owner can reactivate inactive owner when another owner remains'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner2')::uuid,
     'suspended', 'temporary suspension',
     pg_temp.profile_updated_at(current_setting('test.owner2')::uuid)
   ) LIMIT 1) = 'suspended',
  'owner can suspend profile when not last active owner'
);

SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner2')::uuid,
     'active', 'reactivate after suspension',
     pg_temp.profile_updated_at(current_setting('test.owner2')::uuid)
   ) LIMIT 1) = 'active',
  'owner can reactivate suspended profile'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_profile_active(
       current_setting('test.owner2')::uuid,
       'inactive', 'stale timestamp',
       timestamptz '2000-01-01 00:00:00+00'
     ) $$,
  '22000',
  'REVE_STALE_STATE'
);

DO $$
DECLARE
  v_student_entity uuid;
  v_teacher_entity uuid;
BEGIN
  SELECT student_id
  INTO v_student_entity
  FROM public.reve_owner_create_student('S-ROLE', 'Role Change Student')
  LIMIT 1;

  SELECT teacher_id
  INTO v_teacher_entity
  FROM public.reve_owner_create_teacher('T-ROLE', 'Role Change Teacher')
  LIMIT 1;

  PERFORM public.reve_owner_provision_profile(
    current_setting('test.student_role')::uuid,
    'student', 'Role Change User', v_student_entity, NULL
  );

  PERFORM public.reve_owner_set_profile_role(
    current_setting('test.student_role')::uuid,
    'teacher', 'promote student profile to teacher',
    pg_temp.profile_updated_at(current_setting('test.student_role')::uuid),
    NULL, v_teacher_entity
  );

  PERFORM set_config('test.role_change_profile', current_setting('test.student_role'), false);
END $$;

SELECT is(
  (SELECT role FROM public.profiles WHERE id = current_setting('test.role_change_profile')::uuid),
  'teacher',
  'owner sets profile role with reason and entity link'
);

-- ---------------------------------------------------------------------------
-- Student master data
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_student_id uuid;
BEGIN
  SELECT student_id
  INTO v_student_id
  FROM public.reve_owner_create_student('S-CREATE', 'Created Student', '010-2222-2222', 's@test.local')
  LIMIT 1;
  PERFORM set_config('test.student_create', v_student_id::text, false);
END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.students
    WHERE id = current_setting('test.student_create')::uuid
      AND student_code = 'S-CREATE'
      AND name = 'Created Student'
      AND operational_status = 'active'
  ),
  'owner creates student master row'
);

SELECT ok(
  (SELECT student_name FROM public.reve_owner_update_student(
     current_setting('test.student_create')::uuid,
     pg_temp.student_updated_at(current_setting('test.student_create')::uuid),
     'Renamed Student', '010-3333-3333', NULL
   ) LIMIT 1) = 'Renamed Student',
  'owner updates student name'
);

SELECT is(
  (SELECT student_code FROM public.students WHERE id = current_setting('test.student_create')::uuid),
  'S-CREATE',
  'student_code remains immutable after update'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_student('S-CREATE', 'Duplicate Code') $$,
  '23505'
);

DO $$
DECLARE
  v_linked_student uuid;
BEGIN
  SELECT student_id
  INTO v_linked_student
  FROM public.reve_owner_create_student('S-LINKED', 'Linked Student')
  LIMIT 1;
  PERFORM set_config('test.student_linked', v_linked_student::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_student_active(
       current_setting('test.student_entity')::uuid,
       'inactive', 'linked active profile blocks deactivation',
       pg_temp.student_updated_at(current_setting('test.student_entity')::uuid)
     ) $$,
  'P0001',
  'REVE_PROFILE_LINK_CONFLICT'
);

SELECT ok(
  (SELECT operational_status FROM public.reve_owner_set_student_active(
     current_setting('test.student_linked')::uuid,
     'inactive', 'unlinked student deactivation',
     pg_temp.student_updated_at(current_setting('test.student_linked')::uuid)
   ) LIMIT 1) = 'inactive',
  'owner deactivates unlinked student'
);

SELECT throws_ok(
  $$ DELETE FROM public.students WHERE id = current_setting('test.student_create')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_update_student(
       current_setting('test.student_create')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       'Stale Name'
     ) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_student('S-BAD', '  ') $$,
  'P0001',
  'REVE_INVALID_NAME'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_student_active(
       current_setting('test.student_create')::uuid,
       'inactive', '',
       pg_temp.student_updated_at(current_setting('test.student_create')::uuid)
     ) $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

-- ---------------------------------------------------------------------------
-- Teacher master data
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_teacher_free uuid;
  v_teacher_asgn uuid;
  v_student_asgn uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666601';
  v_slot uuid := '77777777-7777-7777-7777-777777777701';
  v_lesson uuid := '99999999-9999-9999-9999-999999999901';
BEGIN
  SELECT teacher_id
  INTO v_teacher_free
  FROM public.reve_owner_create_teacher('T-FREE', 'Free Teacher', NULL, 'free@test.local')
  LIMIT 1;

  SELECT teacher_id
  INTO v_teacher_asgn
  FROM public.reve_owner_create_teacher('T-ASGN', 'Assigned Teacher')
  LIMIT 1;

  SELECT student_id
  INTO v_student_asgn
  FROM public.reve_owner_create_student('S-ASGN', 'Assignment Student')
  LIMIT 1;

  PERFORM set_config('test.teacher_free', v_teacher_free::text, false);
  PERFORM set_config('test.teacher_asgn', v_teacher_asgn::text, false);
END $$;

DO $$
DECLARE
  v_teacher_asgn uuid := current_setting('test.teacher_asgn')::uuid;
  v_student_asgn uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666601';
  v_slot uuid := '77777777-7777-7777-7777-777777777701';
  v_lesson uuid := '99999999-9999-9999-9999-999999999901';
BEGIN
  PERFORM pg_temp.test_reset_role();

  SELECT id INTO v_student_asgn
  FROM public.students
  WHERE student_code = 'S-ASGN';

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date
  ) VALUES (
    v_pass, 'V-SASGN-001', v_student_asgn,
    current_setting('test.course')::uuid, current_setting('test.product')::uuid,
    1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES (
    v_slot, v_pass, v_teacher_asgn, 2, '11:00', 60, CURRENT_DATE
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    v_lesson, v_pass, v_student_asgn, current_setting('test.course')::uuid,
    v_teacher_asgn, v_slot, 1, now() + interval '3 days', 'scheduled'
  );
END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.teachers
    WHERE id = current_setting('test.teacher_free')::uuid
      AND teacher_code = 'T-FREE'
      AND is_active = true
  ),
  'owner creates teacher master row'
);

SELECT ok(
  (SELECT teacher_name FROM public.reve_owner_update_teacher(
     current_setting('test.teacher_free')::uuid,
     pg_temp.teacher_updated_at(current_setting('test.teacher_free')::uuid),
     'Renamed Teacher', '010-4444-4444', NULL
   ) LIMIT 1) = 'Renamed Teacher',
  'owner updates teacher name'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_teacher_active(
       current_setting('test.teacher_asgn')::uuid,
       false, 'future assignment blocks deactivation',
       pg_temp.teacher_updated_at(current_setting('test.teacher_asgn')::uuid)
     ) $$,
  'P0001',
  'REVE_ACTIVE_ASSIGNMENTS_EXIST'
);

SELECT ok(
  NOT (SELECT is_active FROM public.reve_owner_set_teacher_active(
     current_setting('test.teacher_free')::uuid,
     false, 'no assignments allows deactivation',
     pg_temp.teacher_updated_at(current_setting('test.teacher_free')::uuid)
   ) LIMIT 1),
  'owner deactivates teacher without active assignments'
);

SELECT throws_ok(
  $$ DELETE FROM public.teachers WHERE id = current_setting('test.teacher_free')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_update_teacher(
       current_setting('test.teacher_free')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       'Stale Teacher'
     ) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_teacher_active(
       current_setting('test.teacher_asgn')::uuid,
       false, '',
       pg_temp.teacher_updated_at(current_setting('test.teacher_asgn')::uuid)
     ) $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

-- ---------------------------------------------------------------------------
-- Direct-write security (authenticated)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.profiles (id, role, display_name)
     VALUES ('abababab-abab-abab-abab-ababababab01', 'owner', 'Direct Profile') $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.students (student_code, name)
     VALUES ('S-DIRECT', 'Direct Student') $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.teachers (teacher_code, name)
     VALUES ('T-DIRECT', 'Direct Teacher') $$,
  '42501'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_provision')::uuid); END $$;
SELECT throws_ok(
  $$ INSERT INTO public.students (student_code, name)
     VALUES ('S-TEACH-INS', 'Teacher Insert') $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;

-- ---------------------------------------------------------------------------
-- Derived column guardrails
-- ---------------------------------------------------------------------------
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles'
      AND column_name IN ('used_count', 'remaining_count', 'is_deducted')
  ),
  'profiles has no editable derived count columns'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'students'
      AND column_name IN ('used_count', 'remaining_count', 'is_deducted')
  ),
  'students has no editable derived count columns'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'teachers'
      AND column_name IN ('used_count', 'remaining_count', 'is_deducted')
  ),
  'teachers has no editable derived count columns'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();
ROLLBACK;

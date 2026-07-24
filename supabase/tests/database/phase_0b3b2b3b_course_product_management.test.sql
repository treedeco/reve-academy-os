-- REVE ACADEMY OS Phase 0B-3B-2B-3B — course and course product master data pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(70);

-- ---------------------------------------------------------------------------
-- Fixture: auth users and integration subset (courses/products via RPC in tests)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_owner2 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
  v_teacher_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddddda';
  v_student_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_spoof_auth uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddb';
  v_teacher_row uuid := '22222222-2222-2222-2222-222222222222';
  v_student_int uuid := '44444444-4444-4444-4444-444444444401';
  v_pass_int_done uuid := '66666666-6666-6666-6666-666666666601';
  v_slot_int uuid := '77777777-7777-7777-7777-777777777701';
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
     'teacher@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_spoof_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'spoof@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now());

  INSERT INTO public.teachers (id, teacher_code, name, phone, email) VALUES
    (v_teacher_row, 'T-INT', 'Integration Teacher', '010-0000-0001', 't-int@test.local');

  INSERT INTO public.students (id, student_code, name) VALUES
    (v_student_int, 'S-INT', 'Integration Student');

  PERFORM set_config('test.owner1', v_owner1::text, false);
  PERFORM set_config('test.owner2', v_owner2::text, false);
  PERFORM set_config('test.teacher_auth', v_teacher_auth::text, false);
  PERFORM set_config('test.student_auth', v_student_auth::text, false);
  PERFORM set_config('test.spoof_auth', v_spoof_auth::text, false);
  PERFORM set_config('test.teacher_row', v_teacher_row::text, false);
  PERFORM set_config('test.student_int', v_student_int::text, false);
  PERFORM set_config('test.pass_int_done', v_pass_int_done::text, false);
  PERFORM set_config('test.slot_int', v_slot_int::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.course_updated_at(p_course uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.courses WHERE id = p_course;
$$;

CREATE OR REPLACE FUNCTION pg_temp.product_updated_at(p_product uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.course_products WHERE id = p_product;
$$;

CREATE OR REPLACE FUNCTION pg_temp.payment_updated_at(p_payment uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.payments WHERE id = p_payment;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count()
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count_for(p_action text)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs WHERE action = p_action;
$$;

CREATE OR REPLACE FUNCTION pg_temp.create_course_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_create_course(text,text,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.create_product_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_create_course_product(uuid,text,text,integer,integer,integer,text)'::text;
$$;

-- ---------------------------------------------------------------------------
-- Bootstrap owner and provision second owner for inactive-owner tests
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
-- Function existence, contracts, security
-- ---------------------------------------------------------------------------
SELECT has_function('public', 'reve_owner_create_course', ARRAY['text', 'text', 'text']);
SELECT has_function(
  'public', 'reve_owner_update_course',
  ARRAY['uuid', 'timestamptz', 'text', 'text']
);
SELECT has_function(
  'public', 'reve_owner_set_course_active',
  ARRAY['uuid', 'boolean', 'text', 'timestamptz']
);
SELECT has_function(
  'public', 'reve_owner_create_course_product',
  ARRAY['uuid', 'text', 'text', 'integer', 'integer', 'integer', 'text']
);
SELECT has_function(
  'public', 'reve_owner_update_course_product',
  ARRAY['uuid', 'timestamptz', 'text', 'integer', 'integer', 'integer', 'text']
);
SELECT has_function(
  'public', 'reve_owner_set_course_product_active',
  ARRAY['uuid', 'boolean', 'text', 'timestamptz']
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname IN (
        'reve_owner_create_course',
        'reve_owner_update_course',
        'reve_owner_set_course_active',
        'reve_owner_create_course_product',
        'reve_owner_update_course_product',
        'reve_owner_set_course_product_active'
      )
  ),
  'course catalog RPC functions use fixed empty search_path'
);

SELECT ok(
  (
    SELECT bool_and(r.rolname = 'postgres')
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE ns.nspname = 'public'
      AND p.proname IN (
        'reve_owner_create_course',
        'reve_owner_update_course',
        'reve_owner_set_course_active',
        'reve_owner_create_course_product',
        'reve_owner_update_course_product',
        'reve_owner_set_course_product_active'
      )
  ),
  'course catalog RPC functions owned by postgres'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.create_course_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_create_course'
);
SELECT ok(
  NOT has_function_privilege('public', pg_temp.create_product_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_create_course_product'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course('ANON', 'Anon Course') $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course_product(
       '00000000-0000-0000-0000-000000000099'::uuid,
       'ANON-P', 'Anon Product', 4, 1, 100000, NULL) $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course('TEACH', 'Teacher Course') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course_product(
       '00000000-0000-0000-0000-000000000099'::uuid,
       'STU-P', 'Student Product', 4, 1, 100000, NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.spoof_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course('SPOOF', 'Spoof Course') $$,
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
  $$ SELECT count(*) FROM public.reve_owner_create_course('INACT', 'Inactive Owner Course') $$,
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
  $$ INSERT INTO public.courses (course_code, name) VALUES ('DIRECT-C', 'Direct Course') $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.course_products (
       course_id, product_code, product_name,
       default_lesson_count, weekly_frequency, default_tuition_krw
     ) VALUES (
       '00000000-0000-0000-0000-000000000099'::uuid,
       'DIRECT-P', 'Direct Product', 4, 1, 100000
     ) $$,
  '42501'
);

-- ---------------------------------------------------------------------------
-- Course create and update (Phase 2B-2B2: single-letter course prefixes)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course('drums', 'Invalid Prefix Course') $$,
  'P0001',
  'REVE_INVALID_COURSE_PREFIX'
);

DO $$
DECLARE
  v_course_id uuid;
  v_audit_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  PERFORM set_config('test.audit_before_course_create', v_audit_before::text, false);

  SELECT course_id
  INTO v_course_id
  FROM public.reve_owner_create_course('k', 'Drums Course', 'Four-piece kit')
  LIMIT 1;

  PERFORM set_config('test.course_main', v_course_id::text, false);
END $$;

SELECT is(
  (SELECT course_code FROM public.courses WHERE id = current_setting('test.course_main')::uuid),
  'K',
  'course_code normalized to upper case on create'
);
SELECT ok(
  (SELECT is_active FROM public.courses WHERE id = current_setting('test.course_main')::uuid),
  'new course starts active'
);

SELECT ok(
  pg_temp.audit_count() > current_setting('test.audit_before_course_create')::bigint,
  'course create writes audit log'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course('K', 'Duplicate Drums') $$,
  'P0001',
  'REVE_COURSE_CODE_EXISTS'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course('X', '  ') $$,
  'P0001',
  'REVE_INVALID_NAME'
);

DO $$
DECLARE
  v_audit_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  PERFORM set_config('test.audit_before_course_update', v_audit_before::text, false);
END $$;

SELECT ok(
  (
    SELECT course_name = 'Drums Advanced' AND description = 'Updated kit notes'
    FROM public.reve_owner_update_course(
      current_setting('test.course_main')::uuid,
      pg_temp.course_updated_at(current_setting('test.course_main')::uuid),
      'Drums Advanced', 'Updated kit notes'
    )
    LIMIT 1
  ),
  'owner updates course name and description'
);

SELECT is(
  (SELECT course_code FROM public.courses WHERE id = current_setting('test.course_main')::uuid),
  'K',
  'course_code remains immutable after update'
);
SELECT ok(
  pg_temp.audit_count() > current_setting('test.audit_before_course_update')::bigint,
  'successful course update writes audit log'
);

DO $$
DECLARE
  v_audit_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  PERFORM set_config('test.audit_before_course_fail', v_audit_before::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_update_course(
       current_setting('test.course_main')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       'Stale Drums'
     ) $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_update_course(
       current_setting('test.course_main')::uuid,
       pg_temp.course_updated_at(current_setting('test.course_main')::uuid),
       'Drums Advanced', 'Updated kit notes'
     ) $$,
  'P0001',
  'REVE_NO_CHANGES'
);

SELECT ok(
  pg_temp.audit_count() = current_setting('test.audit_before_course_fail')::bigint,
  'failed or no-op course update adds no audit rows'
);

-- ---------------------------------------------------------------------------
-- Course lifecycle and dependency guards
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_course uuid;
  v_product uuid;
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('C', 'Cello Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'CELLO-4', 'Cello 4 Lessons', 4, 1, 250000, NULL
  )
  LIMIT 1;

  PERFORM set_config('test.course_dep_product', v_course::text, false);
  PERFORM set_config('test.product_dep_product', v_product::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_active(
       current_setting('test.course_dep_product')::uuid,
       false, 'active product blocks course deactivation',
       pg_temp.course_updated_at(current_setting('test.course_dep_product')::uuid)
     ) $$,
  'P0001',
  'REVE_COURSE_HAS_ACTIVE_PRODUCTS'
);

DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666602';
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('I', 'Viola Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'VIOLA-4', 'Viola 4 Lessons', 4, 1, 250000, NULL
  )
  LIMIT 1;

  PERFORM public.reve_owner_set_course_product_active(
    v_product, false, 'deactivate for pass dependency test',
    pg_temp.product_updated_at(v_product)
  );

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date
  ) VALUES (
    v_pass, 'V-INT-001', v_student, v_course, v_product,
    1, 'active', 4, 1, 'Viola 4 Lessons', 250000, CURRENT_DATE
  );

  PERFORM set_config('test.course_dep_active_pass', v_course::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_active(
       current_setting('test.course_dep_active_pass')::uuid,
       false, 'active pass blocks course deactivation',
       pg_temp.course_updated_at(current_setting('test.course_dep_active_pass')::uuid)
     ) $$,
  'P0001',
  'REVE_ACTIVE_DEPENDENCIES_EXIST'
);

DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass_active uuid := '66666666-6666-6666-6666-666666666603';
  v_pass_reserved uuid := '67676767-6767-6767-6767-676767676701';
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('F', 'Flute Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'FLUTE-4', 'Flute 4 Lessons', 4, 1, 250000, NULL
  )
  LIMIT 1;

  PERFORM public.reve_owner_set_course_product_active(
    v_product, false, 'deactivate for reserved pass test',
    pg_temp.product_updated_at(v_product)
  );

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, previous_pass_id
  ) VALUES
    (v_pass_active, 'F-INT-001', v_student, v_course, v_product,
     1, 'completed', 4, 1, 'Flute 4 Lessons', 250000, CURRENT_DATE - 30, NULL),
    (v_pass_reserved, 'F-INT-002', v_student, v_course, v_product,
     2, 'reserved', 4, 1, 'Flute 4 Lessons', 250000, CURRENT_DATE + 30, v_pass_active);

  PERFORM set_config('test.course_dep_reserved', v_course::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_active(
       current_setting('test.course_dep_reserved')::uuid,
       false, 'reserved pass blocks course deactivation',
       pg_temp.course_updated_at(current_setting('test.course_dep_reserved')::uuid)
     ) $$,
  'P0001',
  'REVE_ACTIVE_DEPENDENCIES_EXIST'
);

DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666604';
  v_slot uuid := '77777777-7777-7777-7777-777777777702';
  v_lesson uuid := '99999999-9999-9999-9999-999999999901';
  v_teacher uuid := current_setting('test.teacher_row')::uuid;
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('O', 'Oboe Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'OBOE-4', 'Oboe 4 Lessons', 4, 1, 250000, NULL
  )
  LIMIT 1;

  PERFORM public.reve_owner_set_course_product_active(
    v_product, false, 'deactivate for future lesson test',
    pg_temp.product_updated_at(v_product)
  );

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES (
    v_pass, 'O-INT-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Oboe 4 Lessons', 250000, CURRENT_DATE - 60, now() - interval '10 days'
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES (
    v_slot, v_pass, v_teacher, 3, '12:00', 60, CURRENT_DATE - 60
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    v_lesson, v_pass, v_student, v_course, v_teacher,
    v_slot, 1, now() + interval '5 days', 'scheduled'
  );

  PERFORM set_config('test.course_dep_lesson', v_course::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_active(
       current_setting('test.course_dep_lesson')::uuid,
       false, 'future scheduled lesson blocks course deactivation',
       pg_temp.course_updated_at(current_setting('test.course_dep_lesson')::uuid)
     ) $$,
  'P0001',
  'REVE_ACTIVE_DEPENDENCIES_EXIST'
);

DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666605';
  v_payment uuid := '12121212-1212-1212-1212-121212121201';
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('H', 'Harp Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'HARP-4', 'Harp 4 Lessons', 4, 1, 250000, NULL
  )
  LIMIT 1;

  PERFORM public.reve_owner_set_course_product_active(
    v_product, false, 'deactivate for pending payment test',
    pg_temp.product_updated_at(v_product)
  );

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES (
    v_pass, 'H-INT-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Harp 4 Lessons', 250000, CURRENT_DATE - 60, now() - interval '10 days'
  );

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, status, idempotency_key, created_by_profile_id
  ) VALUES (
    v_payment, v_student, v_course, v_product, v_pass,
    250000, 'pending', 'idem-harp-pending', current_setting('test.owner1')::uuid
  );

  PERFORM set_config('test.course_dep_payment', v_course::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_active(
       current_setting('test.course_dep_payment')::uuid,
       false, 'pending payment blocks course deactivation',
       pg_temp.course_updated_at(current_setting('test.course_dep_payment')::uuid)
     ) $$,
  'P0001',
  'REVE_ACTIVE_DEPENDENCIES_EXIST'
);

DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666606';
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('B', 'Bass Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'BASS-4', 'Bass 4 Lessons', 4, 1, 250000, NULL
  )
  LIMIT 1;

  PERFORM public.reve_owner_set_course_product_active(
    v_product, false, 'deactivate product before completed-only pass test',
    pg_temp.product_updated_at(v_product)
  );

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES (
    v_pass, 'B-INT-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Bass 4 Lessons', 250000, CURRENT_DATE - 60, now() - interval '10 days'
  );

  PERFORM set_config('test.course_completed_only', v_course::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT ok(
  NOT (
    SELECT is_active
    FROM public.reve_owner_set_course_active(
      current_setting('test.course_completed_only')::uuid,
      false, 'completed-only pass allows course deactivation',
      pg_temp.course_updated_at(current_setting('test.course_completed_only')::uuid)
    )
    LIMIT 1
  ),
  'course deactivates when only completed passes remain'
);

SELECT ok(
  (
    SELECT is_active
    FROM public.reve_owner_set_course_active(
      current_setting('test.course_completed_only')::uuid,
      true, 'reactivate bass course',
      pg_temp.course_updated_at(current_setting('test.course_completed_only')::uuid)
    )
    LIMIT 1
  ),
  'owner reactivates deactivated course'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_active(
       current_setting('test.course_completed_only')::uuid,
       false, '',
       pg_temp.course_updated_at(current_setting('test.course_completed_only')::uuid)
     ) $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

SELECT throws_ok(
  $$ DELETE FROM public.courses WHERE id = current_setting('test.course_main')::uuid $$,
  '42501'
);

-- ---------------------------------------------------------------------------
-- Product create and update
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_product_4 uuid;
  v_product_8 uuid;
  v_audit_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  PERFORM set_config('test.audit_before_product_create', v_audit_before::text, false);

  SELECT course_product_id INTO v_product_4
  FROM public.reve_owner_create_course_product(
    current_setting('test.course_main')::uuid,
    'drums-4', 'Drums 4 Lessons', 4, 1, 200000, 'none'
  )
  LIMIT 1;

  SELECT course_product_id INTO v_product_8
  FROM public.reve_owner_create_course_product(
    current_setting('test.course_main')::uuid,
    'DRUMS-8', 'Drums 8 Lessons', 8, 2, 380000, NULL
  )
  LIMIT 1;

  PERFORM set_config('test.product_4', v_product_4::text, false);
  PERFORM set_config('test.product_8', v_product_8::text, false);
END $$;

SELECT ok(
  (SELECT default_lesson_count FROM public.course_products WHERE id = current_setting('test.product_4')::uuid) = 4
  AND (SELECT default_lesson_count FROM public.course_products WHERE id = current_setting('test.product_8')::uuid) = 8
  AND (SELECT product_code FROM public.course_products WHERE id = current_setting('test.product_4')::uuid) = 'DRUMS-4',
  'owner creates four-lesson and eight-lesson products with normalized code'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course_product(
       current_setting('test.course_main')::uuid,
       'DRUMS-4', 'Duplicate Product', 4, 1, 200000, NULL) $$,
  'P0001',
  'REVE_PRODUCT_CODE_EXISTS'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course_product(
       current_setting('test.course_main')::uuid,
       'DRUMS-ZERO', 'Zero Count', 0, 1, 200000, NULL) $$,
  'P0001',
  'REVE_INVALID_REGISTERED_COUNT'
);
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course_product(
       current_setting('test.course_main')::uuid,
       'DRUMS-NEG', 'Negative Price', 4, 1, -1, NULL) $$,
  'P0001',
  'REVE_INVALID_PRICE'
);

DO $$
DECLARE
  v_inactive_course uuid;
BEGIN
  SELECT course_id INTO v_inactive_course
  FROM public.reve_owner_create_course('U', 'Ukulele Course')
  LIMIT 1;

  PERFORM public.reve_owner_set_course_active(
    v_inactive_course, false, 'inactive for product create rejection',
    pg_temp.course_updated_at(v_inactive_course)
  );

  PERFORM set_config('test.course_inactive', v_inactive_course::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_course_product(
       current_setting('test.course_inactive')::uuid,
       'UKULELE-4', 'Ukulele 4', 4, 1, 100000, NULL) $$,
  'P0001',
  'REVE_COURSE_INACTIVE'
);

DO $$
DECLARE
  v_audit_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  PERFORM set_config('test.audit_before_product_update', v_audit_before::text, false);
END $$;

SELECT ok(
  (
    SELECT product_name = 'Drums 4 Premium'
      AND default_lesson_count = 4
      AND weekly_frequency = 2
      AND default_tuition_krw = 220000
      AND expiration_policy = '90d'
    FROM public.reve_owner_update_course_product(
      current_setting('test.product_4')::uuid,
      pg_temp.product_updated_at(current_setting('test.product_4')::uuid),
      'Drums 4 Premium', 4, 2, 220000, '90d'
    )
    LIMIT 1
  ),
  'owner updates mutable product fields'
);

SELECT ok(
  (SELECT product_code FROM public.course_products WHERE id = current_setting('test.product_4')::uuid) = 'DRUMS-4'
  AND (SELECT course_id FROM public.course_products WHERE id = current_setting('test.product_4')::uuid)
      = current_setting('test.course_main')::uuid,
  'product_code and course_id remain immutable after update'
);

DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666607';
  v_payment uuid := '12121212-1212-1212-1212-121212121202';
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('S', 'Sax Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'SAX-4', 'Sax 4 Lessons', 4, 1, 300000, NULL
  )
  LIMIT 1;

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES (
    v_pass, 'S-INT-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Sax 4 Lessons', 300000, CURRENT_DATE - 60, now() - interval '10 days'
  );

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, status, idempotency_key, created_by_profile_id
  ) VALUES (
    v_payment, v_student, v_course, v_product, v_pass,
    300000, 'pending', 'idem-sax-pending', current_setting('test.owner1')::uuid
  );

  PERFORM set_config('test.product_pending', v_product::text, false);
  PERFORM set_config('test.payment_pending', v_payment::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_update_course_product(
       current_setting('test.product_pending')::uuid,
       pg_temp.product_updated_at(current_setting('test.product_pending')::uuid),
       'Sax 4 Lessons', 8, 1, 300000, NULL) $$,
  'P0001',
  'REVE_PENDING_PAYMENT_EXISTS'
);

SELECT ok(
  (
    SELECT product_name = 'Sax 4 Renamed'
    FROM public.reve_owner_update_course_product(
      current_setting('test.product_pending')::uuid,
      pg_temp.product_updated_at(current_setting('test.product_pending')::uuid),
      'Sax 4 Renamed', 4, 1, 300000, NULL
    )
    LIMIT 1
  ),
  'non-pricing product update allowed while pending payment exists'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_update_course_product(
       current_setting('test.product_4')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       'Stale Product', 4, 2, 220000, '90d') $$,
  '22000',
  'REVE_STALE_STATE'
);

DO $$
DECLARE
  v_audit_before bigint;
BEGIN
  v_audit_before := pg_temp.audit_count();
  PERFORM set_config('test.audit_before_product_noop', v_audit_before::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_update_course_product(
       current_setting('test.product_4')::uuid,
       pg_temp.product_updated_at(current_setting('test.product_4')::uuid),
       'Drums 4 Premium', 4, 2, 220000, '90d') $$,
  'P0001',
  'REVE_NO_CHANGES'
);

SELECT ok(
  pg_temp.audit_count() = current_setting('test.audit_before_product_noop')::bigint,
  'no-op product update adds no audit rows'
);

-- ---------------------------------------------------------------------------
-- Product lifecycle
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('T', 'Trumpet Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'TRUMPET-4', 'Trumpet 4 Lessons', 4, 1, 280000, NULL
  )
  LIMIT 1;

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES (
    '66666666-6666-6666-6666-666666666608',
    'T-INT-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Trumpet 4 Lessons', 280000,
    CURRENT_DATE - 90, now() - interval '30 days'
  );

  PERFORM set_config('test.product_lifecycle', v_product::text, false);
  PERFORM set_config('test.course_lifecycle', v_course::text, false);
  PERFORM set_config(
    'test.pass_hist_before',
    jsonb_build_object(
      'registered_lesson_count_snapshot', 4,
      'tuition_amount_krw_snapshot', 280000,
      'product_name_snapshot', 'Trumpet 4 Lessons'
    )::text,
    false
  );
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT ok(
  NOT (
    SELECT is_active
    FROM public.reve_owner_set_course_product_active(
      current_setting('test.product_lifecycle')::uuid,
      false, 'retire trumpet product',
      pg_temp.product_updated_at(current_setting('test.product_lifecycle')::uuid)
    )
    LIMIT 1
  ),
  'owner deactivates product with reason'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_product_active(
       current_setting('test.product_pending')::uuid,
       false, 'pending payment blocks product deactivation',
       pg_temp.product_updated_at(current_setting('test.product_pending')::uuid)
     ) $$,
  'P0001',
  'REVE_PENDING_PAYMENT_EXISTS'
);

SELECT ok(
  (
    SELECT jsonb_build_object(
      'registered_lesson_count_snapshot', registered_lesson_count_snapshot,
      'tuition_amount_krw_snapshot', tuition_amount_krw_snapshot,
      'product_name_snapshot', product_name_snapshot
    )
    FROM public.passes
    WHERE course_product_id = current_setting('test.product_lifecycle')::uuid
    LIMIT 1
  ) = current_setting('test.pass_hist_before')::jsonb,
  'historical pass snapshots unchanged after product deactivation'
);

DO $$
BEGIN
  PERFORM public.reve_owner_set_course_active(
    current_setting('test.course_lifecycle')::uuid,
    false, 'deactivate parent course for reactivation guard',
    pg_temp.course_updated_at(current_setting('test.course_lifecycle')::uuid)
  );
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_product_active(
       current_setting('test.product_lifecycle')::uuid,
       true, 'reactivate while course inactive',
       pg_temp.product_updated_at(current_setting('test.product_lifecycle')::uuid)
     ) $$,
  'P0001',
  'REVE_COURSE_INACTIVE'
);

SELECT ok(
  (
    SELECT is_active
    FROM public.reve_owner_set_course_active(
      current_setting('test.course_lifecycle')::uuid,
      true, 'reactivate trumpet course',
      pg_temp.course_updated_at(current_setting('test.course_lifecycle')::uuid)
    )
    LIMIT 1
  ),
  'owner reactivates parent course'
);

SELECT ok(
  (
    SELECT is_active
    FROM public.reve_owner_set_course_product_active(
      current_setting('test.product_lifecycle')::uuid,
      true, 'reactivate trumpet product',
      pg_temp.product_updated_at(current_setting('test.product_lifecycle')::uuid)
    )
    LIMIT 1
  ),
  'owner reactivates product when parent course is active'
);

-- ---------------------------------------------------------------------------
-- Parent-child integrity
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_set_course_active(
       current_setting('test.course_dep_product')::uuid,
       false, 'active product still blocks parent deactivation',
       pg_temp.course_updated_at(current_setting('test.course_dep_product')::uuid)
     ) $$,
  'P0001',
  'REVE_COURSE_HAS_ACTIVE_PRODUCTS'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
SELECT throws_ok(
  $$ DO $inner$
     BEGIN
       SET CONSTRAINTS trg_course_products_validate_active_course DEFERRED;
       INSERT INTO public.course_products (
         course_id, product_code, product_name,
         default_lesson_count, weekly_frequency, default_tuition_krw, is_active
       ) VALUES (
         current_setting('test.course_inactive')::uuid,
         'DEFER-P', 'Deferred Violation', 4, 1, 100000, true
       );
       SET CONSTRAINTS trg_course_products_validate_active_course IMMEDIATE;
     END;
     $inner$; $$,
  'P0001',
  'REVE_COURSE_INACTIVE'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

-- ---------------------------------------------------------------------------
-- Snapshot and payment renewal integration
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass_done uuid := current_setting('test.pass_int_done')::uuid;
  v_payment uuid := '12121212-1212-1212-1212-121212121203';
  v_payment_renew uuid := '12121212-1212-1212-1212-121212121204';
  v_owner uuid := current_setting('test.owner1')::uuid;
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('G', 'Guitar Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'GUITAR-4', 'Guitar 4 Lessons', 4, 1, 200000, NULL
  )
  LIMIT 1;

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES (
    v_pass_done, 'G-INT-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Guitar 4 Lessons', 200000,
    CURRENT_DATE - 90, now() - interval '30 days'
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES (
    current_setting('test.slot_int')::uuid, v_pass_done,
    current_setting('test.teacher_row')::uuid, 2, '11:00', 60, CURRENT_DATE - 60
  );

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, status, idempotency_key, created_by_profile_id
  ) VALUES (
    v_payment, v_student, v_course, v_product, v_pass_done,
    200000, 'pending', 'idem-guitar-first', v_owner
  );

  PERFORM set_config('test.course_int', v_course::text, false);
  PERFORM set_config('test.product_int', v_product::text, false);
  PERFORM set_config('test.payment_int', v_payment::text, false);
  PERFORM set_config('test.payment_int_renew', v_payment_renew::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

DO $$
DECLARE
  v_new_pass uuid;
BEGIN
  SELECT new_pass_id INTO v_new_pass
  FROM public.reve_complete_payment_and_renew_pass(
    current_setting('test.payment_int')::uuid,
    pg_temp.payment_updated_at(current_setting('test.payment_int')::uuid),
    200000, 'cash', now() - interval '1 day', 'idem-guitar-first'
  )
  LIMIT 1;

  PERFORM set_config('test.pass_int_new', v_new_pass::text, false);
END $$;

DO $$
BEGIN
  PERFORM public.reve_owner_update_course_product(
    current_setting('test.product_int')::uuid,
    pg_temp.product_updated_at(current_setting('test.product_int')::uuid),
    'Guitar 6 Lessons', 6, 1, 260000, NULL
  );
END $$;

SELECT is(
  (SELECT registered_lesson_count_snapshot FROM public.passes
   WHERE id = current_setting('test.pass_int_new')::uuid),
  4,
  'pass registered_lesson_count_snapshot unchanged after product edit'
);
SELECT is(
  (SELECT tuition_amount_krw_snapshot FROM public.passes
   WHERE id = current_setting('test.pass_int_new')::uuid),
  200000,
  'pass tuition_amount_krw_snapshot unchanged after product edit'
);

DO $$
DECLARE
  v_pass_done uuid := current_setting('test.pass_int_new')::uuid;
  v_payment uuid := current_setting('test.payment_int_renew')::uuid;
BEGIN
  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, status, idempotency_key, created_by_profile_id
  ) VALUES (
    v_payment,
    current_setting('test.student_int')::uuid,
    current_setting('test.course_int')::uuid,
    current_setting('test.product_int')::uuid,
    v_pass_done,
    260000, 'pending', 'idem-guitar-second', current_setting('test.owner1')::uuid
  );

  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT is(
  (
    SELECT registered_lesson_count
    FROM public.reve_complete_payment_and_renew_pass(
      current_setting('test.payment_int_renew')::uuid,
      pg_temp.payment_updated_at(current_setting('test.payment_int_renew')::uuid),
      260000, 'card', now(), 'idem-guitar-second'
    )
    LIMIT 1
  ),
  6,
  'new renewal uses current product default_lesson_count'
);

DO $$
BEGIN
  PERFORM public.reve_owner_set_course_product_active(
    current_setting('test.product_int')::uuid,
    false, 'deactivate after completed payment for idempotency test',
    pg_temp.product_updated_at(current_setting('test.product_int')::uuid)
  );
END $$;

SELECT ok(
  (
    SELECT idempotent_replay = true AND payment_status = 'completed'
    FROM public.reve_complete_payment_and_renew_pass(
      current_setting('test.payment_int')::uuid,
      pg_temp.payment_updated_at(current_setting('test.payment_int')::uuid),
      200000, 'cash', now() - interval '1 day', 'idem-guitar-first'
    )
    LIMIT 1
  ),
  'completed payment idempotent replay succeeds after product deactivated'
);

DO $$
DECLARE
  v_course uuid;
  v_product uuid;
  v_student uuid := current_setting('test.student_int')::uuid;
  v_pass uuid := '66666666-6666-6666-6666-666666666609';
  v_payment uuid := '12121212-1212-1212-1212-121212121205';
  v_slot uuid := '77777777-7777-7777-7777-777777777703';
BEGIN
  SELECT course_id INTO v_course
  FROM public.reve_owner_create_course('J', 'Banjo Course')
  LIMIT 1;

  SELECT course_product_id INTO v_product
  FROM public.reve_owner_create_course_product(
    v_course, 'BANJO-4', 'Banjo 4 Lessons', 4, 1, 180000, NULL
  )
  LIMIT 1;

  PERFORM public.reve_owner_set_course_product_active(
    v_product, false, 'deactivate before renewal attempt',
    pg_temp.product_updated_at(v_product)
  );

  PERFORM pg_temp.test_reset_role();

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES (
    v_pass, 'BJ-INT-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Banjo 4 Lessons', 180000,
    CURRENT_DATE - 60, now() - interval '10 days'
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES (
    v_slot, v_pass, current_setting('test.teacher_row')::uuid, 4, '13:00', 60, CURRENT_DATE - 60
  );

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, status, idempotency_key, created_by_profile_id
  ) VALUES (
    v_payment, v_student, v_course, v_product, v_pass,
    180000, 'pending', 'idem-banjo-inactive', current_setting('test.owner1')::uuid
  );

  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);

  PERFORM set_config('test.payment_inactive_product', v_payment::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_complete_payment_and_renew_pass(
       current_setting('test.payment_inactive_product')::uuid,
       pg_temp.payment_updated_at(current_setting('test.payment_inactive_product')::uuid),
       180000, 'cash', now(), 'idem-banjo-inactive') $$,
  'P0001',
  'REVE_PAYMENT_NOT_COMPLETABLE'
);

-- ---------------------------------------------------------------------------
-- Lint regression — Phase 2B-2B2 student create contract
-- ---------------------------------------------------------------------------
SELECT has_function('public', 'reve_owner_create_student', ARRAY['text', 'text', 'text']);

SELECT ok(
  (
    SELECT student_name = 'Lint Regression Student'
      AND student_code ~ '^S[0-9]{4,}$'
    FROM public.reve_owner_create_student(
      p_name := 'Lint Regression Student',
      p_phone := NULL,
      p_email := NULL
    )
    LIMIT 1
  ),
  'reve_owner_create_student allocates canonical code after lint fix'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();
ROLLBACK;

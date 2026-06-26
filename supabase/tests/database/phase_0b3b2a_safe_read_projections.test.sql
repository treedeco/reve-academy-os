-- REVE ACADEMY OS Phase 0B-3B-2A — safe read projection pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(47);

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
  v_pass_sa_vocal_active uuid := '66666666-6666-6666-6666-666666666666';
  v_pass_sa_vocal_reserved uuid := '67676767-6767-6767-6767-676767676767';
  v_pass_sa_piano_active uuid := '68686868-6868-6868-6868-686868686868';
  v_pass_sb_completed uuid := '69696969-6969-6969-6969-696969696969';
  v_pass_sb_active uuid := '70707070-7070-7070-7070-707070707070';
  v_slot_sa uuid := '77777777-7777-7777-7777-777777777777';
  v_slot_sb uuid := '88888888-8888-8888-8888-888888888888';
  v_lesson_sa_1 uuid := '99999999-9999-9999-9999-999999999901';
  v_lesson_sa_2 uuid := '99999999-9999-9999-9999-999999999902';
  v_lesson_sa_3 uuid := '99999999-9999-9999-9999-999999999903';
  v_lesson_sa_4 uuid := '99999999-9999-9999-9999-999999999904';
  v_lesson_piano_1 uuid := '99999999-9999-9999-9999-999999999911';
  v_lesson_sb_old uuid := '10101010-1010-1010-1010-101010101001';
  v_lesson_sb_new uuid := '10101010-1010-1010-1010-101010101002';
  v_payment_a uuid := '12121212-1212-1212-1212-121212121212';
  v_payment_b uuid := '12121212-1212-1212-1212-121212121213';
  v_sms_sa_silent uuid := '14141414-1414-1414-1414-141414141401';
  v_sms_sa_notice uuid := '14141414-1414-1414-1414-141414141402';
  v_sms_old_pass uuid := '14141414-1414-1414-1414-141414141403';
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

  INSERT INTO public.students (id, student_code, profile_id, name, phone, email) VALUES
    (v_student_a_row, 'S-A001', v_student_a, 'Student A', '010-1111-1111', 'sa@test.local'),
    (v_student_b_row, 'S-B001', v_student_b, 'Student B', '010-2222-2222', 'sb@test.local');

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
    start_date, expires_on
  ) VALUES
    (v_pass_sa_vocal_active, 'P-SA-V-001', v_student_a_row, v_course_vocal, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE, CURRENT_DATE + 90),
    (v_pass_sa_vocal_reserved, 'P-SA-V-R01', v_student_a_row, v_course_vocal, v_product_4,
     2, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE + 30, NULL),
    (v_pass_sa_piano_active, 'P-SA-P-001', v_student_a_row, v_course_piano, v_product_8,
     1, 'active', 8, 1, 'Piano 8 Lessons', 400000, CURRENT_DATE, NULL),
    (v_pass_sb_completed, 'P-SB-V-000', v_student_b_row, v_course_vocal, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 120, CURRENT_DATE - 30),
    (v_pass_sb_active, 'P-SB-V-001', v_student_b_row, v_course_vocal, v_product_4,
     2, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE, CURRENT_DATE + 60);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot_sa, v_pass_sa_vocal_active, v_teacher_a_row, 1, '10:00', 60, CURRENT_DATE),
    (v_slot_sb, v_pass_sb_active, v_teacher_b_row, 3, '14:00', 60, CURRENT_DATE);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (v_lesson_sa_1, v_pass_sa_vocal_active, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_sa, 1, now() - interval '7 days', 'completed'),
    (v_lesson_sa_2, v_pass_sa_vocal_active, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_sa, 2, now() - interval '3 days', 'same_day_cancelled'),
    (v_lesson_sa_3, v_pass_sa_vocal_active, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_sa, 3, now() + interval '2 days', 'scheduled'),
    (v_lesson_sa_4, v_pass_sa_vocal_active, v_student_a_row, v_course_vocal, v_teacher_a_row,
     v_slot_sa, 4, now() + interval '9 days', 'advance_cancelled'),
    (v_lesson_piano_1, v_pass_sa_piano_active, v_student_a_row, v_course_piano, v_teacher_a_row,
     NULL, 1, now() + interval '1 day', 'scheduled'),
    (v_lesson_sb_old, v_pass_sb_completed, v_student_b_row, v_course_vocal, v_teacher_a_row,
     NULL, 4, now() - interval '60 days', 'completed'),
    (v_lesson_sb_new, v_pass_sb_active, v_student_b_row, v_course_vocal, v_teacher_b_row,
     v_slot_sb, 1, now() + interval '4 days', 'scheduled');

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, payment_method, status, paid_at, idempotency_key,
    processed_at, created_by_profile_id
  ) VALUES
    (v_payment_a, v_student_a_row, v_course_vocal, v_product_4, v_pass_sa_vocal_active,
     200000, 'bank_transfer', 'completed', now() - interval '10 days', 'idem-key-sa-001',
     now() - interval '10 days', v_owner),
    (v_payment_b, v_student_b_row, v_course_vocal, v_product_4, v_pass_sb_active,
     200000, 'cash', 'completed', now() - interval '5 days', 'idem-key-sb-001',
     now() - interval '5 days', v_owner);

  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status,
    message_body_snapshot, target_date, sent_at
  ) VALUES
    (v_sms_sa_silent, v_student_a_row, v_pass_sa_vocal_active, 'renewal_reminder', 'normal',
     NULL, CURRENT_DATE + 14, NULL),
    (v_sms_sa_notice, v_student_a_row, v_pass_sa_piano_active, 'renewal_reminder', 'target',
     'Please renew your piano pass soon.', CURRENT_DATE + 7, NULL),
    (v_sms_old_pass, v_student_b_row, v_pass_sb_completed, 'renewal_reminder', 'sent',
     'Old pass notice should not appear.', CURRENT_DATE - 60, now() - interval '60 days');

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, false);
  PERFORM set_config('test.teacher_b', v_teacher_b::text, false);
  PERFORM set_config('test.student_a', v_student_a::text, false);
  PERFORM set_config('test.student_b', v_student_b::text, false);
  PERFORM set_config('test.pass_sa_vocal_active', v_pass_sa_vocal_active::text, false);
  PERFORM set_config('test.pass_sa_vocal_reserved', v_pass_sa_vocal_reserved::text, false);
  PERFORM set_config('test.pass_sa_piano_active', v_pass_sa_piano_active::text, false);
  PERFORM set_config('test.pass_sb_active', v_pass_sb_active::text, false);
  PERFORM set_config('test.lesson_sa_3', v_lesson_sa_3::text, false);
  PERFORM set_config('test.payment_a', v_payment_a::text, false);
  PERFORM set_config('test.teacher_a_row', v_teacher_a_row::text, false);
  PERFORM set_config('test.teacher_b_row', v_teacher_b_row::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.reve_rpc_result_columns(p_name text)
RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT p.proargnames
  FROM pg_proc p
  JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE ns.nspname = 'public'
    AND p.proname = p_name
    AND p.pronargs = 0
    AND p.proretset = true;
$$;

-- ---------------------------------------------------------------------------
-- Function existence and contracts
-- ---------------------------------------------------------------------------
SELECT has_function('public', 'reve_get_my_pass_summary', ARRAY[]::text[]);
SELECT has_function('public', 'reve_get_my_assigned_student_summaries', ARRAY[]::text[]);
SELECT has_function('public', 'reve_get_my_payment_summary', ARRAY[]::text[]);
SELECT has_function('public', 'reve_get_my_teacher_display', ARRAY[]::text[]);
SELECT has_function('public', 'reve_get_my_current_notice', ARRAY[]::text[]);

SELECT is(
  pg_temp.reve_rpc_result_columns('reve_get_my_pass_summary'),
  ARRAY[
    'pass_id', 'pass_code', 'pass_status', 'course_id', 'course_code', 'course_name',
    'registered_lesson_count', 'used_lesson_count', 'remaining_lesson_count',
    'next_scheduled_at', 'start_date', 'expires_on', 'assigned_teacher_display_name'
  ],
  'reve_get_my_pass_summary return columns'
);

SELECT is(
  pg_temp.reve_rpc_result_columns('reve_get_my_payment_summary'),
  ARRAY[
    'payment_id', 'related_pass_code', 'course_id', 'course_code', 'course_name',
    'paid_amount_krw', 'payment_status', 'payment_method', 'paid_at', 'created_at'
  ],
  'reve_get_my_payment_summary return columns'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname LIKE 'reve_get_%'
      AND pg_get_function_result(p.oid) LIKE 'SETOF %'
  ),
  'RPC functions do not return SETOF base-table row types'
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname IN (
        'reve_get_my_pass_summary',
        'reve_get_my_assigned_student_summaries',
        'reve_get_my_payment_summary',
        'reve_get_my_teacher_display',
        'reve_get_my_current_notice'
      )
  ),
  'All reve_get RPC functions use fixed empty search_path'
);

SET ROLE anon;
SELECT throws_ok($$ SELECT count(*) FROM public.reve_get_my_pass_summary() $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.reve_get_my_assigned_student_summaries() $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.reve_get_my_payment_summary() $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.reve_get_my_teacher_display() $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.reve_get_my_current_notice() $$, '42501');
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ---------------------------------------------------------------------------
-- Student pass summary
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;

SELECT is(
  (SELECT count(*)::integer FROM public.reve_get_my_pass_summary()),
  3,
  'student A sees three current active/reserved passes across two courses'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_pass_summary()
    WHERE pass_id = current_setting('test.pass_sa_vocal_active')::uuid
      AND pass_status = 'active'
      AND registered_lesson_count = 4
      AND used_lesson_count = 2
      AND remaining_lesson_count = 2
  ),
  'student A vocal active pass used and remaining counts derive correctly'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_pass_summary()
    WHERE pass_id = current_setting('test.pass_sa_piano_active')::uuid
      AND registered_lesson_count = 8
      AND used_lesson_count = 0
      AND remaining_lesson_count = 8
  ),
  'student A eight-lesson piano pass remaining count is correct'
);

SELECT is(
  (
    SELECT next_scheduled_at::date
    FROM public.reve_get_my_pass_summary()
    WHERE pass_id = current_setting('test.pass_sa_vocal_active')::uuid
  ),
  (
    SELECT scheduled_at::date
    FROM public.lessons
    WHERE id = current_setting('test.lesson_sa_3')::uuid
  ),
  'student A next lesson is the earliest future scheduled lesson'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_pass_summary()
    WHERE pass_id = current_setting('test.pass_sa_vocal_reserved')::uuid
      AND next_scheduled_at IS NULL
  ),
  'reserved pass may return null next lesson'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.reve_get_my_pass_summary()
    WHERE pass_id = current_setting('test.pass_sb_active')::uuid
  ),
  'student A does not see student B pass summary'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.reve_get_my_pass_summary()
    WHERE pass_code = 'P-SB-V-001'
  ),
  'student A pass summary excludes other students'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM unnest(pg_temp.reve_rpc_result_columns('reve_get_my_pass_summary')) AS col(name)
    WHERE name IN ('tuition_amount_krw_snapshot', 'discount_adjustment_krw_snapshot', 'idempotency_key')
  ),
  'pass summary contract excludes tuition and discount fields'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_b')::uuid); END $$;
SELECT is((SELECT count(*)::integer FROM public.reve_get_my_pass_summary()), 1, 'student B sees only own current pass');

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT is((SELECT count(*)::integer FROM public.reve_get_my_pass_summary()), 0, 'teacher cannot use student pass summary RPC');

-- ---------------------------------------------------------------------------
-- Teacher assigned-student summary
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_assigned_student_summaries()
    WHERE student_code = 'S-A001'
      AND pass_id = current_setting('test.pass_sa_vocal_active')::uuid
      AND used_lesson_count = 2
      AND remaining_lesson_count = 2
  ),
  'teacher A sees assigned student A current vocal pass summary'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.reve_get_my_assigned_student_summaries()
    WHERE student_code = 'S-B001'
  ),
  'teacher A does not see student B after historical-only assignment ended'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.reve_get_my_assigned_student_summaries()
    WHERE student_code = 'S-A001'
      AND pass_id = current_setting('test.pass_sb_active')::uuid
  ),
  'teacher summary excludes unrelated pass ids'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM unnest(pg_temp.reve_rpc_result_columns('reve_get_my_assigned_student_summaries')) AS col(name)
    WHERE name IN ('phone', 'email', 'paid_amount_krw', 'message_body_snapshot')
  ),
  'teacher summary contract excludes contact, payment, and SMS fields'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_b')::uuid); END $$;
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_assigned_student_summaries()
    WHERE student_code = 'S-B001'
      AND pass_id = current_setting('test.pass_sb_active')::uuid
  ),
  'teacher B sees own assigned student B'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;
SELECT is(
  (SELECT count(*)::integer FROM public.reve_get_my_assigned_student_summaries()),
  0,
  'student cannot execute teacher assigned-student summary RPC'
);

-- ---------------------------------------------------------------------------
-- Student payment summary
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_payment_summary()
    WHERE payment_id = current_setting('test.payment_a')::uuid
      AND related_pass_code = 'P-SA-V-001'
      AND paid_amount_krw = 200000
      AND payment_status = 'completed'
      AND payment_method = 'bank_transfer'
  ),
  'student A sees own payment-facing record with expected amounts'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.reve_get_my_payment_summary()
    WHERE related_pass_code = 'P-SB-V-001'
  ),
  'student A cannot see student B payments'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM unnest(pg_temp.reve_rpc_result_columns('reve_get_my_payment_summary')) AS col(name)
    WHERE name IN ('idempotency_key', 'processed_at', 'created_by_profile_id', 'actor_profile_id')
  ),
  'payment summary contract excludes idempotency and actor fields'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT is((SELECT count(*)::integer FROM public.reve_get_my_payment_summary()), 0, 'teacher cannot use student payment summary RPC');

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;
SELECT is(
  reve_private.current_app_role(),
  'student',
  'JWT metadata does not elevate student to owner for RPC authorization'
);

-- ---------------------------------------------------------------------------
-- Student teacher display
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_teacher_display()
    WHERE teacher_id = current_setting('test.teacher_a_row')::uuid
      AND teacher_code = 'T-A001'
      AND teacher_name = 'Teacher A'
  ),
  'student A sees assigned teacher display row'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.reve_get_my_teacher_display()
    WHERE teacher_id = current_setting('test.teacher_b_row')::uuid
  ),
  'student A does not see unrelated teacher B'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM unnest(pg_temp.reve_rpc_result_columns('reve_get_my_teacher_display')) AS col(name)
    WHERE name IN ('phone', 'email')
  ),
  'teacher display contract excludes phone and email'
);

SELECT is(
  (
    SELECT count(*)::bigint
    FROM (
      SELECT DISTINCT teacher_id, course_id
      FROM public.reve_get_my_teacher_display()
    ) d
  ),
  (
    SELECT count(*)::bigint
    FROM public.reve_get_my_teacher_display()
  ),
  'teacher display removes duplicate teacher/course rows'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT is((SELECT count(*)::integer FROM public.reve_get_my_teacher_display()), 0, 'teacher caller receives no teacher-display rows');

-- ---------------------------------------------------------------------------
-- Student current notice (OD-20 provisional)
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.reve_get_my_current_notice()
    WHERE pass_id = current_setting('test.pass_sa_piano_active')::uuid
      AND message_body_snapshot = 'Please renew your piano pass soon.'
  ),
  'student A sees current-pass notice with message body snapshot'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.reve_get_my_current_notice()
    WHERE pass_id = current_setting('test.pass_sa_vocal_active')::uuid
  ),
  'normal notification without user-facing content does not appear'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.reve_get_my_current_notice()
    WHERE message_body_snapshot = 'Old pass notice should not appear.'
  ),
  'old completed-pass notice is not returned as current notice'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM unnest(pg_temp.reve_rpc_result_columns('reve_get_my_current_notice')) AS col(name)
    WHERE name IN ('status', 'sent_confirmed_by_profile_id', 'notification_type', 'actor_profile_id')
  ),
  'current notice contract excludes internal SMS status and actor metadata'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_b')::uuid); END $$;
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.reve_get_my_current_notice()
    WHERE message_body_snapshot = 'Please renew your piano pass soon.'
  ),
  'student B cannot see student A notice'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid); END $$;
SELECT is((SELECT count(*)::integer FROM public.reve_get_my_current_notice()), 0, 'teacher cannot obtain student notices through current-notice RPC');

-- ---------------------------------------------------------------------------
-- Inactive profile receives no operational RPC data
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
UPDATE public.profiles SET account_state = 'inactive' WHERE id = current_setting('test.student_a')::uuid;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;
SELECT is((SELECT count(*)::integer FROM public.reve_get_my_pass_summary()), 0, 'inactive student profile receives no pass summary rows');

SELECT * FROM finish();

ROLLBACK;

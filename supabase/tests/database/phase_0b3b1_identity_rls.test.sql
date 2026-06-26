-- REVE ACADEMY OS Phase 0B-3B-1 — identity helpers and RLS pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(111);

-- ---------------------------------------------------------------------------
-- Fixture: auth users, profiles, and minimum business graph
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
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_pass_a uuid := '66666666-6666-6666-6666-666666666666';
  v_pass_b uuid := '67676767-6767-6767-6767-676767676767';
  v_slot_a uuid := '77777777-7777-7777-7777-777777777777';
  v_slot_b uuid := '88888888-8888-8888-8888-888888888888';
  v_lesson_a uuid := '99999999-9999-9999-9999-999999999999';
  v_lesson_b uuid := '10101010-1010-1010-1010-101010101010';
  v_payment uuid := '12121212-1212-1212-1212-121212121212';
  v_refund uuid := '13131313-1313-1313-1313-131313131313';
  v_sms uuid := '14141414-1414-1414-1414-141414141414';
  v_request uuid := '15151515-1515-1515-1515-151515151515';
  v_event uuid := '16161616-1616-1616-1616-161616161616';
  v_note_internal uuid := '17171717-1717-1717-1717-171717171717';
  v_note_visible uuid := '18181818-1818-1818-1818-181818181818';
  v_note_visible_b uuid := '28282828-2828-2828-2828-282828282828';
  v_audit uuid := '19191919-1919-1919-1919-191919191919';
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
    (v_course, 'VOCAL', 'Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES (v_product, v_course, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date
  ) VALUES
    (v_pass_a, 'P-SA-001', v_student_a_row, v_course, v_product,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE),
    (v_pass_b, 'P-SB-001', v_student_b_row, v_course, v_product,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot_a, v_pass_a, v_teacher_a_row, 1, '10:00', 60, CURRENT_DATE),
    (v_slot_b, v_pass_b, v_teacher_b_row, 3, '14:00', 60, CURRENT_DATE);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (v_lesson_a, v_pass_a, v_student_a_row, v_course, v_teacher_a_row, v_slot_a, 1, now() + interval '1 day', 'scheduled'),
    (v_lesson_b, v_pass_b, v_student_b_row, v_course, v_teacher_b_row, v_slot_b, 1, now() + interval '2 days', 'scheduled');

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, status, idempotency_key
  ) VALUES (
    v_payment, v_student_a_row, v_course, v_product, v_pass_a,
    200000, 'completed', 'pay-key-rls-001'
  );

  INSERT INTO public.payment_refunds (
    id, payment_id, refunded_amount_krw, reason, actor_profile_id, pass_disposition
  ) VALUES (
    v_refund, v_payment, 50000, 'Partial test refund', v_owner, 'active_cancelled_future_advance_cancelled'
  );

  INSERT INTO public.sms_notifications (id, student_id, pass_id, message_body_snapshot)
  VALUES (v_sms, v_student_a_row, v_pass_a, 'Renewal reminder body');

  INSERT INTO public.schedule_change_requests (
    id, student_id, target_lesson_id, requesting_profile_id,
    request_source_role, status, requested_reason
  ) VALUES (
    v_request, v_student_a_row, v_lesson_a, v_student_a,
    'student', 'submitted', 'Need reschedule'
  );

  INSERT INTO public.lesson_schedule_changes (
    id, lesson_id, change_origin, previous_scheduled_at, new_scheduled_at
  ) VALUES (
    v_event, v_lesson_a, 'direct_user', now(), now() + interval '3 days'
  );

  INSERT INTO public.lesson_notes (id, lesson_id, author_profile_id, body, visibility) VALUES
    (v_note_internal, v_lesson_a, v_teacher_a, 'Internal teacher note', 'internal'),
    (v_note_visible, v_lesson_a, v_teacher_a, 'Visible student note', 'student_visible'),
    (v_note_visible_b, v_lesson_b, v_teacher_b, 'Student B visible note', 'student_visible');

  INSERT INTO public.audit_logs (id, action, resource_table, resource_id)
  VALUES (v_audit, 'test.seed', 'students', v_student_a_row);

  PERFORM set_config('test.owner', v_owner::text, true);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, true);
  PERFORM set_config('test.teacher_b', v_teacher_b::text, true);
  PERFORM set_config('test.student_a', v_student_a::text, true);
  PERFORM set_config('test.student_b', v_student_b::text, true);
  PERFORM set_config('test.teacher_a_row', v_teacher_a_row::text, true);
  PERFORM set_config('test.teacher_b_row', v_teacher_b_row::text, true);
  PERFORM set_config('test.student_a_row', v_student_a_row::text, true);
  PERFORM set_config('test.student_b_row', v_student_b_row::text, true);
  PERFORM set_config('test.lesson_a', v_lesson_a::text, true);
  PERFORM set_config('test.lesson_b', v_lesson_b::text, true);
  PERFORM set_config('test.slot_a', v_slot_a::text, true);
  PERFORM set_config('test.slot_b', v_slot_b::text, true);
  PERFORM set_config('test.pass_a', v_pass_a::text, true);
  PERFORM set_config('test.pass_b', v_pass_b::text, true);
  PERFORM set_config('test.payment', v_payment::text, true);
  PERFORM set_config('test.refund', v_refund::text, true);
  PERFORM set_config('test.sms', v_sms::text, true);
  PERFORM set_config('test.request', v_request::text, true);
  PERFORM set_config('test.event', v_event::text, true);
  PERFORM set_config('test.note_internal', v_note_internal::text, true);
  PERFORM set_config('test.note_visible', v_note_visible::text, true);
  PERFORM set_config('test.note_visible_b', v_note_visible_b::text, true);
  PERFORM set_config('test.audit', v_audit::text, true);
  PERFORM set_config('test.course', v_course::text, true);
  PERFORM set_config('test.product', v_product::text, true);
END $$;

-- ---------------------------------------------------------------------------
-- Helper: switch to authenticated JWT subject
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.test_auth_as(p_user uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  SET ROLE authenticated;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.test_reset_role()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM set_config('request.jwt.claim.role', '', false);
END;
$$;

-- ---------------------------------------------------------------------------
-- Identity helper tests
-- ---------------------------------------------------------------------------
SELECT pg_temp.test_reset_role();

SELECT is(reve_private.current_app_role(), NULL, 'unauthenticated current_app_role is null');
SELECT ok(NOT reve_private.is_owner(), 'unauthenticated is_owner is false');
SELECT is(reve_private.current_teacher_id(), NULL, 'unauthenticated current_teacher_id is null');
SELECT is(reve_private.current_student_id(), NULL, 'unauthenticated current_student_id is null');
SELECT ok(
  NOT reve_private.teacher_can_access_lesson(current_setting('test.lesson_a')::uuid),
  'unauthenticated teacher_can_access_lesson is false'
);

SELECT pg_temp.test_auth_as(current_setting('test.owner')::uuid);
SELECT ok(reve_private.is_owner(), 'owner is_owner resolves true');
SELECT is(reve_private.current_app_role(), 'owner', 'owner current_app_role resolves owner');

SELECT pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid);
SELECT is(reve_private.current_app_role(), 'teacher', 'teacher A current_app_role resolves teacher');
SELECT is(
  reve_private.current_teacher_id(),
  current_setting('test.teacher_a_row')::uuid,
  'teacher A current_teacher_id resolves linked teacher row'
);

SELECT pg_temp.test_auth_as(current_setting('test.teacher_b')::uuid);
SELECT is(
  reve_private.current_teacher_id(),
  current_setting('test.teacher_b_row')::uuid,
  'teacher B current_teacher_id resolves linked teacher row'
);

SELECT pg_temp.test_auth_as(current_setting('test.student_a')::uuid);
SELECT is(reve_private.current_app_role(), 'student', 'student A current_app_role resolves student');
SELECT is(
  reve_private.current_student_id(),
  current_setting('test.student_a_row')::uuid,
  'student A current_student_id resolves linked student row'
);

SELECT pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid);
SELECT ok(
  reve_private.teacher_can_access_lesson(current_setting('test.lesson_a')::uuid),
  'teacher A can access teacher A lesson'
);
SELECT ok(
  NOT reve_private.teacher_can_access_lesson(current_setting('test.lesson_b')::uuid),
  'teacher A cannot access teacher B lesson'
);

SELECT pg_temp.test_auth_as(current_setting('test.student_a')::uuid);
SELECT ok(
  reve_private.student_owns_lesson(current_setting('test.lesson_a')::uuid),
  'student A owns student A lesson'
);
SELECT ok(
  NOT reve_private.student_owns_lesson(current_setting('test.lesson_b')::uuid),
  'student A does not own student B lesson'
);

SELECT pg_temp.test_reset_role();
SET ROLE anon;
SELECT throws_ok(
  $$ SELECT reve_private.is_owner() $$,
  '42501'
);
SELECT pg_temp.test_reset_role();

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;
SELECT throws_ok(
  $attempt$
  CREATE OR REPLACE FUNCTION reve_private.is_owner() RETURNS boolean LANGUAGE sql AS $body$ SELECT true $body$
  $attempt$,
  '42501'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'reve_private'
      AND c.relkind IN ('r', 'v', 'm')
  ),
  'reve_private exposes no Data API tables or views'
);

-- ---------------------------------------------------------------------------
-- Anonymous access denied
-- ---------------------------------------------------------------------------
SELECT pg_temp.test_reset_role();
SET ROLE anon;

SELECT throws_ok($$ SELECT count(*) FROM public.profiles $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.students $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.teachers $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.courses $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.course_products $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.passes $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.schedule_slots $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.lessons $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.payments $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.payment_refunds $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.sms_notifications $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.schedule_change_requests $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.lesson_schedule_changes $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.lesson_notes $$, '42501');
SELECT throws_ok($$ SELECT count(*) FROM public.audit_logs $$, '42501');

SELECT throws_ok(
  $$ INSERT INTO public.profiles (id, role, display_name)
     VALUES ('abababab-abab-abab-abab-abababababab', 'student', 'Anon') $$,
  '42501'
);
SELECT throws_ok(
  $$ UPDATE public.courses SET name = 'Hacked' WHERE id = current_setting('test.course')::uuid $$,
  '42501'
);
SELECT throws_ok(
  $$ DELETE FROM public.students WHERE id = current_setting('test.student_a_row')::uuid $$,
  '42501'
);

RESET ROLE;

-- ---------------------------------------------------------------------------
-- Owner access
-- ---------------------------------------------------------------------------
SELECT pg_temp.test_auth_as(current_setting('test.owner')::uuid);

SELECT ok(
  (SELECT count(*) FROM public.profiles) >= 5,
  'owner can select profiles'
);
SELECT ok(
  (SELECT count(*) FROM public.students) >= 2,
  'owner can select students'
);
SELECT ok(
  (SELECT count(*) FROM public.teachers) >= 2,
  'owner can select teachers'
);
SELECT ok(
  (SELECT count(*) FROM public.courses) >= 1,
  'owner can select courses'
);
SELECT ok(
  (SELECT count(*) FROM public.course_products) >= 1,
  'owner can select course_products'
);
SELECT ok(
  (SELECT count(*) FROM public.passes) >= 1,
  'owner can select passes'
);
SELECT ok(
  (SELECT count(*) FROM public.schedule_slots) >= 2,
  'owner can select schedule_slots'
);
SELECT ok(
  (SELECT count(*) FROM public.lessons) >= 2,
  'owner can select lessons'
);
SELECT ok(
  (SELECT count(*) FROM public.payments) >= 1,
  'owner can select payments'
);
SELECT ok(
  (SELECT count(*) FROM public.payment_refunds) >= 1,
  'owner can select payment_refunds'
);
SELECT ok(
  (SELECT count(*) FROM public.sms_notifications) >= 1,
  'owner can select sms_notifications'
);
SELECT ok(
  (SELECT count(*) FROM public.schedule_change_requests) >= 1,
  'owner can select schedule_change_requests'
);
SELECT ok(
  (SELECT count(*) FROM public.lesson_schedule_changes) >= 1,
  'owner can select lesson_schedule_changes'
);
SELECT ok(
  (SELECT count(*) FROM public.lesson_notes) >= 2,
  'owner can select lesson_notes'
);
SELECT ok(
  (SELECT count(*) FROM public.audit_logs) >= 1,
  'owner can select audit_logs'
);

SELECT throws_ok(
  $$ DELETE FROM public.passes WHERE id = current_setting('test.pass_a')::uuid $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.audit_logs (action, resource_table, resource_id)
     VALUES ('bad', 'students', current_setting('test.student_a_row')::uuid) $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.payment_refunds (
       payment_id, refunded_amount_krw, reason, actor_profile_id, pass_disposition
     ) VALUES (
       current_setting('test.payment')::uuid, 1000, 'bad',
       current_setting('test.owner')::uuid, 'reserved_cancelled'
     ) $$,
  '42501'
);
SELECT throws_ok(
  $$ UPDATE public.passes SET status = 'cancelled' WHERE id = current_setting('test.pass_a')::uuid $$,
  '42501'
);
SELECT throws_ok(
  $$ UPDATE public.lessons SET status = 'completed' WHERE id = current_setting('test.lesson_a')::uuid $$,
  '42501'
);
SELECT throws_ok(
  $$ UPDATE public.payments SET status = 'refunded' WHERE id = current_setting('test.payment')::uuid $$,
  '42501'
);

-- ---------------------------------------------------------------------------
-- Teacher isolation
-- ---------------------------------------------------------------------------
SELECT pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.teachers
    WHERE id = current_setting('test.teacher_a_row')::uuid
  ),
  'teacher A can select own teacher record'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.teachers
    WHERE id = current_setting('test.teacher_b_row')::uuid
  ),
  'teacher A cannot select teacher B teacher record'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.students
    WHERE id = current_setting('test.student_a_row')::uuid
  ),
  'teacher A can select assigned student A'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.students
    WHERE id = current_setting('test.student_b_row')::uuid
  ),
  'teacher A cannot select unassigned student B'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.lessons
    WHERE id = current_setting('test.lesson_a')::uuid
  ),
  'teacher A can select assigned lesson A'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lessons
    WHERE id = current_setting('test.lesson_b')::uuid
  ),
  'teacher A cannot select teacher B lesson'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.schedule_slots
    WHERE id = current_setting('test.slot_a')::uuid
  ),
  'teacher A can select assigned schedule slot'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.schedule_slots
    WHERE id = current_setting('test.slot_b')::uuid
  ),
  'teacher A cannot select teacher B schedule slot'
);

SELECT is((SELECT count(*)::integer FROM public.payments), 0, 'teacher cannot read payments');
SELECT is((SELECT count(*)::integer FROM public.payment_refunds), 0, 'teacher cannot read payment_refunds');
SELECT is((SELECT count(*)::integer FROM public.sms_notifications), 0, 'teacher cannot read sms_notifications');
SELECT is((SELECT count(*)::integer FROM public.audit_logs), 0, 'teacher cannot read audit_logs');
SELECT is((SELECT count(*)::integer FROM public.course_products), 0, 'teacher cannot read course_products');
SELECT is((SELECT count(*)::integer FROM public.passes), 0, 'teacher cannot read passes');

SELECT throws_ok(
  $$ UPDATE public.lessons SET status = 'completed' WHERE id = current_setting('test.lesson_a')::uuid $$,
  '42501'
);
SELECT throws_ok(
  $$ UPDATE public.passes SET status = 'cancelled' WHERE id = current_setting('test.pass_a')::uuid $$,
  '42501'
);
SELECT throws_ok(
  $$ UPDATE public.schedule_change_requests
     SET status = 'approved' WHERE id = current_setting('test.request')::uuid $$,
  '42501'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.schedule_change_requests
    WHERE id = current_setting('test.request')::uuid
  ),
  'teacher A can read permitted schedule change request'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.lesson_schedule_changes
    WHERE id = current_setting('test.event')::uuid
  ),
  'teacher A can read assigned lesson schedule change event'
);

SELECT lives_ok(
  $$ INSERT INTO public.lesson_notes (lesson_id, author_profile_id, body, visibility)
     VALUES (
       current_setting('test.lesson_a')::uuid,
       current_setting('test.teacher_a')::uuid,
       'New teacher note', 'internal'
     ) $$,
  'teacher A can insert lesson note on assigned lesson'
);

SELECT throws_ok(
  $$ INSERT INTO public.lesson_notes (lesson_id, author_profile_id, body, visibility)
     VALUES (
       current_setting('test.lesson_b')::uuid,
       current_setting('test.teacher_a')::uuid,
       'Bad note', 'internal'
     ) $$,
  '42501'
);

SELECT throws_ok(
  $$ UPDATE public.lesson_notes
     SET author_profile_id = current_setting('test.teacher_b')::uuid
     WHERE id = current_setting('test.note_internal')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ UPDATE public.lesson_notes
     SET lesson_id = current_setting('test.lesson_b')::uuid
     WHERE id = current_setting('test.note_internal')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ DELETE FROM public.lesson_notes WHERE id = current_setting('test.note_internal')::uuid $$,
  '42501'
);

-- ---------------------------------------------------------------------------
-- Student isolation
-- ---------------------------------------------------------------------------
SELECT pg_temp.test_auth_as(current_setting('test.student_a')::uuid);

SELECT ok(
  EXISTS (SELECT 1 FROM public.profiles WHERE id = current_setting('test.student_a')::uuid),
  'student A can select own profile'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = current_setting('test.student_b')::uuid),
  'student A cannot select student B profile'
);
SELECT ok(
  EXISTS (SELECT 1 FROM public.students WHERE id = current_setting('test.student_a_row')::uuid),
  'student A can select own student record'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.students WHERE id = current_setting('test.student_b_row')::uuid),
  'student A cannot select student B student record'
);
SELECT ok(
  EXISTS (SELECT 1 FROM public.lessons WHERE id = current_setting('test.lesson_a')::uuid),
  'student A can select own lessons'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.lessons WHERE id = current_setting('test.lesson_b')::uuid),
  'student A cannot select student B lessons'
);
SELECT ok(
  EXISTS (SELECT 1 FROM public.schedule_slots WHERE id = current_setting('test.slot_a')::uuid),
  'student A can select own schedule slots'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.schedule_slots WHERE id = current_setting('test.slot_b')::uuid),
  'student A cannot select student B schedule slots'
);

SELECT is((SELECT count(*)::integer FROM public.teachers), 0, 'student cannot select teachers table');
SELECT is((SELECT count(*)::integer FROM public.passes), 0, 'student cannot select passes');
SELECT is((SELECT count(*)::integer FROM public.payments), 0, 'student cannot select payments');
SELECT is((SELECT count(*)::integer FROM public.sms_notifications), 0, 'student cannot select sms records');
SELECT is((SELECT count(*)::integer FROM public.audit_logs), 0, 'student cannot read audit logs');

SELECT throws_ok(
  $$ UPDATE public.lessons SET status = 'completed' WHERE id = current_setting('test.lesson_a')::uuid $$,
  '42501'
);
SELECT throws_ok(
  $$ INSERT INTO public.lesson_notes (lesson_id, author_profile_id, body, visibility)
     VALUES (
       current_setting('test.lesson_a')::uuid,
       current_setting('test.student_a')::uuid,
       'Student note', 'student_visible'
     ) $$,
  '42501'
);
DO $$
DECLARE
  v_rows integer;
BEGIN
  UPDATE public.lesson_notes
  SET body = 'changed'
  WHERE id = current_setting('test.note_visible')::uuid;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM set_config('test.student_note_update_rows', v_rows::text, false);
END $$;

SELECT is(
  current_setting('test.student_note_update_rows'),
  '0',
  'student cannot update lesson notes'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.lesson_notes
    WHERE id = current_setting('test.note_visible')::uuid
  ),
  'student A can read own student-visible note'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lesson_notes
    WHERE id = current_setting('test.note_internal')::uuid
  ),
  'student A cannot read own internal note'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lesson_notes
    WHERE id = current_setting('test.note_visible_b')::uuid
  ),
  'student A cannot read another student note'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.schedule_change_requests
    WHERE id = current_setting('test.request')::uuid
  ),
  'student A can read own schedule change request'
);

SELECT lives_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason
     ) VALUES (
       current_setting('test.student_a_row')::uuid,
       current_setting('test.lesson_a')::uuid,
       current_setting('test.student_a')::uuid,
       'student', 'Student reschedule request'
     ) $$,
  'student A can create valid submitted schedule change request'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_a')::uuid); END $$;

SELECT throws_ok(
  $$ INSERT INTO public.schedule_change_requests (
       student_id, target_lesson_id, requesting_profile_id,
       request_source_role, requested_reason
     ) VALUES (
       current_setting('test.student_a_row')::uuid,
       current_setting('test.lesson_b')::uuid,
       current_setting('test.student_a')::uuid,
       'student', 'Cross-student attempt'
     ) $$,
  '42501'
);

SELECT throws_ok(
  $$ UPDATE public.schedule_change_requests
     SET status = 'approved', decided_at = now()
     WHERE id = current_setting('test.request')::uuid $$,
  '42501'
);

-- ---------------------------------------------------------------------------
-- Cross-role bypass and global write restrictions
-- ---------------------------------------------------------------------------
SELECT pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid);
SELECT is(
  reve_private.current_app_role(),
  'teacher',
  'JWT user metadata does not elevate teacher to owner'
);

SELECT pg_temp.test_auth_as(current_setting('test.student_a')::uuid);
SELECT ok(NOT reve_private.is_owner(), 'student cannot claim owner via JWT metadata');

SELECT pg_temp.test_auth_as(current_setting('test.teacher_a')::uuid);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lessons WHERE id = current_setting('test.lesson_b')::uuid
  ),
  'teacher cannot access another teacher lesson by foreign id'
);

SELECT throws_ok(
  $$ DELETE FROM public.lessons WHERE id = current_setting('test.lesson_a')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ INSERT INTO public.audit_logs (action, resource_table, resource_id)
     VALUES ('bad', 'lessons', current_setting('test.lesson_a')::uuid) $$,
  '42501'
);

SELECT throws_ok(
  $$ INSERT INTO public.lesson_schedule_changes (
       lesson_id, change_origin, previous_scheduled_at, new_scheduled_at
     ) VALUES (
       current_setting('test.lesson_a')::uuid, 'direct_user', now(), now() + interval '1 day'
     ) $$,
  '42501'
);

SELECT * FROM finish();

ROLLBACK;

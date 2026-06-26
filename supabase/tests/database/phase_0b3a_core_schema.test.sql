-- REVE ACADEMY OS Phase 0B-3A — core schema pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(60);

-- ---------------------------------------------------------------------------
-- Structure: 15 application tables
-- ---------------------------------------------------------------------------
SELECT has_table('public', 'profiles', 'profiles table exists');
SELECT has_table('public', 'students', 'students table exists');
SELECT has_table('public', 'teachers', 'teachers table exists');
SELECT has_table('public', 'courses', 'courses table exists');
SELECT has_table('public', 'course_products', 'course_products table exists');
SELECT has_table('public', 'passes', 'passes table exists');
SELECT has_table('public', 'schedule_slots', 'schedule_slots table exists');
SELECT has_table('public', 'lessons', 'lessons table exists');
SELECT has_table('public', 'payments', 'payments table exists');
SELECT has_table('public', 'payment_refunds', 'payment_refunds table exists');
SELECT has_table('public', 'sms_notifications', 'sms_notifications table exists');
SELECT has_table('public', 'schedule_change_requests', 'schedule_change_requests table exists');
SELECT has_table('public', 'lesson_schedule_changes', 'lesson_schedule_changes table exists');
SELECT has_table('public', 'lesson_notes', 'lesson_notes table exists');
SELECT has_table('public', 'audit_logs', 'audit_logs table exists');

-- Primary keys
SELECT col_is_pk('public', 'profiles', 'id', 'profiles.id is PK');
SELECT col_is_pk('public', 'students', 'id', 'students.id is PK');
SELECT col_is_pk('public', 'passes', 'id', 'passes.id is PK');
SELECT col_is_pk('public', 'lessons', 'id', 'lessons.id is PK');
SELECT col_is_pk('public', 'payments', 'id', 'payments.id is PK');

-- Core foreign keys
SELECT fk_ok('public', 'profiles', 'id', 'auth', 'users', 'id', 'profiles.id -> auth.users.id');
SELECT fk_ok('public', 'students', 'profile_id', 'public', 'profiles', 'id', 'students.profile_id -> profiles.id');
SELECT fk_ok('public', 'passes', 'student_id', 'public', 'students', 'id', 'passes.student_id -> students.id');
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conname = 'lessons_pass_student_course_fkey'
      AND conrelid = 'public.lessons'::regclass
  ),
  'lessons composite FK (pass_id, student_id, course_id) -> passes exists'
);
SELECT fk_ok('public', 'payment_refunds', 'payment_id', 'public', 'payments', 'id', 'payment_refunds.payment_id -> payments.id');

-- No forbidden derived/deduction columns
SELECT hasnt_column('public', 'passes', 'used_count', 'passes has no used_count');
SELECT hasnt_column('public', 'passes', 'remaining_count', 'passes has no remaining_count');
SELECT hasnt_column('public', 'lessons', 'is_deducted', 'lessons has no is_deducted');

-- RLS enabled on all 15 tables
SELECT ok(
  (SELECT bool_and(c.relrowsecurity)
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relname IN (
       'profiles', 'students', 'teachers', 'courses', 'course_products',
       'passes', 'schedule_slots', 'lessons', 'payments', 'payment_refunds',
       'sms_notifications', 'schedule_change_requests', 'lesson_schedule_changes',
       'lesson_notes', 'audit_logs'
     )
     AND c.relkind = 'r'),
  'RLS enabled on all 15 application tables'
);

-- ---------------------------------------------------------------------------
-- Test fixture (minimal graph for constraint and protection tests)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_student_a uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_student_b uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_teacher uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_pass uuid := '11111111-1111-1111-1111-111111111111';
  v_pass_b uuid := '22222222-2222-2222-2222-222222222222';
  v_slot uuid := '33333333-3333-3333-3333-333333333333';
  v_lesson uuid := '44444444-4444-4444-4444-444444444444';
  v_payment uuid := '55555555-5555-5555-5555-555555555555';
  v_refund uuid := '66666666-6666-6666-6666-666666666666';
  v_sms uuid := '77777777-7777-7777-7777-777777777777';
  v_event uuid := '88888888-8888-8888-8888-888888888888';
  v_audit uuid := '99999999-9999-9999-9999-999999999999';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner@test.local', crypt('test', gen_salt('bf')), now(), now(), now()
  );

  INSERT INTO public.profiles (id, role, display_name)
  VALUES (v_owner, 'owner', 'Test Owner');

  INSERT INTO public.students (id, student_code, name)
  VALUES
    (v_student_a, 'S001', 'Student A'),
    (v_student_b, 'S002', 'Student B');

  INSERT INTO public.teachers (id, teacher_code, name)
  VALUES (v_teacher, 'T001', 'Teacher One');

  INSERT INTO public.courses (id, course_code, name)
  VALUES (v_course, 'VOCAL', 'Vocal');

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES (v_product, v_course, 'VOCAL-4', 'Vocal 4', 4, 1, 200000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date
  ) VALUES (
    v_pass, 'V-S001-001', v_student_a, v_course, v_product,
    1, 'active', 4, 1, 'Vocal 4', 200000, CURRENT_DATE
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time,
    duration_minutes, effective_from
  ) VALUES (
    v_slot, v_pass, v_teacher, 1, '10:00', 60, CURRENT_DATE
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    v_lesson, v_pass, v_student_a, v_course, v_teacher,
    v_slot, 1, now() + interval '1 day', 'scheduled'
  );

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id,
    paid_amount_krw, status, idempotency_key
  ) VALUES (
    v_payment, v_student_a, v_course, v_product, 200000, 'pending', 'pay-key-001'
  );

  INSERT INTO public.payment_refunds (
    id, payment_id, refunded_amount_krw, reason, actor_profile_id, pass_disposition
  ) VALUES (
    v_refund, v_payment, 200000, 'Test refund', v_owner, 'active_cancelled_future_advance_cancelled'
  );

  INSERT INTO public.sms_notifications (id, student_id, pass_id)
  VALUES (v_sms, v_student_a, v_pass);

  INSERT INTO public.lesson_schedule_changes (
    id, lesson_id, change_origin, previous_scheduled_at, new_scheduled_at
  ) VALUES (
    v_event, v_lesson, 'direct_user', now(), now() + interval '2 days'
  );

  INSERT INTO public.audit_logs (
    id, action, resource_table, resource_id
  ) VALUES (v_audit, 'test.action', 'students', v_student_a);

  -- Store pass_b placeholder for sequence tests (second pass same student/course)
  PERFORM set_config('test.pass_id', v_pass::text, true);
  PERFORM set_config('test.student_a', v_student_a::text, true);
  PERFORM set_config('test.student_b', v_student_b::text, true);
  PERFORM set_config('test.course', v_course::text, true);
  PERFORM set_config('test.product', v_product::text, true);
  PERFORM set_config('test.teacher', v_teacher::text, true);
  PERFORM set_config('test.lesson', v_lesson::text, true);
  PERFORM set_config('test.payment', v_payment::text, true);
  PERFORM set_config('test.refund', v_refund::text, true);
  PERFORM set_config('test.sms', v_sms::text, true);
  PERFORM set_config('test.event', v_event::text, true);
  PERFORM set_config('test.audit', v_audit::text, true);
  PERFORM set_config('test.owner', v_owner::text, true);
END $$;

-- ---------------------------------------------------------------------------
-- Constraint tests
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.students (student_code, name) VALUES ('S001', 'Dup Student') $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.teachers (teacher_code, name) VALUES ('T001', 'Dup Teacher') $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.courses (course_code, name) VALUES ('VOCAL', 'Dup Course') $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.course_products (course_id, product_code, product_name, default_lesson_count, weekly_frequency, default_tuition_krw)
     VALUES (current_setting('test.course')::uuid, 'VOCAL-4', 'Dup Product', 4, 1, 200000) $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.passes (
       pass_code, student_id, course_id, course_product_id, sequence_number, status,
       registered_lesson_count_snapshot, weekly_frequency_snapshot, product_name_snapshot,
       tuition_amount_krw_snapshot, start_date
     ) VALUES (
       'V-S001-001', current_setting('test.student_a')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, 2, 'completed', 4, 1, 'Vocal 4', 200000, CURRENT_DATE
     ) $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.passes (
       pass_code, student_id, course_id, course_product_id, sequence_number, status,
       registered_lesson_count_snapshot, weekly_frequency_snapshot, product_name_snapshot,
       tuition_amount_krw_snapshot, start_date
     ) VALUES (
       'V-S001-002', current_setting('test.student_a')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, 1, 'completed', 4, 1, 'Vocal 4', 200000, CURRENT_DATE
     ) $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.passes (
       pass_code, student_id, course_id, course_product_id, sequence_number, status,
       registered_lesson_count_snapshot, weekly_frequency_snapshot, product_name_snapshot,
       tuition_amount_krw_snapshot, start_date
     ) VALUES (
       'V-S001-003', current_setting('test.student_a')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, 2, 'active', 4, 1, 'Vocal 4', 200000, CURRENT_DATE
     ) $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.passes (
       pass_code, student_id, course_id, course_product_id, sequence_number, status,
       registered_lesson_count_snapshot, weekly_frequency_snapshot, product_name_snapshot,
       tuition_amount_krw_snapshot, start_date
     ) VALUES (
       'V-S001-004', current_setting('test.student_a')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, 3, 'reserved', 4, 1, 'Vocal 4', 200000, CURRENT_DATE
     );
     INSERT INTO public.passes (
       pass_code, student_id, course_id, course_product_id, sequence_number, status,
       registered_lesson_count_snapshot, weekly_frequency_snapshot, product_name_snapshot,
       tuition_amount_krw_snapshot, start_date
     ) VALUES (
       'V-S001-005', current_setting('test.student_a')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, 4, 'reserved', 4, 1, 'Vocal 4', 200000, CURRENT_DATE
     ) $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.lessons (
       pass_id, student_id, course_id, assigned_teacher_id,
       sequence_number, scheduled_at
     ) VALUES (
       current_setting('test.pass_id')::uuid, current_setting('test.student_a')::uuid,
       current_setting('test.course')::uuid, current_setting('test.teacher')::uuid,
       1, now() + interval '3 days'
     ) $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.lessons (
       pass_id, student_id, course_id, assigned_teacher_id,
       sequence_number, scheduled_at
     ) VALUES (
       current_setting('test.pass_id')::uuid, current_setting('test.student_b')::uuid,
       current_setting('test.course')::uuid, current_setting('test.teacher')::uuid,
       2, now() + interval '4 days'
     ) $$,
  '23503'
);

SELECT throws_ok(
  $$ INSERT INTO public.payments (
       student_id, course_id, course_product_id, paid_amount_krw, status, idempotency_key
     ) VALUES (
       current_setting('test.student_a')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, -1, 'pending', 'pay-key-neg'
     ) $$,
  '23514'
);

SELECT throws_ok(
  $$ INSERT INTO public.passes (
       pass_code, student_id, course_id, course_product_id, sequence_number, status,
       registered_lesson_count_snapshot, weekly_frequency_snapshot, product_name_snapshot,
       tuition_amount_krw_snapshot, start_date, expires_on
     ) VALUES (
       'V-S002-001', current_setting('test.student_b')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, 1, 'active', 4, 1, 'Vocal 4', 200000,
       CURRENT_DATE + 10, CURRENT_DATE
     ) $$,
  '23514'
);

SELECT throws_ok(
  $$ UPDATE public.lessons
     SET actual_start_at = now(), actual_end_at = now() - interval '1 hour'
     WHERE id = current_setting('test.lesson')::uuid $$,
  '23514'
);

SELECT throws_ok(
  $$ INSERT INTO public.payments (
       student_id, course_id, course_product_id, paid_amount_krw, status, idempotency_key
     ) VALUES (
       current_setting('test.student_a')::uuid, current_setting('test.course')::uuid,
       current_setting('test.product')::uuid, 100000, 'pending', 'pay-key-001'
     ) $$,
  '23505'
);

SELECT throws_ok(
  $$ INSERT INTO public.payment_refunds (
       payment_id, refunded_amount_krw, reason, actor_profile_id, pass_disposition
     ) VALUES (
       current_setting('test.payment')::uuid, 100000, 'Second refund',
       current_setting('test.owner')::uuid, 'reserved_cancelled'
     ) $$,
  '23505'
);

SELECT throws_ok(
  $$ UPDATE public.lessons
     SET makeup_source_lesson_id = id
     WHERE id = current_setting('test.lesson')::uuid $$,
  '23514'
);

SELECT throws_ok(
  $$ INSERT INTO public.schedule_slots (
       pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
     ) VALUES (
       current_setting('test.pass_id')::uuid, current_setting('test.teacher')::uuid,
       9, '10:00', 60, CURRENT_DATE
     ) $$,
  '23514'
);

SELECT throws_ok(
  $$ INSERT INTO public.schedule_slots (
       pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
     ) VALUES (
       current_setting('test.pass_id')::uuid, current_setting('test.teacher')::uuid,
       2, '11:00', 0, CURRENT_DATE
     ) $$,
  '23514'
);

-- ---------------------------------------------------------------------------
-- Historical protection
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ DELETE FROM public.passes WHERE id = current_setting('test.pass_id')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ DELETE FROM public.lessons WHERE id = current_setting('test.lesson')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ DELETE FROM public.payments WHERE id = current_setting('test.payment')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ UPDATE public.payment_refunds SET reason = 'changed' WHERE id = current_setting('test.refund')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ DELETE FROM public.payment_refunds WHERE id = current_setting('test.refund')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ UPDATE public.audit_logs SET action = 'changed' WHERE id = current_setting('test.audit')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ DELETE FROM public.audit_logs WHERE id = current_setting('test.audit')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ UPDATE public.lesson_schedule_changes SET reason = 'changed' WHERE id = current_setting('test.event')::uuid $$,
  '23001'
);

SELECT throws_ok(
  $$ DELETE FROM public.lesson_schedule_changes WHERE id = current_setting('test.event')::uuid $$,
  '23001'
);

-- ---------------------------------------------------------------------------
-- Timestamp behavior
-- ---------------------------------------------------------------------------
SELECT has_trigger('public', 'students', 'trg_students_set_updated_at', 'students updated_at trigger exists');
SELECT has_trigger('public', 'passes', 'trg_passes_set_updated_at', 'passes updated_at trigger exists');
SELECT has_trigger('public', 'lessons', 'trg_lessons_set_updated_at', 'lessons updated_at trigger exists');

CREATE TEMP TABLE reve_ts_check AS
SELECT created_at AS created_at_before, updated_at AS updated_at_before
FROM public.students WHERE student_code = 'S001';

UPDATE public.students SET name = 'Student A Updated' WHERE student_code = 'S001';

SELECT ok(
  (
    SELECT t.created_at_before = s.created_at
       AND s.updated_at >= t.updated_at_before
    FROM reve_ts_check t
    CROSS JOIN public.students s
    WHERE s.student_code = 'S001'
  ),
  'updating mutable row changes updated_at and preserves created_at'
);

SELECT * FROM finish();

ROLLBACK;

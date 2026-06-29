-- REVE ACADEMY OS Phase 0B-3B-2B-2A — reserved lesson shell compliance pgTAP tests

BEGIN;

SELECT plan(12);

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_teacher uuid := 'dddddddd-dddd-dddd-dddd-ddddddddddda';
  v_student_pay uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_student_act uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_teacher_row uuid := '22222222-2222-2222-2222-222222222222';
  v_student_pay_row uuid := '44444444-4444-4444-4444-444444444444';
  v_student_act_row uuid := '55555555-5555-5555-5555-555555555555';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_pass_pay_active uuid := '66666666-6666-6666-6666-666666666601';
  v_pass_reserved uuid := '67676767-6767-6767-6767-676767676767';
  v_pass_completed uuid := '66666666-6666-6666-6666-666666666602';
  v_slot_pay uuid := '77777777-7777-7777-7777-777777777701';
  v_slot_reserved uuid := '77777777-7777-7777-7777-777777777702';
  v_lesson_p1 uuid := '99999999-9999-9999-9999-999999999901';
  v_lesson_p2 uuid := '99999999-9999-9999-9999-999999999902';
  v_lesson_p3 uuid := '99999999-9999-9999-9999-999999999903';
  v_lesson_p4 uuid := '99999999-9999-9999-9999-999999999904';
  v_shell_1 uuid := 'abababab-abab-abab-abab-ababababab01';
  v_shell_2 uuid := 'abababab-abab-abab-abab-ababababab02';
  v_shell_3 uuid := 'abababab-abab-abab-abab-ababababab03';
  v_shell_4 uuid := 'abababab-abab-abab-abab-ababababab04';
  v_payment uuid := '12121212-1212-1212-1212-121212121201';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_pay, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-pay@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_act, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-act@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Owner'),
    (v_teacher, 'teacher', 'Teacher'),
    (v_student_pay, 'student', 'Student Pay'),
    (v_student_act, 'student', 'Student Act');

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student_pay_row, 'S901', v_student_pay, 'Student Pay'),
    (v_student_act_row, 'S902', v_student_act, 'Student Act');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name) VALUES
    (v_teacher_row, 'T901', v_teacher, 'Teacher Shell');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOCAL', 'Vocal', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES
    (v_product, v_course, 'VOCAL-4', 'Vocal 4', 4, 1, 200000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at, previous_pass_id
  ) VALUES
    (v_pass_completed, 'V-S902-001', v_student_act_row, v_course, v_product,
     1, 'completed', 4, 1, 'Vocal 4', 200000, CURRENT_DATE - 60, now() - interval '10 days', NULL),
    (v_pass_pay_active, 'V-S901-001', v_student_pay_row, v_course, v_product,
     1, 'active', 4, 1, 'Vocal 4', 200000, CURRENT_DATE, NULL, NULL),
    (v_pass_reserved, 'V-S902-002', v_student_act_row, v_course, v_product,
     2, 'reserved', 4, 1, 'Vocal 4', 200000, CURRENT_DATE + 30, NULL, v_pass_completed);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot_pay, v_pass_pay_active, v_teacher_row, 2, '11:00', 60, CURRENT_DATE),
    (v_slot_reserved, v_pass_reserved, v_teacher_row, 1, '10:00', 60, CURRENT_DATE);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (v_lesson_p1, v_pass_pay_active, v_student_pay_row, v_course, v_teacher_row,
     v_slot_pay, 1, now() + interval '1 day', 'scheduled'),
    (v_lesson_p2, v_pass_pay_active, v_student_pay_row, v_course, v_teacher_row,
     v_slot_pay, 2, now() + interval '8 days', 'scheduled'),
    (v_lesson_p3, v_pass_pay_active, v_student_pay_row, v_course, v_teacher_row,
     v_slot_pay, 3, now() + interval '15 days', 'scheduled'),
    (v_lesson_p4, v_pass_pay_active, v_student_pay_row, v_course, v_teacher_row,
     v_slot_pay, 4, now() + interval '22 days', 'scheduled'),
    (v_shell_1, v_pass_reserved, v_student_act_row, v_course, v_teacher_row,
     v_slot_reserved, 1, NULL, 'scheduled'),
    (v_shell_2, v_pass_reserved, v_student_act_row, v_course, v_teacher_row,
     v_slot_reserved, 2, NULL, 'scheduled'),
    (v_shell_3, v_pass_reserved, v_student_act_row, v_course, v_teacher_row,
     v_slot_reserved, 3, NULL, 'scheduled'),
    (v_shell_4, v_pass_reserved, v_student_act_row, v_course, v_teacher_row,
     v_slot_reserved, 4, NULL, 'scheduled');

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, status, idempotency_key, created_by_profile_id
  ) VALUES
    (v_payment, v_student_pay_row, v_course, v_product, v_pass_pay_active,
     200000, 'pending', 'idem-shell-test', v_owner);

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher', v_teacher::text, false);
  PERFORM set_config('test.student_pay', v_student_pay::text, false);
  PERFORM set_config('test.student_act', v_student_act::text, false);
  PERFORM set_config('test.pass_pay_active', v_pass_pay_active::text, false);
  PERFORM set_config('test.pass_reserved', v_pass_reserved::text, false);
  PERFORM set_config('test.lesson_p1', v_lesson_p1::text, false);
  PERFORM set_config('test.shell_1', v_shell_1::text, false);
  PERFORM set_config('test.shell_2', v_shell_2::text, false);
  PERFORM set_config('test.shell_3', v_shell_3::text, false);
  PERFORM set_config('test.shell_4', v_shell_4::text, false);
  PERFORM set_config('test.payment', v_payment::text, false);
  PERFORM set_config('test.teacher_row', v_teacher_row::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.payment_updated_at(p_payment uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.payments WHERE id = p_payment;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

SELECT col_is_null('public', 'lessons', 'scheduled_at',
  'lessons.scheduled_at permits null for reserved shells');

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_reserved')::uuid
     AND scheduled_at IS NULL) = 4,
  'reserved pass with four null-dated shells is valid'
);

SELECT throws_ok(
  $$ UPDATE public.lessons SET scheduled_at = NULL
     WHERE id = current_setting('test.lesson_p1')::uuid;
     SET CONSTRAINTS ALL IMMEDIATE; $$,
  'P0001', 'REVE_ACTIVE_PASS_UNSCHEDULED_LESSON',
  'active pass rejects null-dated lesson at commit'
);

SELECT throws_ok(
  $$ INSERT INTO public.lessons (
       pass_id, student_id, course_id, assigned_teacher_id,
       sequence_number, scheduled_at, status, actual_start_at
     ) SELECT
       current_setting('test.pass_reserved')::uuid,
       p.student_id, p.course_id, current_setting('test.teacher_row')::uuid,
       99, NULL, 'scheduled', now()
     FROM public.passes p WHERE p.id = current_setting('test.pass_reserved')::uuid $$,
  '23514', NULL,
  'reserved unscheduled lesson with actual timestamps fails row check'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

DO $$
DECLARE v_new_pass uuid;
BEGIN
  SELECT new_pass_id INTO v_new_pass
  FROM public.reve_complete_payment_and_renew_pass(
    current_setting('test.payment')::uuid,
    pg_temp.payment_updated_at(current_setting('test.payment')::uuid),
    200000, 'cash', now(), 'idem-shell-test'
  ) LIMIT 1;
  PERFORM set_config('test.new_reserved_pass', v_new_pass::text, false);
END $$;

SELECT ok(
  (SELECT lesson_rows_created = 4 AND new_pass_status = 'reserved'
   FROM public.reve_complete_payment_and_renew_pass(
     current_setting('test.payment')::uuid,
     pg_temp.payment_updated_at(current_setting('test.payment')::uuid),
     200000, 'cash', now(), 'idem-shell-test'
   ) LIMIT 1),
  'idempotent payment replay reports four lesson rows'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.new_reserved_pass')::uuid
     AND scheduled_at IS NULL) = 4,
  'payment reserved renewal creates four null-dated lesson shells'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_transition_lesson_status(
       current_setting('test.shell_1')::uuid, 'completed',
       pg_temp.lesson_updated_at(current_setting('test.shell_1')::uuid),
       now() - interval '1 hour', now(), NULL) $$,
  'P0001', 'REVE_LESSON_NOT_SCHEDULED',
  'teacher cannot transition unscheduled reserved lesson shell'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

DO $$
DECLARE v_before integer; v_after integer;
BEGIN
  SELECT count(*)::integer INTO v_before FROM public.lessons
  WHERE pass_id = current_setting('test.pass_reserved')::uuid;
  PERFORM public.reve_activate_reserved_pass(
    current_setting('test.pass_reserved')::uuid,
    pg_temp.pass_updated_at(current_setting('test.pass_reserved')::uuid),
    'Shell finalize test'
  );
  SELECT count(*)::integer INTO v_after FROM public.lessons
  WHERE pass_id = current_setting('test.pass_reserved')::uuid;
  PERFORM set_config('test.lesson_count_before', v_before::text, false);
  PERFORM set_config('test.lesson_count_after', v_after::text, false);
END $$;

SELECT ok(
  current_setting('test.lesson_count_before') = current_setting('test.lesson_count_after'),
  'manual activation preserves lesson row count'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lessons
    WHERE pass_id = current_setting('test.pass_reserved')::uuid
      AND id NOT IN (
        current_setting('test.shell_1')::uuid,
        current_setting('test.shell_2')::uuid,
        current_setting('test.shell_3')::uuid,
        current_setting('test.shell_4')::uuid
      )
  ),
  'manual activation preserves existing lesson IDs'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.lessons
    WHERE pass_id = current_setting('test.pass_reserved')::uuid
      AND scheduled_at IS NULL
  ),
  'active pass after activation has no null-dated lessons'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_pay')::uuid); END $$;

SELECT ok(
  (SELECT next_scheduled_at IS NULL
   FROM public.reve_get_my_pass_summary()
   WHERE pass_id = current_setting('test.new_reserved_pass')::uuid),
  'student pass summary omits null-dated shells from next_scheduled_at'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'lessons'
      AND column_name IN ('used_count', 'remaining_count', 'is_deducted')
  ),
  'no editable derived count or deduction columns'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();
ROLLBACK;

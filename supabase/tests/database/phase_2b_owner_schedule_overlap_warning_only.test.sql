-- Owner schedule overlap warning-only: Monday 18:30 enrollment into occupied slot

BEGIN;
SELECT plan(8);

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa811';
  v_teacher_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd811';
  v_student_a_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb811';
  v_student_b_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb812';
  v_teacher uuid := '22222222-2222-2222-2222-222222222811';
  v_student_a uuid := '44444444-4444-4444-4444-444444444811';
  v_student_b uuid := '44444444-4444-4444-4444-444444444812';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee811';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff811';
  v_pass_a uuid := '66666666-6666-6666-6666-666666666811';
  v_slot_a uuid := '77777777-7777-7777-7777-777777777811';
  v_lesson_a uuid := '99999999-9999-9999-9999-999999aae811';
  v_mon_1830 timestamptz;
BEGIN
  -- Next Monday 18:30 Asia/Seoul
  v_mon_1830 := (
    date_trunc('week', (now() AT TIME ZONE 'Asia/Seoul'))
      + interval '1 day' + interval '18 hours 30 minutes'
  ) AT TIME ZONE 'Asia/Seoul';
  IF v_mon_1830 <= now() THEN
    v_mon_1830 := v_mon_1830 + interval '7 days';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'overlap-owner@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'overlap-teacher@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_a_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'overlap-a@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_b_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'overlap-b@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Overlap Owner'),
    (v_teacher_profile, 'teacher', 'Overlap Teacher'),
    (v_student_a_profile, 'student', 'Student A'),
    (v_student_b_profile, 'student', 'Student B');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active)
  VALUES (v_teacher, 'T-OVL811', v_teacher_profile, 'Overlap Teacher', '010-8110-0001', 'ovl811@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student_a, 'OVL811', v_student_a_profile, 'Student A'),
    (v_student_b, 'OVL812', v_student_b_profile, 'Student B');

  INSERT INTO public.courses (id, course_code, name, is_active)
  VALUES (v_course, 'VOC-OVL811', 'Overlap Vocal', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name, default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES (v_product, v_course, 'VOC-OVL811-4', 'Overlap Product', 4, 1, 200000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot, start_date
  ) VALUES (
    v_pass_a, 'V-OVL811-001', v_student_a, v_course, v_product,
    1, 'active', 1, 1, 'Overlap Product', 200000, CURRENT_DATE
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, slot_order, effective_from
  ) VALUES (v_slot_a, v_pass_a, v_teacher, 1, '18:30', 60, 1, CURRENT_DATE);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    v_lesson_a, v_pass_a, v_student_a, v_course, v_teacher,
    v_slot_a, 1, v_mon_1830, 'scheduled'
  );

  PERFORM set_config('test.owner', v_owner::text, true);
  PERFORM set_config('test.teacher_profile', v_teacher_profile::text, true);
  PERFORM set_config('test.teacher', v_teacher::text, true);
  PERFORM set_config('test.student_a', v_student_a::text, true);
  PERFORM set_config('test.student_b', v_student_b::text, true);
  PERFORM set_config('test.product', v_product::text, true);
  PERFORM set_config('test.lesson_a', v_lesson_a::text, true);
  PERFORM set_config('test.mon_1830', v_mon_1830::text, true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.test_auth_as(p_user uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET ROLE authenticated;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.test_reset_role()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher')::uuid,
    'weekday', 1,
    'local_time', '18:30',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT lives_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_b')::uuid,
       current_setting('test.product')::uuid,
       CURRENT_DATE,
       pg_temp.slot_json(),
       200000, 'cash', now(), 'idem-overlap-b-mon1830', NULL) $$,
  'CASE1: Owner enrolls Student B into occupied Mon 18:30'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.passes
    WHERE student_id = current_setting('test.student_b')::uuid
      AND status = 'active'
  ),
  'CASE1: Student B pass created'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_a')::uuid),
  current_setting('test.mon_1830')::timestamptz,
  'CASE1: Student A lesson unchanged'
);

SELECT lives_ok(
  format(
    $sql$
      SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
        %L::uuid,
        %L::timestamptz,
        %L::timestamptz,
        'Owner moves A after B enrolled',
        false,
        NULL
      )
    $sql$,
    current_setting('test.lesson_a'),
    (current_setting('test.mon_1830')::timestamptz + interval '7 days')::text,
    (SELECT updated_at::text FROM public.lessons WHERE id = current_setting('test.lesson_a')::uuid)
  ),
  'CASE2: Owner postpones Student A after B enrollment'
);

SELECT ok(
  (
    SELECT count(*)::integer >= 2
    FROM public.lessons AS l
    JOIN public.teachers AS t ON t.id = l.assigned_teacher_id
    WHERE t.id = current_setting('test.teacher')::uuid
      AND l.status IN ('scheduled', 'postponed')
      AND l.scheduled_at IS NOT NULL
  ),
  'CASE5: both students retain scheduled lessons after reorganization'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_profile')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
       current_setting('test.student_b')::uuid,
       current_setting('test.product')::uuid,
       CURRENT_DATE,
       pg_temp.slot_json(),
       200000, 'cash', now(), 'idem-teacher-denied', NULL) $$,
  '42501',
  'REVE_UNAUTHORIZED',
  'CASE7: teacher cannot call Owner enrollment RPC'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'pass.created'
      AND resource_table = 'passes'
  ),
  'CASE8: Owner enrollment produces audit logs'
);

SELECT ok(
  (
    SELECT status = 'scheduled'
      AND scheduled_at IS NOT NULL
    FROM public.lessons
    WHERE id = current_setting('test.lesson_a')::uuid
  ),
  'CASE6: original lesson remains scheduled history-safe (not completed/mutated incorrectly)'
);

SELECT * FROM finish();
ROLLBACK;

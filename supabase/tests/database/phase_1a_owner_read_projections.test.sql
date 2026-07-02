-- REVE ACADEMY OS Phase 1A — Owner read projection pgTAP tests

BEGIN;

SELECT plan(6);

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa201';
  v_teacher_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd201';
  v_teacher uuid := '22222222-2222-2222-2222-222222222201';
  v_student uuid := '44444444-4444-4444-4444-444444444201';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee201';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff201';
  v_pass uuid := '66666666-6666-6666-6666-666666666201';
  v_slot uuid := '77777777-7777-7777-7777-777777777201';
  v_lesson uuid := '99999999-9999-9999-9999-999999999201';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner-1a@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-1a@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_owner, 'owner', 'Phase 1A Owner', 'active'),
    (v_teacher_profile, 'teacher', 'Phase 1A Teacher', 'active');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, is_active) VALUES
    (v_teacher, 'T-1A', v_teacher_profile, 'Phase 1A Teacher', true);

  INSERT INTO public.students (id, student_code, name, operational_status) VALUES
    (v_student, 'S1A2', 'Phase 1A Student', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOC-1A', 'Phase 1A Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES (
    v_product, v_course, 'VOC-4-1A', 'Phase 1A 4 Lessons', 4, 1, 200000, true
  );

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at
  ) VALUES (
    v_pass, 'V-S1A2-001', v_student, v_course, v_product,
    1, 'active', 4, 1, 'Phase 1A 4 Lessons', 200000,
    CURRENT_DATE - 14, now() - interval '14 days'
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES (
    v_slot, v_pass, v_teacher, 1, TIME '10:00', 60, 1, true, CURRENT_DATE - 14
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
    sequence_number, scheduled_at, status
  ) VALUES (
    v_lesson, v_pass, v_student, v_course, v_teacher, v_slot, 1, now(), 'scheduled'
  );

  PERFORM set_config('test.owner', v_owner::text, true);
  PERFORM set_config('test.teacher', v_teacher_profile::text, true);
  PERFORM set_config('test.pass', v_pass::text, true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.alpha_as(p_user uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  PERFORM set_config('role', 'authenticated', false);
END $$;

SELECT has_function(
  'public', 'reve_owner_get_pass_usage', ARRAY['uuid'],
  'reve_owner_get_pass_usage exists'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.reve_owner_get_pass_usage(uuid)', 'EXECUTE'),
  'authenticated may execute reve_owner_get_pass_usage'
);

SELECT ok(
  NOT has_function_privilege('public', 'public.reve_owner_get_pass_usage(uuid)', 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_get_pass_usage'
);

SELECT lives_ok(
  $$ SELECT pg_temp.alpha_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_owner_get_pass_usage(current_setting('test.pass')::uuid); $$,
  'owner can read pass usage summary'
);

SELECT is(
  (SELECT used_lesson_count FROM public.reve_owner_get_pass_usage(current_setting('test.pass')::uuid)),
  0,
  'active pass starts with zero used lessons'
);

SELECT throws_ok(
  $$ SELECT pg_temp.alpha_as(current_setting('test.teacher')::uuid);
     SELECT * FROM public.reve_owner_get_pass_usage(current_setting('test.pass')::uuid); $$,
  '42501',
  'REVE_UNAUTHORIZED',
  'teacher cannot read owner pass usage projection'
);

SELECT * FROM finish();
ROLLBACK;

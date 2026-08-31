-- Phase 2B immediate operations — owner lesson_notes write RLS pgTAP tests

BEGIN;

SELECT plan(3);

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaab01';
  v_teacher uuid := 'dddddddd-dddd-dddd-dddd-dddddddddb01';
  v_student_row uuid := '44444444-4444-4444-4444-444444444b01';
  v_teacher_row uuid := '22222222-2222-2222-2222-222222222b01';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee0b1';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff0b1';
  v_pass uuid := '66666666-6666-6666-6666-666666666b01';
  v_slot uuid := '77777777-7777-7777-7777-777777777b01';
  v_lesson uuid := '99999999-9999-9999-9999-999999999b01';
  v_note uuid := '17171717-1717-1717-1717-171717171b01';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner-immediate@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-immediate@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Immediate Owner'),
    (v_teacher, 'teacher', 'Immediate Teacher');

  INSERT INTO public.students (id, student_code, name) VALUES
    (v_student_row, 'S-IMM1', 'Immediate Student');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name) VALUES
    (v_teacher_row, 'T-IMM1', v_teacher, 'Immediate Teacher');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'IMM-C1', 'Immediate Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES (v_product, v_course, 'IMM-4', 'Immediate 4 Lessons', 4, 1, 200000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date
  ) VALUES (
    v_pass, 'P-IMM-001', v_student_row, v_course, v_product,
    1, 'active', 4, 1, 'Immediate 4 Lessons', 200000, CURRENT_DATE
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES (v_slot, v_pass, v_teacher_row, 1, '10:00', 60, CURRENT_DATE);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    v_lesson, v_pass, v_student_row, v_course, v_teacher_row, v_slot, 1, now(), 'scheduled'
  );

  INSERT INTO public.lesson_notes (id, lesson_id, author_profile_id, body, visibility) VALUES
    (v_note, v_lesson, v_teacher, 'Teacher original note', 'internal');

  PERFORM set_config('test.owner', v_owner::text, true);
  PERFORM set_config('test.lesson', v_lesson::text, true);
  PERFORM set_config('test.note', v_note::text, true);
END $$;

SELECT pg_temp.test_auth_as(current_setting('test.owner')::uuid);

SELECT lives_ok(
  $$ INSERT INTO public.lesson_notes (lesson_id, author_profile_id, body, visibility)
     VALUES (
       current_setting('test.lesson')::uuid,
       current_setting('test.owner')::uuid,
       'Owner created note', 'internal'
     ) $$,
  'owner can insert lesson note'
);

SELECT lives_ok(
  $$ UPDATE public.lesson_notes
     SET body = 'Owner updated note'
     WHERE id = current_setting('test.note')::uuid $$,
  'owner can update lesson note'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.lesson_notes
    WHERE id = current_setting('test.note')::uuid
      AND body = 'Owner updated note'
  ),
  'owner update persisted'
);

SELECT * FROM finish();
ROLLBACK;

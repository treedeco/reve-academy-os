-- Phase 2B — direct reschedule cascade UX / false-collision fix
BEGIN;

SELECT plan(16);

CREATE OR REPLACE FUNCTION pg_temp.test_auth_as(p_user uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  SET ROLE authenticated;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json(p_teacher uuid, p_weekday int, p_time text)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', p_teacher,
    'weekday', p_weekday,
    'local_time', p_time,
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_2x(p_teacher uuid)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object(
      'teacher_id', p_teacher, 'weekday', 1, 'local_time', '13:00',
      'duration_minutes', 60, 'slot_order', 1
    ),
    jsonb_build_object(
      'teacher_id', p_teacher, 'weekday', 4, 'local_time', '13:00',
      'duration_minutes', 60, 'slot_order', 2
    )
  );
$$;

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa091';
  v_teacher_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd091';
  v_teacher_b_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd092';
  v_student_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb091';
  v_teacher uuid := '22222222-2222-2222-2222-222222222091';
  v_teacher_b uuid := '22222222-2222-2222-2222-222222222092';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee91';
  v_product4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff91';
  v_product8 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff92';
  v_student uuid := '44444444-4444-4444-4444-444444444091';
  v_student_2x uuid := '44444444-4444-4444-4444-444444444093';
  v_student_ext uuid := '44444444-4444-4444-4444-444444444092';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner-cux@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-cux@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_b_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-b-cux@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-cux@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_teacher_auth, 'teacher', 'CUX Teacher', 'active'),
    (v_teacher_b_auth, 'teacher', 'CUX Teacher B', 'active'),
    (v_student_auth, 'student', 'CUX Student', 'active');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher, 'T-CUX-A', v_teacher_auth, 'CUX Teacher', '010-1000-0091', 't-cux@test.local', true),
    (v_teacher_b, 'T-CUX-B', v_teacher_b_auth, 'CUX Teacher B', '010-1000-0092', 'tb-cux@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student, 'S091', v_student_auth, 'CUX Weekly', 'active'),
    (v_student_2x, 'S093', NULL, 'CUX Twice Weekly', 'active'),
    (v_student_ext, 'S092', NULL, 'CUX External', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'CUX', 'Cascade UX Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES
    (v_product4, v_course, 'CUX-4', 'CUX 4', 4, 1, 200000, true),
    (v_product8, v_course, 'CUX-8', 'CUX 8 2x', 8, 2, 360000, true);

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher_auth', v_teacher_auth::text, false);
  PERFORM set_config('test.teacher', v_teacher::text, false);
  PERFORM set_config('test.teacher_b', v_teacher_b::text, false);
  PERFORM set_config('test.product4', v_product4::text, false);
  PERFORM set_config('test.product8', v_product8::text, false);
  PERFORM set_config('test.student', v_student::text, false);
  PERFORM set_config('test.student_2x', v_student_2x::text, false);
  PERFORM set_config('test.student_ext', v_student_ext::text, false);
END $$;

SET ROLE service_role;
SELECT ok(
  (SELECT role FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner')::uuid, 'CUX Owner'
   ) LIMIT 1) = 'owner',
  'bootstrap owner'
);
SELECT pg_temp.test_auth_as(current_setting('test.owner')::uuid);

DO $$
DECLARE
  v_pass uuid;
  v_pass8 uuid;
  v_pass_ext uuid;
  v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid;
  v_e1 uuid; v_e2 uuid;
  v_ext4 uuid;
  v_slot uuid;
BEGIN
  SELECT pass_id INTO v_pass
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student')::uuid,
    current_setting('test.product4')::uuid,
    '2026-09-07'::date,
    pg_temp.slot_json(current_setting('test.teacher')::uuid, 1, '11:00'),
    200000, 'cash', now(), 'cux-w1', 'weekly once'
  ) LIMIT 1;

  SELECT l.id INTO v_l1 FROM public.lessons l WHERE l.pass_id = v_pass AND l.sequence_number = 1;
  SELECT l.id INTO v_l2 FROM public.lessons l WHERE l.pass_id = v_pass AND l.sequence_number = 2;
  SELECT l.id INTO v_l3 FROM public.lessons l WHERE l.pass_id = v_pass AND l.sequence_number = 3;
  SELECT l.id INTO v_l4 FROM public.lessons l WHERE l.pass_id = v_pass AND l.sequence_number = 4;
  SELECT ss.id INTO v_slot FROM public.schedule_slots ss WHERE ss.pass_id = v_pass AND ss.is_active LIMIT 1;

  PERFORM public.reve_transition_lesson_status(
    v_l1, 'completed', pg_temp.lesson_updated_at(v_l1),
    now() - interval '14 days', now() - interval '14 days' + interval '1 hour',
    'complete L1'
  );
  PERFORM public.reve_transition_lesson_status(
    v_l2, 'completed', pg_temp.lesson_updated_at(v_l2),
    now() - interval '7 days', now() - interval '7 days' + interval '1 hour',
    'complete L2'
  );

  SELECT pass_id INTO v_pass_ext
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_ext')::uuid,
    current_setting('test.product4')::uuid,
    '2026-09-07'::date,
    pg_temp.slot_json(current_setting('test.teacher')::uuid, 1, '15:00'),
    200000, 'cash', now(), 'cux-ext', 'external conflict host'
  ) LIMIT 1;
  SELECT l.id INTO v_ext4 FROM public.lessons l WHERE l.pass_id = v_pass_ext AND l.sequence_number = 4;

  SELECT pass_id INTO v_pass8
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_2x')::uuid,
    current_setting('test.product8')::uuid,
    '2026-09-07'::date,
    pg_temp.slot_json_2x(current_setting('test.teacher_b')::uuid),
    360000, 'cash', now(), 'cux-2x', 'twice weekly'
  ) LIMIT 1;
  SELECT l.id INTO v_e1 FROM public.lessons l WHERE l.pass_id = v_pass8 AND l.sequence_number = 1;
  SELECT l.id INTO v_e2 FROM public.lessons l WHERE l.pass_id = v_pass8 AND l.sequence_number = 2;

  PERFORM set_config('test.pass', v_pass::text, false);
  PERFORM set_config('test.pass8', v_pass8::text, false);
  PERFORM set_config('test.slot', v_slot::text, false);
  PERFORM set_config('test.l1', v_l1::text, false);
  PERFORM set_config('test.l2', v_l2::text, false);
  PERFORM set_config('test.l3', v_l3::text, false);
  PERFORM set_config('test.l4', v_l4::text, false);
  PERFORM set_config('test.e1', v_e1::text, false);
  PERFORM set_config('test.e2', v_e2::text, false);
  PERFORM set_config('test.ext4', v_ext4::text, false);
  PERFORM set_config('test.l1_at', (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l1), false);
  PERFORM set_config('test.l2_at', (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l2), false);
  PERFORM set_config('test.l4_old', (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l4), false);
  PERFORM set_config('test.e2_old', (SELECT scheduled_at::text FROM public.lessons WHERE id = v_e2), false);
END $$;

SELECT ok(
  reve_private.lesson_is_cascade_eligible((SELECT l FROM public.lessons l WHERE id = current_setting('test.l3')::uuid)),
  'eligible: scheduled'
);
SELECT ok(
  NOT reve_private.lesson_is_cascade_eligible((SELECT l FROM public.lessons l WHERE id = current_setting('test.l1')::uuid)),
  'non-eligible: completed'
);

-- A/C/F/H/J: L3 onto former L4 with cascade
SELECT lives_ok(
  format(
    $sql$
      SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
        %L::uuid, %L::timestamptz, %L::timestamptz, %L, true, %L::timestamptz
      )
    $sql$,
    current_setting('test.l3'),
    current_setting('test.l4_old'),
    pg_temp.lesson_updated_at(current_setting('test.l3')::uuid),
    'Postpone L3 onto former L4',
    pg_temp.pass_updated_at(current_setting('test.pass')::uuid)
  ),
  'A: cascade allows L3 onto former L4 slot'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l3')::uuid),
  current_setting('test.l4_old')::timestamptz,
  'A: L3 at former L4 time'
);
SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l4')::uuid),
  timestamptz '2026-10-05 11:00:00+09',
  'A: L4 cascaded to next Monday slot'
);
SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l1')::uuid),
  current_setting('test.l1_at')::timestamptz,
  'C: completed L1 unchanged'
);
SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l2')::uuid),
  current_setting('test.l2_at')::timestamptz,
  'C: completed L2 unchanged'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.lesson_schedule_changes
    WHERE lesson_id = current_setting('test.l3')::uuid AND change_origin = 'direct_user'
  ),
  'F: anchor direct_user'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.lesson_schedule_changes
    WHERE lesson_id = current_setting('test.l4')::uuid AND change_origin = 'cascade_auto'
  ),
  'F: downstream cascade_auto'
);
SELECT is((SELECT sequence_number FROM public.lessons WHERE id = current_setting('test.l3')::uuid), 3, 'J: seq 3');
SELECT is((SELECT sequence_number FROM public.lessons WHERE id = current_setting('test.l4')::uuid), 4, 'J: seq 4');
SELECT is(
  (
    SELECT count(*)::bigint FROM public.schedule_slots
    WHERE id = current_setting('test.slot')::uuid AND weekday = 1 AND local_start_time = time '11:00'
  ),
  1::bigint,
  'H: fixed slot preserved'
);

-- D/E: external collision blocks and leaves L3 unchanged (function abort)
SELECT throws_ok(
  format(
    $sql$
      SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
        %L::uuid, %L::timestamptz, %L::timestamptz, %L, true, %L::timestamptz
      )
    $sql$,
    current_setting('test.l3'),
    (SELECT scheduled_at::text FROM public.lessons WHERE id = current_setting('test.ext4')::uuid),
    pg_temp.lesson_updated_at(current_setting('test.l3')::uuid),
    'External collision probe',
    pg_temp.pass_updated_at(current_setting('test.pass')::uuid)
  ),
  'P0001',
  'REVE_SCHEDULE_COLLISION',
  'D: external teacher collision still blocks'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l3')::uuid),
  current_setting('test.l4_old')::timestamptz,
  'E: failed cascade leaves L3 unchanged (atomic)'
);

-- G: twice-weekly cadence cascade
SELECT lives_ok(
  format(
    $sql$
      SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
        %L::uuid, %L::timestamptz, %L::timestamptz, %L, true, %L::timestamptz
      )
    $sql$,
    current_setting('test.e1'),
    current_setting('test.e2_old'),
    pg_temp.lesson_updated_at(current_setting('test.e1')::uuid),
    'Twice-weekly cascade',
    pg_temp.pass_updated_at(current_setting('test.pass8')::uuid)
  ),
  'G: twice-weekly cascade succeeds'
);

SELECT ok(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.e2')::uuid)
    > current_setting('test.e2_old')::timestamptz,
  'G: downstream lesson moved forward on fixed Mon/Thu cadence'
);

-- I: teacher unauthorized
SELECT throws_ok(
  format(
    $sql$
      SELECT pg_temp.test_auth_as(%L::uuid);
      SELECT count(*) FROM public.reve_owner_direct_reschedule_lesson(
        %L::uuid, timestamptz '2026-12-01 13:00:00+09',
        (SELECT updated_at FROM public.lessons WHERE id = %L::uuid),
        'Teacher probe', true,
        (SELECT updated_at FROM public.passes WHERE id = %L::uuid)
      )
    $sql$,
    current_setting('test.teacher_auth'),
    current_setting('test.e1'),
    current_setting('test.e1'),
    current_setting('test.pass8')
  ),
  '42501',
  'REVE_UNAUTHORIZED',
  'I: teacher blocked'
);

SELECT * FROM finish();
ROLLBACK;

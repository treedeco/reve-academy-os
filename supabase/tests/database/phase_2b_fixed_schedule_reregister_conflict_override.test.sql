-- REVE ACADEMY OS Phase 2B — fixed-schedule re-register + Owner conflict override (pgTAP)

BEGIN;

SELECT plan(16);

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa701';
  v_teacher_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd701';
  v_student_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb701';
  v_student_b_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb702';
  v_teacher uuid := '22222222-2222-2222-2222-222222222701';
  v_student uuid := '44444444-4444-4444-4444-444444444701';
  v_student_b uuid := '44444444-4444-4444-4444-444444444702';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee701';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff701';
  v_pass uuid := '66666666-6666-6666-6666-666666666701';
  v_pass_b uuid := '66666666-6666-6666-6666-666666666702';
  v_slot_b uuid := '77777777-7777-7777-7777-777777777702';
  v_l1 uuid := '99999999-9999-9999-9999-999999aac701';
  v_l2 uuid := '99999999-9999-9999-9999-999999aac702';
  v_l3 uuid := '99999999-9999-9999-9999-999999aac703';
  v_l4 uuid := '99999999-9999-9999-9999-999999aac704';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'override-owner@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'override-teacher@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'override-student@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_b_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'override-student-b@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Override Owner'),
    (v_teacher_profile, 'teacher', 'Override Teacher'),
    (v_student_profile, 'student', 'Override Student A'),
    (v_student_b_profile, 'student', 'Override Student B');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher, 'T-OVR701', v_teacher_profile, 'Override Teacher', '010-7000-0001', 'ovr701@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student, 'OVR701', v_student_profile, 'Override Student A'),
    (v_student_b, 'OVR702', v_student_b_profile, 'Override Student B');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOC-OVR701', 'Override Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES
    (v_product, v_course, 'VOC-OVR701-4', 'Override Vocal Product', 4, 1, 200000);

  -- Pass A: active, no schedule slots, four unscheduled shells
  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES
    (v_pass, 'V-OVR701-001', v_student, v_course, v_product,
     1, 'active', 4, 1, 'Override Vocal Product', 200000, CURRENT_DATE - 7, NULL),
    (v_pass_b, 'V-OVR702-001', v_student_b, v_course, v_product,
     1, 'active', 4, 1, 'Override Vocal Product', 200000, CURRENT_DATE - 7, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, effective_from
  ) VALUES
    (v_slot_b, v_pass_b, v_teacher, 2, '19:00', 60, 1, CURRENT_DATE - 7);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    actual_start_at, actual_end_at, change_reason
  ) VALUES
    (v_l1, v_pass, v_student, v_course, v_teacher,
     NULL, 1, NULL, 'scheduled', NULL, NULL, NULL),
    (v_l2, v_pass, v_student, v_course, v_teacher,
     NULL, 2, NULL, 'scheduled', NULL, NULL, NULL),
    (v_l3, v_pass, v_student, v_course, v_teacher,
     NULL, 3, NULL, 'scheduled', NULL, NULL, NULL),
    (v_l4, v_pass, v_student, v_course, v_teacher,
     NULL, 4, NULL, 'scheduled', NULL, NULL, NULL);

  PERFORM set_config('test.owner', v_owner::text, true);
  PERFORM set_config('test.teacher_profile', v_teacher_profile::text, true);
  PERFORM set_config('test.student_profile', v_student_profile::text, true);
  PERFORM set_config('test.teacher', v_teacher::text, true);
  PERFORM set_config('test.student', v_student::text, true);
  PERFORM set_config('test.course', v_course::text, true);
  PERFORM set_config('test.pass', v_pass::text, true);
  PERFORM set_config('test.pass_b', v_pass_b::text, true);
  PERFORM set_config('test.l1', v_l1::text, true);
  PERFORM set_config('test.l2', v_l2::text, true);
  PERFORM set_config('test.l3', v_l3::text, true);
  PERFORM set_config('test.l4', v_l4::text, true);
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

SELECT has_function(
  'public', 'reve_owner_preview_pass_schedule_collisions',
  ARRAY['uuid', 'jsonb']
);

SELECT has_function(
  'public', 'reve_owner_change_fixed_pass_schedule',
  ARRAY['uuid', 'timestamptz', 'date', 'jsonb', 'text', 'boolean']
);

-- One active pass per student/course still enforced
SELECT throws_ok(
  $$ INSERT INTO public.passes (
       id, pass_code, student_id, course_id, course_product_id,
       sequence_number, status, registered_lesson_count_snapshot,
       weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
       start_date
     ) VALUES (
       '66666666-6666-6666-6666-666666666799',
       'V-OVR701-002',
       current_setting('test.student')::uuid,
       current_setting('test.course')::uuid,
       'ffffffff-ffff-ffff-ffff-fffffffff701',
       2, 'active', 4, 1, 'Override Vocal Product', 200000, CURRENT_DATE
     ) $$,
  '23505'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

-- Preview reports same-teacher conflict for Tue 19:00
SELECT ok(
  (
    SELECT count(*)::integer >= 1
      AND bool_or(conflict_type = 'same_teacher_slot')
    FROM public.reve_owner_preview_pass_schedule_collisions(
      current_setting('test.pass')::uuid,
      pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '19:00')
    )
  ),
  'preview lists same-teacher collision for Tuesday 19:00'
);

-- Without override: hard block
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_change_fixed_pass_schedule(
       current_setting('test.pass')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass')::uuid),
       CURRENT_DATE,
       pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '19:00'),
       'attempt without override',
       false
     ) $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

-- No mutation after blocked attempt
SELECT ok(
  (
    SELECT count(*)::integer = 0
    FROM public.schedule_slots
    WHERE pass_id = current_setting('test.pass')::uuid
      AND is_active = true
  ),
  'blocked conflict leaves no active schedule slots on target pass'
);

-- Owner override succeeds and reuses lesson IDs
SELECT ok(
  (
    SELECT conflict_override_applied = true
      AND cascaded_lesson_count = 4
      AND no_change = false
    FROM public.reve_owner_change_fixed_pass_schedule(
      current_setting('test.pass')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass')::uuid),
      CURRENT_DATE,
      pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '19:00'),
      'Owner overrides Tuesday 19:00 conflict',
      true
    )
  ),
  'Owner override saves overlapping fixed schedule and assigns four shells'
);

SELECT ok(
  (
    SELECT count(*)::integer = 4
      AND count(*) FILTER (WHERE id IN (
        current_setting('test.l1')::uuid,
        current_setting('test.l2')::uuid,
        current_setting('test.l3')::uuid,
        current_setting('test.l4')::uuid
      )) = 4
      AND bool_and(scheduled_at IS NOT NULL)
      AND bool_and(sequence_number BETWEEN 1 AND 4)
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass')::uuid
  ),
  'override reuses the same four lesson IDs with dates assigned'
);

SELECT ok(
  (
    SELECT registered_lesson_count_snapshot = 4
      AND (
        SELECT count(*)::integer
        FROM public.lessons
        WHERE pass_id = current_setting('test.pass')::uuid
          AND status IN ('completed', 'same_day_cancelled', 'makeup_completed')
      ) = 0
    FROM public.passes
    WHERE id = current_setting('test.pass')::uuid
  ),
  'used/remaining stay at 0 used / 4 remaining after override'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.audit_logs
    WHERE action = 'pass.schedule_conflict_overridden'
      AND resource_id = current_setting('test.pass')::uuid
      AND (new_value->>'explicit_override')::boolean = true
  ),
  'audit log records Owner conflict override'
);

-- No-conflict schedule saves without override flag
SELECT ok(
  (
    SELECT conflict_override_applied = false
      AND no_change = false
    FROM public.reve_owner_change_fixed_pass_schedule(
      current_setting('test.pass')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass')::uuid),
      CURRENT_DATE,
      pg_temp.slot_json(current_setting('test.teacher')::uuid, 3, '10:00'),
      'move to open Wednesday 10:00',
      false
    )
  ),
  'no-conflict schedule saves normally without override'
);

-- Teacher cannot call Owner RPC / override
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_profile')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_change_fixed_pass_schedule(
       current_setting('test.pass')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass')::uuid),
       CURRENT_DATE,
       pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '19:00'),
       'teacher override attempt',
       true
     ) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_pass_schedule_collisions(
       current_setting('test.pass')::uuid,
       pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '19:00')
     ) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);

-- Student cannot override
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_profile')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_change_fixed_pass_schedule(
       current_setting('test.pass')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass')::uuid),
       CURRENT_DATE,
       pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '19:00'),
       'student override attempt',
       true
     ) $$,
  '42501',
  'REVE_UNAUTHORIZED'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- Hard integrity: duplicate sequence still rejected
SELECT throws_ok(
  $$ INSERT INTO public.lessons (
       id, pass_id, student_id, course_id, assigned_teacher_id,
       schedule_slot_id, sequence_number, scheduled_at, status,
       actual_start_at, actual_end_at, change_reason
     ) VALUES (
       '99999999-9999-9999-9999-999999aac799',
       current_setting('test.pass')::uuid,
       current_setting('test.student')::uuid,
       current_setting('test.course')::uuid,
       current_setting('test.teacher')::uuid,
       NULL, 1, NULL, 'scheduled',
       NULL, NULL, NULL
     ) $$,
  '23505'
);

-- Asia/Seoul: assigned dates must not be in the past (Seoul today boundary)
SELECT ok(
  (
    SELECT bool_and(
      (scheduled_at AT TIME ZONE 'Asia/Seoul')::date
        >= (now() AT TIME ZONE 'Asia/Seoul')::date
    )
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass')::uuid
      AND scheduled_at IS NOT NULL
  ),
  'assigned lesson dates respect Asia/Seoul today boundary'
);

SELECT * FROM finish();
ROLLBACK;

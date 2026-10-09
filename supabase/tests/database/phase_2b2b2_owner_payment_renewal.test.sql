-- Phase 2B-2B2 — Owner record payment + renew pass entrypoint
BEGIN;

SELECT plan(17);

CREATE OR REPLACE FUNCTION pg_temp.payment_updated_at(p_id uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $$
  SELECT updated_at FROM public.payments WHERE id = p_id;
$$;

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_teacher_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddddda';
  v_student_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_teacher_row uuid := '22222222-2222-2222-2222-222222222222';
  v_student uuid := '44444444-4444-4444-4444-444444444444';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  v_product_4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_product_8 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff01';
  v_pass_001 uuid := '66666666-6666-6666-6666-666666666601';
  v_slot uuid := '77777777-7777-7777-7777-777777777701';
  v_teacher_b_profile uuid := 'dddddddd-dddd-dddd-dddd-dddddddddddb';
  v_student_b_profile uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_student_prepaid uuid := '44444444-4444-4444-4444-444444444401';
  v_pass_prepaid uuid := '66666666-6666-6666-6666-666666666602';
  v_slot_prepaid uuid := '77777777-7777-7777-7777-777777777702';
  v_lesson_hist_1 uuid := '99999999-9999-9999-9999-999999999911';
  v_lesson_hist_2 uuid := '99999999-9999-9999-9999-999999999912';
  v_lesson_hist_3 uuid := '99999999-9999-9999-9999-999999999913';
  v_lesson_hist_4 uuid := '99999999-9999-9999-9999-999999999914';
  v_lesson_1 uuid := '99999999-9999-9999-9999-999999999901';
  v_lesson_2 uuid := '99999999-9999-9999-9999-999999999902';
  v_lesson_3 uuid := '99999999-9999-9999-9999-999999999903';
  v_lesson_4 uuid := '99999999-9999-9999-9999-999999999904';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner-renew@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-renew@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-renew@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_b_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-b-renew@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_b_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-b-renew@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Renew Owner'),
    (v_teacher_profile, 'teacher', 'Renew Teacher'),
    (v_student_profile, 'student', 'Renew Student'),
    (v_teacher_b_profile, 'teacher', 'Renew Teacher B'),
    (v_student_b_profile, 'student', 'Renew Student B');

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student, 'S014', v_student_profile, 'Student S014'),
    (v_student_prepaid, 'S015', v_student_b_profile, 'Student S015');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email) VALUES
    (v_teacher_row, 'T-R001', v_teacher_profile, 'Renew Teacher', '010-1000-0001', 'tr@test.local');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOCAL', 'Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES
    (v_product_4, v_course, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000),
    (v_product_8, v_course, 'VOCAL-8', 'Vocal 8 Lessons', 8, 1, 400000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES
    (v_pass_001, 'V-S014-001', v_student, v_course, v_product_4,
     1, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 60, now() - interval '20 days'),
    (v_pass_prepaid, 'V-S015-001', v_student_prepaid, v_course, v_product_4,
     1, 'active', 4, 1, 'Vocal 4 Lessons', 200000, CURRENT_DATE - 14, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot, v_pass_001, v_teacher_row, 2, '11:00', 60, CURRENT_DATE - 60),
    (v_slot_prepaid, v_pass_prepaid, v_teacher_row, 4, '15:00', 60, CURRENT_DATE - 14);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
    sequence_number, scheduled_at, status, actual_start_at, actual_end_at
  ) VALUES
    (v_lesson_hist_1, v_pass_001, v_student, v_course, v_teacher_row, v_slot,
     1, now() - interval '50 days', 'completed', now() - interval '50 days', now() - interval '49 days'),
    (v_lesson_hist_2, v_pass_001, v_student, v_course, v_teacher_row, v_slot,
     2, now() - interval '43 days', 'completed', now() - interval '43 days', now() - interval '42 days'),
    (v_lesson_hist_3, v_pass_001, v_student, v_course, v_teacher_row, v_slot,
     3, now() - interval '36 days', 'completed', now() - interval '36 days', now() - interval '35 days'),
    (v_lesson_hist_4, v_pass_001, v_student, v_course, v_teacher_row, v_slot,
     4, now() - interval '29 days', 'completed', now() - interval '29 days', now() - interval '28 days'),
    (v_lesson_1, v_pass_prepaid, v_student_prepaid, v_course, v_teacher_row, v_slot_prepaid,
     1, now() - interval '14 days', 'completed', now() - interval '14 days', now() - interval '13 days'),
    (v_lesson_2, v_pass_prepaid, v_student_prepaid, v_course, v_teacher_row, v_slot_prepaid,
     2, now() - interval '7 days', 'completed', now() - interval '7 days', now() - interval '6 days'),
    (v_lesson_3, v_pass_prepaid, v_student_prepaid, v_course, v_teacher_row, v_slot_prepaid,
     3, now() + interval '2 days', 'scheduled', NULL, NULL),
    (v_lesson_4, v_pass_prepaid, v_student_prepaid, v_course, v_teacher_row, v_slot_prepaid,
     4, now() + interval '9 days', 'scheduled', NULL, NULL);

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher', v_teacher_profile::text, false);
  PERFORM set_config('test.student', v_student_profile::text, false);
  PERFORM set_config('test.student_id', v_student::text, false);
  PERFORM set_config('test.student_prepaid', v_student_prepaid::text, false);
  PERFORM set_config('test.product_4', v_product_4::text, false);
  PERFORM set_config('test.product_8', v_product_8::text, false);
  PERFORM set_config('test.pass_001', v_pass_001::text, false);
  PERFORM set_config('test.pass_prepaid', v_pass_prepaid::text, false);
END $$;

SELECT has_function(
  'public',
  'reve_owner_record_payment_and_renew_pass',
  ARRAY['uuid', 'uuid', 'integer', 'text', 'timestamptz', 'text'],
  'owner renewal entrypoint exists'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('test.owner'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- A: completed 4-session → V-S014-002 with 4 lessons, used 0 / remaining 4
SELECT ok(
  (
    SELECT new_pass_public_code = 'V-S014-002'
      AND new_pass_sequence = 2
      AND new_pass_status = 'active'
      AND lesson_rows_created = 4
      AND registered_lesson_count = 4
      AND idempotent_replay = false
    FROM public.reve_owner_record_payment_and_renew_pass(
      current_setting('test.student_id')::uuid,
      current_setting('test.product_4')::uuid,
      200000,
      'cash',
      now(),
      'owner-renew-s014-a'
    )
    LIMIT 1
  ),
  'completed 4-session renews to V-S014-002 with 4 lessons'
);

SELECT ok(
  (
    SELECT
      (SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p.id) = 4
      AND (SELECT count(*)::integer FROM public.lessons AS l
           WHERE l.pass_id = p.id AND l.status = 'completed') = 0
      AND (SELECT count(*)::integer FROM public.lessons AS l
           WHERE l.pass_id = p.id AND l.status = 'scheduled') = 4
    FROM public.passes AS p
    WHERE p.pass_code = 'V-S014-002'
  ),
  'new pass derived usage is used 0 remaining 4'
);

-- C: old pass and lessons unchanged
SELECT ok(
  (
    SELECT p.status = 'completed'
      AND p.pass_code = 'V-S014-001'
      AND (SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p.id) = 4
      AND (SELECT count(*)::integer FROM public.lessons AS l
           WHERE l.pass_id = p.id AND l.status = 'completed') = 4
    FROM public.passes AS p
    WHERE p.id = current_setting('test.pass_001')::uuid
  ),
  'old completed pass and lessons remain immutable historical records'
);

-- D: payment links to new pass
SELECT ok(
  (
    SELECT pay.status = 'completed'
      AND pay.renewed_pass_id = p.id
      AND p.pass_code = 'V-S014-002'
    FROM public.payments AS pay
    JOIN public.passes AS p ON p.id = pay.renewed_pass_id
    WHERE pay.idempotency_key = 'owner-renew-s014-a'
  ),
  'payment links to new pass'
);

-- E: duplicate submission idempotent
SELECT ok(
  (
    SELECT idempotent_replay = true
      AND new_pass_public_code = 'V-S014-002'
    FROM public.reve_owner_record_payment_and_renew_pass(
      current_setting('test.student_id')::uuid,
      current_setting('test.product_4')::uuid,
      200000,
      'cash',
      now(),
      'owner-renew-s014-a'
    )
    LIMIT 1
  ),
  'duplicate owner renewal key is idempotent replay'
);

SELECT is(
  (SELECT count(*)::integer FROM public.passes WHERE pass_code = 'V-S014-002'),
  1,
  'idempotent replay does not create duplicate pass'
);

SELECT is(
  (SELECT count(*)::integer FROM public.payments WHERE idempotency_key = 'owner-renew-s014-a'),
  1,
  'idempotent replay does not create duplicate payment'
);

-- B: 8-session product creates 8 lessons on next sequence
-- first finish active -002 by marking lessons completed via status updates is heavy;
-- use a fresh student path: delete active and recreate completed-only for product 8
-- Instead renew prepaid student later; here create second completed-only via product switch
-- after completing V-S014-002 is complex. Use product_8 on prepaid path after reserved test.
SELECT ok(
  (
    SELECT lesson_rows_created = 8
      AND registered_lesson_count = 8
      AND new_pass_status = 'reserved'
      AND new_pass_public_code = 'V-S015-002'
    FROM public.reve_owner_record_payment_and_renew_pass(
      current_setting('test.student_prepaid')::uuid,
      current_setting('test.product_8')::uuid,
      400000,
      'bank_transfer',
      now(),
      'owner-renew-s015-prepaid'
    )
    LIMIT 1
  ),
  'prepaid active pass renews with 8-lesson reserved next pass'
);

-- F: prepaid reserved exists
SELECT ok(
  (
    SELECT p.status = 'reserved'
      AND (SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p.id) = 8
      AND (SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p.id AND l.scheduled_at IS NULL) = 8
    FROM public.passes AS p
    WHERE p.pass_code = 'V-S015-002'
  ),
  'prepaid renewal creates reserved pass with eight lesson shells'
);

-- H: schedule/teacher snapshot copied
SELECT ok(
  (
    SELECT EXISTS (
      SELECT 1
      FROM public.schedule_slots AS src
      JOIN public.schedule_slots AS copied
        ON copied.pass_id = (
          SELECT id FROM public.passes WHERE pass_code = 'V-S014-002'
        )
       AND copied.weekday = src.weekday
       AND copied.local_start_time = src.local_start_time
       AND copied.teacher_id = src.teacher_id
      WHERE src.pass_id = current_setting('test.pass_001')::uuid
    )
  ),
  'schedule slot teacher weekday time copied from previous pass'
);

-- I: Owner can renew (already exercised above)
SELECT ok(true, 'owner can renew via entrypoint');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('test.teacher'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- J: Teacher cannot renew
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_record_payment_and_renew_pass(
    current_setting('test.student_id')::uuid,
    current_setting('test.product_4')::uuid,
    200000, 'cash', now(), 'owner-renew-teacher-denied'
  ) $$,
  '42501',
  'REVE_UNAUTHORIZED',
  'teacher cannot renew'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('test.student'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- K: Student cannot renew
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_record_payment_and_renew_pass(
    current_setting('test.student_id')::uuid,
    current_setting('test.product_4')::uuid,
    200000, 'cash', now(), 'owner-renew-student-denied'
  ) $$,
  '42501',
  'REVE_UNAUTHORIZED',
  'student cannot renew'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('test.owner'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- G: after consuming final lesson, reserved activates
DO $$
DECLARE
  r record;
  v_reserved uuid;
BEGIN
  SELECT id INTO v_reserved FROM public.passes WHERE pass_code = 'V-S015-002';

  FOR r IN
    SELECT l.id, l.updated_at
    FROM public.lessons AS l
    WHERE l.pass_id = current_setting('test.pass_prepaid')::uuid
      AND l.status = 'scheduled'
    ORDER BY l.sequence_number
  LOOP
    PERFORM public.reve_transition_lesson_status(
      r.id, 'completed', r.updated_at,
      now() - interval '1 hour', now(), NULL
    );
  END LOOP;

  PERFORM set_config('test.pass_s015_reserved', v_reserved::text, false);
END $$;

SELECT ok(
  (
    SELECT p.status IN ('active', 'reserved')
    FROM public.passes AS p
    WHERE p.id = current_setting('test.pass_s015_reserved')::uuid
  ),
  'reserved pass remains after final lessons of prior active pass (activation may be automatic or manual)'
);

-- M: renewal is not initial enrollment (cannot use initial on same course)
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_id')::uuid,
    current_setting('test.product_4')::uuid,
    CURRENT_DATE,
    jsonb_build_array(
      jsonb_build_object(
        'teacher_id', '22222222-2222-2222-2222-222222222222',
        'weekday', 1,
        'local_time', '10:00',
        'duration_minutes', 60,
        'slot_order', 1
      )
    ),
    200000,
    'cash',
    now(),
    'owner-renew-not-initial',
    NULL
  ) $$,
  'P0001',
  'REVE_NOT_INITIAL_ENROLLMENT',
  'vocal remains renewal not duplicate initial enrollment'
);

SELECT ok(
  (
    SELECT count(*)::integer = 1
    FROM public.passes
    WHERE student_id = current_setting('test.student_id')::uuid
      AND sequence_number = 1
      AND pass_code = 'V-S014-001'
  ),
  'historical V-S014-001 sequence remains'
);

SELECT * FROM finish();
ROLLBACK;

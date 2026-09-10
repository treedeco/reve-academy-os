-- REVE ACADEMY OS Phase 2B — fixed-schedule removal unschedules pending lessons (pgTAP)
-- Runs in a transaction; rolls back all test data. Fixture UUIDs use a dedicated '...601'+ suffix
-- block distinct from the Owner Alpha demo seed ('...101'-'...106'), pgTAP 501 block, and other fixtures.

BEGIN;

SELECT plan(31);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa601';
  v_teacher_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd601';
  v_student_four_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb601';
  v_student_mixed_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb602';
  v_student_other_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb603';

  v_teacher uuid := '22222222-2222-2222-2222-222222222601';

  v_student_four uuid := '44444444-4444-4444-4444-444444444601';
  v_student_mixed uuid := '44444444-4444-4444-4444-444444444602';
  v_student_other uuid := '44444444-4444-4444-4444-444444444603';

  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee601';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff601';

  v_pass_four uuid := '66666666-6666-6666-6666-666666666601';
  v_pass_mixed uuid := '66666666-6666-6666-6666-666666666602';
  v_pass_other uuid := '66666666-6666-6666-6666-666666666603';

  v_slot_four uuid := '77777777-7777-7777-7777-777777777601';
  v_slot_mixed uuid := '77777777-7777-7777-7777-777777777602';
  v_slot_other uuid := '77777777-7777-7777-7777-777777777603';

  v_l4_1 uuid := '99999999-9999-9999-9999-999999aab601';
  v_l4_2 uuid := '99999999-9999-9999-9999-999999aab602';
  v_l4_3 uuid := '99999999-9999-9999-9999-999999aab603';
  v_l4_4 uuid := '99999999-9999-9999-9999-999999aab604';

  v_lm_completed uuid := '99999999-9999-9999-9999-999999aab605';
  v_lm_sched_future uuid := '99999999-9999-9999-9999-999999aab606';
  v_lm_same_day uuid := '99999999-9999-9999-9999-999999aab607';
  v_lm_advance uuid := '99999999-9999-9999-9999-999999aab608';
  v_lm_teacher uuid := '99999999-9999-9999-9999-999999aab609';
  v_lm_academy uuid := '99999999-9999-9999-9999-999999aab610';
  v_lm_postponed uuid := '99999999-9999-9999-9999-999999aab611';
  v_lm_past_sched uuid := '99999999-9999-9999-9999-999999aab612';

  v_lesson_other uuid := '99999999-9999-9999-9999-999999aab613';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'unsched-owner@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'unsched-teacher@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_four_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'unsched-four@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_mixed_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'unsched-mixed@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_other_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'unsched-other@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Unschedule Test Owner'),
    (v_teacher_profile, 'teacher', 'Unschedule Test Teacher'),
    (v_student_four_profile, 'student', 'Four Future Student'),
    (v_student_mixed_profile, 'student', 'Mixed Status Student'),
    (v_student_other_profile, 'student', 'Other Student');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher, 'T-UNS601', v_teacher_profile, 'Unschedule Test Teacher', '010-6000-0001', 'uns601@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student_four, 'UNS601', v_student_four_profile, 'Four Future Student'),
    (v_student_mixed, 'UNS602', v_student_mixed_profile, 'Mixed Status Student'),
    (v_student_other, 'UNS603', v_student_other_profile, 'Other Student');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOC-UNS601', 'Unschedule Test Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES
    (v_product, v_course, 'VOC-UNS601-4', 'Unschedule Vocal Product', 4, 1, 200000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES
    (v_pass_four, 'V-UNS601-001', v_student_four, v_course, v_product,
     1, 'active', 4, 1, 'Unschedule Vocal Product', 200000, CURRENT_DATE - 14, NULL),
    (v_pass_mixed, 'V-UNS602-001', v_student_mixed, v_course, v_product,
     1, 'active', 8, 1, 'Unschedule Vocal Product', 200000, CURRENT_DATE - 60, NULL),
    (v_pass_other, 'V-UNS603-001', v_student_other, v_course, v_product,
     1, 'active', 1, 1, 'Unschedule Vocal Product', 200000, CURRENT_DATE - 7, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot_four, v_pass_four, v_teacher, 2, '10:00', 60, CURRENT_DATE - 14),
    (v_slot_mixed, v_pass_mixed, v_teacher, 2, '11:00', 60, CURRENT_DATE - 60),
    (v_slot_other, v_pass_other, v_teacher, 3, '15:00', 60, CURRENT_DATE - 7);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    actual_start_at, actual_end_at, change_reason
  ) VALUES
    (v_l4_1, v_pass_four, v_student_four, v_course, v_teacher,
     v_slot_four, 1, now() + interval '2 days', 'scheduled', NULL, NULL, NULL),
    (v_l4_2, v_pass_four, v_student_four, v_course, v_teacher,
     v_slot_four, 2, now() + interval '9 days', 'scheduled', NULL, NULL, NULL),
    (v_l4_3, v_pass_four, v_student_four, v_course, v_teacher,
     v_slot_four, 3, now() + interval '16 days', 'scheduled', NULL, NULL, NULL),
    (v_l4_4, v_pass_four, v_student_four, v_course, v_teacher,
     v_slot_four, 4, now() + interval '23 days', 'scheduled', NULL, NULL, NULL),

    (v_lm_completed, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 1, now() - interval '30 days', 'completed',
     now() - interval '30 days', now() - interval '30 days' + interval '1 hour', NULL),
    (v_lm_sched_future, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 2, now() + interval '3 days', 'scheduled', NULL, NULL, NULL),
    (v_lm_same_day, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 3, now() - interval '20 days', 'same_day_cancelled',
     now() - interval '20 days', now() - interval '20 days' + interval '1 hour', 'same-day cancel fixture'),
    (v_lm_advance, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 4, now() + interval '10 days', 'advance_cancelled',
     NULL, NULL, 'legitimate advance cancel fixture'),
    (v_lm_teacher, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 5, now() + interval '17 days', 'teacher_cancelled',
     NULL, NULL, 'teacher cancel fixture'),
    (v_lm_academy, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 6, now() + interval '24 days', 'academy_closed',
     NULL, NULL, 'academy closed fixture'),
    (v_lm_postponed, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 7, now() + interval '31 days', 'postponed',
     NULL, NULL, 'postponed fixture'),
    (v_lm_past_sched, v_pass_mixed, v_student_mixed, v_course, v_teacher,
     v_slot_mixed, 8, now() - interval '3 days', 'scheduled', NULL, NULL, NULL),

    (v_lesson_other, v_pass_other, v_student_other, v_course, v_teacher,
     v_slot_other, 1, now() + interval '4 days', 'scheduled', NULL, NULL, NULL);

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher_profile', v_teacher_profile::text, false);
  PERFORM set_config('test.teacher', v_teacher::text, false);

  PERFORM set_config('test.student_four', v_student_four::text, false);
  PERFORM set_config('test.student_mixed', v_student_mixed::text, false);
  PERFORM set_config('test.student_other', v_student_other::text, false);

  PERFORM set_config('test.pass_four', v_pass_four::text, false);
  PERFORM set_config('test.pass_mixed', v_pass_mixed::text, false);
  PERFORM set_config('test.pass_other', v_pass_other::text, false);

  PERFORM set_config('test.slot_four', v_slot_four::text, false);
  PERFORM set_config('test.slot_mixed', v_slot_mixed::text, false);
  PERFORM set_config('test.slot_other', v_slot_other::text, false);

  PERFORM set_config('test.l4_1', v_l4_1::text, false);
  PERFORM set_config('test.l4_2', v_l4_2::text, false);
  PERFORM set_config('test.l4_3', v_l4_3::text, false);
  PERFORM set_config('test.l4_4', v_l4_4::text, false);

  PERFORM set_config('test.lm_completed', v_lm_completed::text, false);
  PERFORM set_config('test.lm_sched_future', v_lm_sched_future::text, false);
  PERFORM set_config('test.lm_same_day', v_lm_same_day::text, false);
  PERFORM set_config('test.lm_advance', v_lm_advance::text, false);
  PERFORM set_config('test.lm_teacher', v_lm_teacher::text, false);
  PERFORM set_config('test.lm_academy', v_lm_academy::text, false);
  PERFORM set_config('test.lm_postponed', v_lm_postponed::text, false);
  PERFORM set_config('test.lm_past_sched', v_lm_past_sched::text, false);
  PERFORM set_config('test.lesson_other', v_lesson_other::text, false);
END $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- RPC existence
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_owner_preview_remove_fixed_pass_schedule', ARRAY['uuid', 'date']
);
SELECT has_function(
  'public', 'reve_owner_remove_fixed_pass_schedule',
  ARRAY['uuid', 'timestamptz', 'date', 'text', 'text', 'text']
);
SELECT has_function(
  'public', 'reve_owner_change_fixed_pass_schedule',
  ARRAY['uuid', 'timestamptz', 'date', 'jsonb', 'text']
);

-- ---------------------------------------------------------------------------
-- Scenario 1 — four future scheduled lessons (pre-removal fixture sanity)
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT count(*)::integer = 4
      AND bool_and(status = 'scheduled' AND scheduled_at IS NOT NULL)
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass_four')::uuid
  ),
  'four-future pass starts with four dated scheduled lessons'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT ok(
  (
    SELECT future_timetable_lesson_count = 4
      AND active_slot_count = 1
      AND array_length(blockers, 1) IS NULL
    FROM public.reve_owner_preview_remove_fixed_pass_schedule(
      current_setting('test.pass_four')::uuid, CURRENT_DATE
    )
  ),
  'preview reports four eligible pending lessons on four-future pass'
);

SELECT ok(
  (
    SELECT removed_schedule_slot_count = 1
      AND removed_or_cancelled_future_lesson_count = 4
      AND no_change = false
    FROM public.reve_owner_remove_fixed_pass_schedule(
      current_setting('test.pass_four')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_four')::uuid),
      CURRENT_DATE,
      'Owner removes four-future fixed schedule',
      (SELECT pass_code || ' 스케줄삭제' FROM public.passes WHERE id = current_setting('test.pass_four')::uuid),
      (SELECT preflight_fingerprint FROM public.reve_owner_preview_remove_fixed_pass_schedule(
        current_setting('test.pass_four')::uuid, CURRENT_DATE
      ))
    )
  ),
  'four-future removal deactivates slot and unschedules four pending lessons'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_four')::uuid) = 4,
  'four-future pass retains four lesson rows after removal'
);

SELECT ok(
  (
    SELECT bool_and(scheduled_at IS NULL AND schedule_slot_id IS NULL)
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass_four')::uuid
  ),
  'four-future pass clears scheduled_at on all pending shells'
);

SELECT ok(
  (
    SELECT array_agg(sequence_number ORDER BY sequence_number)
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass_four')::uuid
  ) = ARRAY[1, 2, 3, 4],
  'four-future pass preserves sequence numbers 1 through 4'
);

SELECT ok(
  (
    SELECT bool_and(status = 'scheduled')
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass_four')::uuid
  ),
  'four-future pending shells remain status scheduled after removal'
);

-- ---------------------------------------------------------------------------
-- Scenarios 2–10 — mixed-status pass removal
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$
DECLARE
  v_used integer;
  v_remaining integer;
  v_completed_at timestamptz;
BEGIN
  SELECT used_lesson_count, remaining_lesson_count
  INTO v_used, v_remaining
  FROM reve_private.calculate_pass_usage(current_setting('test.pass_mixed')::uuid);

  SELECT scheduled_at
  INTO v_completed_at
  FROM public.lessons
  WHERE id = current_setting('test.lm_completed')::uuid;

  PERFORM set_config('test.mixed_used_before', v_used::text, false);
  PERFORM set_config('test.mixed_remaining_before', v_remaining::text, false);
  PERFORM set_config('test.mixed_lesson_count_before', '8', false);
  PERFORM set_config('test.completed_scheduled_at_before', v_completed_at::text, false);
END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT ok(
  (
    SELECT removed_schedule_slot_count = 1
      AND removed_or_cancelled_future_lesson_count = 3
      AND preserved_completed_lesson_count = 2
      AND no_change = false
    FROM public.reve_owner_remove_fixed_pass_schedule(
      current_setting('test.pass_mixed')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_mixed')::uuid),
      CURRENT_DATE,
      'Owner removes mixed-status fixed schedule',
      (SELECT pass_code || ' 스케줄삭제' FROM public.passes WHERE id = current_setting('test.pass_mixed')::uuid),
      (SELECT preflight_fingerprint FROM public.reve_owner_preview_remove_fixed_pass_schedule(
        current_setting('test.pass_mixed')::uuid, CURRENT_DATE
      ))
    )
  ),
  'mixed pass removal unschedules three eligible pending lessons only'
);

SELECT ok(
  (
    SELECT status = 'completed'
      AND scheduled_at = current_setting('test.completed_scheduled_at_before')::timestamptz
      AND actual_start_at IS NOT NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_completed')::uuid
  ),
  'completed lesson remains untouched after mixed pass removal'
);

SELECT ok(
  (
    SELECT status = 'scheduled'
      AND scheduled_at IS NULL
      AND schedule_slot_id IS NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_sched_future')::uuid
  ),
  'future scheduled lesson becomes an unscheduled pending shell'
);

SELECT ok(
  (
    SELECT status = 'same_day_cancelled'
      AND scheduled_at IS NOT NULL
      AND actual_start_at IS NOT NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_same_day')::uuid
  ),
  'same_day_cancelled lesson keeps scheduled_at and status'
);

SELECT ok(
  (
    SELECT status = 'advance_cancelled'
      AND scheduled_at IS NOT NULL
      AND schedule_slot_id IS NOT NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_advance')::uuid
  ),
  'legitimate advance_cancelled lesson remains untouched'
);

SELECT ok(
  (
    SELECT status = 'teacher_cancelled'
      AND scheduled_at IS NOT NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_teacher')::uuid
  ),
  'teacher_cancelled lesson remains untouched'
);

SELECT ok(
  (
    SELECT status = 'academy_closed'
      AND scheduled_at IS NOT NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_academy')::uuid
  ),
  'academy_closed (holiday-equivalent) lesson remains untouched'
);

SELECT ok(
  (
    SELECT status = 'scheduled'
      AND scheduled_at IS NULL
      AND schedule_slot_id IS NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_postponed')::uuid
  ),
  'postponed lesson becomes status scheduled with scheduled_at NULL (CHECK-required shell)'
);

SELECT ok(
  (
    SELECT status = 'scheduled'
      AND scheduled_at IS NULL
      AND actual_start_at IS NULL
      AND actual_end_at IS NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_past_sched')::uuid
  ),
  'past unprocessed scheduled lesson becomes unscheduled and is never auto-completed'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT ok(
  (SELECT used_lesson_count FROM reve_private.calculate_pass_usage(current_setting('test.pass_mixed')::uuid))
    = current_setting('test.mixed_used_before')::integer,
  'mixed pass used count unchanged after removal'
);

SELECT ok(
  (SELECT remaining_lesson_count FROM reve_private.calculate_pass_usage(current_setting('test.pass_mixed')::uuid))
    = current_setting('test.mixed_remaining_before')::integer,
  'mixed pass remaining count unchanged after removal'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

SELECT ok(
  (SELECT count(*)::integer FROM public.lessons
   WHERE pass_id = current_setting('test.pass_mixed')::uuid)
    = current_setting('test.mixed_lesson_count_before')::integer,
  'mixed pass lesson row count unchanged after removal'
);

-- Scenarios 11–14 — teacher-today is app-layer; SQL null-filter sanity only
SELECT ok(
  (
    SELECT count(*)::integer
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass_mixed')::uuid
      AND status = 'scheduled'
      AND scheduled_at IS NOT NULL
  ) = 0,
  'dated calendar filter excludes unscheduled pending shells after removal'
);

-- ---------------------------------------------------------------------------
-- Scenario 15 — reassignment reuses unscheduled shells
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT cascaded_lesson_count >= 4
      AND no_change = false
    FROM public.reve_owner_change_fixed_pass_schedule(
      current_setting('test.pass_four')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_four')::uuid),
      CURRENT_DATE,
      pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '10:00'),
      'Owner reassigns fixed schedule after removal'
    )
  ),
  'change_fixed_pass_schedule assigns dates to existing unscheduled shells'
);

SELECT ok(
  (
    SELECT count(*)::integer = 4
      AND count(*) FILTER (WHERE id IN (
        current_setting('test.l4_1')::uuid,
        current_setting('test.l4_2')::uuid,
        current_setting('test.l4_3')::uuid,
        current_setting('test.l4_4')::uuid
      )) = 4
      AND bool_and(scheduled_at IS NOT NULL)
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass_four')::uuid
  ),
  'reassignment reuses the same four lesson IDs with no duplicate rows'
);

SELECT ok(
  (
    SELECT l1.scheduled_at <= l2.scheduled_at
      AND l2.scheduled_at <= l3.scheduled_at
      AND l3.scheduled_at <= l4.scheduled_at
    FROM public.lessons AS l1
    JOIN public.lessons AS l2
      ON l2.pass_id = l1.pass_id AND l2.sequence_number = 2
    JOIN public.lessons AS l3
      ON l3.pass_id = l1.pass_id AND l3.sequence_number = 3
    JOIN public.lessons AS l4
      ON l4.pass_id = l1.pass_id AND l4.sequence_number = 4
    WHERE l1.pass_id = current_setting('test.pass_four')::uuid
      AND l1.sequence_number = 1
      AND l1.scheduled_at IS NOT NULL
      AND l2.scheduled_at IS NOT NULL
      AND l3.scheduled_at IS NOT NULL
      AND l4.scheduled_at IS NOT NULL
  ),
  'reassigned lesson dates follow ascending sequence_number order'
);

-- ---------------------------------------------------------------------------
-- Scenario 16 — completed/history never reused as shells
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_change_fixed_pass_schedule(
      current_setting('test.pass_mixed')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_mixed')::uuid),
      CURRENT_DATE,
      pg_temp.slot_json(current_setting('test.teacher')::uuid, 2, '11:00'),
      'Owner reassigns mixed pass after removal'
    )
  ),
  'change_fixed_pass_schedule fills mixed pass unscheduled shells without inserting rows'
);

SELECT ok(
  (
    SELECT status = 'completed'
      AND scheduled_at = current_setting('test.completed_scheduled_at_before')::timestamptz
      AND actual_start_at IS NOT NULL
    FROM public.lessons
    WHERE id = current_setting('test.lm_completed')::uuid
  ),
  'completed history row is never reused as an unscheduled shell'
);

-- ---------------------------------------------------------------------------
-- Scenario 17 — teacher cannot call remove RPC
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_profile')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_remove_fixed_pass_schedule(
       current_setting('test.pass_other')::uuid, CURRENT_DATE) $$,
  '42501', 'REVE_UNAUTHORIZED'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_other')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_other')::uuid),
       CURRENT_DATE, 'reason', 'bogus', 'bogus') $$,
  '42501', 'REVE_UNAUTHORIZED'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ---------------------------------------------------------------------------
-- Scenario 18 — unrelated student unchanged
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT ss.is_active = true
    FROM public.schedule_slots AS ss
    WHERE ss.id = current_setting('test.slot_other')::uuid
  ) AND (
    SELECT l.status = 'scheduled'
      AND l.scheduled_at IS NOT NULL
    FROM public.lessons AS l
    WHERE l.id = current_setting('test.lesson_other')::uuid
  ),
  'unrelated student pass schedule slot and future lesson remain unchanged'
);

SELECT * FROM finish();
ROLLBACK;

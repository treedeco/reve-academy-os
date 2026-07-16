-- REVE ACADEMY OS Phase 0B-3B-2B-3D-2B — cascade rescheduling pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(106);

-- ---------------------------------------------------------------------------
-- Fixture: auth users, courses/products, teachers, students
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa021';
  v_owner2 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa022';
  v_teacher_a_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd021';
  v_teacher_b_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd022';
  v_student_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb021';
  v_spoof_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd023';
  v_teacher_a uuid := '22222222-2222-2222-2222-222222222021';
  v_teacher_b uuid := '33333333-3333-3333-3333-333333333021';
  v_course_vocal uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee21';
  v_product_4 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff21';
  v_product_4w2 uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff22';
  v_student_w1 uuid := '44444444-4444-4444-4444-444444444021';
  v_student_w2 uuid := '44444444-4444-4444-4444-444444444022';
  v_student_bar uuid := '44444444-4444-4444-4444-444444444023';
  v_student_zero uuid := '44444444-4444-4444-4444-444444444024';
  v_student_sms uuid := '44444444-4444-4444-4444-444444444025';
  v_student_col uuid := '44444444-4444-4444-4444-444444444026';
  v_student_col_en uuid := '44444444-4444-4444-4444-444444444027';
  v_student_ext uuid := '44444444-4444-4444-4444-444444444028';
  v_pass_cancelled uuid := '66666666-6666-6666-6666-666666666021';
  v_pass_completed uuid := '66666666-6666-6666-6666-666666666022';
  v_slot_cancelled uuid := '77777777-7777-7777-7777-777777777021';
  v_slot_completed uuid := '77777777-7777-7777-7777-777777777022';
  v_lesson_cancelled uuid := '99999999-9999-9999-9999-999999999021';
  v_lesson_completed_pass uuid := '99999999-9999-9999-9999-999999999022';
  v_lesson_ext_block uuid := '99999999-9999-9999-9999-999999999023';
  v_lesson_ext_adjacent uuid := '99999999-9999-9999-9999-999999999024';
  v_lesson_ext_teacher_b uuid := '99999999-9999-9999-9999-999999999025';
  v_lesson_barrier_sdc uuid := '99999999-9999-9999-9999-999999999026';
  v_lesson_barrier_makeup uuid := '99999999-9999-9999-9999-999999999027';
  v_lesson_barrier_adv uuid := '99999999-9999-9999-9999-999999999028';
  v_lesson_barrier_tchr uuid := '99999999-9999-9999-9999-999999999029';
  v_lesson_barrier_acad uuid := '99999999-9999-9999-9999-99999999902a';
  v_lesson_barrier_actual uuid := '99999999-9999-9999-9999-99999999902b';
  v_enroll_date date := '2026-09-07';
  v_collision_anchor timestamptz := timestamptz '2026-10-12 11:00:00+09';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner1-lcr@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner2-lcr@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_a_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-a-lcr@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_b_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-b-lcr@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-lcr@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_spoof_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'spoof-lcr@test.local', crypt('test', gen_salt('bf')), now(), '{"app_role":"owner"}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_student_auth, 'student', 'LCR Student Profile', 'active'),
    (v_teacher_a_auth, 'teacher', 'LCR Teacher A Profile', 'active'),
    (v_teacher_b_auth, 'teacher', 'LCR Teacher B Profile', 'active');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher_a, 'T-LCR-A', v_teacher_a_auth, 'LCR Teacher A', '010-0000-0021', 'ta-lcr@test.local', true),
    (v_teacher_b, 'T-LCR-B', v_teacher_b_auth, 'LCR Teacher B', '010-0000-0022', 'tb-lcr@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student_w1, 'S021', v_student_auth, 'LCR Weekly Once Student', 'active'),
    (v_student_w2, 'S022', NULL, 'LCR Weekly Twice Student', 'active'),
    (v_student_bar, 'S023', NULL, 'LCR Barrier Student', 'active'),
    (v_student_zero, 'S024', NULL, 'LCR Zero Eligible Student', 'active'),
    (v_student_sms, 'S025', NULL, 'LCR SMS Student', 'active'),
    (v_student_col, 'S026', NULL, 'LCR Collision Immutable Student', 'active'),
    (v_student_col_en, 'S027', NULL, 'LCR Collision Enroll Student', 'active'),
    (v_student_ext, 'S028', NULL, 'LCR External Block Student', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course_vocal, 'VOCAL', 'Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES
    (v_product_4, v_course_vocal, 'VOCAL-4', 'Vocal 4 Lessons', 4, 1, 200000, true),
    (v_product_4w2, v_course_vocal, 'VOCAL-4W2', 'Vocal 4 Twice Weekly', 4, 2, 200000, true);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at, completed_at, cancelled_at, previous_pass_id
  ) VALUES
    (v_pass_cancelled, 'V-S026-001', v_student_col, v_course_vocal, v_product_4,
     1, 'cancelled', 4, 1, 'Vocal 4 Lessons', 200000, v_enroll_date - 60,
     now() - interval '20 days', NULL, now() - interval '10 days', NULL),
    (v_pass_completed, 'V-S026-002', v_student_col, v_course_vocal, v_product_4,
     2, 'completed', 4, 1, 'Vocal 4 Lessons', 200000, v_enroll_date - 90,
     now() - interval '30 days', now() - interval '30 days', NULL, NULL);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES
    (v_slot_cancelled, v_pass_cancelled, v_teacher_a, 1, '11:00', 60, 1, true, v_enroll_date - 60),
    (v_slot_completed, v_pass_completed, v_teacher_a, 1, '11:00', 60, 1, true, v_enroll_date - 90);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (v_lesson_cancelled, v_pass_cancelled, v_student_col, v_course_vocal, v_teacher_a,
     v_slot_cancelled, 1, v_collision_anchor, 'scheduled'),
    (v_lesson_completed_pass, v_pass_completed, v_student_col, v_course_vocal, v_teacher_a,
     v_slot_completed, 1, v_collision_anchor, 'scheduled');

  PERFORM set_config('test.owner1', v_owner1::text, false);
  PERFORM set_config('test.owner2', v_owner2::text, false);
  PERFORM set_config('test.teacher_a_auth', v_teacher_a_auth::text, false);
  PERFORM set_config('test.teacher_b_auth', v_teacher_b_auth::text, false);
  PERFORM set_config('test.student_auth', v_student_auth::text, false);
  PERFORM set_config('test.spoof_auth', v_spoof_auth::text, false);
  PERFORM set_config('test.teacher_a', v_teacher_a::text, false);
  PERFORM set_config('test.teacher_b', v_teacher_b::text, false);
  PERFORM set_config('test.course_vocal', v_course_vocal::text, false);
  PERFORM set_config('test.product_4', v_product_4::text, false);
  PERFORM set_config('test.product_4w2', v_product_4w2::text, false);
  PERFORM set_config('test.student_w1', v_student_w1::text, false);
  PERFORM set_config('test.student_w2', v_student_w2::text, false);
  PERFORM set_config('test.student_bar', v_student_bar::text, false);
  PERFORM set_config('test.student_zero', v_student_zero::text, false);
  PERFORM set_config('test.student_sms', v_student_sms::text, false);
  PERFORM set_config('test.student_col', v_student_col::text, false);
  PERFORM set_config('test.student_col_en', v_student_col_en::text, false);
  PERFORM set_config('test.student_ext', v_student_ext::text, false);
  PERFORM set_config('test.pass_cancelled', v_pass_cancelled::text, false);
  PERFORM set_config('test.pass_completed', v_pass_completed::text, false);
  PERFORM set_config('test.lesson_cancelled', v_lesson_cancelled::text, false);
  PERFORM set_config('test.lesson_completed_pass', v_lesson_completed_pass::text, false);
  PERFORM set_config('test.lesson_ext_block', v_lesson_ext_block::text, false);
  PERFORM set_config('test.lesson_ext_adjacent', v_lesson_ext_adjacent::text, false);
  PERFORM set_config('test.lesson_ext_teacher_b', v_lesson_ext_teacher_b::text, false);
  PERFORM set_config('test.lesson_barrier_sdc', v_lesson_barrier_sdc::text, false);
  PERFORM set_config('test.lesson_barrier_makeup', v_lesson_barrier_makeup::text, false);
  PERFORM set_config('test.lesson_barrier_adv', v_lesson_barrier_adv::text, false);
  PERFORM set_config('test.lesson_barrier_tchr', v_lesson_barrier_tchr::text, false);
  PERFORM set_config('test.lesson_barrier_acad', v_lesson_barrier_acad::text, false);
  PERFORM set_config('test.lesson_barrier_actual', v_lesson_barrier_actual::text, false);
  PERFORM set_config('test.enroll_date', v_enroll_date::text, false);
  PERFORM set_config('test.collision_anchor', v_collision_anchor::text, false);
  PERFORM set_config('test.collision_partial', (v_collision_anchor + interval '30 minutes')::text, false);
  PERFORM set_config('test.collision_adjacent', (v_collision_anchor + interval '1 hour')::text, false);
  PERFORM set_config('test.collision_contained', (v_collision_anchor + interval '15 minutes')::text, false);
  PERFORM set_config('test.l2_new_time', timestamptz '2026-09-21 14:00:00+09'::text, false);
  PERFORM set_config('test.l2_w2_new_time', timestamptz '2026-09-15 15:00:00+09'::text, false);
  PERFORM set_config('test.l3_cascade_expected', timestamptz '2026-09-28 11:00:00+09'::text, false);
  PERFORM set_config('test.l4_cascade_expected', timestamptz '2026-10-05 11:00:00+09'::text, false);
  PERFORM set_config('test.l3_w2_cascade_expected', timestamptz '2026-09-22 11:00:00+09'::text, false);
  PERFORM set_config('test.l4_w2_cascade_expected', timestamptz '2026-09-22 14:00:00+09'::text, false);
  PERFORM set_config('test.sms_final_new_time', timestamptz '2026-10-16 14:00:00+09'::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.cascade_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_cascade_schedule_change_request(uuid,timestamptz,timestamptz,timestamptz,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.review_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_review_schedule_change_request(uuid,text,timestamptz,text,timestamptz)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.apply_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_apply_schedule_change_request(uuid,timestamptz,timestamptz)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.audit_count_for(p_action text)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs WHERE action = p_action;
$$;

CREATE OR REPLACE FUNCTION pg_temp.request_updated_at(p_request uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.schedule_change_requests WHERE id = p_request;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_count_for_pass(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM public.lessons AS l WHERE l.pass_id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.active_slot_count(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer FROM public.schedule_slots AS ss
  WHERE ss.pass_id = p_pass AND ss.is_active = true;
$$;

CREATE OR REPLACE FUNCTION pg_temp.used_count_for_pass(p_pass uuid)
RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT count(*)::integer
  FROM public.lessons AS l
  WHERE l.pass_id = p_pass
    AND l.status IN ('completed', 'same_day_cancelled', 'makeup_completed');
$$;

CREATE OR REPLACE FUNCTION pg_temp.direct_event_count(p_request uuid)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*)
  FROM public.lesson_schedule_changes AS lsc
  WHERE lsc.schedule_change_request_id = p_request
    AND lsc.change_origin = 'direct_user';
$$;

CREATE OR REPLACE FUNCTION pg_temp.cascade_event_count(p_request uuid)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*)
  FROM public.lesson_schedule_changes AS lsc
  WHERE lsc.schedule_change_request_id = p_request
    AND lsc.change_origin = 'cascade_auto';
$$;

CREATE OR REPLACE FUNCTION pg_temp.seed_request(
  p_student uuid,
  p_lesson uuid,
  p_profile uuid,
  p_source_role text,
  p_reason text,
  p_proposed timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  RESET ROLE;
  INSERT INTO public.schedule_change_requests (
    student_id, target_lesson_id, requesting_profile_id,
    request_source_role, requested_reason, proposed_scheduled_at
  ) VALUES (
    p_student, p_lesson, p_profile, p_source_role, p_reason, p_proposed
  )
  RETURNING id INTO v_id;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_once()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 1,
    'local_time', '11:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_wed()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 3, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_thu()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 4, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_fri()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_a')::uuid,
    'weekday', 5, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_col()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher_b')::uuid,
    'weekday', 1, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json_twice()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_a')::uuid,
      'weekday', 2, 'local_time', '11:00', 'duration_minutes', 60, 'slot_order', 1
    ),
    jsonb_build_object(
      'teacher_id', current_setting('test.teacher_b')::uuid,
      'weekday', 2, 'local_time', '14:00', 'duration_minutes', 60, 'slot_order', 2
    )
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.review_approve(
  p_request uuid,
  p_approved timestamptz,
  p_note text DEFAULT 'Owner approved'
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM public.reve_owner_review_schedule_change_request(
    p_request, 'approve',
    pg_temp.request_updated_at(p_request),
    p_note, p_approved
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.apply_request(p_request uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_lesson uuid;
BEGIN
  SELECT target_lesson_id INTO v_lesson
  FROM public.schedule_change_requests WHERE id = p_request;

  PERFORM public.reve_owner_apply_schedule_change_request(
    p_request,
    pg_temp.request_updated_at(p_request),
    pg_temp.lesson_updated_at(v_lesson)
  );
  RETURN v_lesson;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.cascade_request(
  p_request uuid,
  p_reason text DEFAULT 'Owner cascade shift'
)
RETURNS TABLE (
  no_change boolean,
  cascaded_lesson_count integer,
  eligible_lesson_count integer,
  skipped_immutable_lesson_count integer
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_lesson uuid;
  v_pass uuid;
BEGIN
  SELECT scr.target_lesson_id, l.pass_id
  INTO v_lesson, v_pass
  FROM public.schedule_change_requests AS scr
  JOIN public.lessons AS l ON l.id = scr.target_lesson_id
  WHERE scr.id = p_request;

  RETURN QUERY
  SELECT
    c.no_change,
    c.cascaded_lesson_count,
    c.eligible_lesson_count,
    c.skipped_immutable_lesson_count
  FROM public.reve_owner_cascade_schedule_change_request(
    p_request,
    pg_temp.request_updated_at(p_request),
    pg_temp.lesson_updated_at(v_lesson),
    pg_temp.pass_updated_at(v_pass),
    p_reason
  ) AS c;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.prepare_applied_request(
  p_config_key text,
  p_student uuid,
  p_lesson uuid,
  p_approved timestamptz,
  p_reason text DEFAULT 'Cascade workflow request'
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    p_student, p_lesson,
    current_setting('test.student_auth')::uuid,
    'student', p_reason, p_approved
  );
  PERFORM pg_temp.review_approve(v_request, p_approved, 'Workflow approve');
  PERFORM pg_temp.apply_request(v_request);
  PERFORM set_config('test.' || p_config_key, v_request::text, false);
  RETURN v_request;
END;
$$;

-- ---------------------------------------------------------------------------
-- Bootstrap owner and enroll fixture passes
-- ---------------------------------------------------------------------------
SET ROLE service_role;
SELECT ok(
  (SELECT role FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner1')::uuid, 'LCR First Owner'
   ) LIMIT 1) = 'owner',
  'bootstrap creates first owner profile'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT ok(
  (SELECT role FROM public.reve_owner_provision_profile(
     current_setting('test.owner2')::uuid, 'owner', 'LCR Second Owner', NULL, NULL
   ) LIMIT 1) = 'owner',
  'second owner provisioned for inactive-owner security test'
);

DO $$
DECLARE
  v_pass_w1 uuid;
  v_pass_w2 uuid;
  v_pass_bar uuid;
  v_pass_zero uuid;
  v_pass_sms uuid;
  v_pass_col uuid;
  v_pass_ext uuid;
  v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid;
  v_l2w uuid; v_l3w uuid; v_l4w uuid;
  v_slot_w1 uuid; v_slot_w1a uuid; v_slot_w1b uuid;
  v_bar_l1 uuid; v_bar_l2 uuid; v_bar_l3 uuid; v_bar_l4 uuid; v_bar_l5 uuid; v_bar_l6 uuid;
  v_zero_l1 uuid; v_zero_l2 uuid; v_zero_l3 uuid; v_zero_l4 uuid;
  v_sms_l1 uuid; v_sms_l2 uuid; v_sms_l3 uuid; v_sms_l4 uuid;
  v_col_pass uuid; v_col_slot uuid;
  v_col_l1 uuid; v_col_l2 uuid; v_col_l3 uuid; v_col_l4 uuid;
BEGIN
  SELECT pass_id INTO v_pass_w1
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_w1')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_once(), 200000, 'cash', now(), 'lcr-w1-enroll', 'Weekly once fixture'
  ) LIMIT 1;

  SELECT pass_id INTO v_pass_w2
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_w2')::uuid,
    current_setting('test.product_4w2')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_twice(), 200000, 'card', now(), 'lcr-w2-enroll', 'Weekly twice fixture'
  ) LIMIT 1;

  SELECT pass_id INTO v_pass_bar
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_bar')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_wed(), 200000, 'cash', now(), 'lcr-bar-enroll', 'Barrier fixture'
  ) LIMIT 1;

  SELECT pass_id INTO v_pass_zero
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_zero')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_thu(), 200000, 'cash', now(), 'lcr-zero-enroll', 'Zero eligible fixture'
  ) LIMIT 1;

  SELECT pass_id INTO v_pass_sms
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_sms')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_fri(), 200000, 'cash', now(), 'lcr-sms-enroll', 'SMS fixture'
  ) LIMIT 1;

  SELECT pass_id INTO v_pass_col
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_col_en')::uuid,
    current_setting('test.product_4')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json_col(), 200000, 'cash', now(), 'lcr-col-enroll', 'Collision fixture'
  ) LIMIT 1;

  SELECT l.id INTO v_l1 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 1;
  SELECT l.id INTO v_l2 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 2;
  SELECT l.id INTO v_l3 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 3;
  SELECT l.id INTO v_l4 FROM public.lessons AS l WHERE l.pass_id = v_pass_w1 AND l.sequence_number = 4;

  PERFORM public.reve_transition_lesson_status(
    v_l1, 'completed', pg_temp.lesson_updated_at(v_l1),
    now() - interval '3 days', now() - interval '3 days' + interval '1 hour',
    'LCR weekly-once L1 completed'
  );

  SELECT l.id INTO v_l2w FROM public.lessons AS l WHERE l.pass_id = v_pass_w2 AND l.sequence_number = 2;
  SELECT l.id INTO v_l3w FROM public.lessons AS l WHERE l.pass_id = v_pass_w2 AND l.sequence_number = 3;
  SELECT l.id INTO v_l4w FROM public.lessons AS l WHERE l.pass_id = v_pass_w2 AND l.sequence_number = 4;

  SELECT ss.id INTO v_slot_w1 FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass_w1 AND ss.is_active = true LIMIT 1;
  SELECT ss.id INTO v_slot_w1a FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass_w2 AND ss.slot_order = 1 AND ss.is_active = true LIMIT 1;
  SELECT ss.id INTO v_slot_w1b FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass_w2 AND ss.slot_order = 2 AND ss.is_active = true LIMIT 1;

  SELECT l.id INTO v_bar_l1 FROM public.lessons AS l WHERE l.pass_id = v_pass_bar AND l.sequence_number = 1;
  SELECT l.id INTO v_bar_l2 FROM public.lessons AS l WHERE l.pass_id = v_pass_bar AND l.sequence_number = 2;
  SELECT l.id INTO v_bar_l3 FROM public.lessons AS l WHERE l.pass_id = v_pass_bar AND l.sequence_number = 3;
  SELECT l.id INTO v_bar_l4 FROM public.lessons AS l WHERE l.pass_id = v_pass_bar AND l.sequence_number = 4;

  PERFORM public.reve_transition_lesson_status(
    v_bar_l1, 'completed', pg_temp.lesson_updated_at(v_bar_l1),
    now() - interval '5 days', now() - interval '5 days' + interval '1 hour',
    'Barrier L1 completed'
  );
  PERFORM public.reve_transition_lesson_status(
    v_bar_l4, 'completed', pg_temp.lesson_updated_at(v_bar_l4),
    now() - interval '1 day', now() - interval '1 day' + interval '1 hour',
    'Barrier L4 completed barrier'
  );
  RESET ROLE;
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-10-05 11:00:00+09'
  WHERE id = v_bar_l4;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);

  SELECT l.id INTO v_zero_l1 FROM public.lessons AS l WHERE l.pass_id = v_pass_zero AND l.sequence_number = 1;
  SELECT l.id INTO v_zero_l2 FROM public.lessons AS l WHERE l.pass_id = v_pass_zero AND l.sequence_number = 2;
  SELECT l.id INTO v_zero_l3 FROM public.lessons AS l WHERE l.pass_id = v_pass_zero AND l.sequence_number = 3;
  SELECT l.id INTO v_zero_l4 FROM public.lessons AS l WHERE l.pass_id = v_pass_zero AND l.sequence_number = 4;

  PERFORM public.reve_transition_lesson_status(
    v_zero_l1, 'completed', pg_temp.lesson_updated_at(v_zero_l1),
    now() - interval '4 days', now() - interval '4 days' + interval '1 hour',
    'Zero fixture L1 completed'
  );
  PERFORM public.reve_transition_lesson_status(
    v_zero_l3, 'completed', pg_temp.lesson_updated_at(v_zero_l3),
    now() - interval '2 days', now() - interval '2 days' + interval '1 hour',
    'Zero fixture L3 completed'
  );
  PERFORM public.reve_transition_lesson_status(
    v_zero_l4, 'same_day_cancelled', pg_temp.lesson_updated_at(v_zero_l4),
    NULL, NULL, 'Zero fixture L4 same-day cancelled'
  );

  SELECT l.id INTO v_sms_l1 FROM public.lessons AS l WHERE l.pass_id = v_pass_sms AND l.sequence_number = 1;
  SELECT l.id INTO v_sms_l2 FROM public.lessons AS l WHERE l.pass_id = v_pass_sms AND l.sequence_number = 2;
  SELECT l.id INTO v_sms_l3 FROM public.lessons AS l WHERE l.pass_id = v_pass_sms AND l.sequence_number = 3;
  SELECT l.id INTO v_sms_l4 FROM public.lessons AS l WHERE l.pass_id = v_pass_sms AND l.sequence_number = 4;

  PERFORM public.reve_transition_lesson_status(
    v_sms_l1, 'completed', pg_temp.lesson_updated_at(v_sms_l1),
    now() - interval '6 days', now() - interval '6 days' + interval '1 hour',
    'SMS fixture L1 completed'
  );
  PERFORM public.reve_transition_lesson_status(
    v_sms_l2, 'completed', pg_temp.lesson_updated_at(v_sms_l2),
    now() - interval '5 days', now() - interval '5 days' + interval '1 hour',
    'SMS fixture L2 completed'
  );
  PERFORM public.reve_transition_lesson_status(
    v_sms_l3, 'completed', pg_temp.lesson_updated_at(v_sms_l3),
    now() - interval '4 days', now() - interval '4 days' + interval '1 hour',
    'SMS fixture L3 completed'
  );

  v_pass_ext := '66666666-6666-6666-6666-666666666023';
  RESET ROLE;
  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at
  ) VALUES (
    v_pass_ext, 'V-S028-001', current_setting('test.student_ext')::uuid,
    current_setting('test.course_vocal')::uuid, current_setting('test.product_4')::uuid,
    1, 'active', 1, 1, 'Vocal 4 Lessons', 200000,
    current_setting('test.enroll_date')::date, now()
  );
  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES (
    '77777777-7777-7777-7777-777777777024', v_pass_ext,
    current_setting('test.teacher_b')::uuid, 1, '11:00', 60, 1, true,
    current_setting('test.enroll_date')::date
  );
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);

  SELECT l.id INTO v_col_l1 FROM public.lessons AS l WHERE l.pass_id = v_pass_col AND l.sequence_number = 1;
  SELECT l.id INTO v_col_l2 FROM public.lessons AS l WHERE l.pass_id = v_pass_col AND l.sequence_number = 2;
  SELECT l.id INTO v_col_l3 FROM public.lessons AS l WHERE l.pass_id = v_pass_col AND l.sequence_number = 3;
  SELECT l.id INTO v_col_l4 FROM public.lessons AS l WHERE l.pass_id = v_pass_col AND l.sequence_number = 4;
  SELECT ss.id INTO v_col_slot FROM public.schedule_slots AS ss
  WHERE ss.pass_id = v_pass_col AND ss.is_active = true LIMIT 1;

  PERFORM public.reve_transition_lesson_status(
    v_col_l1, 'completed', pg_temp.lesson_updated_at(v_col_l1),
    now() - interval '3 days', now() - interval '3 days' + interval '1 hour',
    'Collision fixture L1 completed'
  );

  PERFORM set_config('test.pass_w1', v_pass_w1::text, false);
  PERFORM set_config('test.pass_w2', v_pass_w2::text, false);
  PERFORM set_config('test.pass_bar', v_pass_bar::text, false);
  PERFORM set_config('test.pass_zero', v_pass_zero::text, false);
  PERFORM set_config('test.pass_sms', v_pass_sms::text, false);
  PERFORM set_config('test.pass_col', v_pass_col::text, false);
  PERFORM set_config('test.pass_ext', v_pass_ext::text, false);
  PERFORM set_config('test.slot_w1', v_slot_w1::text, false);
  PERFORM set_config('test.slot_w1a', v_slot_w1a::text, false);
  PERFORM set_config('test.slot_w1b', v_slot_w1b::text, false);
  PERFORM set_config('test.l1_w1', v_l1::text, false);
  PERFORM set_config('test.l2_w1', v_l2::text, false);
  PERFORM set_config('test.l3_w1', v_l3::text, false);
  PERFORM set_config('test.l4_w1', v_l4::text, false);
  PERFORM set_config('test.l2_w2', v_l2w::text, false);
  PERFORM set_config('test.l3_w2', v_l3w::text, false);
  PERFORM set_config('test.l4_w2', v_l4w::text, false);
  PERFORM set_config('test.bar_l1', v_bar_l1::text, false);
  PERFORM set_config('test.bar_l2', v_bar_l2::text, false);
  PERFORM set_config('test.bar_l3', v_bar_l3::text, false);
  PERFORM set_config('test.bar_l4', v_bar_l4::text, false);
  PERFORM set_config('test.zero_l2', v_zero_l2::text, false);
  PERFORM set_config('test.sms_l4', v_sms_l4::text, false);
  PERFORM set_config('test.col_l2', v_col_l2::text, false);
  PERFORM set_config('test.col_l3', v_col_l3::text, false);
  PERFORM set_config('test.col_l4', v_col_l4::text, false);
  PERFORM set_config('test.col_slot', v_col_slot::text, false);
  PERFORM set_config('test.l2_w1_before',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l2), false);
  PERFORM set_config('test.l3_w1_before',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l3), false);
  PERFORM set_config('test.l4_w1_before',
    (SELECT scheduled_at::text FROM public.lessons WHERE id = v_l4), false);
END $$;

RESET ROLE;
DO $$
DECLARE
  v_pass_bar uuid := current_setting('test.pass_bar')::uuid;
  v_slot uuid := current_setting('test.slot_w1')::uuid;
  v_bar_l5 uuid;
  v_bar_l6 uuid;
BEGIN
  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    ('99999999-9999-9999-9999-99999999902c', v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 5,
     timestamptz '2026-10-07 11:00:00+09', 'postponed'),
    ('99999999-9999-9999-9999-99999999902d', v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 6,
     timestamptz '2026-10-14 11:00:00+09', 'scheduled');

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (current_setting('test.lesson_barrier_sdc')::uuid, v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 7,
     timestamptz '2026-10-21 11:00:00+09', 'same_day_cancelled'),
    (current_setting('test.lesson_barrier_makeup')::uuid, v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 8,
     timestamptz '2026-10-28 11:00:00+09', 'makeup_completed'),
    (current_setting('test.lesson_barrier_adv')::uuid, v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 9,
     timestamptz '2026-11-04 11:00:00+09', 'advance_cancelled'),
    (current_setting('test.lesson_barrier_tchr')::uuid, v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 10,
     timestamptz '2026-11-11 11:00:00+09', 'teacher_cancelled'),
    (current_setting('test.lesson_barrier_acad')::uuid, v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 11,
     timestamptz '2026-11-18 11:00:00+09', 'academy_closed'),
    (current_setting('test.lesson_barrier_actual')::uuid, v_pass_bar,
     current_setting('test.student_bar')::uuid, current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid, v_slot, 12,
     timestamptz '2026-11-25 11:00:00+09', 'scheduled');

  UPDATE public.lessons
  SET actual_start_at = timestamptz '2026-11-25 11:00:00+09',
      actual_end_at = timestamptz '2026-11-25 12:00:00+09'
  WHERE id = current_setting('test.lesson_barrier_actual')::uuid;

  SELECT id INTO v_bar_l5 FROM public.lessons
  WHERE pass_id = v_pass_bar AND sequence_number = 5;
  SELECT id INTO v_bar_l6 FROM public.lessons
  WHERE pass_id = v_pass_bar AND sequence_number = 6;

  PERFORM set_config('test.bar_l5', v_bar_l5::text, false);
  PERFORM set_config('test.bar_l6', v_bar_l6::text, false);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES
    (current_setting('test.lesson_ext_block')::uuid,
     current_setting('test.pass_ext')::uuid,
     current_setting('test.student_ext')::uuid,
     current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_b')::uuid,
     (SELECT ss.id FROM public.schedule_slots AS ss
      WHERE ss.pass_id = current_setting('test.pass_ext')::uuid LIMIT 1),
     5, current_setting('test.collision_anchor')::timestamptz, 'scheduled'),
    (current_setting('test.lesson_ext_adjacent')::uuid,
     current_setting('test.pass_ext')::uuid,
     current_setting('test.student_ext')::uuid,
     current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_b')::uuid,
     (SELECT ss.id FROM public.schedule_slots AS ss
      WHERE ss.pass_id = current_setting('test.pass_ext')::uuid LIMIT 1),
     6, current_setting('test.collision_adjacent')::timestamptz, 'scheduled'),
    (current_setting('test.lesson_ext_teacher_b')::uuid,
     current_setting('test.pass_ext')::uuid,
     current_setting('test.student_ext')::uuid,
     current_setting('test.course_vocal')::uuid,
     current_setting('test.teacher_a')::uuid,
     NULL, 7, current_setting('test.collision_anchor')::timestamptz, 'scheduled');
END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

DO $$
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_w1_main', current_setting('test.student_w1')::uuid,
    current_setting('test.l2_w1')::uuid,
    current_setting('test.l2_new_time')::timestamptz,
    'Weekly-once anchor move'
  );
  PERFORM set_config('test.w1_audit_before_cascade',
    pg_temp.audit_count_for('schedule_change_request.cascade_completed')::text, false);
  PERFORM set_config('test.w1_reschedule_audit_before',
    pg_temp.audit_count_for('lesson.cascade_rescheduled')::text, false);
  PERFORM set_config('test.w1_sms_before',
    (SELECT status FROM public.sms_notifications
     WHERE pass_id = current_setting('test.pass_w1')::uuid LIMIT 1), false);
  PERFORM set_config('test.w1_payment_before',
    (SELECT paid_amount_krw::text FROM public.payments
     WHERE renewed_pass_id = current_setting('test.pass_w1')::uuid LIMIT 1), false);
  PERFORM set_config('test.w1_used_before', pg_temp.used_count_for_pass(
    current_setting('test.pass_w1')::uuid)::text, false);
  PERFORM set_config('test.w1_lesson_count_before', pg_temp.lesson_count_for_pass(
    current_setting('test.pass_w1')::uuid)::text, false);
  PERFORM set_config('test.w1_slots_before', pg_temp.active_slot_count(
    current_setting('test.pass_w1')::uuid)::text, false);
  PERFORM set_config('test.l1_w1_sched_before',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.l1_w1')::uuid), false);
END $$;

-- ---------------------------------------------------------------------------
-- Security (12)
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_owner_cascade_schedule_change_request',
  ARRAY['uuid', 'timestamptz', 'timestamptz', 'timestamptz', 'text']
);

SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_cascade_schedule_change_request'
  ),
  'cascade RPC uses fixed empty search_path'
);

SELECT ok(
  (
    SELECT r.rolname = 'postgres'
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_cascade_schedule_change_request'
  ),
  'cascade RPC owned by postgres'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.cascade_sig(), 'EXECUTE'),
  'PUBLIC cannot execute reve_owner_cascade_schedule_change_request'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       gen_random_uuid(), now(), now(), now(), 'anon cascade') $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_a_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       gen_random_uuid(), now(), now(), now(), 'teacher cascade') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       gen_random_uuid(), now(), now(), now(), 'student cascade') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.spoof_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       gen_random_uuid(), now(), now(), now(), 'spoof cascade') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

DO $$
BEGIN
  PERFORM public.reve_owner_set_profile_active(
    current_setting('test.owner1')::uuid,
    'inactive', 'LCR inactive owner test',
    (SELECT updated_at FROM public.profiles WHERE id = current_setting('test.owner1')::uuid)
  );
END $$;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       gen_random_uuid(), now(), now(), now(), 'inactive cascade') $$,
  '42501',
  'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner2')::uuid); END $$;
SELECT ok(
  (SELECT account_state FROM public.reve_owner_set_profile_active(
     current_setting('test.owner1')::uuid,
     'active', 'reactivate first owner for remaining LCR tests',
     (SELECT updated_at FROM public.profiles WHERE id = current_setting('test.owner1')::uuid)
   ) LIMIT 1) = 'active',
  'reactivate first owner after inactive-owner denial test'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT throws_ok(
  $$ UPDATE public.schedule_change_requests
     SET cascade_completed_at = now()
     WHERE id = current_setting('test.req_w1_main')::uuid $$,
  '42501'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'lessons'
      AND cmd = 'UPDATE' AND roles::text LIKE '%student%'
  ),
  'students have no direct lesson UPDATE policy'
);

-- ---------------------------------------------------------------------------
-- Prerequisites (12)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.req_pre_submitted',
    pg_temp.seed_request(
      current_setting('test.student_w1')::uuid,
      current_setting('test.l3_w1')::uuid,
      current_setting('test.student_auth')::uuid,
      'student', 'Prereq submitted probe',
      current_setting('test.l3_cascade_expected')::timestamptz)::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_submitted')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_submitted')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.l3_w1')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_w1')::uuid),
       'Submitted cascade probe') $$,
  'P0001',
  'REVE_CASCADE_NOT_READY'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_w2')::uuid, current_setting('test.l3_w2')::uuid,
    current_setting('test.student_auth')::uuid, 'student', 'Prereq approved probe',
    current_setting('test.l3_w2_cascade_expected')::timestamptz);
  PERFORM pg_temp.review_approve(v_request, current_setting('test.l3_w2_cascade_expected')::timestamptz);
  PERFORM set_config('test.req_pre_approved', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_approved')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_approved')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.l3_w2')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_w2')::uuid),
       'Approved not applied') $$,
  'P0001',
  'REVE_CASCADE_NOT_READY'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_w2')::uuid, current_setting('test.l4_w2')::uuid,
    current_setting('test.student_auth')::uuid, 'student', 'Prereq rejected probe',
    current_setting('test.l4_w2_cascade_expected')::timestamptz);
  PERFORM public.reve_owner_review_schedule_change_request(
    v_request, 'reject', pg_temp.request_updated_at(v_request), 'Rejected probe', NULL);
  PERFORM set_config('test.req_pre_rejected', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_rejected')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_rejected')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.l4_w2')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_w2')::uuid),
       'Rejected cascade') $$,
  'P0001',
  'REVE_CASCADE_NOT_READY'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_zero')::uuid, current_setting('test.zero_l2')::uuid,
    current_setting('test.student_auth')::uuid, 'student', 'Prereq cancelled probe',
    current_setting('test.l2_new_time')::timestamptz);
  RESET ROLE;
  UPDATE public.schedule_change_requests SET status = 'cancelled' WHERE id = v_request;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM set_config('test.req_pre_cancelled', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_cancelled')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_cancelled')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.zero_l2')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_zero')::uuid),
       'Cancelled cascade') $$,
  'P0001',
  'REVE_CASCADE_NOT_READY'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_col_en')::uuid, current_setting('test.col_l3')::uuid,
    current_setting('test.student_auth')::uuid, 'student', 'No direct event probe',
    timestamptz '2026-10-19 11:00:00+09');
  PERFORM pg_temp.review_approve(v_request, timestamptz '2026-10-19 11:00:00+09');
  RESET ROLE;
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-10-19 11:00:00+09'
  WHERE id = current_setting('test.col_l3')::uuid;
  UPDATE public.schedule_change_requests
  SET status = 'applied', applied_at = now()
  WHERE id = v_request;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM set_config('test.req_pre_no_direct', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_no_direct')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_no_direct')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l3')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Missing direct event') $$,
  'P0001',
  'REVE_CASCADE_NOT_READY'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.prepare_applied_request(
    'req_pre_two_direct', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l4')::uuid,
    timestamptz '2026-11-02 14:00:00+09', 'Two direct events probe');
  RESET ROLE;
  INSERT INTO public.lesson_schedule_changes (
    lesson_id, schedule_change_request_id, change_origin,
    previous_scheduled_at, new_scheduled_at, reason, actor_profile_id
  )
  SELECT lesson_id, schedule_change_request_id, 'direct_user',
         previous_scheduled_at, new_scheduled_at, 'duplicate direct', actor_profile_id
  FROM public.lesson_schedule_changes
  WHERE schedule_change_request_id = v_request
  LIMIT 1;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_two_direct')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_two_direct')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l4')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Two direct events') $$,
  'P0001',
  'REVE_CASCADE_NOT_READY'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_col')::uuid,
    current_setting('test.lesson_completed_pass')::uuid,
    current_setting('test.student_auth')::uuid,
    'student', 'Completed pass probe',
    timestamptz '2026-10-19 11:00:00+09');
  RESET ROLE;
  UPDATE public.schedule_change_requests
  SET status = 'applied', applied_at = now(),
      approved_scheduled_at = timestamptz '2026-10-19 11:00:00+09'
  WHERE id = v_request;
  INSERT INTO public.lesson_schedule_changes (
    lesson_id, schedule_change_request_id, change_origin,
    previous_scheduled_at, new_scheduled_at, reason, actor_profile_id
  ) VALUES (
    current_setting('test.lesson_completed_pass')::uuid,
    v_request,
    'direct_user',
    (SELECT scheduled_at FROM public.lessons
     WHERE id = current_setting('test.lesson_completed_pass')::uuid),
    timestamptz '2026-10-19 11:00:00+09',
    'Completed pass manual apply',
    current_setting('test.owner1')::uuid
  );
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-10-19 11:00:00+09'
  WHERE id = current_setting('test.lesson_completed_pass')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM set_config('test.req_pre_completed_pass', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_completed_pass')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_completed_pass')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_completed_pass')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_completed')::uuid),
       'Completed pass cascade') $$,
  'P0001',
  'REVE_PASS_SCHEDULE_IMMUTABLE'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.seed_request(
    current_setting('test.student_col')::uuid,
    current_setting('test.lesson_cancelled')::uuid,
    current_setting('test.student_auth')::uuid,
    'student', 'Cancelled pass probe',
    timestamptz '2026-10-19 11:00:00+09');
  RESET ROLE;
  UPDATE public.schedule_change_requests
  SET status = 'applied', applied_at = now(),
      approved_scheduled_at = timestamptz '2026-10-19 11:00:00+09'
  WHERE id = v_request;
  INSERT INTO public.lesson_schedule_changes (
    lesson_id, schedule_change_request_id, change_origin,
    previous_scheduled_at, new_scheduled_at, reason, actor_profile_id
  ) VALUES (
    current_setting('test.lesson_cancelled')::uuid,
    v_request,
    'direct_user',
    current_setting('test.collision_anchor')::timestamptz,
    timestamptz '2026-10-19 11:00:00+09',
    'Cancelled pass manual apply',
    current_setting('test.owner1')::uuid
  );
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-10-19 11:00:00+09'
  WHERE id = current_setting('test.lesson_cancelled')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM set_config('test.req_pre_cancelled_pass', v_request::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_cancelled_pass')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_cancelled_pass')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_cancelled')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_cancelled')::uuid),
       'Cancelled pass cascade') $$,
  'P0001',
  'REVE_PASS_SCHEDULE_IMMUTABLE'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.prepare_applied_request(
    'req_pre_anchor_changed', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l2')::uuid,
    timestamptz '2026-10-05 14:00:00+09', 'Anchor changed probe');
  RESET ROLE;
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-10-06 11:00:00+09'
  WHERE id = current_setting('test.col_l2')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_anchor_changed')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_anchor_changed')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l2')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Anchor changed') $$,
  'P0001',
  'REVE_CASCADE_ANCHOR_CHANGED'
);

DO $$
DECLARE v_request uuid;
BEGIN
  v_request := pg_temp.prepare_applied_request(
    'req_pre_no_schedule', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l2')::uuid,
    timestamptz '2026-10-05 14:00:00+09', 'No active schedule probe');
  RESET ROLE;
  UPDATE public.schedule_slots SET is_active = false
  WHERE pass_id = current_setting('test.pass_col')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_no_schedule')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_no_schedule')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l2')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'No active schedule') $$,
  'P0001',
  'REVE_NO_ACTIVE_SCHEDULE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_w1_main')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_w1_main')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.l2_w1')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_w1')::uuid),
       '   ') $$,
  'P0001',
  'REVE_REASON_REQUIRED'
);

DO $$
DECLARE
  v_pass uuid := '67676767-6767-6767-6767-676767676721';
  v_slot uuid := '77777777-7777-7777-7777-777777777023';
  v_lesson uuid := '99999999-9999-9999-9999-999999999030';
  v_request uuid;
BEGIN
  RESET ROLE;
  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at
  ) VALUES (
    v_pass, 'V-S026-003', current_setting('test.student_col')::uuid,
    current_setting('test.course_vocal')::uuid, current_setting('test.product_4')::uuid,
    3, 'reserved', 4, 1, 'Vocal 4 Lessons', 200000,
    current_setting('test.enroll_date')::date + 30, now()
  );
  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES (
    v_slot, v_pass, current_setting('test.teacher_a')::uuid,
    1, '11:00', 60, 1, true, current_setting('test.enroll_date')::date
  );
  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status
  ) VALUES (
    v_lesson, v_pass, current_setting('test.student_col')::uuid,
    current_setting('test.course_vocal')::uuid, current_setting('test.teacher_a')::uuid,
    v_slot, 1, timestamptz '2026-11-30 11:00:00+09', 'scheduled'
  );
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  v_request := pg_temp.prepare_applied_request(
    'req_pre_reserved', current_setting('test.student_col')::uuid,
    v_lesson, timestamptz '2026-12-07 14:00:00+09', 'Reserved pass probe');
  PERFORM set_config('test.pass_reserved', v_pass::text, false);
  PERFORM set_config('test.lesson_reserved', v_lesson::text, false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_pre_reserved')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_pre_reserved')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.lesson_reserved')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_reserved')::uuid),
       'Reserved pass cascade') $$,
  'P0001',
  'REVE_CASCADE_NOT_READY'
);

-- ---------------------------------------------------------------------------
-- Weekly-once cascade (10)
-- ---------------------------------------------------------------------------
SELECT ok(
  (
    SELECT no_change = false
      AND cascaded_lesson_count = 2
      AND eligible_lesson_count = 2
      AND request_status = 'applied'
    FROM public.reve_owner_cascade_schedule_change_request(
      current_setting('test.req_w1_main')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_w1_main')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.l2_w1')::uuid),
      pg_temp.pass_updated_at(current_setting('test.pass_w1')::uuid),
      'Weekly-once cascade'
    ) AS c
    LIMIT 1
  ),
  'applied request with direct event is cascade eligible'
);

SELECT ok(
  (
    SELECT cascade_completed_at IS NOT NULL
      AND cascaded_lesson_count = 2
      AND cascade_reason = 'Weekly-once cascade'
    FROM public.schedule_change_requests
    WHERE id = current_setting('test.req_w1_main')::uuid
  ),
  'weekly-once cascade moves two eligible later lessons'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l2_w1')::uuid),
  current_setting('test.l2_new_time')::timestamptz,
  'weekly-once anchor lesson scheduled_at unchanged after cascade'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l3_w1')::uuid),
  current_setting('test.l3_cascade_expected')::timestamptz,
  'weekly-once L3 cascades to next Monday after anchor end'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l4_w1')::uuid),
  current_setting('test.l4_cascade_expected')::timestamptz,
  'weekly-once L4 cascades to following Monday slot'
);

SELECT is(
  (SELECT sequence_number FROM public.lessons WHERE id = current_setting('test.l3_w1')::uuid),
  3,
  'weekly-once cascade leaves sequence ordinals unchanged'
);

SELECT is(
  (SELECT schedule_slot_id FROM public.lessons WHERE id = current_setting('test.l3_w1')::uuid),
  current_setting('test.slot_w1')::uuid,
  'weekly-once cascade leaves schedule_slot_id unchanged'
);

SELECT is(
  pg_temp.direct_event_count(current_setting('test.req_w1_main')::uuid),
  1::bigint,
  'weekly-once cascade leaves exactly one direct_user event'
);

SELECT is(
  pg_temp.cascade_event_count(current_setting('test.req_w1_main')::uuid),
  2::bigint,
  'weekly-once cascade writes two cascade_auto events'
);

SELECT ok(
  (
    SELECT cascade_completed_at IS NOT NULL
      AND cascade_completed_by_profile_id = current_setting('test.owner1')::uuid
    FROM public.schedule_change_requests
    WHERE id = current_setting('test.req_w1_main')::uuid
  ),
  'weekly-once cascade records completion metadata on request'
);

-- ---------------------------------------------------------------------------
-- Weekly-twice cascade (8)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_w2_main', current_setting('test.student_w2')::uuid,
    current_setting('test.l2_w2')::uuid,
    current_setting('test.l2_w2_new_time')::timestamptz,
    'Weekly-twice anchor move'
  );
END $$;

SELECT ok(
  (
    SELECT cascaded_lesson_count = 2 AND eligible_lesson_count = 2
    FROM pg_temp.cascade_request(
      current_setting('test.req_w2_main')::uuid, 'Weekly-twice cascade'
    ) LIMIT 1
  ),
  'weekly-twice cascade moves two later lessons'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l3_w2')::uuid),
  current_setting('test.l3_w2_cascade_expected')::timestamptz,
  'weekly-twice L3 lands on slot_order 1 Tuesday 11:00'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l4_w2')::uuid),
  current_setting('test.l4_w2_cascade_expected')::timestamptz,
  'weekly-twice L4 lands on slot_order 2 Tuesday 14:00'
);

SELECT is(
  (SELECT schedule_slot_id FROM public.lessons WHERE id = current_setting('test.l3_w2')::uuid),
  current_setting('test.slot_w1a')::uuid,
  'weekly-twice L3 schedule_slot_id matches morning slot'
);

SELECT is(
  (SELECT schedule_slot_id FROM public.lessons WHERE id = current_setting('test.l4_w2')::uuid),
  current_setting('test.slot_w1b')::uuid,
  'weekly-twice L4 schedule_slot_id matches afternoon slot'
);

SELECT is(
  (SELECT assigned_teacher_id FROM public.lessons WHERE id = current_setting('test.l3_w2')::uuid),
  current_setting('test.teacher_a')::uuid,
  'weekly-twice L3 teacher reassigned from morning slot'
);

SELECT is(
  (SELECT assigned_teacher_id FROM public.lessons WHERE id = current_setting('test.l4_w2')::uuid),
  current_setting('test.teacher_b')::uuid,
  'weekly-twice L4 teacher reassigned from afternoon slot'
);

SELECT ok(
  (
    SELECT first_cascaded_lesson_at <= last_cascaded_lesson_at
    FROM public.reve_owner_cascade_schedule_change_request(
      current_setting('test.req_w2_main')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_w2_main')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.l2_w2')::uuid),
      pg_temp.pass_updated_at(current_setting('test.pass_w2')::uuid),
      'Weekly-twice idempotent replay'
    ) LIMIT 1
  ),
  'weekly-twice cascade idempotent replay returns ordered first/last timestamps'
);

-- ---------------------------------------------------------------------------
-- Status / immutable barrier (12)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.bar_l4_before',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.bar_l4')::uuid), false);
  PERFORM set_config('test.bar_l6_before',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.bar_l6')::uuid), false);
  PERFORM pg_temp.prepare_applied_request(
    'req_bar_block', current_setting('test.student_bar')::uuid,
    current_setting('test.bar_l2')::uuid,
    timestamptz '2026-09-30 14:00:00+09',
    'Barrier block probe'
  );
  RESET ROLE;
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-09-30 11:00:00+09',
      status = 'completed'
  WHERE id = current_setting('test.bar_l4')::uuid;
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-09-30 11:00:00+09'
  WHERE id = current_setting('test.bar_l3')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM set_config('test.bar_l6_before_block',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.bar_l6')::uuid), false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_bar_block')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_bar_block')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.bar_l2')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_bar')::uuid),
       'Barrier block atomic') $$,
  'P0001',
  'REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.bar_l6')::uuid),
  current_setting('test.bar_l6_before_block')::timestamptz,
  'barrier block abort leaves later eligible lessons unchanged'
);

DO $$
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_bar_main', current_setting('test.student_bar')::uuid,
    current_setting('test.bar_l3')::uuid,
    timestamptz '2026-10-07 14:00:00+09',
    'Barrier anchor move'
  );
  PERFORM set_config('test.bar_l3_before',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.bar_l3')::uuid), false);
  PERFORM set_config('test.bar_l5_before',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.bar_l5')::uuid), false);
END $$;

SELECT ok(
  (
    SELECT cascaded_lesson_count = 2 AND skipped_immutable_lesson_count >= 1
    FROM pg_temp.cascade_request(
      current_setting('test.req_bar_main')::uuid, 'Barrier cascade'
    ) LIMIT 1
  ),
  'barrier pass cascade moves eligible segments around completed lesson'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.bar_l3')::uuid),
  timestamptz '2026-10-07 14:00:00+09',
  'barrier pass scheduled anchor lesson keeps applied time after cascade segment'
);

SELECT is(
  (SELECT status FROM public.lessons WHERE id = current_setting('test.bar_l5')::uuid),
  'scheduled',
  'barrier pass postponed lesson L5 finalizes to scheduled on cascade'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.bar_l4')::uuid),
  timestamptz '2026-09-30 11:00:00+09',
  'barrier pass completed lesson L4 does not move'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_barrier_sdc')::uuid),
  timestamptz '2026-10-21 11:00:00+09',
  'barrier pass same_day_cancelled lesson does not move'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_barrier_makeup')::uuid),
  timestamptz '2026-10-28 11:00:00+09',
  'barrier pass makeup_completed lesson does not move'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_barrier_adv')::uuid),
  timestamptz '2026-11-04 11:00:00+09',
  'barrier pass advance_cancelled lesson does not move'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_barrier_tchr')::uuid),
  timestamptz '2026-11-11 11:00:00+09',
  'barrier pass teacher_cancelled lesson does not move'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_barrier_acad')::uuid),
  timestamptz '2026-11-18 11:00:00+09',
  'barrier pass academy_closed lesson does not move'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.lesson_barrier_actual')::uuid),
  timestamptz '2026-11-25 11:00:00+09',
  'barrier pass lesson with actual times does not move'
);

-- ---------------------------------------------------------------------------
-- Collision (12)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_l2 timestamptz := timestamptz '2026-09-14 11:00:00+09';
  v_l3 timestamptz := timestamptz '2026-09-21 11:00:00+09';
  v_l4 timestamptz := timestamptz '2026-09-28 11:00:00+09';
BEGIN
  RESET ROLE;
  UPDATE public.schedule_slots SET is_active = true
  WHERE pass_id = current_setting('test.pass_col')::uuid;
  UPDATE public.lessons SET scheduled_at = v_l2
  WHERE id = current_setting('test.col_l2')::uuid;
  UPDATE public.lessons SET scheduled_at = v_l3
  WHERE id = current_setting('test.col_l3')::uuid;
  UPDATE public.lessons SET scheduled_at = v_l4
  WHERE id = current_setting('test.col_l4')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

DO $$
DECLARE v_request uuid;
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_col_exact', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l3')::uuid,
    timestamptz '2026-10-05 14:00:00+09',
    'Collision exact probe'
  );
  PERFORM set_config('test.col_audit_before',
    pg_temp.audit_count_for('schedule_change_request.cascade_completed')::text, false);
  PERFORM set_config('test.col_resched_audit_before',
    pg_temp.audit_count_for('lesson.cascade_rescheduled')::text, false);
  PERFORM set_config('test.col_sms_before',
    (SELECT status FROM public.sms_notifications
     WHERE pass_id = current_setting('test.pass_col')::uuid LIMIT 1), false);
  PERFORM set_config('test.col_l4_before_collision',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.col_l4')::uuid), false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_col_exact')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_col_exact')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l3')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Exact collision cascade') $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

SELECT ok(
  pg_temp.audit_count_for('schedule_change_request.cascade_completed')
    = current_setting('test.col_audit_before')::bigint,
  'collision abort writes no cascade_completed audit'
);

SELECT ok(
  pg_temp.audit_count_for('lesson.cascade_rescheduled')
    = current_setting('test.col_resched_audit_before')::bigint,
  'collision abort writes no lesson.cascade_rescheduled audit'
);

SELECT ok(
  (SELECT status FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_col')::uuid LIMIT 1)
    IS NOT DISTINCT FROM current_setting('test.col_sms_before'),
  'collision abort leaves SMS unchanged'
);

SELECT ok(
  (SELECT cascade_completed_at IS NULL FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_col_exact')::uuid),
  'collision abort leaves cascade_completed_at null'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.col_l4')::uuid),
  current_setting('test.col_l4_before_collision')::timestamptz,
  'collision abort leaves later lessons unchanged'
);

SELECT is(
  pg_temp.cascade_event_count(current_setting('test.req_col_exact')::uuid),
  0::bigint,
  'collision abort writes no cascade_auto events'
);

DO $$
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_col_partial', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l3')::uuid,
    timestamptz '2026-10-05 14:30:00+09',
    'Collision partial probe'
  );
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_col_partial')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_col_partial')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l3')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Partial collision cascade') $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

DO $$
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_col_contained', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l3')::uuid,
    timestamptz '2026-10-05 14:15:00+09',
    'Collision contained probe'
  );
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_col_contained')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_col_contained')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l3')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Contained collision cascade') $$,
  'P0001',
  'REVE_SCHEDULE_COLLISION'
);

DO $$
BEGIN
  RESET ROLE;
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-11-02 11:00:00+09'
  WHERE id = current_setting('test.lesson_ext_block')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM pg_temp.prepare_applied_request(
    'req_col_adjacent', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l3')::uuid,
    timestamptz '2026-10-05 14:00:00+09',
    'Collision adjacent ok'
  );
END $$;

SELECT lives_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_col_adjacent')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_col_adjacent')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l3')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Adjacent collision ok cascade') $$,
  'adjacent external slot does not block cascade'
);

DO $$
BEGIN
  RESET ROLE;
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-11-02 11:00:00+09'
  WHERE id = current_setting('test.lesson_ext_block')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM pg_temp.prepare_applied_request(
    'req_col_teacher_b', current_setting('test.student_col_en')::uuid,
    current_setting('test.col_l3')::uuid,
    timestamptz '2026-10-05 14:00:00+09',
    'Different teacher collision ok'
  );
END $$;

SELECT lives_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_col_teacher_b')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_col_teacher_b')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.col_l3')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_col')::uuid),
       'Different teacher cascade') $$,
  'different teacher overlap does not block cascade'
);

-- ---------------------------------------------------------------------------
-- Concurrency (10)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_conc', current_setting('test.student_zero')::uuid,
    current_setting('test.zero_l2')::uuid,
    timestamptz '2026-09-17 14:00:00+09',
    'Concurrency probe'
  );
  PERFORM set_config('test.conc_l2_before',
    (SELECT scheduled_at::text FROM public.lessons
     WHERE id = current_setting('test.zero_l2')::uuid), false);
END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_conc')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       pg_temp.lesson_updated_at(current_setting('test.zero_l2')::uuid),
       pg_temp.pass_updated_at(current_setting('test.pass_zero')::uuid),
       'Stale request token') $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_conc')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_conc')::uuid),
       timestamptz '2000-01-01 00:00:00+00',
       pg_temp.pass_updated_at(current_setting('test.pass_zero')::uuid),
       'Stale anchor token') $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_cascade_schedule_change_request(
       current_setting('test.req_conc')::uuid,
       pg_temp.request_updated_at(current_setting('test.req_conc')::uuid),
       pg_temp.lesson_updated_at(current_setting('test.zero_l2')::uuid),
       timestamptz '2000-01-01 00:00:00+00',
       'Stale pass token') $$,
  '22000',
  'REVE_STALE_STATE'
);

SELECT is(
  pg_temp.cascade_event_count(current_setting('test.req_conc')::uuid),
  0::bigint,
  'stale request token writes no cascade events'
);

SELECT is(
  (SELECT cascade_completed_at FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_conc')::uuid),
  NULL::timestamptz,
  'stale request token leaves cascade_completed_at null'
);

SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.zero_l2')::uuid),
  current_setting('test.conc_l2_before')::timestamptz,
  'stale request token leaves anchor lesson unchanged'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'schedule_change_request.cascade_completed'
      AND resource_id = current_setting('test.req_conc')::uuid
  ),
  'stale request token writes no cascade_completed audit'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'lesson.cascade_rescheduled'
      AND resource_id IN (
        SELECT l.id FROM public.lessons AS l
        WHERE l.pass_id = current_setting('test.pass_zero')::uuid
          AND l.sequence_number > 2
      )
  ),
  'stale anchor token writes no lesson cascade audit'
);

SELECT ok(
  (SELECT status FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_zero')::uuid LIMIT 1) IS NOT NULL,
  'stale pass token leaves SMS row intact without cascade sync'
);

SELECT ok(
  pg_temp.direct_event_count(current_setting('test.req_conc')::uuid) = 1,
  'stale tokens leave direct apply event intact'
);

-- ---------------------------------------------------------------------------
-- Idempotency (10)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('test.w1_cascade_audit_count',
    pg_temp.audit_count_for('schedule_change_request.cascade_completed')::text, false);
END $$;

SELECT ok(
  (
    SELECT no_change = true
      AND cascaded_lesson_count = 2
      AND cascade_completed_at IS NOT NULL
    FROM public.reve_owner_cascade_schedule_change_request(
      current_setting('test.req_w1_main')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_w1_main')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.l2_w1')::uuid),
      pg_temp.pass_updated_at(current_setting('test.pass_w1')::uuid),
      'Weekly-once cascade retry'
    ) LIMIT 1
  ),
  'cascade retry on completed request returns no_change true'
);

SELECT is(
  pg_temp.cascade_event_count(current_setting('test.req_w1_main')::uuid),
  2::bigint,
  'cascade retry does not append duplicate cascade_auto events'
);

SELECT is(
  pg_temp.audit_count_for('schedule_change_request.cascade_completed'),
  current_setting('test.w1_cascade_audit_count')::bigint,
  'cascade retry does not append duplicate cascade_completed audit'
);

SELECT ok(
  (
    SELECT cascade_completed_at = (
      SELECT cascade_completed_at FROM public.schedule_change_requests
      WHERE id = current_setting('test.req_w1_main')::uuid
    )
    FROM public.reve_owner_cascade_schedule_change_request(
      current_setting('test.req_w1_main')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_w1_main')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.l2_w1')::uuid),
      pg_temp.pass_updated_at(current_setting('test.pass_w1')::uuid),
      'Weekly-once cascade retry timestamp'
    ) LIMIT 1
  ),
  'cascade retry preserves cascade_completed_at timestamp'
);

DO $$
BEGIN
  PERFORM pg_temp.cascade_request(
    current_setting('test.req_conc')::uuid, 'Zero-eligible cascade completion'
  );
END $$;

SELECT ok(
  (
    SELECT cascaded_lesson_count = 0
    FROM public.schedule_change_requests
    WHERE id = current_setting('test.req_conc')::uuid
  ),
  'zero-eligible cascade completes with cascaded_lesson_count 0'
);

SELECT ok(
  (
    SELECT no_change = true AND cascaded_lesson_count = 0
    FROM public.reve_owner_cascade_schedule_change_request(
      current_setting('test.req_conc')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_conc')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.zero_l2')::uuid),
      pg_temp.pass_updated_at(current_setting('test.pass_zero')::uuid),
      'Zero-eligible cascade retry'
    ) LIMIT 1
  ),
  'zero-eligible cascade retry returns no_change true'
);

SELECT is(
  pg_temp.cascade_event_count(current_setting('test.req_conc')::uuid),
  0::bigint,
  'zero-eligible cascade writes no cascade_auto events'
);

SELECT ok(
  (SELECT cascade_completed_at IS NOT NULL FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_conc')::uuid),
  'zero-eligible cascade sets cascade_completed_at'
);

SELECT ok(
  (SELECT cascade_reason = 'Zero-eligible cascade completion'
   FROM public.schedule_change_requests
   WHERE id = current_setting('test.req_conc')::uuid),
  'zero-eligible cascade stores cascade_reason'
);

SELECT is(
  pg_temp.direct_event_count(current_setting('test.req_conc')::uuid),
  1::bigint,
  'zero-eligible cascade leaves single direct_user event'
);

-- ---------------------------------------------------------------------------
-- SMS (10)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_sms_before text;
  v_target_before date;
BEGIN
  SELECT status, target_date
  INTO v_sms_before, v_target_before
  FROM public.sms_notifications
  WHERE pass_id = current_setting('test.pass_sms')::uuid
  LIMIT 1;

  PERFORM set_config('test.sms_status_before_apply', v_sms_before, false);
  PERFORM set_config('test.sms_target_before_apply', COALESCE(v_target_before::text, ''), false);

  PERFORM pg_temp.prepare_applied_request(
    'req_sms_final', current_setting('test.student_sms')::uuid,
    current_setting('test.sms_l4')::uuid,
    current_setting('test.sms_final_new_time')::timestamptz,
    'SMS final lesson apply'
  );
END $$;

SELECT is(
  (SELECT target_date FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_sms')::uuid LIMIT 1),
  (current_setting('test.sms_final_new_time')::timestamptz AT TIME ZONE 'Asia/Seoul')::date - 1,
  'direct apply on final remaining lesson updates SMS target_date'
);

SELECT ok(
  (
    SELECT status IN ('scheduled', 'target')
    FROM public.sms_notifications
    WHERE pass_id = current_setting('test.pass_sms')::uuid LIMIT 1
  ),
  'final-lesson apply sets SMS status to scheduled or target when remaining is 1'
);

DO $$
BEGIN
  PERFORM set_config('test.sms_mid_before',
    (SELECT status FROM public.sms_notifications
     WHERE pass_id = current_setting('test.pass_w1')::uuid LIMIT 1), false);
END $$;

SELECT ok(
  (SELECT status FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_w1')::uuid LIMIT 1)
    IS NOT DISTINCT FROM current_setting('test.sms_mid_before'),
  'non-final cascade pass keeps SMS stable when remaining count stays above 1'
);

RESET ROLE;
UPDATE public.sms_notifications
SET status = 'sent', sent_at = now()
WHERE pass_id = current_setting('test.pass_sms')::uuid;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

SELECT ok(
  (
    SELECT cascaded_lesson_count = 0 AND no_change = false
    FROM pg_temp.cascade_request(
      current_setting('test.req_sms_final')::uuid, 'SMS sent cascade probe'
    ) LIMIT 1
  ),
  'sent SMS status preserved on zero-eligible cascade completion'
);

SELECT is(
  (SELECT status FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_sms')::uuid LIMIT 1),
  'sent',
  'sent SMS row remains sent after cascade call'
);

DO $$
BEGIN
  PERFORM pg_temp.prepare_applied_request(
    'req_sms_cascade', current_setting('test.student_sms')::uuid,
    current_setting('test.sms_l4')::uuid,
    timestamptz '2026-10-23 14:00:00+09',
    'SMS cascade sync probe'
  );
  RESET ROLE;
  UPDATE public.sms_notifications
  SET status = 'normal', sent_at = NULL, target_date = NULL
  WHERE pass_id = current_setting('test.pass_sms')::uuid;
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT ok(
  (
    SELECT sms_notification_status IS NOT NULL
    FROM public.reve_owner_cascade_schedule_change_request(
      current_setting('test.req_sms_cascade')::uuid,
      pg_temp.request_updated_at(current_setting('test.req_sms_cascade')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.sms_l4')::uuid),
      pg_temp.pass_updated_at(current_setting('test.pass_sms')::uuid),
      'SMS cascade sync'
    ) LIMIT 1
  ),
  'cascade SMS sync returns sms_notification_status'
);

SELECT ok(
  pg_temp.audit_count_for('sms_notification.state_sync')
    >= 1,
  'schedule change cascade path can write sms_notification.state_sync audit'
);

SELECT ok(
  (SELECT message_body_snapshot IS NOT NULL FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_sms')::uuid LIMIT 1),
  'SMS message_body_snapshot remains populated after sync'
);

SELECT ok(
  (SELECT target_date IS NOT NULL FROM public.sms_notifications
   WHERE pass_id = current_setting('test.pass_sms')::uuid LIMIT 1),
  'cascade SMS sync sets target_date from final lesson schedule'
);

-- ---------------------------------------------------------------------------
-- Scope / history (10)
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT scheduled_at FROM public.lessons WHERE id = current_setting('test.l1_w1')::uuid),
  current_setting('test.l1_w1_sched_before')::timestamptz,
  'cascade leaves earlier completed lessons unchanged'
);

SELECT is(
  pg_temp.active_slot_count(current_setting('test.pass_w1')::uuid),
  current_setting('test.w1_slots_before')::integer,
  'cascade does not change active schedule slot count'
);

SELECT is(
  (SELECT paid_amount_krw::text FROM public.payments
   WHERE renewed_pass_id = current_setting('test.pass_w1')::uuid LIMIT 1),
  current_setting('test.w1_payment_before'),
  'cascade leaves linked payment amount unchanged'
);

SELECT is(
  pg_temp.lesson_count_for_pass(current_setting('test.pass_w1')::uuid),
  current_setting('test.w1_lesson_count_before')::integer,
  'cascade does not add or remove lesson rows'
);

SELECT is(
  pg_temp.used_count_for_pass(current_setting('test.pass_w1')::uuid),
  current_setting('test.w1_used_before')::integer,
  'cascade leaves deductible used lesson count unchanged'
);

SELECT ok(
  pg_temp.audit_count_for('schedule_change_request.cascade_completed')
    > current_setting('test.w1_audit_before_cascade')::bigint,
  'successful cascade writes schedule_change_request.cascade_completed audit'
);

SELECT ok(
  pg_temp.audit_count_for('lesson.cascade_rescheduled')
    > current_setting('test.w1_reschedule_audit_before')::bigint,
  'successful cascade writes lesson.cascade_rescheduled audit per moved lesson'
);

SELECT throws_ok(
  $$ UPDATE public.lesson_schedule_changes
     SET reason = 'mutated'
     WHERE schedule_change_request_id = current_setting('test.req_w1_main')::uuid $$,
  '42501'
);

SELECT throws_ok(
  $$ DELETE FROM public.lesson_schedule_changes
     WHERE schedule_change_request_id = current_setting('test.req_w1_main')::uuid $$,
  '42501'
);

SELECT ok(
  (
    SELECT count(*) = 3
    FROM public.lesson_schedule_changes AS lsc
    WHERE lsc.schedule_change_request_id = current_setting('test.req_w1_main')::uuid
  ),
  'scope history retains one direct and two append-only cascade events'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT * FROM finish();

ROLLBACK;

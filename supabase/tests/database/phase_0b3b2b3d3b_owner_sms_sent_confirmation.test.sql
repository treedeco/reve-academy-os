-- REVE ACADEMY OS Phase 0B-3B-2B-3D-3B — Owner SMS sent confirmation pgTAP tests
-- Runs in a transaction; rolls back all test data.

BEGIN;

SELECT plan(27);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa031';
  v_owner2 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa032';
  v_teacher_auth uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd031';
  v_student_auth uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb031';
  v_teacher uuid := '22222222-2222-2222-2222-222222222031';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee31';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff31';
  v_student uuid := '44444444-4444-4444-4444-444444444031';
  v_student_b uuid := '44444444-4444-4444-4444-444444444032';
  v_student_hist uuid := '44444444-4444-4444-4444-444444444033';
  v_student_new uuid := '44444444-4444-4444-4444-444444444034';
  v_pass_scheduled uuid := '66666666-6666-6666-6666-666666666031';
  v_pass_target uuid := '66666666-6666-6666-6666-666666666032';
  v_pass_exhausted uuid := '66666666-6666-6666-6666-666666666033';
  v_pass_normal uuid := '66666666-6666-6666-6666-666666666034';
  v_pass_derive uuid := '66666666-6666-6666-6666-666666666035';
  v_pass_idempotent uuid := '66666666-6666-6666-6666-666666666036';
  v_pass_concurrent uuid := '66666666-6666-6666-6666-666666666037';
  v_pass_atomic uuid := '66666666-6666-6666-6666-666666666038';
  v_sms_scheduled uuid := '88888888-8888-8888-8888-888888888031';
  v_sms_target uuid := '88888888-8888-8888-8888-888888888032';
  v_sms_exhausted uuid := '88888888-8888-8888-8888-888888888033';
  v_sms_normal uuid := '88888888-8888-8888-8888-888888888034';
  v_sms_derive uuid := '88888888-8888-8888-8888-888888888035';
  v_sms_idempotent uuid := '88888888-8888-8888-8888-888888888036';
  v_sms_concurrent uuid := '88888888-8888-8888-8888-888888888037';
  v_sms_atomic uuid := '88888888-8888-8888-8888-888888888038';
  v_enroll_date date := '2026-09-07';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner1-osc@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner2-osc@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-osc@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_auth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-osc@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_student_auth, 'student', 'OSC Student Profile', 'active'),
    (v_teacher_auth, 'teacher', 'OSC Teacher Profile', 'active');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher, 'T-OSC', v_teacher_auth, 'OSC Teacher', '010-0000-0031', 't-osc@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student, 'S031', v_student_auth, 'OSC Student A', 'active'),
    (v_student_b, 'S032', NULL, 'OSC Student B', 'active'),
    (v_student_hist, 'S033', NULL, 'OSC History Student', 'active'),
    (v_student_new, 'S034', NULL, 'OSC New Pass Student', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOCAL-OSC', 'OSC Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES
    (v_product, v_course, 'VOCAL-4-OSC', 'OSC Vocal 4 Lessons', 4, 1, 200000, true);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at, completed_at
  ) VALUES
    (v_pass_scheduled, 'V-S031-SCH', v_student, v_course, v_product,
     91, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days'),
    (v_pass_target, 'V-S031-TGT', v_student, v_course, v_product,
     92, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days'),
    (v_pass_exhausted, 'V-S031-EXH', v_student, v_course, v_product,
     93, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days'),
    (v_pass_normal, 'V-S031-NRM', v_student, v_course, v_product,
     94, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days'),
    (v_pass_derive, 'V-S031-DER', v_student, v_course, v_product,
     95, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days'),
    (v_pass_idempotent, 'V-S031-IDM', v_student, v_course, v_product,
     96, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days'),
    (v_pass_concurrent, 'V-S031-CNC', v_student, v_course, v_product,
     97, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days'),
    (v_pass_atomic, 'V-S031-ATM', v_student, v_course, v_product,
     98, 'completed', 4, 1, 'OSC Vocal 4 Lessons', 200000, v_enroll_date - 120, now() - interval '90 days', now() - interval '60 days');

  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status,
    message_body_snapshot, target_date
  ) VALUES
    (v_sms_scheduled, v_student, v_pass_scheduled, 'renewal_reminder', 'scheduled',
     'OSC scheduled body', CURRENT_DATE + 3),
    (v_sms_target, v_student, v_pass_target, 'renewal_reminder', 'target',
     'OSC target body', CURRENT_DATE),
    (v_sms_exhausted, v_student, v_pass_exhausted, 'renewal_reminder', 'exhausted_unsent',
     'OSC exhausted body', CURRENT_DATE - 1),
    (v_sms_normal, v_student, v_pass_normal, 'renewal_reminder', 'normal',
     'OSC normal body', CURRENT_DATE + 10),
    (v_sms_derive, v_student, v_pass_derive, 'renewal_reminder', 'scheduled',
     'OSC derive body', CURRENT_DATE + 2),
    (v_sms_idempotent, v_student, v_pass_idempotent, 'renewal_reminder', 'scheduled',
     'OSC idempotent body', CURRENT_DATE + 2),
    (v_sms_concurrent, v_student, v_pass_concurrent, 'renewal_reminder', 'scheduled',
     'OSC concurrent body', CURRENT_DATE + 2),
    (v_sms_atomic, v_student, v_pass_atomic, 'renewal_reminder', 'normal',
     'OSC atomic body', CURRENT_DATE + 10);

  PERFORM set_config('test.owner1', v_owner1::text, false);
  PERFORM set_config('test.owner2', v_owner2::text, false);
  PERFORM set_config('test.teacher_auth', v_teacher_auth::text, false);
  PERFORM set_config('test.student_auth', v_student_auth::text, false);
  PERFORM set_config('test.teacher', v_teacher::text, false);
  PERFORM set_config('test.course', v_course::text, false);
  PERFORM set_config('test.product', v_product::text, false);
  PERFORM set_config('test.student', v_student::text, false);
  PERFORM set_config('test.student_b', v_student_b::text, false);
  PERFORM set_config('test.student_hist', v_student_hist::text, false);
  PERFORM set_config('test.student_new', v_student_new::text, false);
  PERFORM set_config('test.sms_scheduled', v_sms_scheduled::text, false);
  PERFORM set_config('test.sms_target', v_sms_target::text, false);
  PERFORM set_config('test.sms_exhausted', v_sms_exhausted::text, false);
  PERFORM set_config('test.sms_normal', v_sms_normal::text, false);
  PERFORM set_config('test.sms_derive', v_sms_derive::text, false);
  PERFORM set_config('test.sms_idempotent', v_sms_idempotent::text, false);
  PERFORM set_config('test.sms_concurrent', v_sms_concurrent::text, false);
  PERFORM set_config('test.sms_atomic', v_sms_atomic::text, false);
  PERFORM set_config('test.pass_derive', v_pass_derive::text, false);
  PERFORM set_config('test.enroll_date', v_enroll_date::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.confirm_sig()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'public.reve_owner_confirm_sms_sent(uuid)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.sent_confirm_audit_count(p_sms uuid)
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*)
  FROM public.audit_logs AS al
  WHERE al.action = 'sms_notification.sent_confirmed'
    AND al.resource_table = 'sms_notifications'
    AND al.resource_id = p_sms;
$$;

CREATE OR REPLACE FUNCTION pg_temp.slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher')::uuid,
    'weekday', 1,
    'local_time', '11:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.lesson_updated_at(p_lesson uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.lessons WHERE id = p_lesson;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.new_pass_slot_json()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'teacher_id', current_setting('test.teacher')::uuid,
    'weekday', 3,
    'local_time', '14:00',
    'duration_minutes', 60,
    'slot_order', 1
  ));
$$;

SET ROLE service_role;
SELECT ok(
  (SELECT role FROM public.reve_bootstrap_first_owner(
     current_setting('test.owner1')::uuid, 'OSC First Owner'
   ) LIMIT 1) = 'owner',
  'bootstrap creates first owner profile'
);
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

DO $$
DECLARE
  v_pass_hist uuid;
  v_lesson_1 uuid;
  v_lesson_2 uuid;
  v_lesson_3 uuid;
  v_lesson_4 uuid;
  v_sms_hist uuid;
BEGIN
  SELECT pass_id INTO v_pass_hist
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_hist')::uuid,
    current_setting('test.product')::uuid,
    current_setting('test.enroll_date')::date,
    pg_temp.slot_json(),
    200000, 'cash', now(), 'osc-hist-enroll', 'OSC history pass'
  )
  LIMIT 1;

  SELECT l.id INTO v_lesson_1 FROM public.lessons AS l
  WHERE l.pass_id = v_pass_hist AND l.sequence_number = 1;
  SELECT l.id INTO v_lesson_2 FROM public.lessons AS l
  WHERE l.pass_id = v_pass_hist AND l.sequence_number = 2;
  SELECT l.id INTO v_lesson_3 FROM public.lessons AS l
  WHERE l.pass_id = v_pass_hist AND l.sequence_number = 3;
  SELECT l.id INTO v_lesson_4 FROM public.lessons AS l
  WHERE l.pass_id = v_pass_hist AND l.sequence_number = 4;

  PERFORM public.reve_transition_lesson_status(
    v_lesson_1, 'completed', pg_temp.lesson_updated_at(v_lesson_1),
    now() - interval '3 days', now() - interval '3 days' + interval '1 hour', 'OSC hist 1'
  );
  PERFORM public.reve_transition_lesson_status(
    v_lesson_2, 'completed', pg_temp.lesson_updated_at(v_lesson_2),
    now() - interval '2 days', now() - interval '2 days' + interval '1 hour', 'OSC hist 2'
  );
  PERFORM public.reve_transition_lesson_status(
    v_lesson_3, 'completed', pg_temp.lesson_updated_at(v_lesson_3),
    now() - interval '1 day', now() - interval '1 day' + interval '1 hour', 'OSC hist 3'
  );

  SELECT sn.id INTO v_sms_hist
  FROM public.sms_notifications AS sn
  WHERE sn.pass_id = v_pass_hist AND sn.notification_type = 'renewal_reminder'
  LIMIT 1;

  PERFORM set_config('test.pass_hist', v_pass_hist::text, false);
  PERFORM set_config('test.sms_hist', v_sms_hist::text, false);
  PERFORM set_config('test.lesson_hist_4', v_lesson_4::text, false);
  PERFORM set_config('test.lesson_hist_3', v_lesson_3::text, false);
END $$;

-- Authorization before any confirms (tests 5-9)
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_confirm_sms_sent(
       current_setting('test.sms_scheduled')::uuid) $$,
  '42501', NULL, 'teacher cannot confirm SMS sent'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.student_auth')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_confirm_sms_sent(
       current_setting('test.sms_scheduled')::uuid) $$,
  '42501', NULL, 'student cannot confirm SMS sent'
);

SELECT pg_temp.test_reset_role();
SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_confirm_sms_sent(
       current_setting('test.sms_scheduled')::uuid) $$,
  '42501', NULL, 'unauthenticated caller cannot confirm SMS sent'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_confirm_sms_sent(
       '00000000-0000-0000-0000-000000000099'::uuid) $$,
  '42501', NULL, 'missing notification is rejected'
);

SELECT ok(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.proname = 'reve_owner_confirm_sms_sent'
      AND pg_get_function_arguments(p.oid) = 'p_sms_notification_id uuid'
  ) = 1,
  'RPC accepts SMS notification id only (no client student or pass override)'
);

-- Eligible confirms (tests 1-3)
SELECT ok(
  (
    SELECT previous_status = 'scheduled' AND new_status = 'sent' AND no_change = false
    FROM public.reve_owner_confirm_sms_sent(current_setting('test.sms_scheduled')::uuid)
    LIMIT 1
  ),
  'owner confirms scheduled SMS to sent'
);

SELECT ok(
  (
    SELECT previous_status = 'target' AND new_status = 'sent' AND no_change = false
    FROM public.reve_owner_confirm_sms_sent(current_setting('test.sms_target')::uuid)
    LIMIT 1
  ),
  'owner confirms target SMS to sent'
);

SELECT ok(
  (
    SELECT previous_status = 'exhausted_unsent' AND new_status = 'sent' AND no_change = false
    FROM public.reve_owner_confirm_sms_sent(current_setting('test.sms_exhausted')::uuid)
    LIMIT 1
  ),
  'owner confirms exhausted_unsent SMS to sent'
);

-- Reject normal (test 4)
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_confirm_sms_sent(
       current_setting('test.sms_normal')::uuid) $$,
  'P0001', 'REVE_SMS_NOT_CONFIRMABLE', 'normal SMS confirmation is rejected'
);

-- Derive student and pass (test 10)
SELECT ok(
  (
    SELECT student_id = current_setting('test.student')::uuid
      AND pass_id = current_setting('test.pass_derive')::uuid
      AND no_change = false
    FROM public.reve_owner_confirm_sms_sent(current_setting('test.sms_derive')::uuid)
    LIMIT 1
  ),
  'RPC derives student and pass from notification row'
);

-- First success metadata (tests 11-13)
SELECT ok(
  (
    SELECT sent_at IS NOT NULL AND no_change = false
    FROM public.reve_owner_confirm_sms_sent(current_setting('test.sms_idempotent')::uuid)
    LIMIT 1
  ),
  'first success records sent_at'
);

SELECT is(
  (SELECT sent_confirmed_by_profile_id FROM public.sms_notifications
   WHERE id = current_setting('test.sms_idempotent')::uuid),
  current_setting('test.owner1')::uuid,
  'first success records confirming owner profile id'
);

SELECT is(
  pg_temp.sent_confirm_audit_count(current_setting('test.sms_idempotent')::uuid),
  1::bigint,
  'first success creates exactly one sent_confirmed audit row'
);

-- Idempotent retry (tests 14-17)
DO $$
DECLARE
  v_first_sent timestamptz;
  v_first_confirmer uuid;
BEGIN
  SELECT sent_at, sent_confirmed_by_profile_id
  INTO v_first_sent, v_first_confirmer
  FROM public.sms_notifications
  WHERE id = current_setting('test.sms_idempotent')::uuid;

  PERFORM set_config('test.idem_sent_at', v_first_sent::text, false);
  PERFORM set_config('test.idem_confirmer', v_first_confirmer::text, false);
END $$;

SELECT ok(
  (SELECT no_change FROM public.reve_owner_confirm_sms_sent(
     current_setting('test.sms_idempotent')::uuid) LIMIT 1),
  'retry returns no_change true'
);

SELECT is(
  (SELECT sent_at::text FROM public.sms_notifications
   WHERE id = current_setting('test.sms_idempotent')::uuid),
  current_setting('test.idem_sent_at'),
  'retry preserves original sent_at'
);

SELECT is(
  (SELECT sent_confirmed_by_profile_id::text FROM public.sms_notifications
   WHERE id = current_setting('test.sms_idempotent')::uuid),
  current_setting('test.idem_confirmer'),
  'retry preserves original confirming owner'
);

SELECT is(
  pg_temp.sent_confirm_audit_count(current_setting('test.sms_idempotent')::uuid),
  1::bigint,
  'retry creates no additional sent_confirmed audit row'
);

-- Sent-history preservation (tests 19-23)
RESET ROLE;
UPDATE public.sms_notifications
SET status = 'sent',
    sent_at = timestamptz '2026-06-01 10:00:00+09',
    sent_confirmed_by_profile_id = current_setting('test.owner1')::uuid,
    message_body_snapshot = 'OSC preserved sent body'
WHERE id = current_setting('test.sms_hist')::uuid;
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid); END $$;

DO $$
DECLARE
  v_req uuid;
  v_lesson uuid := current_setting('test.lesson_hist_4')::uuid;
  v_new_time timestamptz := timestamptz '2026-10-19 11:00:00+09';
BEGIN
  RESET ROLE;
  INSERT INTO public.schedule_change_requests (
    student_id, target_lesson_id, requesting_profile_id,
    request_source_role, requested_reason, proposed_scheduled_at,
    status, approved_scheduled_at, decided_by_profile_id, decided_at
  ) VALUES (
    current_setting('test.student_hist')::uuid, v_lesson, current_setting('test.owner1')::uuid,
    'owner', 'OSC direct schedule change on sent SMS pass', v_new_time,
    'approved', v_new_time, current_setting('test.owner1')::uuid, now()
  )
  RETURNING id INTO v_req;
  PERFORM set_config('test.req_direct', v_req::text, false);
  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
END $$;

SELECT ok(
  (
    SELECT no_change = false
    FROM public.reve_owner_apply_schedule_change_request(
      current_setting('test.req_direct')::uuid,
      (SELECT updated_at FROM public.schedule_change_requests
       WHERE id = current_setting('test.req_direct')::uuid),
      pg_temp.lesson_updated_at(current_setting('test.lesson_hist_4')::uuid)
    ) LIMIT 1
  )
  AND (SELECT status FROM public.sms_notifications
       WHERE id = current_setting('test.sms_hist')::uuid) = 'sent'
  AND (SELECT message_body_snapshot FROM public.sms_notifications
       WHERE id = current_setting('test.sms_hist')::uuid) = 'OSC preserved sent body',
  'direct schedule change preserves sent SMS history'
);

DO $$
DECLARE
  v_req uuid;
  v_lesson uuid := current_setting('test.lesson_hist_4')::uuid;
  v_pass uuid := current_setting('test.pass_hist')::uuid;
  v_new_time timestamptz := timestamptz '2026-10-26 11:00:00+09';
BEGIN
  RESET ROLE;
  INSERT INTO public.schedule_change_requests (
    student_id, target_lesson_id, requesting_profile_id,
    request_source_role, requested_reason, proposed_scheduled_at,
    status, approved_scheduled_at, decided_by_profile_id, decided_at
  ) VALUES (
    current_setting('test.student_hist')::uuid, v_lesson, current_setting('test.owner1')::uuid,
    'owner', 'OSC cascade probe on sent SMS pass', v_new_time,
    'approved', v_new_time, current_setting('test.owner1')::uuid, now()
  )
  RETURNING id INTO v_req;

  PERFORM pg_temp.test_auth_as(current_setting('test.owner1')::uuid);
  PERFORM public.reve_owner_apply_schedule_change_request(
    v_req,
    (SELECT updated_at FROM public.schedule_change_requests WHERE id = v_req),
    pg_temp.lesson_updated_at(v_lesson)
  );

  PERFORM set_config('test.req_cascade', v_req::text, false);
  PERFORM set_config('test.pass_hist_updated_at', pg_temp.pass_updated_at(v_pass)::text, false);
  PERFORM set_config('test.lesson_hist_4_updated_at',
    pg_temp.lesson_updated_at(v_lesson)::text, false);
END $$;

SELECT ok(
  (
    SELECT sms_notification_status = 'sent'
    FROM public.reve_owner_cascade_schedule_change_request(
      current_setting('test.req_cascade')::uuid,
      (SELECT updated_at FROM public.schedule_change_requests
       WHERE id = current_setting('test.req_cascade')::uuid),
      current_setting('test.lesson_hist_4_updated_at')::timestamptz,
      current_setting('test.pass_hist_updated_at')::timestamptz,
      'OSC cascade on sent SMS pass'
    ) LIMIT 1
  )
  AND (SELECT status FROM public.sms_notifications
       WHERE id = current_setting('test.sms_hist')::uuid) = 'sent',
  'cascade schedule change preserves sent SMS status'
);

SELECT ok(
  (
    SELECT sms_notification_status = 'sent'
    FROM public.reve_transition_lesson_status(
      current_setting('test.lesson_hist_4')::uuid,
      'completed',
      pg_temp.lesson_updated_at(current_setting('test.lesson_hist_4')::uuid),
      now(), now() + interval '1 hour',
      'OSC lesson complete after sent SMS'
    ) LIMIT 1
  )
  AND (SELECT status FROM public.sms_notifications
       WHERE id = current_setting('test.sms_hist')::uuid) = 'sent',
  'lesson-state and pass-count synchronization preserve sent SMS status'
);

DO $$
DECLARE
  v_pass_new uuid;
  v_sms_old uuid;
  v_sms_new uuid;
BEGIN
  SELECT pass_id INTO v_pass_new
  FROM public.reve_owner_create_initial_enrollment(
    current_setting('test.student_new')::uuid,
    current_setting('test.product')::uuid,
    current_setting('test.enroll_date')::date + 30,
    pg_temp.new_pass_slot_json(),
    200000, 'cash', now(), 'osc-new-pass-enroll', 'OSC independent SMS lifecycle'
  )
  LIMIT 1;

  SELECT id INTO v_sms_old
  FROM public.sms_notifications
  WHERE pass_id = current_setting('test.pass_hist')::uuid
    AND notification_type = 'renewal_reminder'
  LIMIT 1;

  SELECT id INTO v_sms_new
  FROM public.sms_notifications
  WHERE pass_id = v_pass_new AND notification_type = 'renewal_reminder'
  LIMIT 1;

  PERFORM set_config('test.sms_new_pass', v_sms_new::text, false);
  PERFORM set_config('test.sms_old_status',
    (SELECT status FROM public.sms_notifications WHERE id = v_sms_old), false);
  PERFORM set_config('test.sms_new_status',
    (SELECT status FROM public.sms_notifications WHERE id = v_sms_new), false);
END $$;

SELECT ok(
  current_setting('test.sms_new_pass')::uuid <> current_setting('test.sms_hist')::uuid
  AND current_setting('test.sms_old_status') = 'sent'
  AND current_setting('test.sms_new_status') <> 'sent',
  'new pass starts independent unsent SMS lifecycle while old sent row is preserved'
);

-- Failure atomicity (test 24)
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_confirm_sms_sent(
       current_setting('test.sms_atomic')::uuid) $$,
  'P0001', 'REVE_SMS_NOT_CONFIRMABLE', 'failed confirm on normal status is rejected'
);

SELECT is(
  (SELECT status FROM public.sms_notifications
   WHERE id = current_setting('test.sms_atomic')::uuid),
  'normal',
  'failed confirm leaves SMS status unchanged'
);

SELECT is(
  pg_temp.sent_confirm_audit_count(current_setting('test.sms_atomic')::uuid),
  0::bigint,
  'failed confirm creates no sent_confirmed audit row'
);

-- Security (tests 25-26)
SELECT ok(
  (
    SELECT bool_and('search_path=""' = ANY(p.proconfig))
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public' AND p.proname = 'reve_owner_confirm_sms_sent'
  ),
  'reve_owner_confirm_sms_sent uses fixed empty search_path'
);

SELECT ok(
  NOT has_function_privilege('public', pg_temp.confirm_sig(), 'EXECUTE')
  AND NOT has_function_privilege('anon', pg_temp.confirm_sig(), 'EXECUTE')
  AND has_function_privilege('authenticated', pg_temp.confirm_sig(), 'EXECUTE'),
  'reve_owner_confirm_sms_sent execute privileges are restricted correctly'
);

SELECT * FROM finish();
ROLLBACK;

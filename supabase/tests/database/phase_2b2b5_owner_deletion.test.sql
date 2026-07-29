-- REVE ACADEMY OS Phase 2B-2B5 — owner permanent deletion and fixed-schedule removal pgTAP tests
-- Runs in a transaction; rolls back all test data. Fixture UUIDs use a dedicated '...501'+ suffix
-- block distinct from the Owner Alpha demo seed ('...101'-'...106') and other pgTAP fixtures.

BEGIN;

SELECT plan(86);

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa501';
  v_teacher_helper_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd501';
  v_teacher_replacement_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd502';
  v_teacher_reassign_profile uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd503';
  v_student_sched_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb501';
  v_student_del_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb502';
  v_student_confirm_profile uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb503';

  v_teacher_helper uuid := '22222222-2222-2222-2222-222222222501';
  v_teacher_replacement uuid := '22222222-2222-2222-2222-222222222502';
  v_teacher_inactive uuid := '22222222-2222-2222-2222-222222222503';
  v_teacher_reassign_target uuid := '22222222-2222-2222-2222-222222222504';
  v_teacher_remove_target uuid := '22222222-2222-2222-2222-222222222505';

  v_student_sched uuid := '44444444-4444-4444-4444-444444444501';
  v_student_other uuid := '44444444-4444-4444-4444-444444444502';
  v_student_stale uuid := '44444444-4444-4444-4444-444444444503';
  v_student_del uuid := '44444444-4444-4444-4444-444444444504';
  v_student_confirm uuid := '44444444-4444-4444-4444-444444444505';
  v_student_ta uuid := '44444444-4444-4444-4444-444444444506';
  v_student_tb uuid := '44444444-4444-4444-4444-444444444507';
  v_student_blocked uuid := '44444444-4444-4444-4444-444444444508';

  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee501';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff501';

  v_pass_sched uuid := '66666666-6666-6666-6666-666666666501';
  v_pass_other uuid := '66666666-6666-6666-6666-666666666502';
  v_pass_stale uuid := '66666666-6666-6666-6666-666666666503';
  v_pass_del uuid := '66666666-6666-6666-6666-666666666504';
  v_pass_confirm uuid := '66666666-6666-6666-6666-666666666505';
  v_pass_ta uuid := '66666666-6666-6666-6666-666666666506';
  v_pass_tb uuid := '66666666-6666-6666-6666-666666666507';
  v_pass_blocked uuid := '66666666-6666-6666-6666-666666666508';

  v_slot_sched_1 uuid := '77777777-7777-7777-7777-777777777501';
  v_slot_sched_2 uuid := '77777777-7777-7777-7777-777777777502';
  v_slot_other uuid := '77777777-7777-7777-7777-777777777503';
  v_slot_stale uuid := '77777777-7777-7777-7777-777777777504';
  v_slot_del uuid := '77777777-7777-7777-7777-777777777505';
  v_slot_ta uuid := '77777777-7777-7777-7777-777777777506';
  v_slot_tb uuid := '77777777-7777-7777-7777-777777777507';

  v_lesson_sched_past1 uuid := '99999999-9999-9999-9999-999999aab501';
  v_lesson_sched_past2 uuid := '99999999-9999-9999-9999-999999aab502';
  v_lesson_sched_future1 uuid := '99999999-9999-9999-9999-999999aab503';
  v_lesson_sched_future2 uuid := '99999999-9999-9999-9999-999999aab504';
  v_lesson_other_future uuid := '99999999-9999-9999-9999-999999aab505';
  v_lesson_stale_future uuid := '99999999-9999-9999-9999-999999aab506';
  v_lesson_del_past uuid := '99999999-9999-9999-9999-999999aab507';
  v_lesson_del_future uuid := '99999999-9999-9999-9999-999999aab508';
  v_lesson_confirm uuid := '99999999-9999-9999-9999-999999aab509';
  v_lesson_ta_past uuid := '99999999-9999-9999-9999-999999aab510';
  v_lesson_ta_future uuid := '99999999-9999-9999-9999-999999aab511';
  v_lesson_tb_past uuid := '99999999-9999-9999-9999-999999aab512';
  v_lesson_tb_future uuid := '99999999-9999-9999-9999-999999aab513';

  v_payment_del uuid := '12121212-1212-1212-1212-121212121501';
  v_payment_ta uuid := '12121212-1212-1212-1212-121212121502';
  v_payment_confirm uuid := '12121212-1212-1212-1212-121212121503';
  v_payment_tb uuid := '12121212-1212-1212-1212-121212121504';

  v_sms_del uuid := '14141414-1414-1414-1414-141414141501';
  v_refund_del uuid := '15151515-1515-1515-1515-151515151501';
  v_scr_del uuid := '16161616-1616-1616-1616-161616161601';
  v_lsc_del uuid := '17171717-1717-1717-1717-171717171701';
  v_lsc_sched_future2 uuid := '17171717-1717-1717-1717-171717171702';
  v_note_del uuid := '18181818-1818-1818-1818-181818181801';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'del-owner@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_helper_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'del-teacher-helper@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_replacement_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'del-teacher-replacement@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher_reassign_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'del-teacher-reassign@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_sched_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'del-student-sched@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_del_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'del-student-del@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student_confirm_profile, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'del-student-confirm@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name) VALUES
    (v_owner, 'owner', 'Deletion Test Owner'),
    (v_teacher_helper_profile, 'teacher', 'Helper Teacher'),
    (v_teacher_replacement_profile, 'teacher', 'Replacement Teacher'),
    (v_teacher_reassign_profile, 'teacher', 'Reassign Target Teacher'),
    (v_student_sched_profile, 'student', 'Schedule Student'),
    (v_student_del_profile, 'student', 'Delete Target Student PII Name'),
    (v_student_confirm_profile, 'student', 'Confirm Mismatch Student');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, phone, email, is_active) VALUES
    (v_teacher_helper, 'T-HLP501', v_teacher_helper_profile, 'Helper Teacher', '010-5000-0001', 'hlp501@test.local', true),
    (v_teacher_replacement, 'T-RPL501', v_teacher_replacement_profile, 'Replacement Teacher', '010-5000-0002', 'rpl501@test.local', true),
    (v_teacher_inactive, 'T-INA501', NULL, 'Inactive Teacher', '010-5000-0003', 'ina501@test.local', false),
    (v_teacher_reassign_target, 'T-RSN501', v_teacher_reassign_profile, 'Reassign Target Teacher', '010-5000-0004', 'rsn501@test.local', true),
    (v_teacher_remove_target, 'T-RMV501', NULL, 'Remove Target Teacher', '010-5000-0005', 'rmv501@test.local', true);

  INSERT INTO public.students (id, student_code, profile_id, name) VALUES
    (v_student_sched, 'SCH501', v_student_sched_profile, 'Schedule Student'),
    (v_student_other, 'SCH502', NULL, 'Other Student'),
    (v_student_stale, 'SCH503', NULL, 'Stale Student'),
    (v_student_del, 'DEL501', v_student_del_profile, 'Delete Target Student PII Name'),
    (v_student_confirm, 'CFM501', v_student_confirm_profile, 'Confirm Mismatch Student'),
    (v_student_ta, 'TA501', NULL, 'Teacher Reassign Owner Student'),
    (v_student_tb, 'TB501', NULL, 'Teacher Remove Owner Student'),
    (v_student_blocked, 'BLK501', NULL, 'Blocked Pass Student');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOC-DEL501', 'Deletion Test Vocal Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw
  ) VALUES
    (v_product, v_course, 'VOC-DEL501-4', 'Deletion Vocal 4 Lessons', 4, 1, 200000);

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, completed_at
  ) VALUES
    (v_pass_sched, 'V-SCH501-001', v_student_sched, v_course, v_product,
     1, 'active', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 30, NULL),
    (v_pass_other, 'V-SCH502-001', v_student_other, v_course, v_product,
     1, 'active', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 30, NULL),
    (v_pass_stale, 'V-SCH503-001', v_student_stale, v_course, v_product,
     1, 'active', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 30, NULL),
    (v_pass_del, 'V-DEL501-001', v_student_del, v_course, v_product,
     1, 'active', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 30, NULL),
    (v_pass_confirm, 'V-CFM501-001', v_student_confirm, v_course, v_product,
     1, 'active', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 30, NULL),
    (v_pass_ta, 'V-TA501-001', v_student_ta, v_course, v_product,
     1, 'active', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 30, NULL),
    (v_pass_tb, 'V-TB501-001', v_student_tb, v_course, v_product,
     1, 'active', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 30, NULL),
    (v_pass_blocked, 'V-BLK501-001', v_student_blocked, v_course, v_product,
     1, 'completed', 4, 1, 'Deletion Vocal 4 Lessons', 200000, CURRENT_DATE - 90, now() - interval '30 days');

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, effective_from
  ) VALUES
    (v_slot_sched_1, v_pass_sched, v_teacher_helper, 1, '10:00', 60, CURRENT_DATE - 30),
    (v_slot_sched_2, v_pass_sched, v_teacher_helper, 3, '14:00', 60, CURRENT_DATE - 30),
    (v_slot_other, v_pass_other, v_teacher_helper, 2, '11:00', 60, CURRENT_DATE - 30),
    (v_slot_stale, v_pass_stale, v_teacher_helper, 4, '09:00', 60, CURRENT_DATE - 30),
    (v_slot_del, v_pass_del, v_teacher_helper, 5, '15:00', 60, CURRENT_DATE - 30),
    (v_slot_ta, v_pass_ta, v_teacher_reassign_target, 1, '09:00', 60, CURRENT_DATE - 30),
    (v_slot_tb, v_pass_tb, v_teacher_remove_target, 2, '10:00', 60, CURRENT_DATE - 30);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    actual_start_at, actual_end_at
  ) VALUES
    (v_lesson_sched_past1, v_pass_sched, v_student_sched, v_course, v_teacher_helper,
     v_slot_sched_1, 1, now() - interval '14 days', 'completed',
     now() - interval '14 days', now() - interval '14 days' + interval '1 hour'),
    (v_lesson_sched_past2, v_pass_sched, v_student_sched, v_course, v_teacher_helper,
     v_slot_sched_1, 2, now() - interval '7 days', 'completed',
     now() - interval '7 days', now() - interval '7 days' + interval '1 hour'),
    (v_lesson_sched_future1, v_pass_sched, v_student_sched, v_course, v_teacher_helper,
     v_slot_sched_1, 3, now() + interval '2 days', 'scheduled', NULL, NULL),
    (v_lesson_sched_future2, v_pass_sched, v_student_sched, v_course, v_teacher_helper,
     v_slot_sched_2, 4, now() + interval '9 days', 'scheduled', NULL, NULL),
    (v_lesson_other_future, v_pass_other, v_student_other, v_course, v_teacher_helper,
     v_slot_other, 1, now() + interval '3 days', 'scheduled', NULL, NULL),
    (v_lesson_stale_future, v_pass_stale, v_student_stale, v_course, v_teacher_helper,
     v_slot_stale, 1, now() + interval '2 days', 'scheduled', NULL, NULL),
    (v_lesson_del_past, v_pass_del, v_student_del, v_course, v_teacher_helper,
     v_slot_del, 1, now() - interval '10 days', 'completed',
     now() - interval '10 days', now() - interval '10 days' + interval '1 hour'),
    (v_lesson_del_future, v_pass_del, v_student_del, v_course, v_teacher_helper,
     v_slot_del, 2, now() + interval '5 days', 'scheduled', NULL, NULL),
    (v_lesson_confirm, v_pass_confirm, v_student_confirm, v_course, v_teacher_helper,
     NULL, 1, now() + interval '2 days', 'scheduled', NULL, NULL),
    (v_lesson_ta_past, v_pass_ta, v_student_ta, v_course, v_teacher_reassign_target,
     v_slot_ta, 1, now() - interval '20 days', 'completed',
     now() - interval '20 days', now() - interval '20 days' + interval '1 hour'),
    (v_lesson_ta_future, v_pass_ta, v_student_ta, v_course, v_teacher_reassign_target,
     v_slot_ta, 2, now() + interval '4 days', 'scheduled', NULL, NULL),
    (v_lesson_tb_past, v_pass_tb, v_student_tb, v_course, v_teacher_remove_target,
     v_slot_tb, 1, now() - interval '20 days', 'completed',
     now() - interval '20 days', now() - interval '20 days' + interval '1 hour'),
    (v_lesson_tb_future, v_pass_tb, v_student_tb, v_course, v_teacher_remove_target,
     v_slot_tb, 2, now() + interval '4 days', 'scheduled', NULL, NULL);

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id,
    paid_amount_krw, payment_method, status, paid_at, idempotency_key,
    created_by_profile_id
  ) VALUES
    (v_payment_del, v_student_del, v_course, v_product, v_pass_del,
     200000, 'cash', 'completed', now() - interval '10 days', 'idem-del-501', v_owner),
    (v_payment_ta, v_student_ta, v_course, v_product, v_pass_ta,
     200000, 'cash', 'completed', now() - interval '20 days', 'idem-del-502', v_owner),
    (v_payment_confirm, v_student_confirm, v_course, v_product, v_pass_confirm,
     200000, 'cash', 'completed', now() - interval '5 days', 'idem-del-503', v_owner),
    (v_payment_tb, v_student_tb, v_course, v_product, v_pass_tb,
     200000, 'cash', 'completed', now() - interval '20 days', 'idem-del-504', v_owner);

  INSERT INTO public.payment_refunds (
    id, payment_id, refunded_amount_krw, reason, actor_profile_id, pass_disposition
  ) VALUES
    (v_refund_del, v_payment_del, 50000, 'Deletion fixture refund', v_owner, 'active_cancelled_future_advance_cancelled');

  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status, message_body_snapshot
  ) VALUES
    (v_sms_del, v_student_del, v_pass_del, 'renewal_reminder', 'normal', 'Deletion fixture SMS');

  INSERT INTO public.schedule_change_requests (
    id, student_id, target_lesson_id, requesting_profile_id, request_source_role, requested_reason
  ) VALUES
    (v_scr_del, v_student_del, v_lesson_del_future, v_owner, 'owner', 'Deletion fixture schedule change request');

  INSERT INTO public.lesson_schedule_changes (
    id, lesson_id, change_origin, previous_scheduled_at, new_scheduled_at, reason, actor_profile_id
  ) VALUES
    (v_lsc_del, v_lesson_del_future, 'direct_user', now() + interval '5 days', now() + interval '6 days',
     'Deletion fixture reschedule', v_owner),
    (v_lsc_sched_future2, v_lesson_sched_future2, 'direct_user', now() + interval '8 days', now() + interval '9 days',
     'Manually moved future lesson', v_owner);

  INSERT INTO public.lesson_notes (id, lesson_id, author_profile_id, body) VALUES
    (v_note_del, v_lesson_del_past, v_owner, 'Deletion fixture lesson note');

  PERFORM set_config('test.owner', v_owner::text, false);
  PERFORM set_config('test.teacher_helper_profile', v_teacher_helper_profile::text, false);
  PERFORM set_config('test.teacher_reassign_profile', v_teacher_reassign_profile::text, false);
  PERFORM set_config('test.student_sched_profile', v_student_sched_profile::text, false);
  PERFORM set_config('test.student_del_profile', v_student_del_profile::text, false);

  PERFORM set_config('test.teacher_helper', v_teacher_helper::text, false);
  PERFORM set_config('test.teacher_replacement', v_teacher_replacement::text, false);
  PERFORM set_config('test.teacher_inactive', v_teacher_inactive::text, false);
  PERFORM set_config('test.teacher_reassign_target', v_teacher_reassign_target::text, false);
  PERFORM set_config('test.teacher_remove_target', v_teacher_remove_target::text, false);

  PERFORM set_config('test.student_sched', v_student_sched::text, false);
  PERFORM set_config('test.student_other', v_student_other::text, false);
  PERFORM set_config('test.student_stale', v_student_stale::text, false);
  PERFORM set_config('test.student_del', v_student_del::text, false);
  PERFORM set_config('test.student_confirm', v_student_confirm::text, false);
  PERFORM set_config('test.student_ta', v_student_ta::text, false);
  PERFORM set_config('test.student_tb', v_student_tb::text, false);

  PERFORM set_config('test.pass_sched', v_pass_sched::text, false);
  PERFORM set_config('test.pass_other', v_pass_other::text, false);
  PERFORM set_config('test.pass_stale', v_pass_stale::text, false);
  PERFORM set_config('test.pass_del', v_pass_del::text, false);
  PERFORM set_config('test.pass_confirm', v_pass_confirm::text, false);
  PERFORM set_config('test.pass_ta', v_pass_ta::text, false);
  PERFORM set_config('test.pass_tb', v_pass_tb::text, false);
  PERFORM set_config('test.pass_blocked', v_pass_blocked::text, false);

  PERFORM set_config('test.slot_ta', v_slot_ta::text, false);
  PERFORM set_config('test.slot_tb', v_slot_tb::text, false);

  PERFORM set_config('test.lesson_sched_future1', v_lesson_sched_future1::text, false);
  PERFORM set_config('test.lesson_sched_future2', v_lesson_sched_future2::text, false);
  PERFORM set_config('test.lesson_other_future', v_lesson_other_future::text, false);
  PERFORM set_config('test.lesson_del_past', v_lesson_del_past::text, false);
  PERFORM set_config('test.lesson_del_future', v_lesson_del_future::text, false);
  PERFORM set_config('test.lesson_ta_past', v_lesson_ta_past::text, false);
  PERFORM set_config('test.lesson_ta_future', v_lesson_ta_future::text, false);
  PERFORM set_config('test.lesson_tb_past', v_lesson_tb_past::text, false);
  PERFORM set_config('test.lesson_tb_future', v_lesson_tb_future::text, false);

  PERFORM set_config('test.payment_del', v_payment_del::text, false);
  PERFORM set_config('test.payment_ta', v_payment_ta::text, false);
  PERFORM set_config('test.payment_tb', v_payment_tb::text, false);
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

CREATE OR REPLACE FUNCTION pg_temp.audit_count()
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT count(*) FROM public.audit_logs;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pass_updated_at(p_pass uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.passes WHERE id = p_pass;
$$;

CREATE OR REPLACE FUNCTION pg_temp.student_updated_at(p_student uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.students WHERE id = p_student;
$$;

CREATE OR REPLACE FUNCTION pg_temp.teacher_updated_at(p_teacher uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT updated_at FROM public.teachers WHERE id = p_teacher;
$$;

-- ---------------------------------------------------------------------------
-- Function existence and contracts
-- ---------------------------------------------------------------------------
SELECT has_function(
  'public', 'reve_owner_preview_remove_fixed_pass_schedule', ARRAY['uuid', 'date']
);
SELECT has_function(
  'public', 'reve_owner_remove_fixed_pass_schedule',
  ARRAY['uuid', 'timestamptz', 'date', 'text', 'text', 'text']
);
SELECT has_function(
  'public', 'reve_owner_preview_delete_student', ARRAY['uuid']
);
SELECT has_function(
  'public', 'reve_owner_permanently_delete_student',
  ARRAY['uuid', 'timestamptz', 'text', 'text', 'text']
);
SELECT has_function(
  'public', 'reve_owner_preview_delete_teacher', ARRAY['uuid']
);
SELECT has_function(
  'public', 'reve_owner_permanently_delete_teacher',
  ARRAY['uuid', 'timestamptz', 'text', 'uuid', 'text', 'text', 'text']
);

-- ---------------------------------------------------------------------------
-- Grants: PUBLIC denied, authenticated allowed
-- ---------------------------------------------------------------------------
SELECT ok(
  NOT has_function_privilege(
    'public', 'public.reve_owner_preview_remove_fixed_pass_schedule(uuid,date)'::regprocedure, 'EXECUTE'
  ),
  'PUBLIC cannot execute reve_owner_preview_remove_fixed_pass_schedule'
);
SELECT ok(
  NOT has_function_privilege(
    'public', 'public.reve_owner_remove_fixed_pass_schedule(uuid,timestamptz,date,text,text,text)'::regprocedure, 'EXECUTE'
  ),
  'PUBLIC cannot execute reve_owner_remove_fixed_pass_schedule'
);
SELECT ok(
  NOT has_function_privilege(
    'public', 'public.reve_owner_preview_delete_student(uuid)'::regprocedure, 'EXECUTE'
  ),
  'PUBLIC cannot execute reve_owner_preview_delete_student'
);
SELECT ok(
  NOT has_function_privilege(
    'public', 'public.reve_owner_permanently_delete_student(uuid,timestamptz,text,text,text)'::regprocedure, 'EXECUTE'
  ),
  'PUBLIC cannot execute reve_owner_permanently_delete_student'
);
SELECT ok(
  NOT has_function_privilege(
    'public', 'public.reve_owner_preview_delete_teacher(uuid)'::regprocedure, 'EXECUTE'
  ),
  'PUBLIC cannot execute reve_owner_preview_delete_teacher'
);
SELECT ok(
  NOT has_function_privilege(
    'public', 'public.reve_owner_permanently_delete_teacher(uuid,timestamptz,text,uuid,text,text,text)'::regprocedure, 'EXECUTE'
  ),
  'PUBLIC cannot execute reve_owner_permanently_delete_teacher'
);

SELECT ok(
  has_function_privilege(
    'authenticated', 'public.reve_owner_preview_remove_fixed_pass_schedule(uuid,date)'::regprocedure, 'EXECUTE'
  ),
  'authenticated may execute reve_owner_preview_remove_fixed_pass_schedule'
);
SELECT ok(
  has_function_privilege(
    'authenticated', 'public.reve_owner_remove_fixed_pass_schedule(uuid,timestamptz,date,text,text,text)'::regprocedure, 'EXECUTE'
  ),
  'authenticated may execute reve_owner_remove_fixed_pass_schedule'
);
SELECT ok(
  has_function_privilege(
    'authenticated', 'public.reve_owner_preview_delete_student(uuid)'::regprocedure, 'EXECUTE'
  ),
  'authenticated may execute reve_owner_preview_delete_student'
);
SELECT ok(
  has_function_privilege(
    'authenticated', 'public.reve_owner_permanently_delete_student(uuid,timestamptz,text,text,text)'::regprocedure, 'EXECUTE'
  ),
  'authenticated may execute reve_owner_permanently_delete_student'
);
SELECT ok(
  has_function_privilege(
    'authenticated', 'public.reve_owner_preview_delete_teacher(uuid)'::regprocedure, 'EXECUTE'
  ),
  'authenticated may execute reve_owner_preview_delete_teacher'
);
SELECT ok(
  has_function_privilege(
    'authenticated', 'public.reve_owner_permanently_delete_teacher(uuid,timestamptz,text,uuid,text,text,text)'::regprocedure, 'EXECUTE'
  ),
  'authenticated may execute reve_owner_permanently_delete_teacher'
);

-- ---------------------------------------------------------------------------
-- Unauthorized: anon (no EXECUTE grant) and non-owner authenticated caller
-- ---------------------------------------------------------------------------
SET ROLE anon;
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_remove_fixed_pass_schedule(
       current_setting('test.pass_sched')::uuid, NULL) $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_sched')::uuid, now(), NULL, 'x', 'x', 'x') $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_delete_student(current_setting('test.student_del')::uuid) $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_student(
       current_setting('test.student_del')::uuid, now(), 'x', 'x', 'x') $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_delete_teacher(current_setting('test.teacher_reassign_target')::uuid) $$,
  '42501'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_teacher(
       current_setting('test.teacher_reassign_target')::uuid, now(), 'reassign',
       current_setting('test.teacher_replacement')::uuid, 'x', 'x', 'x') $$,
  '42501'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.teacher_helper_profile')::uuid); END $$;
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_remove_fixed_pass_schedule(
       current_setting('test.pass_sched')::uuid, NULL) $$,
  '42501', 'REVE_UNAUTHORIZED'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_sched')::uuid, now(), NULL, 'x', 'x', 'x') $$,
  '42501', 'REVE_UNAUTHORIZED'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_delete_student(current_setting('test.student_del')::uuid) $$,
  '42501', 'REVE_UNAUTHORIZED'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_student(
       current_setting('test.student_del')::uuid, now(), 'x', 'x', 'x') $$,
  '42501', 'REVE_UNAUTHORIZED'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_preview_delete_teacher(current_setting('test.teacher_reassign_target')::uuid) $$,
  '42501', 'REVE_UNAUTHORIZED'
);
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_teacher(
       current_setting('test.teacher_reassign_target')::uuid, now(), 'reassign',
       current_setting('test.teacher_replacement')::uuid, 'x', 'x', 'x') $$,
  '42501', 'REVE_UNAUTHORIZED'
);
DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- ===========================================================================
-- Fixed pass-schedule removal
-- ===========================================================================
DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner')::uuid); END $$;

-- Preview: active slots, future lessons, one manually moved
SELECT ok(
  (
    SELECT student_code = 'SCH501'
      AND pass_code = 'V-SCH501-001'
      AND pass_status = 'active'
      AND active_slot_count = 2
      AND future_timetable_lesson_count = 2
      AND manually_moved_future_lesson_count = 1
      AND preserved_past_lesson_count = 0
      AND preserved_completed_lesson_count = 2
      AND array_length(blockers, 1) IS NULL
      AND array_length(warnings, 1) >= 1
    FROM public.reve_owner_preview_remove_fixed_pass_schedule(
      current_setting('test.pass_sched')::uuid, CURRENT_DATE
    )
  ),
  'schedule removal preview reports active slots, future lesson counts, and manual-move warning'
);

-- Execute: removes active slots, advance_cancels future lessons, preserves history
SELECT ok(
  (
    SELECT pass_id = current_setting('test.pass_sched')::uuid
      AND removed_schedule_slot_count = 2
      AND removed_or_cancelled_future_lesson_count = 2
      AND preserved_past_lesson_count = 0
      AND preserved_completed_lesson_count = 2
      AND no_change = false
    FROM public.reve_owner_remove_fixed_pass_schedule(
      current_setting('test.pass_sched')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_sched')::uuid),
      CURRENT_DATE,
      'Owner requested fixed schedule removal',
      (SELECT pass_code || ' 스케줄삭제' FROM public.passes WHERE id = current_setting('test.pass_sched')::uuid),
      (SELECT preflight_fingerprint FROM public.reve_owner_preview_remove_fixed_pass_schedule(
        current_setting('test.pass_sched')::uuid, CURRENT_DATE
      ))
    )
  ),
  'schedule removal execute deactivates slots and processes future lessons'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.schedule_slots
    WHERE pass_id = current_setting('test.pass_sched')::uuid AND is_active = true
  ),
  'all active schedule slots deactivated on the target pass'
);

SELECT ok(
  (
    SELECT bool_and(status = 'advance_cancelled' AND change_reason IS NOT NULL)
    FROM public.lessons
    WHERE id IN (
      current_setting('test.lesson_sched_future1')::uuid,
      current_setting('test.lesson_sched_future2')::uuid
    )
  ),
  'both future lessons on the pass are advance_cancelled with a change reason'
);

SELECT ok(
  (
    SELECT bool_and(status = 'completed')
    FROM public.lessons
    WHERE pass_id = current_setting('test.pass_sched')::uuid
      AND status = 'completed'
  ) AND (
    SELECT count(*)::integer FROM public.lessons
    WHERE pass_id = current_setting('test.pass_sched')::uuid AND status = 'completed'
  ) = 2,
  'past completed lessons remain untouched after schedule removal'
);

-- Idempotent no_change: re-preview then re-execute with nothing left to remove
SELECT ok(
  (
    SELECT active_slot_count = 0 AND array_length(warnings, 1) >= 1
    FROM public.reve_owner_preview_remove_fixed_pass_schedule(
      current_setting('test.pass_sched')::uuid, CURRENT_DATE
    )
  ),
  're-preview after removal shows zero active slots with a warning'
);

DO $$
DECLARE
  v_before_audit bigint := pg_temp.audit_count();
BEGIN
  PERFORM set_config('test.audit_before_idem_schedule', v_before_audit::text, false);
END $$;

SELECT ok(
  (
    SELECT no_change = true
      AND removed_schedule_slot_count = 0
      AND removed_or_cancelled_future_lesson_count = 0
    FROM public.reve_owner_remove_fixed_pass_schedule(
      current_setting('test.pass_sched')::uuid,
      pg_temp.pass_updated_at(current_setting('test.pass_sched')::uuid),
      CURRENT_DATE,
      'Owner re-runs removal with nothing left',
      (SELECT pass_code || ' 스케줄삭제' FROM public.passes WHERE id = current_setting('test.pass_sched')::uuid),
      (SELECT preflight_fingerprint FROM public.reve_owner_preview_remove_fixed_pass_schedule(
        current_setting('test.pass_sched')::uuid, CURRENT_DATE
      ))
    )
  ),
  'idempotent re-execution reports no_change without side effects'
);

SELECT ok(
  pg_temp.audit_count() = current_setting('test.audit_before_idem_schedule')::bigint,
  'idempotent no_change re-execution adds no new audit rows'
);

-- Audit correlation
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'pass.fixed_schedule_removed'
      AND resource_table = 'passes'
      AND resource_id = current_setting('test.pass_sched')::uuid
      AND correlation_id IS NOT NULL
  ),
  'schedule removal writes a pass.fixed_schedule_removed audit row with a correlation id'
);

SELECT ok(
  (
    SELECT count(*)::integer FROM public.audit_logs AS lesson_audit
    JOIN public.audit_logs AS pass_audit ON pass_audit.correlation_id = lesson_audit.correlation_id
    WHERE pass_audit.action = 'pass.fixed_schedule_removed'
      AND pass_audit.resource_id = current_setting('test.pass_sched')::uuid
      AND lesson_audit.action = 'lesson.status_transition'
      AND lesson_audit.resource_id IN (
        current_setting('test.lesson_sched_future1')::uuid,
        current_setting('test.lesson_sched_future2')::uuid
      )
  ) = 2,
  'both cancelled-lesson audit rows share the schedule removal correlation id'
);

-- Other student unaffected
SELECT ok(
  (
    SELECT ss.is_active = true
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = current_setting('test.pass_other')::uuid
  ) AND (
    SELECT l.status = 'scheduled'
    FROM public.lessons AS l
    WHERE l.id = current_setting('test.lesson_other_future')::uuid
  ),
  'other student pass schedule slot and future lesson remain unchanged'
);

-- Validation failures
SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_stale')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       CURRENT_DATE, 'reason', 'bogus', 'bogus') $$,
  '22000', 'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_blocked')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_blocked')::uuid),
       CURRENT_DATE, 'reason', 'bogus', 'bogus') $$,
  'P0001', 'REVE_DELETION_BLOCKED'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_stale')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_stale')::uuid),
       CURRENT_DATE, '', 'bogus', 'bogus') $$,
  'P0001', 'REVE_REASON_REQUIRED'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_stale')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_stale')::uuid),
       CURRENT_DATE, 'reason', 'not the phrase', 'bogus') $$,
  'P0001', 'REVE_CONFIRMATION_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_remove_fixed_pass_schedule(
       current_setting('test.pass_stale')::uuid,
       pg_temp.pass_updated_at(current_setting('test.pass_stale')::uuid),
       CURRENT_DATE, 'reason',
       (SELECT pass_code || ' 스케줄삭제' FROM public.passes WHERE id = current_setting('test.pass_stale')::uuid),
       'bogus-fingerprint') $$,
  'P0001', 'REVE_PREFLIGHT_MISMATCH'
);

-- ===========================================================================
-- Student permanent deletion
-- ===========================================================================
SELECT ok(
  (
    SELECT student_code = 'DEL501'
      AND operational_status = 'active'
      AND auth_user_exists = true
      AND lesson_count = 2
      AND pass_count = 1
      AND payment_count = 1
      AND payment_refund_count = 1
      AND sms_notification_count = 1
      AND schedule_slot_count = 1
      AND lesson_note_count = 1
      AND schedule_change_request_count = 1
      AND lesson_schedule_change_count = 1
      AND array_length(warnings, 1) >= 1
    FROM public.reve_owner_preview_delete_student(current_setting('test.student_del')::uuid)
  ),
  'student deletion preview reports full dependent-row counts and warnings'
);

DO $$
DECLARE
  v_preview record;
BEGIN
  SELECT * INTO v_preview
  FROM public.reve_owner_preview_delete_student(current_setting('test.student_confirm')::uuid);

  PERFORM set_config('test.confirm_updated_at', v_preview.updated_at::text, false);
  PERFORM set_config('test.confirm_fingerprint', v_preview.preflight_fingerprint, false);
END $$;

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_student(
       current_setting('test.student_confirm')::uuid,
       current_setting('test.confirm_updated_at')::timestamptz,
       'CFM501 영구삭제', '', current_setting('test.confirm_fingerprint')) $$,
  'P0001', 'REVE_REASON_REQUIRED'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_student(
       current_setting('test.student_confirm')::uuid,
       current_setting('test.confirm_updated_at')::timestamptz,
       'wrong phrase', 'valid reason', current_setting('test.confirm_fingerprint')) $$,
  'P0001', 'REVE_CONFIRMATION_MISMATCH'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_student(
       current_setting('test.student_confirm')::uuid,
       timestamptz '2000-01-01 00:00:00+00',
       'CFM501 영구삭제', 'valid reason', current_setting('test.confirm_fingerprint')) $$,
  '22000', 'REVE_STALE_STATE'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_student(
       current_setting('test.student_confirm')::uuid,
       current_setting('test.confirm_updated_at')::timestamptz,
       'CFM501 영구삭제', 'valid reason', 'bogus-fingerprint') $$,
  'P0001', 'REVE_PREFLIGHT_MISMATCH'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.students WHERE id = current_setting('test.student_confirm')::uuid) = 1,
  'student with rejected deletion attempts still exists'
);

DO $$
DECLARE
  v_preview record;
BEGIN
  SELECT * INTO v_preview
  FROM public.reve_owner_preview_delete_student(current_setting('test.student_del')::uuid);

  PERFORM set_config('test.del_updated_at', v_preview.updated_at::text, false);
  PERFORM set_config('test.del_fingerprint', v_preview.preflight_fingerprint, false);
END $$;

SELECT ok(
  (
    SELECT already_deleted = false
      AND deleted_lesson_count = 2
      AND deleted_pass_count = 1
      AND deleted_payment_count = 1
      AND deleted_payment_refund_count = 1
      AND deleted_sms_notification_count = 1
      AND deleted_schedule_slot_count = 1
      AND deleted_lesson_note_count = 1
      AND deleted_schedule_change_request_count = 1
      AND deleted_lesson_schedule_change_count = 1
      AND profile_deleted = true
      AND auth_user_id = current_setting('test.student_del_profile')::uuid
    FROM public.reve_owner_permanently_delete_student(
      current_setting('test.student_del')::uuid,
      current_setting('test.del_updated_at')::timestamptz,
      'DEL501 영구삭제',
      'Owner requested permanent deletion',
      current_setting('test.del_fingerprint')
    )
  ),
  'student permanent deletion returns matching deleted-row counts and profile disposition'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.students WHERE id = current_setting('test.student_del')::uuid) = 0
    AND (SELECT count(*)::integer FROM public.passes WHERE student_id = current_setting('test.student_del')::uuid) = 0
    AND (SELECT count(*)::integer FROM public.lessons WHERE student_id = current_setting('test.student_del')::uuid) = 0
    AND (SELECT count(*)::integer FROM public.payments WHERE student_id = current_setting('test.student_del')::uuid) = 0,
  'student, passes, lessons, and payments are physically removed'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.sms_notifications WHERE student_id = current_setting('test.student_del')::uuid) = 0
    AND (SELECT count(*)::integer FROM public.lesson_notes WHERE lesson_id = current_setting('test.lesson_del_past')::uuid) = 0
    AND (SELECT count(*)::integer FROM public.schedule_change_requests WHERE student_id = current_setting('test.student_del')::uuid) = 0
    AND (SELECT count(*)::integer FROM public.lesson_schedule_changes WHERE lesson_id = current_setting('test.lesson_del_future')::uuid) = 0
    AND (SELECT count(*)::integer FROM public.payment_refunds WHERE payment_id = current_setting('test.payment_del')::uuid) = 0,
  'sms, lesson notes, schedule change requests, lesson schedule changes, and refunds are removed'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.profiles WHERE id = current_setting('test.student_del_profile')::uuid) = 0,
  'linked profile row is removed with the student'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'student.permanently_deleted'
      AND resource_table = 'students'
      AND resource_id = current_setting('test.student_del')::uuid
      AND previous_value->>'student_code' = 'DEL501'
      AND previous_value::text NOT ILIKE '%PII Name%'
      AND new_value IS NULL
  ),
  'student tombstone audit row retains student_code but omits the PII display name'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action = 'profile.deleted_with_student'
      AND resource_table = 'profiles'
      AND resource_id = current_setting('test.student_del_profile')::uuid
  ),
  'linked profile deletion writes its own audit row'
);

DO $$
DECLARE
  v_before_audit bigint := pg_temp.audit_count();
BEGIN
  PERFORM set_config('test.audit_before_idem_student', v_before_audit::text, false);
END $$;

SELECT ok(
  (
    SELECT already_deleted = true
      AND deleted_lesson_count = 0
      AND deleted_pass_count = 0
      AND deleted_payment_count = 0
      AND profile_deleted = false
      AND auth_user_id IS NULL
    FROM public.reve_owner_permanently_delete_student(
      current_setting('test.student_del')::uuid,
      current_setting('test.del_updated_at')::timestamptz,
      'DEL501 영구삭제',
      'Owner retries after already deleted',
      current_setting('test.del_fingerprint')
    )
  ),
  'idempotent replay on an already-deleted student reports already_deleted with zero counts'
);

SELECT ok(
  pg_temp.audit_count() = current_setting('test.audit_before_idem_student')::bigint,
  'idempotent student-deletion replay adds no new audit rows'
);

-- ===========================================================================
-- Teacher permanent deletion — reassign mode
-- ===========================================================================
SELECT ok(
  (
    SELECT teacher_code = 'T-RSN501'
      AND is_active = true
      AND auth_user_exists = true
      AND total_lesson_count = 2
      AND future_eligible_lesson_count = 1
      AND past_deductible_lesson_count = 1
      AND active_schedule_slot_count = 1
      AND total_schedule_slot_count = 1
      AND array_length(warnings, 1) >= 1
    FROM public.reve_owner_preview_delete_teacher(current_setting('test.teacher_reassign_target')::uuid)
  ),
  'teacher deletion preview (reassign target) reports lesson and slot counts'
);

DO $$
DECLARE
  v_preview record;
BEGIN
  SELECT * INTO v_preview
  FROM public.reve_owner_preview_delete_teacher(current_setting('test.teacher_reassign_target')::uuid);

  PERFORM set_config('test.reassign_updated_at', v_preview.updated_at::text, false);
  PERFORM set_config('test.reassign_fingerprint', v_preview.preflight_fingerprint, false);
END $$;

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_teacher(
       current_setting('test.teacher_reassign_target')::uuid,
       current_setting('test.reassign_updated_at')::timestamptz,
       'bogus_mode', NULL,
       'T-RSN501 영구삭제', 'reason', current_setting('test.reassign_fingerprint')) $$,
  'P0001', 'REVE_INVALID_LINK_HANDLING'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_teacher(
       current_setting('test.teacher_reassign_target')::uuid,
       current_setting('test.reassign_updated_at')::timestamptz,
       'reassign', NULL,
       'T-RSN501 영구삭제', 'reason', current_setting('test.reassign_fingerprint')) $$,
  'P0001', 'REVE_REPLACEMENT_TEACHER_INVALID'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_teacher(
       current_setting('test.teacher_reassign_target')::uuid,
       current_setting('test.reassign_updated_at')::timestamptz,
       'reassign', current_setting('test.teacher_reassign_target')::uuid,
       'T-RSN501 영구삭제', 'reason', current_setting('test.reassign_fingerprint')) $$,
  'P0001', 'REVE_REPLACEMENT_TEACHER_INVALID'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_teacher(
       current_setting('test.teacher_reassign_target')::uuid,
       current_setting('test.reassign_updated_at')::timestamptz,
       'reassign', current_setting('test.teacher_inactive')::uuid,
       'T-RSN501 영구삭제', 'reason', current_setting('test.reassign_fingerprint')) $$,
  'P0001', 'REVE_REPLACEMENT_TEACHER_INVALID'
);

SELECT throws_ok(
  $$ SELECT * FROM public.reve_owner_permanently_delete_teacher(
       current_setting('test.teacher_reassign_target')::uuid,
       current_setting('test.reassign_updated_at')::timestamptz,
       'remove_future_schedule', current_setting('test.teacher_replacement')::uuid,
       'T-RSN501 영구삭제', 'reason', current_setting('test.reassign_fingerprint')) $$,
  'P0001', 'REVE_REPLACEMENT_TEACHER_INVALID'
);

SELECT ok(
  (
    SELECT already_deleted = false
      AND link_handling_mode = 'reassign'
      AND future_reassigned_lesson_count = 1
      AND future_cancelled_lesson_count = 0
      AND reassigned_active_slot_count = 1
      AND snapshotted_lesson_count = 1
      AND deleted_schedule_slot_count = 0
      AND profile_deleted = false
      AND auth_user_id IS NOT NULL
    FROM public.reve_owner_permanently_delete_teacher(
      current_setting('test.teacher_reassign_target')::uuid,
      current_setting('test.reassign_updated_at')::timestamptz,
      'reassign', current_setting('test.teacher_replacement')::uuid,
      'T-RSN501 영구삭제', 'Owner reassigns to replacement teacher',
      current_setting('test.reassign_fingerprint')
    )
  ),
  'reassign-mode deletion reassigns future lessons and active slots, snapshots history'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.teachers WHERE id = current_setting('test.teacher_reassign_target')::uuid) = 0,
  'reassign target teacher row is physically removed'
);

SELECT ok(
  (
    SELECT teacher_id = current_setting('test.teacher_replacement')::uuid AND is_active = true
    FROM public.schedule_slots WHERE id = current_setting('test.slot_ta')::uuid
  ),
  'active schedule slot is reassigned to the replacement teacher and stays active'
);

SELECT ok(
  (
    SELECT assigned_teacher_id = current_setting('test.teacher_replacement')::uuid
      AND assigned_teacher_name_snapshot IS NULL
    FROM public.lessons WHERE id = current_setting('test.lesson_ta_future')::uuid
  ),
  'future eligible lesson is reassigned to the replacement teacher without a name snapshot'
);

SELECT ok(
  (
    SELECT assigned_teacher_id IS NULL AND assigned_teacher_name_snapshot = 'Reassign Target Teacher'
    FROM public.lessons WHERE id = current_setting('test.lesson_ta_past')::uuid
  ),
  'past completed lesson keeps a teacher-name history snapshot and clears the FK'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.students WHERE id = current_setting('test.student_ta')::uuid) = 1
    AND (SELECT count(*)::integer FROM public.passes WHERE id = current_setting('test.pass_ta')::uuid) = 1
    AND (SELECT count(*)::integer FROM public.payments WHERE id = current_setting('test.payment_ta')::uuid) = 1,
  'reassign-mode teacher deletion preserves the student, pass, and payment'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.profiles WHERE id = current_setting('test.teacher_reassign_profile')::uuid) = 1,
  'reassign target teacher profile row is intentionally preserved (not deleted with the teacher row)'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.profiles WHERE id = current_setting('test.teacher_helper_profile')::uuid) = 1,
  'unrelated helper teacher profile remains present'
);

DO $$
DECLARE
  v_before_audit bigint := pg_temp.audit_count();
BEGIN
  PERFORM set_config('test.audit_before_idem_teacher', v_before_audit::text, false);
END $$;

SELECT ok(
  (
    SELECT already_deleted = true
      AND link_handling_mode = 'reassign'
      AND future_reassigned_lesson_count = 0
      AND future_cancelled_lesson_count = 0
      AND deleted_schedule_slot_count = 0
      AND profile_deleted = false
      AND auth_user_id IS NULL
    FROM public.reve_owner_permanently_delete_teacher(
      current_setting('test.teacher_reassign_target')::uuid,
      current_setting('test.reassign_updated_at')::timestamptz,
      'reassign', current_setting('test.teacher_replacement')::uuid,
      'T-RSN501 영구삭제', 'Owner retries after already deleted',
      current_setting('test.reassign_fingerprint')
    )
  ),
  'idempotent replay on an already-deleted teacher reports already_deleted with zero counts'
);

SELECT ok(
  pg_temp.audit_count() = current_setting('test.audit_before_idem_teacher')::bigint,
  'idempotent teacher-deletion replay adds no new audit rows'
);

-- ===========================================================================
-- Teacher permanent deletion — remove_future_schedule mode
-- ===========================================================================
SELECT ok(
  (
    SELECT teacher_code = 'T-RMV501'
      AND total_lesson_count = 2
      AND future_eligible_lesson_count = 1
      AND past_deductible_lesson_count = 1
      AND active_schedule_slot_count = 1
    FROM public.reve_owner_preview_delete_teacher(current_setting('test.teacher_remove_target')::uuid)
  ),
  'teacher deletion preview (remove_future_schedule target) reports lesson and slot counts'
);

DO $$
DECLARE
  v_preview record;
BEGIN
  SELECT * INTO v_preview
  FROM public.reve_owner_preview_delete_teacher(current_setting('test.teacher_remove_target')::uuid);

  PERFORM set_config('test.remove_updated_at', v_preview.updated_at::text, false);
  PERFORM set_config('test.remove_fingerprint', v_preview.preflight_fingerprint, false);
END $$;

SELECT ok(
  (
    SELECT already_deleted = false
      AND link_handling_mode = 'remove_future_schedule'
      AND future_reassigned_lesson_count = 0
      AND future_cancelled_lesson_count = 1
      AND reassigned_active_slot_count = 0
      AND snapshotted_lesson_count = 2
      AND deleted_schedule_slot_count = 1
      AND profile_deleted = false
      AND auth_user_id IS NULL
    FROM public.reve_owner_permanently_delete_teacher(
      current_setting('test.teacher_remove_target')::uuid,
      current_setting('test.remove_updated_at')::timestamptz,
      'remove_future_schedule', NULL,
      'T-RMV501 영구삭제', 'Owner removes future schedule instead of reassigning',
      current_setting('test.remove_fingerprint')
    )
  ),
  'remove_future_schedule-mode deletion cancels future lessons and deletes schedule slots'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.teachers WHERE id = current_setting('test.teacher_remove_target')::uuid) = 0,
  'remove-mode target teacher row is physically removed'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.schedule_slots WHERE teacher_id = current_setting('test.teacher_remove_target')::uuid) = 0,
  'all schedule slots for the removed teacher are physically deleted'
);

SELECT ok(
  (
    SELECT status = 'advance_cancelled'
      AND assigned_teacher_id IS NULL
      AND assigned_teacher_name_snapshot = 'Remove Target Teacher'
    FROM public.lessons WHERE id = current_setting('test.lesson_tb_future')::uuid
  ),
  'future lesson is advance_cancelled and snapshotted as history (remove_future_schedule mode)'
);

SELECT ok(
  (
    SELECT status = 'completed'
      AND assigned_teacher_id IS NULL
      AND assigned_teacher_name_snapshot = 'Remove Target Teacher'
    FROM public.lessons WHERE id = current_setting('test.lesson_tb_past')::uuid
  ),
  'past completed lesson keeps its status and gains a teacher-name history snapshot'
);

SELECT ok(
  (SELECT count(*)::integer FROM public.students WHERE id = current_setting('test.student_tb')::uuid) = 1
    AND (SELECT count(*)::integer FROM public.passes WHERE id = current_setting('test.pass_tb')::uuid) = 1
    AND (SELECT count(*)::integer FROM public.payments WHERE id = current_setting('test.payment_tb')::uuid) = 1,
  'remove_future_schedule-mode teacher deletion preserves the student, pass, and payment'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_logs AS lesson_audit
    JOIN public.audit_logs AS teacher_audit ON teacher_audit.correlation_id = lesson_audit.correlation_id
    WHERE teacher_audit.action = 'teacher.permanently_deleted'
      AND teacher_audit.resource_id = current_setting('test.teacher_remove_target')::uuid
      AND lesson_audit.action = 'lesson.status_transition'
      AND lesson_audit.resource_id = current_setting('test.lesson_tb_future')::uuid
  ),
  'teacher deletion audit row shares a correlation id with the cancelled-lesson audit row'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

-- auth.users is not selectable as 'authenticated'; verify preserved auth users as the test runner role.
SELECT ok(
  (SELECT count(*)::integer FROM auth.users WHERE id = current_setting('test.student_del_profile')::uuid) = 1,
  'underlying auth.users row for the deleted student profile is preserved for separate owner access revocation'
);

SELECT ok(
  (SELECT count(*)::integer FROM auth.users WHERE id = current_setting('test.teacher_reassign_profile')::uuid) = 1,
  'underlying auth.users row for the reassign target teacher profile is intentionally preserved'
);

SELECT * FROM finish();
ROLLBACK;

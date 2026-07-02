-- REVE ACADEMY OS Phase 0B-3B-2B-3E — Owner payment refund pgTAP tests

BEGIN;

SELECT plan(28);

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa041';
  v_teacher uuid := 'dddddddd-dddd-dddd-dddd-ddddddddd041';
  v_student uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbb041';
  v_teacher_row uuid := '22222222-2222-2222-2222-222222222041';
  v_student_row uuid := '44444444-4444-4444-4444-444444444041';
  v_student_row2 uuid := '44444444-4444-4444-4444-444444444042';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee41';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-ffffffffff41';
  v_pass_reserved uuid := '66666666-6666-6666-6666-666666666041';
  v_pass_active uuid := '66666666-6666-6666-6666-666666666042';
  v_slot uuid := '77777777-7777-7777-7777-777777777741';
  v_lesson_c1 uuid := '99999999-9999-9999-9999-999999999941';
  v_lesson_c2 uuid := '99999999-9999-9999-9999-999999999942';
  v_lesson_f1 uuid := '99999999-9999-9999-9999-999999999943';
  v_lesson_f2 uuid := '99999999-9999-9999-9999-999999999944';
  v_lesson_past_nc uuid := '99999999-9999-9999-9999-999999999945';
  v_payment_reserved uuid := '12121212-1212-1212-1212-121212121241';
  v_payment_active uuid := '12121212-1212-1212-1212-121212121242';
  v_payment_pending uuid := '12121212-1212-1212-1212-121212121243';
  v_payment_bad_amt uuid := '12121212-1212-1212-1212-121212121244';
  v_pass_bad_amt uuid := '66666666-6666-6666-6666-666666666043';
  v_sms_active uuid := '88888888-8888-8888-8888-888888888041';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner-refund@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'teacher-refund@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_student, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'student-refund@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_owner, 'owner', 'Refund Owner', 'active'),
    (v_teacher, 'teacher', 'Refund Teacher', 'active'),
    (v_student, 'student', 'Refund Student', 'active');

  INSERT INTO public.teachers (id, teacher_code, profile_id, name, is_active) VALUES
    (v_teacher_row, 'T-RF', v_teacher, 'Refund Teacher', true);

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status) VALUES
    (v_student_row, 'S041', v_student, 'Refund Student', 'active'),
    (v_student_row2, 'S042', NULL, 'Refund Student B', 'active');

  INSERT INTO public.courses (id, course_code, name, is_active) VALUES
    (v_course, 'VOC-RF', 'Refund Course', true);

  INSERT INTO public.course_products (
    id, course_id, product_code, product_name,
    default_lesson_count, weekly_frequency, default_tuition_krw, is_active
  ) VALUES (
    v_product, v_course, 'VOC-4-RF', 'Refund Product', 4, 1, 200000, true
  );

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at
  ) VALUES
    (
      v_pass_reserved, 'V-S041-R01', v_student_row, v_course, v_product,
      1, 'reserved', 4, 1, 'Refund Product', 200000,
      DATE '2026-10-01', NULL
    ),
    (
      v_pass_active, 'V-S041-A01', v_student_row, v_course, v_product,
      2, 'active', 4, 1, 'Refund Product', 200000,
      DATE '2026-08-01', now() - interval '60 days'
    ),
    (
      v_pass_bad_amt, 'V-S042-A01', v_student_row2, v_course, v_product,
      1, 'active', 4, 1, 'Refund Product', 200000,
      DATE '2026-09-01', now() - interval '30 days'
    );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES (
    v_slot, v_pass_active, v_teacher_row, 1, TIME '10:00', 60, 1, true, DATE '2026-08-01'
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
    sequence_number, scheduled_at, status
  ) VALUES
    (v_lesson_c1, v_pass_active, v_student_row, v_course, v_teacher_row, v_slot,
      1, now() - interval '30 days', 'completed'),
    (v_lesson_c2, v_pass_active, v_student_row, v_course, v_teacher_row, v_slot,
      2, now() - interval '20 days', 'completed'),
    (v_lesson_past_nc, v_pass_active, v_student_row, v_course, v_teacher_row, v_slot,
      3, now() - interval '10 days', 'teacher_cancelled'),
    (v_lesson_f1, v_pass_active, v_student_row, v_course, v_teacher_row, v_slot,
      4, now() + interval '7 days', 'scheduled'),
    (v_lesson_f2, v_pass_active, v_student_row, v_course, v_teacher_row, v_slot,
      5, now() + interval '14 days', 'scheduled');

  INSERT INTO public.payments (
    id, student_id, course_id, course_product_id, related_pass_id, renewed_pass_id,
    paid_amount_krw, payment_method, status, paid_at, idempotency_key, processed_at
  ) VALUES
    (
      v_payment_reserved, v_student_row, v_course, v_product, NULL, v_pass_reserved,
      200000, 'card', 'completed', now() - interval '5 days', 'refund-reserved-key', now()
    ),
    (
      v_payment_active, v_student_row, v_course, v_product, v_pass_reserved, v_pass_active,
      200000, 'card', 'completed', now() - interval '55 days', 'refund-active-key', now()
    ),
    (
      v_payment_pending, v_student_row, v_course, v_product, NULL, NULL,
      200000, NULL, 'pending', NULL, 'refund-pending-key', NULL
    ),
    (
      v_payment_bad_amt, v_student_row2, v_course, v_product, NULL, v_pass_bad_amt,
      200000, 'card', 'completed', now() - interval '20 days', 'refund-bad-amt-key', now()
    );

  INSERT INTO public.sms_notifications (
    id, student_id, pass_id, notification_type, status, message_body_snapshot, target_date
  ) VALUES (
    v_sms_active, v_student_row, v_pass_active, 'renewal_reminder', 'normal',
    'Refund test SMS', CURRENT_DATE + 7
  );

  PERFORM set_config('test.owner', v_owner::text, true);
  PERFORM set_config('test.teacher', v_teacher::text, true);
  PERFORM set_config('test.student', v_student::text, true);
  PERFORM set_config('test.payment_reserved', v_payment_reserved::text, true);
  PERFORM set_config('test.payment_active', v_payment_active::text, true);
  PERFORM set_config('test.payment_pending', v_payment_pending::text, true);
  PERFORM set_config('test.payment_bad_amt', v_payment_bad_amt::text, true);
  PERFORM set_config('test.pass_reserved', v_pass_reserved::text, true);
  PERFORM set_config('test.pass_active', v_pass_active::text, true);
  PERFORM set_config('test.lesson_c1', v_lesson_c1::text, true);
  PERFORM set_config('test.lesson_c2', v_lesson_c2::text, true);
  PERFORM set_config('test.lesson_f1', v_lesson_f1::text, true);
  PERFORM set_config('test.lesson_f2', v_lesson_f2::text, true);
  PERFORM set_config('test.lesson_past_nc', v_lesson_past_nc::text, true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.refund_as(p_user uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  PERFORM set_config('role', 'authenticated', false);
END $$;

SELECT has_function(
  'public', 'reve_process_payment_refund',
  ARRAY['uuid', 'integer', 'text'],
  'reve_process_payment_refund exists with expected signature'
);

SELECT ok(
  NOT has_function_privilege('public', 'public.reve_process_payment_refund(uuid, integer, text)', 'EXECUTE'),
  'PUBLIC cannot execute reve_process_payment_refund'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.reve_process_payment_refund(uuid, integer, text)', 'EXECUTE'),
  'authenticated may execute reve_process_payment_refund'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.teacher')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_active')::uuid, 200000, 'teacher attempt'
     ); $$,
  '42501',
  'REVE_UNAUTHORIZED',
  'teacher cannot process payment refund'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.student')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_active')::uuid, 200000, 'student attempt'
     ); $$,
  '42501',
  'REVE_UNAUTHORIZED',
  'student cannot process payment refund'
);

SELECT throws_ok(
  $$ SELECT set_config('request.jwt.claim.sub', '', false);
     SELECT set_config('request.jwt.claim.role', '', false);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_active')::uuid, 200000, 'anon attempt'
     ); $$,
  '42501',
  'REVE_UNAUTHORIZED',
  'unauthenticated caller cannot process payment refund'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_active')::uuid, 200000, '   '
     ); $$,
  'P0001',
  'REVE_REASON_REQUIRED',
  'empty refund reason is rejected'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_pending')::uuid, 200000, 'pending payment'
     ); $$,
  'P0001',
  'REVE_PAYMENT_NOT_REFUNDABLE',
  'pending payment cannot be refunded'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_bad_amt')::uuid, 100000, 'wrong amount'
     ); $$,
  'P0001',
  'REVE_REFUND_AMOUNT_MISMATCH',
  'partial refund amount is rejected'
);

SELECT is(
  (SELECT count(*)::integer FROM public.payment_refunds WHERE payment_id = current_setting('test.payment_pending')::uuid),
  0,
  'failed refund leaves no refund row'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     INSERT INTO public.payment_refunds (
       payment_id, refunded_amount_krw, reason, actor_profile_id, pass_disposition
     ) VALUES (
       current_setting('test.payment_pending')::uuid,
       200000, 'direct insert', current_setting('test.owner')::uuid, 'reserved_cancelled'
     ); $$,
  '42501',
  NULL,
  'direct client insert into payment_refunds remains denied'
);

SELECT lives_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_reserved')::uuid, 200000, 'Reserved pass refund'
     ); $$,
  'owner reserved pass refund succeeds'
);

SELECT is(
  (SELECT status FROM public.payments WHERE id = current_setting('test.payment_reserved')::uuid),
  'refunded',
  'reserved refund sets payment status refunded'
);

SELECT is(
  (SELECT status FROM public.passes WHERE id = current_setting('test.pass_reserved')::uuid),
  'cancelled',
  'reserved refund cancels pass'
);

SELECT is(
  (SELECT pass_disposition FROM public.payment_refunds WHERE payment_id = current_setting('test.payment_reserved')::uuid),
  'reserved_cancelled',
  'reserved refund disposition recorded'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_activate_reserved_pass(
       current_setting('test.pass_reserved')::uuid,
       (SELECT updated_at FROM public.passes WHERE id = current_setting('test.pass_reserved')::uuid),
       'attempt after refund'
     ); $$,
  'P0001',
  NULL,
  'cancelled reserved pass cannot activate after refund'
);

SELECT lives_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_active')::uuid, 200000, 'Active pass full refund'
     ); $$,
  'owner active pass refund succeeds'
);

SELECT is(
  (SELECT count(*)::integer
   FROM public.payment_refunds
   WHERE payment_id = current_setting('test.payment_active')::uuid),
  1,
  'exactly one refund row exists for active payment after refund'
);

SELECT is(
  (SELECT count(*)::integer
   FROM public.payment_refunds
   WHERE payment_id = current_setting('test.payment_reserved')::uuid),
  1,
  'exactly one refund row exists for reserved payment after refund'
);

SELECT is(
  (SELECT status FROM public.lessons WHERE id = current_setting('test.lesson_c1')::uuid),
  'completed',
  'deductible completed lesson unchanged after active refund'
);

SELECT is(
  (SELECT status FROM public.lessons WHERE id = current_setting('test.lesson_c2')::uuid),
  'completed',
  'second completed lesson unchanged after active refund'
);

SELECT is(
  (SELECT status FROM public.lessons WHERE id = current_setting('test.lesson_past_nc')::uuid),
  'teacher_cancelled',
  'past non-deducted lesson unchanged after active refund'
);

SELECT is(
  (SELECT count(*)::integer
   FROM public.lessons
   WHERE pass_id = current_setting('test.pass_active')::uuid
     AND status = 'advance_cancelled'),
  2,
  'future non-deducted lessons become advance_cancelled'
);

DO $$ BEGIN RESET ROLE; END $$;

SELECT is(
  (SELECT used_lesson_count FROM reve_private.calculate_pass_usage(current_setting('test.pass_active')::uuid)),
  2,
  'used count remains derived from deductible lessons after refund'
);

SELECT is(
  (SELECT remaining_lesson_count FROM reve_private.calculate_pass_usage(current_setting('test.pass_active')::uuid)),
  2,
  'remaining count remains derived after refund'
);

SELECT ok(
  (
    WITH active_refund AS (
      SELECT al.correlation_id
      FROM public.audit_logs AS al
      WHERE al.action = 'payment.refunded'
        AND al.resource_id = current_setting('test.payment_active')::uuid
      LIMIT 1
    )
    SELECT count(*)::integer >= 4
    FROM public.audit_logs AS al
    CROSS JOIN active_refund AS ar
    WHERE al.correlation_id = ar.correlation_id
  ),
  'active refund audit entries share one correlation identifier'
);

SELECT throws_ok(
  $$ SELECT pg_temp.refund_as(current_setting('test.owner')::uuid);
     SELECT * FROM public.reve_process_payment_refund(
       current_setting('test.payment_active')::uuid, 200000, 'duplicate attempt'
     ); $$,
  'P0001',
  'REVE_REFUND_ALREADY_EXISTS',
  'duplicate refund attempt is rejected'
);

SELECT is(
  (SELECT count(*)::integer
   FROM public.payment_refunds
   WHERE payment_id = current_setting('test.payment_active')::uuid),
  1,
  'duplicate refund attempt creates no second refund row for active payment'
);

SELECT * FROM finish();
ROLLBACK;

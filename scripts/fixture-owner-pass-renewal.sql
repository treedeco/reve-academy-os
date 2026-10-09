-- E2E fixture: dedicated completed vocal pass ready for Owner renewal UI.
-- Local-only: disables user triggers inside a transaction so rollback restores them on failure.

BEGIN;

ALTER TABLE public.sms_notifications DISABLE TRIGGER USER;
ALTER TABLE public.lessons DISABLE TRIGGER USER;
ALTER TABLE public.payments DISABLE TRIGGER USER;
ALTER TABLE public.passes DISABLE TRIGGER USER;

DELETE FROM public.sms_notifications
WHERE pass_id IN (
  SELECT id FROM public.passes WHERE student_id = '44444444-4444-4444-4444-444444444201'
);

DELETE FROM public.lessons
WHERE id IN (
  '99999999-9999-9999-9999-999999999401',
  '99999999-9999-9999-9999-999999999402',
  '99999999-9999-9999-9999-999999999403',
  '99999999-9999-9999-9999-999999999404'
)
OR pass_id IN (
  SELECT id FROM public.passes WHERE student_id = '44444444-4444-4444-4444-444444444201'
);

DELETE FROM public.schedule_slots
WHERE id = '77777777-7777-7777-7777-777777777201'
OR pass_id IN (
  SELECT id FROM public.passes WHERE student_id = '44444444-4444-4444-4444-444444444201'
);

DELETE FROM public.payments
WHERE student_id = '44444444-4444-4444-4444-444444444201';

DELETE FROM public.passes
WHERE student_id = '44444444-4444-4444-4444-444444444201'
OR id = '66666666-6666-6666-6666-666666666201';

DELETE FROM public.students
WHERE id = '44444444-4444-4444-4444-444444444201';

DO $$
DECLARE
  v_student uuid := '44444444-4444-4444-4444-444444444201';
  v_pass_001 uuid := '66666666-6666-6666-6666-666666666201';
  v_slot_001 uuid := '77777777-7777-7777-7777-777777777201';
  v_lesson_1 uuid := '99999999-9999-9999-9999-999999999401';
  v_lesson_2 uuid := '99999999-9999-9999-9999-999999999402';
  v_lesson_3 uuid := '99999999-9999-9999-9999-999999999403';
  v_lesson_4 uuid := '99999999-9999-9999-9999-999999999404';
  v_course uuid;
  v_product uuid;
  v_teacher uuid;
BEGIN
  SELECT id INTO v_course FROM public.courses WHERE course_code = 'VOC-A1' LIMIT 1;
  SELECT id INTO v_product
  FROM public.course_products
  WHERE course_id = v_course AND product_code = 'VOC-4-A1'
  LIMIT 1;
  SELECT id INTO v_teacher FROM public.teachers WHERE teacher_code = 'T-A1' LIMIT 1;

  IF v_course IS NULL OR v_product IS NULL OR v_teacher IS NULL THEN
    RAISE EXCEPTION 'Alpha Vocal course/product/teacher missing; seed Owner Alpha first';
  END IF;

  INSERT INTO public.students (id, student_code, profile_id, name, operational_status)
  VALUES (v_student, 'S1RN1', NULL, 'Renewal E2E Student', 'active');

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, activated_at, completed_at
  ) VALUES (
    v_pass_001, 'V-S1RN1-001', v_student, v_course, v_product,
    1, 'completed', 4, 1, 'Alpha 4 Lessons', 200000,
    CURRENT_DATE - 60, now() - interval '60 days', now() - interval '20 days'
  );

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes,
    slot_order, is_active, effective_from
  ) VALUES (
    v_slot_001, v_pass_001, v_teacher, 2, TIME '14:00', 60, 1, true, CURRENT_DATE - 60
  );

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id, schedule_slot_id,
    sequence_number, scheduled_at, status, actual_start_at, actual_end_at
  ) VALUES
    (v_lesson_1, v_pass_001, v_student, v_course, v_teacher, v_slot_001,
     1, now() - interval '50 days', 'completed', now() - interval '50 days', now() - interval '49 days'),
    (v_lesson_2, v_pass_001, v_student, v_course, v_teacher, v_slot_001,
     2, now() - interval '43 days', 'completed', now() - interval '43 days', now() - interval '42 days'),
    (v_lesson_3, v_pass_001, v_student, v_course, v_teacher, v_slot_001,
     3, now() - interval '36 days', 'completed', now() - interval '36 days', now() - interval '35 days'),
    (v_lesson_4, v_pass_001, v_student, v_course, v_teacher, v_slot_001,
     4, now() - interval '29 days', 'completed', now() - interval '29 days', now() - interval '28 days');
END $$;

ALTER TABLE public.sms_notifications ENABLE TRIGGER USER;
ALTER TABLE public.lessons ENABLE TRIGGER USER;
ALTER TABLE public.payments ENABLE TRIGGER USER;
ALTER TABLE public.passes ENABLE TRIGGER USER;

COMMIT;

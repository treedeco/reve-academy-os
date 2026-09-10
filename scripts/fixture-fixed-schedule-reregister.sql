-- Local e2e fixture: active pass with no fixed schedule + four unscheduled shells,
-- plus a conflicting same-teacher Tue 19:00 slot on another student.

BEGIN;

SET LOCAL session_replication_role = replica;

DO $$
DECLARE
  v_teacher uuid := '22222222-2222-2222-2222-222222222101';
  v_course uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee101';
  v_product uuid := 'ffffffff-ffff-ffff-ffff-fffffffff101';
  v_student uuid := '44444444-4444-4444-4444-444444444801';
  v_student_b uuid := '44444444-4444-4444-4444-444444444802';
  v_pass uuid := '66666666-6666-6666-6666-666666666801';
  v_pass_b uuid := '66666666-6666-6666-6666-666666666802';
  v_slot_b uuid := '77777777-7777-7777-7777-777777777802';
  v_l1 uuid := '99999999-9999-9999-9999-999999aad801';
  v_l2 uuid := '99999999-9999-9999-9999-999999aad802';
  v_l3 uuid := '99999999-9999-9999-9999-999999aad803';
  v_l4 uuid := '99999999-9999-9999-9999-999999aad804';
  v_lb1 uuid := '99999999-9999-9999-9999-999999aad805';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE role = 'owner') THEN
    RAISE EXCEPTION 'Owner Alpha seed required before fixture';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.courses WHERE id = v_course) THEN
    RAISE EXCEPTION 'Alpha course missing; run db:seed:alpha first';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.course_products WHERE id = v_product) THEN
    RAISE EXCEPTION 'Alpha product missing; run db:seed:alpha first';
  END IF;

  DELETE FROM public.lessons WHERE pass_id IN (v_pass, v_pass_b);
  DELETE FROM public.schedule_slots WHERE pass_id IN (v_pass, v_pass_b);
  DELETE FROM public.passes WHERE id IN (v_pass, v_pass_b);
  DELETE FROM public.students WHERE id IN (v_student, v_student_b);

  INSERT INTO public.students (id, student_code, profile_id, name)
  VALUES
    (v_student, 'E2E801', NULL, 'E2E 고정일정재등록'),
    (v_student_b, 'E2E802', NULL, 'E2E 충돌상대');

  INSERT INTO public.passes (
    id, pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date
  ) VALUES
    (v_pass, 'V-E2E801-001', v_student, v_course, v_product,
     1, 'active', 4, 1, 'E2E Vocal', 200000, CURRENT_DATE - 7),
    (v_pass_b, 'V-E2E802-001', v_student_b, v_course, v_product,
     1, 'active', 1, 1, 'E2E Vocal', 200000, CURRENT_DATE - 7);

  INSERT INTO public.schedule_slots (
    id, pass_id, teacher_id, weekday, local_start_time, duration_minutes, slot_order, effective_from
  ) VALUES
    (v_slot_b, v_pass_b, v_teacher, 2, '19:00', 60, 1, CURRENT_DATE - 7);

  INSERT INTO public.lessons (
    id, pass_id, student_id, course_id, assigned_teacher_id,
    schedule_slot_id, sequence_number, scheduled_at, status,
    actual_start_at, actual_end_at, change_reason
  ) VALUES
    (v_l1, v_pass, v_student, v_course, v_teacher, NULL, 1, NULL, 'scheduled', NULL, NULL, NULL),
    (v_l2, v_pass, v_student, v_course, v_teacher, NULL, 2, NULL, 'scheduled', NULL, NULL, NULL),
    (v_l3, v_pass, v_student, v_course, v_teacher, NULL, 3, NULL, 'scheduled', NULL, NULL, NULL),
    (v_l4, v_pass, v_student, v_course, v_teacher, NULL, 4, NULL, 'scheduled', NULL, NULL, NULL),
    (v_lb1, v_pass_b, v_student_b, v_course, v_teacher, v_slot_b, 1,
     now() + interval '3 days', 'scheduled', NULL, NULL, NULL);
END $$;

SET LOCAL session_replication_role = DEFAULT;

COMMIT;

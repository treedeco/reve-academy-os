-- Remove Vitest integration students (student_code like 'S-*') and dependent rows.
-- Alpha fixture students use codes such as S1A1 and are preserved.

BEGIN;

CREATE TEMP TABLE tmp_integration_students ON COMMIT DROP AS
SELECT id
FROM public.students
WHERE student_code ~ '^S-'
   OR student_code ~ '^S[0-9]+$';

CREATE TEMP TABLE tmp_integration_products ON COMMIT DROP AS
SELECT id
FROM public.course_products
WHERE id NOT IN (
  'ffffffff-ffff-ffff-ffff-fffffffff101'::uuid,
  'ffffffff-ffff-ffff-ffff-fffffffff102'::uuid
);

CREATE TEMP TABLE tmp_integration_passes ON COMMIT DROP AS
SELECT id
FROM public.passes
WHERE student_id IN (SELECT id FROM tmp_integration_students);

CREATE TEMP TABLE tmp_integration_lessons ON COMMIT DROP AS
SELECT id
FROM public.lessons
WHERE student_id IN (SELECT id FROM tmp_integration_students);

CREATE TEMP TABLE tmp_integration_payments ON COMMIT DROP AS
SELECT id
FROM public.payments
WHERE student_id IN (SELECT id FROM tmp_integration_students);

SET LOCAL session_replication_role = replica;

DELETE FROM public.lesson_schedule_changes
WHERE lesson_id IN (SELECT id FROM tmp_integration_lessons);

DELETE FROM public.schedule_change_requests
WHERE target_lesson_id IN (SELECT id FROM tmp_integration_lessons);

DELETE FROM public.lesson_notes
WHERE lesson_id IN (SELECT id FROM tmp_integration_lessons);

DELETE FROM public.sms_notifications
WHERE student_id IN (SELECT id FROM tmp_integration_students);

DELETE FROM public.payment_refunds
WHERE payment_id IN (SELECT id FROM tmp_integration_payments);

DELETE FROM public.payments
WHERE id IN (SELECT id FROM tmp_integration_payments);

DELETE FROM public.lessons
WHERE id IN (SELECT id FROM tmp_integration_lessons);

DELETE FROM public.schedule_slots
WHERE pass_id IN (SELECT id FROM tmp_integration_passes);

DELETE FROM public.passes
WHERE id IN (SELECT id FROM tmp_integration_passes);

DELETE FROM public.payments
WHERE course_product_id IN (SELECT id FROM tmp_integration_products);

DELETE FROM public.course_products
WHERE id IN (SELECT id FROM tmp_integration_products);

DELETE FROM public.audit_logs
WHERE resource_id IN (SELECT id FROM tmp_integration_passes)
   OR resource_id IN (SELECT id FROM tmp_integration_students);

DELETE FROM public.students
WHERE id IN (SELECT id FROM tmp_integration_students);

SET LOCAL session_replication_role = DEFAULT;

COMMIT;

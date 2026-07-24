-- Local E2E only: clear course products while preserving Owner auth from alpha seed.
-- Restored by seed-owner-alpha.ps1 in afterAll.

BEGIN;

SET LOCAL session_replication_role = replica;

DELETE FROM public.sms_notifications
WHERE pass_id IN (SELECT id FROM public.passes);

DELETE FROM public.payment_refunds
WHERE payment_id IN (SELECT id FROM public.payments);

DELETE FROM public.payments;

DELETE FROM public.lesson_schedule_changes
WHERE lesson_id IN (SELECT id FROM public.lessons);

DELETE FROM public.schedule_change_requests
WHERE target_lesson_id IN (SELECT id FROM public.lessons);

DELETE FROM public.lesson_notes
WHERE lesson_id IN (SELECT id FROM public.lessons);

DELETE FROM public.lessons;

DELETE FROM public.schedule_slots;

DELETE FROM public.passes;

DELETE FROM public.course_products;

SET LOCAL session_replication_role = DEFAULT;

COMMIT;

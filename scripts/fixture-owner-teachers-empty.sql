-- Playwright isolation fixture: empty teacher master rows without Supabase container restart.
-- Clears lesson/pass rows that reference teachers, then deletes all teachers.
-- Owner auth and profile rows are preserved. Re-apply seed-owner-alpha.sql to restore Alpha data.

BEGIN;

SET LOCAL session_replication_role = replica;

UPDATE public.lessons
SET makeup_source_lesson_id = NULL
WHERE makeup_source_lesson_id IS NOT NULL;

UPDATE public.passes
SET
  previous_pass_id = NULL,
  correction_source_pass_id = NULL;

DELETE FROM public.lesson_schedule_changes;
DELETE FROM public.schedule_change_requests;
DELETE FROM public.lesson_notes;
DELETE FROM public.sms_notifications;
DELETE FROM public.payment_refunds;
DELETE FROM public.payments;
DELETE FROM public.lessons;
DELETE FROM public.schedule_slots;
DELETE FROM public.passes;
DELETE FROM public.teachers;

SET LOCAL session_replication_role = DEFAULT;

COMMIT;

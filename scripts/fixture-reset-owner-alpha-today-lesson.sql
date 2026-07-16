-- Playwright isolation fixture: restore Alpha Student lesson 1 for today's-lessons tests.
-- Uses the same Asia/Seoul "today at 15:00" anchor as scripts/seed-owner-alpha.sql.

DO $$
DECLARE
  v_today timestamptz := date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') AT TIME ZONE 'Asia/Seoul' + interval '15 hours';
  v_lesson uuid := '99999999-9999-9999-9999-999999999101';
  v_pass uuid := '66666666-6666-6666-6666-666666666101';
BEGIN
  UPDATE public.lessons
  SET
    status = 'scheduled',
    scheduled_at = v_today,
    updated_at = now(),
    actual_start_at = NULL,
    actual_end_at = NULL,
    change_reason = NULL
  WHERE id = v_lesson;

  UPDATE public.passes
  SET
    status = 'active',
    cancelled_at = NULL,
    updated_at = now()
  WHERE id = v_pass;
END $$;

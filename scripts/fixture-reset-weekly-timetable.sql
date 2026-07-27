-- Playwright fixture: fixed Seoul week 2026-07-27 (Mon) through 2026-08-02 (Sun).
-- Lessons at 10:00 and cross-week boundary for navigation tests.

DO $$
BEGIN
  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-07-28 10:00:00+09', status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999101';

  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-07-29 10:00:00+09', status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999201';

  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-07-29 15:00:00+09', status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999202';

  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-08-01 15:00:00+09', status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999211';

  UPDATE public.lessons
  SET scheduled_at = timestamptz '2026-08-03 14:00:00+09', status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999102';
END $$;

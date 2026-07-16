-- Playwright fixture: anchor weekly timetable lessons to the current Seoul week (13:00–21:00).

DO $$
DECLARE
  v_week_start timestamptz := date_trunc('week', now() AT TIME ZONE 'Asia/Seoul') AT TIME ZONE 'Asia/Seoul';
  v_monday timestamptz := v_week_start + interval '13 hours';
  v_wednesday timestamptz := v_week_start + interval '2 days 15 hours';
  v_wednesday_b timestamptz := v_week_start + interval '2 days 16 hours';
  v_friday timestamptz := v_week_start + interval '4 days 15 hours';
BEGIN
  UPDATE public.lessons
  SET scheduled_at = v_monday, status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999101';

  UPDATE public.lessons
  SET scheduled_at = v_wednesday, status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999201';

  UPDATE public.lessons
  SET scheduled_at = v_wednesday_b, status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999202';

  UPDATE public.lessons
  SET scheduled_at = v_friday, status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999211';

  UPDATE public.lessons
  SET scheduled_at = v_week_start + interval '6 days 21 hours', status = 'scheduled', updated_at = now()
  WHERE id = '99999999-9999-9999-9999-999999999102';
END $$;

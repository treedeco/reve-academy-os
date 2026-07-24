-- Reset Owner SMS eligible-notification fixtures from seed-owner-alpha.sql
-- Local integration tests only.

BEGIN;

UPDATE public.sms_notifications
SET
  status = 'scheduled',
  message_body_snapshot = '[Beta] Alpha 4 Lessons 수강권 갱신 안내 SMS',
  target_date = CURRENT_DATE + 3,
  sent_at = NULL,
  sent_confirmed_by_profile_id = NULL,
  updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888102';

UPDATE public.sms_notifications
SET
  status = 'target',
  message_body_snapshot = '[Delta] Alpha 4 Lessons 수강권 갱신 안내 SMS',
  target_date = CURRENT_DATE,
  sent_at = NULL,
  sent_confirmed_by_profile_id = NULL,
  updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888103';

UPDATE public.sms_notifications
SET
  status = 'exhausted_unsent',
  message_body_snapshot = '[Gamma] Alpha 4 Lessons 수강권 갱신 안내 SMS (미발송 소진)',
  target_date = CURRENT_DATE - 1,
  sent_at = NULL,
  sent_confirmed_by_profile_id = NULL,
  updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888104';

COMMIT;

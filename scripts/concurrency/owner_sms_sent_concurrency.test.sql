-- Phase 0B-3B-2B-3D-3B scenario 18 — post-concurrency database state
-- Invoked explicitly by scripts/verify_sms_concurrency.ps1 after parallel sessions run.

BEGIN;

SELECT plan(1);

SELECT ok(
  (
    SELECT sn.status = 'sent'
      AND sn.sent_at IS NOT NULL
      AND sn.sent_confirmed_by_profile_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa039'::uuid
      AND (
        SELECT count(*)::integer
        FROM public.audit_logs AS al
        WHERE al.action = 'sms_notification.sent_confirmed'
          AND al.resource_table = 'sms_notifications'
          AND al.resource_id = sn.id
      ) = 1
    FROM public.sms_notifications AS sn
    WHERE sn.id = '88888888-8888-8888-8888-888888888039'::uuid
  ),
  'concurrent confirm leaves single sent row with authoritative metadata and one audit record'
);

SELECT * FROM finish();
ROLLBACK;

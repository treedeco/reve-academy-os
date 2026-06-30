-- Phase 0B-3B-2B-3D-3B scenario 18 — concurrency (run scripts/verify_sms_concurrency.ps1 before this file)
BEGIN;
SELECT plan(1);

SELECT ok(
  (
    SELECT passed
    FROM reve_test.concurrency_assertions
    WHERE test_name = 'sms_confirm_concurrency'
  ),
  'concurrent confirm calls produce one transition and one audit row'
);

SELECT * FROM finish();
ROLLBACK;

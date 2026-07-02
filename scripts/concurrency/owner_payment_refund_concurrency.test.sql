-- Phase 0B-3B-2B-3E RC-05 / duplicate refund — post-concurrency database state
-- Invoked by scripts/verify_refund_concurrency.ps1 after parallel sessions.

BEGIN;

SELECT plan(2);

SELECT ok(
  (
    SELECT count(*)::integer = 1
    FROM public.payment_refunds AS pr
    WHERE pr.payment_id = '12121212-1212-1212-1212-12121212124a'::uuid
  ),
  'duplicate refund scenario leaves exactly one refund row'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM reve_concurrency_runtime.refund_session_results AS r
    WHERE r.scenario IN ('duplicate_refund', 'refund_vs_complete')
      AND r.outcome IN ('pass', 'refund_won', 'complete_won')
  ),
  'runtime harness recorded an authoritative concurrency outcome'
);

SELECT * FROM finish();
ROLLBACK;

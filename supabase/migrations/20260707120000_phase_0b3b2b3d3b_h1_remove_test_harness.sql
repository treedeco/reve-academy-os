-- REVE ACADEMY OS Phase 0B-3B-2B-3D-3B-H1 — remove test-only concurrency harness from production schema
-- Forward cleanup only; does not alter Owner SMS sent confirmation RPC or core domain tables.

DROP TABLE IF EXISTS reve_test.concurrency_assertions;

DROP SCHEMA IF EXISTS reve_test;

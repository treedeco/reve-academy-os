-- REVE ACADEMY OS Phase 0B-3A — foundation
-- Extensions and reusable triggers. No business-policy functions.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

COMMENT ON EXTENSION pgcrypto IS 'UUID and crypto helpers for REVE ACADEMY OS';

-- Reusable updated_at maintenance (Phase 0B-2 §10)
CREATE OR REPLACE FUNCTION public.reve_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.reve_set_updated_at() IS
  'Sets updated_at on row UPDATE. Does not modify created_at or event timestamps.';

-- Block physical DELETE on protected historical tables (Phase 0B-3A)
CREATE OR REPLACE FUNCTION public.reve_block_row_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'Physical DELETE prohibited on % (REVE historical protection)', TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION public.reve_block_row_delete() IS
  'Prevents physical DELETE. Lifecycle changes use trusted operations in Phase 0B-3B.';

-- Block UPDATE and DELETE on append-only / immutable tables
CREATE OR REPLACE FUNCTION public.reve_block_row_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'UPDATE prohibited on % (append-only / immutable)', TG_TABLE_NAME
      USING ERRCODE = 'restrict_violation';
  ELSIF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'DELETE prohibited on % (append-only / immutable)', TG_TABLE_NAME
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.reve_block_row_mutation() IS
  'Immutable row protection for refunds, schedule events, and audit logs.';

-- pgTAP for local database tests (Supabase test runner)
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

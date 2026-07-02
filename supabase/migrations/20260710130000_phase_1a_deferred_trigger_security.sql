-- REVE ACADEMY OS Phase 1A — deferred invariant triggers must run with definer rights
-- PostgREST RPC calls commit per request; deferred triggers otherwise execute as the
-- authenticated session user and fail on reve_private.validate_pass_lesson_invariants.

CREATE OR REPLACE FUNCTION reve_private.trg_deferred_validate_lessons()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM reve_private.validate_pass_lesson_invariants(COALESCE(NEW.pass_id, OLD.pass_id));
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.trg_deferred_validate_pass_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    PERFORM reve_private.validate_pass_lesson_invariants(NEW.id);
  END IF;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION reve_private.trg_deferred_validate_lessons() FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.trg_deferred_validate_pass_status() FROM PUBLIC;

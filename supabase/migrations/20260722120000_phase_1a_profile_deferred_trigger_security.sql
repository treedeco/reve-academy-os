-- REVE ACADEMY OS Phase 1A — profile deferred invariant triggers must run with definer rights
-- PostgREST RPC calls commit per request; deferred triggers otherwise execute as the
-- RPC session user (service_role) and fail on reve_private.validate_profile_role_links.

CREATE OR REPLACE FUNCTION reve_private.trg_deferred_validate_profile_links()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_TABLE_NAME = 'profiles' THEN
    PERFORM reve_private.validate_profile_role_links(COALESCE(NEW.id, OLD.id));
  ELSIF TG_TABLE_NAME = 'students' THEN
    IF COALESCE(NEW.profile_id, OLD.profile_id) IS NOT NULL THEN
      PERFORM reve_private.validate_profile_role_links(COALESCE(NEW.profile_id, OLD.profile_id));
    END IF;
  ELSIF TG_TABLE_NAME = 'teachers' THEN
    IF COALESCE(NEW.profile_id, OLD.profile_id) IS NOT NULL THEN
      PERFORM reve_private.validate_profile_role_links(COALESCE(NEW.profile_id, OLD.profile_id));
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION reve_private.trg_deferred_validate_profile_links() FROM PUBLIC;

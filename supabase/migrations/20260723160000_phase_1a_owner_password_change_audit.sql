-- REVE ACADEMY OS Phase 1A — Owner password change audit RPC
-- Records successful password change completion without storing password material.

CREATE OR REPLACE FUNCTION public.reve_owner_record_password_change_completed()
RETURNS TABLE (
  profile_id uuid,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_correlation_id uuid := gen_random_uuid();
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();

  IF EXISTS (
    SELECT 1
    FROM public.audit_logs AS al
    WHERE al.action = 'profile.password_changed'
      AND al.resource_table = 'profiles'
      AND al.resource_id = v_actor
      AND al.actor_profile_id = v_actor
      AND al.new_value = jsonb_build_object('success', true)
      AND al.created_at > now() - interval '10 minutes'
  ) THEN
    profile_id := v_actor;
    idempotent_replay := true;
    RETURN NEXT;
    RETURN;
  END IF;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'profile.password_changed',
    'profiles',
    v_actor,
    NULL,
    jsonb_build_object('success', true),
    NULL,
    v_correlation_id
  );

  profile_id := v_actor;
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.reve_owner_record_password_change_completed() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_record_password_change_completed() FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_record_password_change_completed() TO authenticated;

COMMENT ON FUNCTION public.reve_owner_record_password_change_completed IS
  'Phase 1A owner password change audit: active owner only; no password material; idempotent retry within 10 minutes.';

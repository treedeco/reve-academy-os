-- REVE ACADEMY OS Phase 0B-3B-2B-3D-3B — Owner manual SMS sent confirmation
-- Owner-only trusted RPC: atomic transition to sent, idempotent retry, audit on first success.

-- ===========================================================================
-- Public RPC — owner confirm SMS manually sent
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_confirm_sms_sent(
  p_sms_notification_id uuid
)
RETURNS TABLE (
  sms_notification_id uuid,
  student_id uuid,
  pass_id uuid,
  previous_status text,
  new_status text,
  sent_at timestamptz,
  sent_confirmed_by_profile_id uuid,
  no_change boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_sms public.sms_notifications%ROWTYPE;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
  v_sent_at timestamptz;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();

  SELECT *
  INTO v_sms
  FROM public.sms_notifications AS sn
  WHERE sn.id = p_sms_notification_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_sms.status = 'sent' THEN
    sms_notification_id := v_sms.id;
    student_id := v_sms.student_id;
    pass_id := v_sms.pass_id;
    previous_status := v_sms.status;
    new_status := v_sms.status;
    sent_at := v_sms.sent_at;
    sent_confirmed_by_profile_id := v_sms.sent_confirmed_by_profile_id;
    no_change := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_sms.status NOT IN ('scheduled', 'target', 'exhausted_unsent') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_SMS_NOT_CONFIRMABLE';
  END IF;

  v_sent_at := now();

  v_previous := jsonb_build_object(
    'status', v_sms.status,
    'sent_at', v_sms.sent_at,
    'sent_confirmed_by_profile_id', v_sms.sent_confirmed_by_profile_id,
    'message_body_snapshot', v_sms.message_body_snapshot,
    'student_id', v_sms.student_id,
    'pass_id', v_sms.pass_id
  );

  UPDATE public.sms_notifications AS sn
  SET
    status = 'sent',
    sent_at = v_sent_at,
    sent_confirmed_by_profile_id = v_actor
  WHERE sn.id = v_sms.id;

  v_new := jsonb_build_object(
    'status', 'sent',
    'sent_at', v_sent_at,
    'sent_confirmed_by_profile_id', v_actor,
    'student_id', v_sms.student_id,
    'pass_id', v_sms.pass_id,
    'message_body_snapshot', v_sms.message_body_snapshot
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'sms_notification.sent_confirmed',
    'sms_notifications',
    v_sms.id,
    v_previous,
    v_new,
    NULL,
    v_correlation_id
  );

  sms_notification_id := v_sms.id;
  student_id := v_sms.student_id;
  pass_id := v_sms.pass_id;
  previous_status := v_sms.status;
  new_status := 'sent';
  sent_at := v_sent_at;
  sent_confirmed_by_profile_id := v_actor;
  no_change := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Security grants
-- ===========================================================================

REVOKE ALL ON FUNCTION public.reve_owner_confirm_sms_sent(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_confirm_sms_sent(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_confirm_sms_sent(uuid) TO authenticated;

DO $$
BEGIN
  EXECUTE format(
    'ALTER FUNCTION %s OWNER TO postgres',
    'public.reve_owner_confirm_sms_sent(uuid)'::regprocedure
  );
END $$;

COMMENT ON FUNCTION public.reve_owner_confirm_sms_sent IS
  'Phase 0B-3B-2B-3D-3B owner-only manual SMS sent confirmation: scheduled/target/exhausted_unsent → sent; idempotent when already sent.';

-- ===========================================================================
-- Local concurrency test harness (pgTAP scenario 18 via scripts/verify_sms_concurrency.ps1)
-- ===========================================================================

CREATE SCHEMA IF NOT EXISTS reve_test;

CREATE TABLE IF NOT EXISTS reve_test.concurrency_assertions (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text,
  checked_at timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON SCHEMA reve_test FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA reve_test FROM PUBLIC;
GRANT USAGE ON SCHEMA reve_test TO postgres, authenticated, service_role;
GRANT SELECT ON reve_test.concurrency_assertions TO postgres, authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON reve_test.concurrency_assertions TO postgres, service_role;

-- REVE ACADEMY OS Phase 1A — profile deferred trigger security pgTAP tests
-- Simulates PostgREST per-request commit via SET CONSTRAINTS ALL IMMEDIATE.

BEGIN;

SELECT plan(14);

DO $$
DECLARE
  v_bootstrap uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc01';
  v_mismatch uuid := 'cccccccc-cccc-cccc-cccc-cccccccccc02';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_bootstrap, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'bootstrap-commit@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_mismatch, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'role-mismatch@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  PERFORM set_config('test.bootstrap_commit', v_bootstrap::text, false);
  PERFORM set_config('test.role_mismatch', v_mismatch::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.bootstrap_sig()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'public.reve_bootstrap_first_owner(uuid,text)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.validate_links_sig()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'reve_private.validate_profile_role_links(uuid)'::text;
$$;

CREATE OR REPLACE FUNCTION pg_temp.profile_trigger_sig()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'reve_private.trg_deferred_validate_profile_links()'::text;
$$;

-- ---------------------------------------------------------------------------
-- Bootstrap RPC privilege contract
-- ---------------------------------------------------------------------------
SELECT ok(
  has_function_privilege('service_role', pg_temp.bootstrap_sig(), 'EXECUTE'),
  'service_role may execute reve_bootstrap_first_owner'
);
SELECT ok(
  NOT has_function_privilege('anon', pg_temp.bootstrap_sig(), 'EXECUTE'),
  'anon may not execute reve_bootstrap_first_owner'
);
SELECT ok(
  NOT has_function_privilege('authenticated', pg_temp.bootstrap_sig(), 'EXECUTE'),
  'authenticated may not execute reve_bootstrap_first_owner'
);
SELECT ok(
  NOT has_function_privilege('service_role', pg_temp.validate_links_sig(), 'EXECUTE'),
  'service_role may not execute validate_profile_role_links directly'
);

SELECT ok(
  (
    SELECT p.prosecdef
    FROM pg_proc AS p
    INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'reve_private'
      AND p.proname = 'trg_deferred_validate_profile_links'
  ),
  'profile deferred trigger function is SECURITY DEFINER'
);

SELECT ok(
  (
    SELECT COALESCE(array_to_string(p.proconfig, ','), '') LIKE 'search_path=%'
    FROM pg_proc AS p
    INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'reve_private'
      AND p.proname = 'trg_deferred_validate_profile_links'
  ),
  'profile deferred trigger function uses explicit search_path'
);

SELECT ok(
  NOT has_function_privilege('anon', pg_temp.profile_trigger_sig(), 'EXECUTE'),
  'anon may not execute profile deferred trigger function directly'
);
SELECT ok(
  NOT has_function_privilege('authenticated', pg_temp.profile_trigger_sig(), 'EXECUTE'),
  'authenticated may not execute profile deferred trigger function directly'
);

-- ---------------------------------------------------------------------------
-- PostgREST commit simulation: deferred validation must succeed under service_role
-- ---------------------------------------------------------------------------
SET ROLE service_role;

SELECT lives_ok(
  $$
    SELECT role
    FROM public.reve_bootstrap_first_owner(
      current_setting('test.bootstrap_commit')::uuid,
      'Commit Test Owner'
    );
    SET CONSTRAINTS ALL IMMEDIATE;
  $$,
  'service_role bootstrap succeeds when deferred profile validation fires immediately'
);

SELECT ok(
  (
    SELECT role
    FROM public.reve_bootstrap_first_owner(
      current_setting('test.bootstrap_commit')::uuid,
      'Commit Test Owner'
    )
    LIMIT 1
  ) = 'owner',
  'bootstrap creates owner profile with role owner'
);

SELECT ok(
  (
    SELECT idempotent_replay
    FROM public.reve_bootstrap_first_owner(
      current_setting('test.bootstrap_commit')::uuid,
      'Commit Test Owner'
    )
    LIMIT 1
  ),
  'repeated bootstrap returns idempotent_replay without duplicate profile'
);

DO $$ BEGIN RESET ROLE; END $$;

SELECT ok(
  (
    SELECT count(*)::integer
    FROM public.profiles AS p
    WHERE p.id = current_setting('test.bootstrap_commit')::uuid
  ) = 1,
  'bootstrap leaves exactly one profile row for the Auth user'
);

-- ---------------------------------------------------------------------------
-- Validation trigger behavior preserved
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$
    INSERT INTO public.profiles AS p (id, role, display_name, account_state)
    VALUES (
      current_setting('test.role_mismatch')::uuid,
      'owner',
      'Mismatch Owner',
      'active'
    );
    INSERT INTO public.students (
      student_code, name, operational_status, profile_id
    ) VALUES (
      'MISMATCH-01', 'Mismatch Student', 'active',
      current_setting('test.role_mismatch')::uuid
    );
    SET CONSTRAINTS ALL IMMEDIATE;
  $$,
  'P0001',
  'REVE_ROLE_LINK_MISMATCH',
  'deferred profile validation still rejects invalid owner/student link'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = current_setting('test.role_mismatch')::uuid
  ),
  'invalid profile-role link attempt does not persist profile row'
);

SELECT finish();
ROLLBACK;

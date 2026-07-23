-- REVE ACADEMY OS Phase 1A — owner password change audit pgTAP tests

BEGIN;

SELECT plan(7);

DO $$
DECLARE
  v_owner uuid := 'dddddddd-dddd-dddd-dddd-dddddddddd01';
  v_teacher uuid := 'dddddddd-dddd-dddd-dddd-dddddddddd02';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'password-audit-owner@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()),
    (v_teacher, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'password-audit-teacher@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_owner, 'owner', 'Password Audit Owner', 'active'),
    (v_teacher, 'teacher', 'Password Audit Teacher', 'active');

  INSERT INTO public.teachers (teacher_code, name, profile_id, is_active) VALUES
    ('PWD-T1', 'Password Audit Teacher', v_teacher, true);

  PERFORM set_config('test.password_owner', v_owner::text, false);
  PERFORM set_config('test.password_teacher', v_teacher::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.test_auth_as(p_user uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  SET ROLE authenticated;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.test_reset_role()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM set_config('request.jwt.claim.role', '', false);
END;
$$;

SELECT has_function(
  'public', 'reve_owner_record_password_change_completed', ARRAY[]::text[]
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.reve_owner_record_password_change_completed()',
    'EXECUTE'
  ),
  'authenticated owner may execute password change audit RPC'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.reve_owner_record_password_change_completed()',
    'EXECUTE'
  ),
  'anon may not execute password change audit RPC'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.password_owner')::uuid); END $$;

SELECT ok(
  (SELECT idempotent_replay FROM public.reve_owner_record_password_change_completed() LIMIT 1) = false,
  'first password change audit insert succeeds'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.audit_logs AS al
    WHERE al.action = 'profile.password_changed'
      AND al.resource_table = 'profiles'
      AND al.resource_id = current_setting('test.password_owner')::uuid
      AND al.new_value = jsonb_build_object('success', true)
  ),
  'password change audit stores success flag only'
);

SELECT ok(
  (SELECT idempotent_replay FROM public.reve_owner_record_password_change_completed() LIMIT 1),
  'repeated password change audit within window is idempotent'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.password_teacher')::uuid); END $$;

SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_record_password_change_completed() $$,
  '42501'
);

DO $$ BEGIN PERFORM pg_temp.test_reset_role(); END $$;

SELECT finish();
ROLLBACK;

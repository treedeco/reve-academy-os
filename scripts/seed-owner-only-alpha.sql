-- Local Playwright fixture: active Owner account only (no teacher master rows).
-- Apply after `npx supabase db reset` against the local Supabase container.
-- Owner password is supplied via PostgreSQL setting `reve.owner_seed_password`.

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa101';
  v_owner_email text := 'reve@owner.local';
  v_owner_password text := current_setting('reve.owner_seed_password', true);
BEGIN
  IF v_owner_password IS NULL OR btrim(v_owner_password) = '' THEN
    RAISE EXCEPTION 'reve.owner_seed_password must be set before applying seed-owner-only-alpha.sql';
  END IF;

  DELETE FROM auth.users
  WHERE email = 'owner-alpha@test.local'
    AND id <> v_owner;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, reauthentication_token,
    created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    v_owner_email, crypt(v_owner_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', now(), now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = EXCLUDED.email_confirmed_at,
    raw_app_meta_data = EXCLUDED.raw_app_meta_data,
    confirmation_token = '',
    recovery_token = '',
    email_change_token_new = '',
    email_change = '',
    email_change_token_current = '',
    reauthentication_token = '',
    updated_at = now();

  INSERT INTO public.profiles (id, role, display_name, account_state) VALUES
    (v_owner, 'owner', 'Alpha Owner', 'active')
  ON CONFLICT (id) DO UPDATE SET
    role = EXCLUDED.role,
    display_name = EXCLUDED.display_name,
    account_state = EXCLUDED.account_state;
END $$;

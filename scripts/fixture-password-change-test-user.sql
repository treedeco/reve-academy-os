-- Local integration fixture: isolated Owner account for password-change tests.
-- Never run against hosted/production databases.

BEGIN;

DO $$
DECLARE
  v_user uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01';
BEGIN
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    reauthentication_token,
    created_at,
    updated_at
  ) VALUES (
    v_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'password-change-owner@test.local',
    crypt('PasswordChangeTest123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('must_change_password', true),
    '',
    '',
    '',
    '',
    '',
    '',
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = EXCLUDED.email_confirmed_at,
    raw_app_meta_data = EXCLUDED.raw_app_meta_data,
    raw_user_meta_data = EXCLUDED.raw_user_meta_data,
    confirmation_token = '',
    recovery_token = '',
    email_change_token_new = '',
    email_change = '',
    email_change_token_current = '',
    reauthentication_token = '',
    updated_at = now();

  INSERT INTO public.profiles (id, role, display_name, account_state)
  VALUES (v_user, 'owner', 'Password Change Test Owner', 'active')
  ON CONFLICT (id) DO UPDATE SET
    role = EXCLUDED.role,
    display_name = EXCLUDED.display_name,
    account_state = EXCLUDED.account_state;
END $$;

COMMIT;

-- REVE ACADEMY OS Phase 2B-2B2 — canonical courses and student code generation pgTAP

BEGIN;

SELECT plan(10);

DO $$
DECLARE
  v_owner uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabb01';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner-codes@test.local', crypt('test', gen_salt('bf')), now(), '{}'::jsonb, now(), now()
  );

  INSERT INTO public.profiles (id, role, display_name, account_state)
  VALUES (v_owner, 'owner', 'Owner Codes Test', 'active');

  PERFORM set_config('test.owner_codes', v_owner::text, false);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.test_auth_as(p_user uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_user::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  SET ROLE authenticated;
END;
$$;

SELECT ok(
  (SELECT count(*) FROM public.courses WHERE is_active = true AND course_code IN ('V', 'P', 'M', 'D')) = 4,
  'canonical active courses V/P/M/D exist'
);

SELECT ok(
  reve_private.validate_course_prefix('v') = 'V',
  'validate_course_prefix uppercases single letter'
);

SELECT throws_ok(
  $$ SELECT reve_private.validate_course_prefix('VO') $$,
  'P0001'
);

SELECT ok(
  reve_private.format_student_code(1) = 'S0001',
  'format_student_code pads to four digits'
);

SELECT ok(
  reve_private.is_canonical_student_code('S0001'),
  'S0001 is canonical'
);

SELECT ok(
  NOT reve_private.is_canonical_student_code('1'),
  'numeric-only legacy code is not canonical'
);

SELECT ok(
  (SELECT reve_private.build_pass_public_code('V', 'S0001', 1)) = 'V-S0001-001',
  'pass code uses course prefix and student code'
);

SELECT ok(
  (SELECT reve_private.build_pass_public_code('P', 'S0001', 1)) = 'P-S0001-001',
  'piano pass code uses P prefix'
);

DO $$ BEGIN PERFORM pg_temp.test_auth_as(current_setting('test.owner_codes')::uuid); END $$;

SELECT ok(
  (SELECT student_code FROM public.reve_owner_create_student('Code Gen Student A') LIMIT 1) ~ '^S[0-9]{4,}$',
  'reve_owner_create_student returns generated canonical code'
);

DO $$ BEGIN PERFORM public.reve_owner_create_student('Code Gen Student B'); END $$;

SELECT ok(
  (SELECT count(DISTINCT student_code) FROM public.students WHERE name LIKE 'Code Gen Student%') = 2,
  'two generated student codes are distinct after double create'
);

DO $$ BEGIN RESET ROLE; END $$;

SELECT finish();
ROLLBACK;

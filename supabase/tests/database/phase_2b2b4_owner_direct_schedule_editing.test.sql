-- Phase 2B-2B4 owner direct schedule editing (RPC contract smoke tests)

BEGIN;
SELECT plan(6);

SELECT has_function(
  'public', 'reve_owner_change_fixed_pass_schedule',
  ARRAY['uuid', 'timestamptz', 'date', 'jsonb', 'text']
);

SELECT has_function(
  'public', 'reve_owner_replace_pass_schedule_slots',
  ARRAY['uuid', 'timestamptz', 'jsonb', 'text', 'date']
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'reve_private'
      AND p.proname = 'student_has_operational_lesson_collision'
  ),
  'student collision helper exists for direct schedule edits'
);

SELECT ok(
  NOT has_function_privilege(
    'public',
    'reve_owner_change_fixed_pass_schedule(uuid, timestamptz, date, jsonb, text)'::regprocedure,
    'EXECUTE'
  ),
  'PUBLIC cannot execute reve_owner_change_fixed_pass_schedule'
);

SET ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.reve_owner_change_fixed_pass_schedule(
       gen_random_uuid(), now(), current_date, '[]'::jsonb, 'anon') $$,
  '42501'
);
RESET ROLE;

SELECT ok(
  has_function_privilege(
    'authenticated',
    'reve_owner_change_fixed_pass_schedule(uuid, timestamptz, date, jsonb, text)'::regprocedure,
    'EXECUTE'
  ),
  'authenticated can execute reve_owner_change_fixed_pass_schedule'
);

SELECT * FROM finish();
ROLLBACK;

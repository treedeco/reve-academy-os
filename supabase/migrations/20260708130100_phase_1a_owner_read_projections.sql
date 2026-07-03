-- REVE ACADEMY OS Phase 1A — Owner read-only pass usage projection
-- Wraps authoritative reve_private.calculate_pass_usage for Owner UI reads.

CREATE OR REPLACE FUNCTION public.reve_owner_get_pass_usage(p_pass_id uuid)
RETURNS TABLE (
  pass_id uuid,
  pass_code text,
  pass_status text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_lesson_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pass public.passes%ROWTYPE;
BEGIN
  PERFORM reve_private.assert_active_owner_caller();

  SELECT *
  INTO v_pass
  FROM public.passes AS p
  WHERE p.id = p_pass_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT
    v_pass.id,
    v_pass.pass_code,
    v_pass.status,
    u.registered_lesson_count,
    u.used_lesson_count,
    u.remaining_lesson_count,
    reve_private.find_next_lesson_at(v_pass.id)
  FROM reve_private.calculate_pass_usage(v_pass.id) AS u;
END;
$$;

REVOKE ALL ON FUNCTION public.reve_owner_get_pass_usage(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_get_pass_usage(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_get_pass_usage(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.reve_owner_get_pass_usage IS
  'Phase 1A owner read-only pass usage summary using authoritative calculate_pass_usage.';

-- Phase 2B-2B4R1: Align academy operating hours with 10:00–21:00 lesson starts (22:00 close).

CREATE OR REPLACE FUNCTION reve_private.validate_academy_operating_hours(
  p_start timestamptz,
  p_duration_minutes integer
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_local_start time;
  v_start_minutes integer;
  v_end_minutes integer;
BEGIN
  v_local_start := (p_start AT TIME ZONE 'Asia/Seoul')::time;
  v_start_minutes :=
    EXTRACT(HOUR FROM v_local_start)::integer * 60
    + EXTRACT(MINUTE FROM v_local_start)::integer;
  v_end_minutes := v_start_minutes + p_duration_minutes;

  IF v_start_minutes < 10 * 60 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACADEMY_HOURS_BEFORE_OPEN';
  END IF;

  IF v_start_minutes >= 22 * 60 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACADEMY_HOURS_AFTER_CLOSE';
  END IF;

  IF v_end_minutes > 22 * 60 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACADEMY_HOURS_END_AFTER_CLOSE';
  END IF;
END;
$$;

COMMENT ON FUNCTION reve_private.validate_academy_operating_hours IS
  'Asia/Seoul academy window: lesson starts 10:00–21:00 inclusive; end by 22:00.';

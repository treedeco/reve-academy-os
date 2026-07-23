-- REVE ACADEMY OS Phase 2B-2B2 — canonical course prefixes and database-generated student codes
-- Idempotent canonical course seed; sequence-based student codes; legacy code migration.

-- ===========================================================================
-- Course prefix validation (single uppercase ASCII letter)
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.validate_course_prefix(p_code text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_code text := upper(btrim(COALESCE(p_code, '')));
BEGIN
  IF v_code !~ '^[A-Z]$' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_COURSE_PREFIX';
  END IF;
  RETURN v_code;
END;
$$;

REVOKE ALL ON FUNCTION reve_private.validate_course_prefix(text) FROM PUBLIC;

-- ===========================================================================
-- Student code sequence (concurrency-safe; never reuse)
-- ===========================================================================

CREATE SEQUENCE IF NOT EXISTS reve_private.student_code_number_seq
  AS bigint
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

CREATE OR REPLACE FUNCTION reve_private.format_student_code(p_number bigint)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT 'S' || lpad(p_number::text, 4, '0');
$$;

CREATE OR REPLACE FUNCTION reve_private.is_canonical_student_code(p_code text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT COALESCE(p_code, '') ~ '^S[0-9]{4,}$';
$$;

CREATE OR REPLACE FUNCTION reve_private.sync_student_code_sequence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_max bigint;
BEGIN
  SELECT COALESCE(max(substring(s.student_code from 2)::bigint), 0)
  INTO v_max
  FROM public.students AS s
  WHERE reve_private.is_canonical_student_code(s.student_code);

  IF v_max = 0 THEN
    PERFORM setval('reve_private.student_code_number_seq', 1, false);
  ELSE
    PERFORM setval('reve_private.student_code_number_seq', v_max, true);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.allocate_student_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_number bigint;
BEGIN
  v_number := nextval('reve_private.student_code_number_seq');
  RETURN reve_private.format_student_code(v_number);
END;
$$;

REVOKE ALL ON FUNCTION reve_private.sync_student_code_sequence() FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.allocate_student_code() FROM PUBLIC;

-- ===========================================================================
-- Canonical course reference data (idempotent)
-- ===========================================================================

INSERT INTO public.courses AS c (course_code, name, description, is_active)
VALUES
  ('V', '보컬', 'Vocal', true),
  ('P', '피아노', 'Piano', true),
  ('M', '작곡', 'Composition', true),
  ('D', '드럼', 'Drums', true)
ON CONFLICT (course_code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  is_active = true,
  updated_at = now()
WHERE c.course_code IN ('V', 'P', 'M', 'D');

-- ===========================================================================
-- Legacy student-code migration (preserve UUIDs and relationships)
-- ===========================================================================

DO $$
DECLARE
  v_student record;
  v_old_code text;
  v_new_code text;
BEGIN
  PERFORM reve_private.sync_student_code_sequence();

  FOR v_student IN
    SELECT s.id, s.student_code
    FROM public.students AS s
    WHERE NOT reve_private.is_canonical_student_code(s.student_code)
    ORDER BY s.created_at, s.id
  LOOP
    v_old_code := v_student.student_code;
    v_new_code := reve_private.allocate_student_code();

    UPDATE public.passes AS p
    SET pass_code = reve_private.build_pass_public_code(
      c.course_code,
      v_new_code,
      p.sequence_number
    )
    FROM public.courses AS c
    WHERE p.course_id = c.id
      AND p.student_id = v_student.id;

    UPDATE public.students AS s
    SET student_code = v_new_code,
        updated_at = now()
    WHERE s.id = v_student.id;

    PERFORM reve_private.append_audit_log(
      NULL,
      'system',
      'student.code_migrated',
      'students',
      v_student.id,
      jsonb_build_object('student_code', v_old_code),
      jsonb_build_object('student_code', v_new_code, 'success', true),
      'canonical_student_code_migration',
      gen_random_uuid()
    );
  END LOOP;
END $$;

-- ===========================================================================
-- Owner create student — database-generated code only
-- ===========================================================================

DROP FUNCTION IF EXISTS public.reve_owner_create_student(text, text, text, text);

CREATE OR REPLACE FUNCTION public.reve_owner_create_student(
  p_name text,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS TABLE (
  student_id uuid,
  student_code text,
  student_name text,
  operational_status text,
  linked_profile_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_code text;
  v_name text;
  v_correlation_id uuid := gen_random_uuid();
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_name := NULLIF(btrim(COALESCE(p_name, '')), '');

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  v_code := reve_private.allocate_student_code();

  INSERT INTO public.students AS ins (
    student_code, name, phone, email, operational_status
  ) VALUES (
    v_code,
    v_name,
    reve_private.normalize_optional_text(p_phone),
    reve_private.normalize_optional_text(p_email),
    'active'
  )
  RETURNING ins.id, ins.student_code, ins.name, ins.operational_status, ins.profile_id, ins.created_at, ins.updated_at
  INTO student_id, student_code, student_name, operational_status, linked_profile_id, created_at, updated_at;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'student.created',
    'students',
    student_id,
    NULL,
    jsonb_build_object(
      'student_code', student_code,
      'name', student_name,
      'operational_status', operational_status,
      'auto_generated_code', true
    ),
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.reve_owner_create_student(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_create_student(text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_create_student(text, text, text) TO authenticated;

-- ===========================================================================
-- Course create — enforce single-letter prefix for new courses
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_create_course(
  p_course_code text,
  p_name text,
  p_description text DEFAULT NULL
)
RETURNS TABLE (
  course_id uuid,
  course_code text,
  course_name text,
  is_active boolean,
  description text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_code text;
  v_name text;
  v_description text;
  v_correlation_id uuid := gen_random_uuid();
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_code := reve_private.validate_course_prefix(p_course_code);
  v_name := NULLIF(btrim(COALESCE(p_name, '')), '');
  v_description := reve_private.normalize_optional_text(p_description);

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.courses AS c WHERE c.course_code = v_code
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_CODE_EXISTS';
  END IF;

  INSERT INTO public.courses AS ins (
    course_code, name, description, is_active
  ) VALUES (
    v_code, v_name, v_description, true
  )
  RETURNING
    ins.id, ins.course_code, ins.name, ins.is_active, ins.description, ins.created_at, ins.updated_at
  INTO course_id, course_code, course_name, is_active, description, created_at, updated_at;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'course.created',
    'courses',
    course_id,
    NULL,
    jsonb_build_object(
      'course_code', course_code,
      'name', course_name,
      'description', description,
      'is_active', is_active
    ),
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.reve_owner_create_student IS
  'Phase 2B-2B2: active owner creates student with database-generated S#### code.';

COMMENT ON FUNCTION reve_private.validate_course_prefix IS
  'Validates a single uppercase ASCII course prefix letter (V/P/M/D style).';

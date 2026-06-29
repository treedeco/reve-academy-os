-- REVE ACADEMY OS Phase 0B-3B-2B-3A — profile provisioning and owner people master data
-- OD-19 / OD-21 provisional: deactivation not deletion; multiple owners; last-owner protection

-- ===========================================================================
-- Internal helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.auth_user_exists(p_auth_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users AS u WHERE u.id = p_auth_user_id
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.assert_active_owner_caller()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_profile_id uuid;
BEGIN
  v_profile_id := auth.uid();
  IF v_profile_id IS NULL OR NOT reve_private.is_owner() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;
  RETURN v_profile_id;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.count_active_owners()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::integer
  FROM public.profiles AS p
  WHERE p.role = 'owner'
    AND p.account_state = 'active';
$$;

CREATE OR REPLACE FUNCTION reve_private.assert_not_last_active_owner(p_profile_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(878721);

  IF EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = p_profile_id
      AND p.role = 'owner'
      AND p.account_state = 'active'
  ) AND reve_private.count_active_owners() <= 1 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_LAST_OWNER';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.validate_profile_role_links(p_profile_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_student_count integer;
  v_teacher_count integer;
BEGIN
  SELECT *
  INTO v_profile
  FROM public.profiles AS p
  WHERE p.id = p_profile_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT count(*)::integer
  INTO v_student_count
  FROM public.students AS s
  WHERE s.profile_id = p_profile_id;

  SELECT count(*)::integer
  INTO v_teacher_count
  FROM public.teachers AS t
  WHERE t.profile_id = p_profile_id;

  IF v_profile.role = 'owner' THEN
    IF v_student_count > 0 OR v_teacher_count > 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
  ELSIF v_profile.role = 'teacher' THEN
    IF v_teacher_count <> 1 OR v_student_count > 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
  ELSIF v_profile.role = 'student' THEN
    IF v_student_count <> 1 OR v_teacher_count > 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.trg_deferred_validate_profile_links()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_TABLE_NAME = 'profiles' THEN
    PERFORM reve_private.validate_profile_role_links(COALESCE(NEW.id, OLD.id));
  ELSIF TG_TABLE_NAME = 'students' THEN
    IF COALESCE(NEW.profile_id, OLD.profile_id) IS NOT NULL THEN
      PERFORM reve_private.validate_profile_role_links(COALESCE(NEW.profile_id, OLD.profile_id));
    END IF;
  ELSIF TG_TABLE_NAME = 'teachers' THEN
    IF COALESCE(NEW.profile_id, OLD.profile_id) IS NOT NULL THEN
      PERFORM reve_private.validate_profile_role_links(COALESCE(NEW.profile_id, OLD.profile_id));
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_profiles_validate_role_links
  AFTER INSERT OR UPDATE OF role ON public.profiles
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION reve_private.trg_deferred_validate_profile_links();

CREATE CONSTRAINT TRIGGER trg_students_validate_profile_links
  AFTER INSERT OR UPDATE OF profile_id ON public.students
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION reve_private.trg_deferred_validate_profile_links();

CREATE CONSTRAINT TRIGGER trg_teachers_validate_profile_links
  AFTER INSERT OR UPDATE OF profile_id ON public.teachers
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION reve_private.trg_deferred_validate_profile_links();

CREATE OR REPLACE FUNCTION reve_private.teacher_has_future_active_assignments(p_teacher_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.lessons AS l
    INNER JOIN public.passes AS p ON p.id = l.pass_id
    WHERE l.assigned_teacher_id = p_teacher_id
      AND p.status IN ('active', 'reserved')
      AND l.status = 'scheduled'
      AND l.scheduled_at IS NOT NULL
      AND l.scheduled_at > now()
  )
  OR EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    INNER JOIN public.passes AS p ON p.id = ss.pass_id
    WHERE ss.teacher_id = p_teacher_id
      AND ss.is_active = true
      AND p.status IN ('active', 'reserved')
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.normalize_optional_text(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT NULLIF(btrim(COALESCE(p_value, '')), '');
$$;

CREATE OR REPLACE FUNCTION reve_private.validate_person_code(p_code text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_code text := NULLIF(btrim(COALESCE(p_code, '')), '');
BEGIN
  IF v_code IS NULL OR char_length(v_code) > 32 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_CODE';
  END IF;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.clear_profile_entity_links(p_profile_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.students AS s
  SET profile_id = NULL
  WHERE s.profile_id = p_profile_id;

  UPDATE public.teachers AS t
  SET profile_id = NULL
  WHERE t.profile_id = p_profile_id;
END;
$$;

-- ===========================================================================
-- Bootstrap first owner (service_role only)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_bootstrap_first_owner(
  p_auth_user_id uuid,
  p_display_name text
)
RETURNS TABLE (
  profile_id uuid,
  role text,
  account_state text,
  display_name text,
  updated_at timestamptz,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing public.profiles%ROWTYPE;
  v_name text;
  v_correlation_id uuid := gen_random_uuid();
BEGIN
  v_name := NULLIF(btrim(COALESCE(p_display_name, '')), '');
  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_DISPLAY_NAME';
  END IF;

  IF NOT reve_private.auth_user_exists(p_auth_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_AUTH_USER_NOT_FOUND';
  END IF;

  SELECT *
  INTO v_existing
  FROM public.profiles AS p
  WHERE p.id = p_auth_user_id;

  IF FOUND THEN
    IF v_existing.role = 'owner'
      AND v_existing.display_name = v_name
      AND v_existing.account_state = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.students AS s WHERE s.profile_id = p_auth_user_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.teachers AS t WHERE t.profile_id = p_auth_user_id
      ) THEN
      profile_id := v_existing.id;
      role := v_existing.role;
      account_state := v_existing.account_state;
      display_name := v_existing.display_name;
      updated_at := v_existing.updated_at;
      idempotent_replay := true;
      RETURN NEXT;
      RETURN;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_EXISTS';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles AS p WHERE p.role = 'owner'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_BOOTSTRAP_ALREADY_COMPLETED';
  END IF;

  INSERT INTO public.profiles AS ins (id, role, display_name, account_state)
  VALUES (p_auth_user_id, 'owner', v_name, 'active')
  RETURNING ins.id, ins.role, ins.account_state, ins.display_name, ins.updated_at
  INTO profile_id, role, account_state, display_name, updated_at;

  PERFORM reve_private.append_audit_log(
    NULL,
    'system',
    'profile.bootstrap_first_owner',
    'profiles',
    profile_id,
    NULL,
    jsonb_build_object(
      'role', role,
      'account_state', account_state,
      'display_name', display_name
    ),
    NULL,
    v_correlation_id
  );

  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Owner profile provisioning
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_provision_profile(
  p_auth_user_id uuid,
  p_role text,
  p_display_name text,
  p_student_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL
)
RETURNS TABLE (
  profile_id uuid,
  role text,
  account_state text,
  student_id uuid,
  teacher_id uuid,
  display_name text,
  updated_at timestamptz,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_name text;
  v_correlation_id uuid := gen_random_uuid();
  v_student_id uuid;
  v_teacher_id uuid;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_name := NULLIF(btrim(COALESCE(p_display_name, '')), '');

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_DISPLAY_NAME';
  END IF;

  IF p_role NOT IN ('owner', 'teacher', 'student') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
  END IF;

  IF NOT reve_private.auth_user_exists(p_auth_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_AUTH_USER_NOT_FOUND';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles AS p WHERE p.id = p_auth_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_EXISTS';
  END IF;

  IF p_role = 'owner' THEN
    IF p_student_id IS NOT NULL OR p_teacher_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
  ELSIF p_role = 'teacher' THEN
    IF p_teacher_id IS NULL OR p_student_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
    PERFORM 1
    FROM public.teachers AS t
    WHERE t.id = p_teacher_id
      AND t.is_active = true
      AND t.profile_id IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_LINK_CONFLICT';
    END IF;
    v_teacher_id := p_teacher_id;
  ELSE
    IF p_student_id IS NULL OR p_teacher_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
    PERFORM 1
    FROM public.students AS s
    WHERE s.id = p_student_id
      AND s.operational_status = 'active'
      AND s.profile_id IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_LINK_CONFLICT';
    END IF;
    v_student_id := p_student_id;
  END IF;

  INSERT INTO public.profiles (id, role, display_name, account_state)
  VALUES (p_auth_user_id, p_role, v_name, 'active');

  IF v_teacher_id IS NOT NULL THEN
    UPDATE public.teachers AS t
    SET profile_id = p_auth_user_id
    WHERE t.id = v_teacher_id;
  END IF;

  IF v_student_id IS NOT NULL THEN
    UPDATE public.students AS s
    SET profile_id = p_auth_user_id
    WHERE s.id = v_student_id;
  END IF;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'profile.provisioned',
    'profiles',
    p_auth_user_id,
    NULL,
    jsonb_build_object(
      'role', p_role,
      'account_state', 'active',
      'display_name', v_name,
      'student_id', v_student_id,
      'teacher_id', v_teacher_id
    ),
    NULL,
    v_correlation_id
  );

  profile_id := p_auth_user_id;
  role := p_role;
  account_state := 'active';
  student_id := v_student_id;
  teacher_id := v_teacher_id;
  display_name := v_name;
  updated_at := (SELECT p.updated_at FROM public.profiles AS p WHERE p.id = p_auth_user_id);
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Owner profile role change
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_set_profile_role(
  p_profile_id uuid,
  p_new_role text,
  p_reason text,
  p_expected_updated_at timestamptz,
  p_student_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL
)
RETURNS TABLE (
  profile_id uuid,
  role text,
  account_state text,
  student_id uuid,
  teacher_id uuid,
  display_name text,
  updated_at timestamptz,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_profile public.profiles%ROWTYPE;
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
  v_student_id uuid;
  v_teacher_id uuid;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  IF p_new_role NOT IN ('owner', 'teacher', 'student') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
  END IF;

  SELECT *
  INTO v_profile
  FROM public.profiles AS p
  WHERE p.id = p_profile_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_profile.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_profile.role = 'owner'
    AND p_new_role <> 'owner'
    AND v_profile.account_state = 'active' THEN
    PERFORM reve_private.assert_not_last_active_owner(p_profile_id);
  END IF;

  v_previous := jsonb_build_object(
    'role', v_profile.role,
    'student_id', (SELECT s.id FROM public.students AS s WHERE s.profile_id = p_profile_id LIMIT 1),
    'teacher_id', (SELECT t.id FROM public.teachers AS t WHERE t.profile_id = p_profile_id LIMIT 1)
  );

  IF p_new_role = 'owner' THEN
    IF p_student_id IS NOT NULL OR p_teacher_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
    PERFORM reve_private.clear_profile_entity_links(p_profile_id);
    v_student_id := NULL;
    v_teacher_id := NULL;
  ELSIF p_new_role = 'teacher' THEN
    IF p_teacher_id IS NULL OR p_student_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
    PERFORM 1
    FROM public.teachers AS t
    WHERE t.id = p_teacher_id
      AND t.is_active = true
      AND (t.profile_id IS NULL OR t.profile_id = p_profile_id)
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_LINK_CONFLICT';
    END IF;
    PERFORM reve_private.clear_profile_entity_links(p_profile_id);
    UPDATE public.teachers AS t
    SET profile_id = p_profile_id
    WHERE t.id = p_teacher_id;
    v_teacher_id := p_teacher_id;
    v_student_id := NULL;
  ELSE
    IF p_student_id IS NULL OR p_teacher_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ROLE_LINK_MISMATCH';
    END IF;
    PERFORM 1
    FROM public.students AS s
    WHERE s.id = p_student_id
      AND s.operational_status = 'active'
      AND (s.profile_id IS NULL OR s.profile_id = p_profile_id)
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_LINK_CONFLICT';
    END IF;
    PERFORM reve_private.clear_profile_entity_links(p_profile_id);
    UPDATE public.students AS s
    SET profile_id = p_profile_id
    WHERE s.id = p_student_id;
    v_student_id := p_student_id;
    v_teacher_id := NULL;
  END IF;

  UPDATE public.profiles AS p
  SET role = p_new_role
  WHERE p.id = p_profile_id
  RETURNING p.display_name, p.account_state, p.updated_at
  INTO display_name, account_state, updated_at;

  v_new := jsonb_build_object(
    'role', p_new_role,
    'student_id', v_student_id,
    'teacher_id', v_teacher_id
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'profile.role_changed',
    'profiles',
    p_profile_id,
    v_previous,
    v_new,
    v_reason,
    v_correlation_id
  );

  profile_id := p_profile_id;
  role := p_new_role;
  student_id := v_student_id;
  teacher_id := v_teacher_id;
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Owner profile activation state
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_set_profile_active(
  p_profile_id uuid,
  p_account_state text,
  p_reason text,
  p_expected_updated_at timestamptz
)
RETURNS TABLE (
  profile_id uuid,
  role text,
  account_state text,
  student_id uuid,
  teacher_id uuid,
  display_name text,
  updated_at timestamptz,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;
  v_actor_role text;
  v_profile public.profiles%ROWTYPE;
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  IF p_account_state NOT IN ('active', 'inactive', 'suspended') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_ACCOUNT_STATE';
  END IF;

  SELECT *
  INTO v_profile
  FROM public.profiles AS p
  WHERE p.id = p_profile_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_profile.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_profile.role = 'owner'
    AND v_profile.account_state = 'active'
    AND p_account_state <> 'active' THEN
    PERFORM reve_private.assert_not_last_active_owner(p_profile_id);
  END IF;

  IF p_account_state = 'active' THEN
    PERFORM reve_private.validate_profile_role_links(p_profile_id);
  END IF;

  v_previous := jsonb_build_object('account_state', v_profile.account_state);

  UPDATE public.profiles AS p
  SET account_state = p_account_state
  WHERE p.id = p_profile_id
  RETURNING p.role, p.display_name, p.updated_at
  INTO role, display_name, updated_at;

  v_new := jsonb_build_object('account_state', p_account_state);

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'profile.account_state_changed',
    'profiles',
    p_profile_id,
    v_previous,
    v_new,
    v_reason,
    v_correlation_id
  );

  profile_id := p_profile_id;
  account_state := p_account_state;
  student_id := (
    SELECT s.id FROM public.students AS s WHERE s.profile_id = p_profile_id LIMIT 1
  );
  teacher_id := (
    SELECT t.id FROM public.teachers AS t WHERE t.profile_id = p_profile_id LIMIT 1
  );
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Student master data
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_create_student(
  p_student_code text,
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
  v_id uuid;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_code := reve_private.validate_person_code(p_student_code);
  v_name := NULLIF(btrim(COALESCE(p_name, '')), '');

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

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
      'operational_status', operational_status
    ),
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_update_student(
  p_student_id uuid,
  p_expected_updated_at timestamptz,
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
  v_row public.students%ROWTYPE;
  v_name text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_name := NULLIF(btrim(COALESCE(p_name, '')), '');

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  SELECT *
  INTO v_row
  FROM public.students AS s
  WHERE s.id = p_student_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  v_previous := jsonb_build_object(
    'name', v_row.name,
    'phone', v_row.phone,
    'email', v_row.email
  );

  UPDATE public.students AS s
  SET
    name = v_name,
    phone = reve_private.normalize_optional_text(p_phone),
    email = reve_private.normalize_optional_text(p_email)
  WHERE s.id = p_student_id
  RETURNING
    s.id, s.student_code, s.name, s.operational_status, s.profile_id, s.created_at, s.updated_at
  INTO student_id, student_code, student_name, operational_status, linked_profile_id, created_at, updated_at;

  v_new := jsonb_build_object(
    'name', student_name,
    'phone', (SELECT s.phone FROM public.students AS s WHERE s.id = p_student_id),
    'email', (SELECT s.email FROM public.students AS s WHERE s.id = p_student_id)
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'student.updated',
    'students',
    p_student_id,
    v_previous,
    v_new,
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_set_student_active(
  p_student_id uuid,
  p_operational_status text,
  p_reason text,
  p_expected_updated_at timestamptz
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
  v_row public.students%ROWTYPE;
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  IF p_operational_status NOT IN ('active', 'inactive', 'archived') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_STATUS';
  END IF;

  SELECT *
  INTO v_row
  FROM public.students AS s
  WHERE s.id = p_student_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF p_operational_status <> 'active'
    AND v_row.profile_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.profiles AS p
      WHERE p.id = v_row.profile_id
        AND p.account_state = 'active'
    ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_LINK_CONFLICT';
  END IF;

  v_previous := jsonb_build_object('operational_status', v_row.operational_status);

  UPDATE public.students AS s
  SET operational_status = p_operational_status
  WHERE s.id = p_student_id
  RETURNING
    s.id, s.student_code, s.name, s.operational_status, s.profile_id, s.created_at, s.updated_at
  INTO student_id, student_code, student_name, operational_status, linked_profile_id, created_at, updated_at;

  v_new := jsonb_build_object('operational_status', operational_status);

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'student.status_changed',
    'students',
    p_student_id,
    v_previous,
    v_new,
    v_reason,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Teacher master data
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_create_teacher(
  p_teacher_code text,
  p_name text,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS TABLE (
  teacher_id uuid,
  teacher_code text,
  teacher_name text,
  is_active boolean,
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
  v_code := reve_private.validate_person_code(p_teacher_code);
  v_name := NULLIF(btrim(COALESCE(p_name, '')), '');

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  INSERT INTO public.teachers AS ins (
    teacher_code, name, phone, email, is_active
  ) VALUES (
    v_code,
    v_name,
    reve_private.normalize_optional_text(p_phone),
    reve_private.normalize_optional_text(p_email),
    true
  )
  RETURNING ins.id, ins.teacher_code, ins.name, ins.is_active, ins.profile_id, ins.created_at, ins.updated_at
  INTO teacher_id, teacher_code, teacher_name, is_active, linked_profile_id, created_at, updated_at;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'teacher.created',
    'teachers',
    teacher_id,
    NULL,
    jsonb_build_object(
      'teacher_code', teacher_code,
      'name', teacher_name,
      'is_active', is_active
    ),
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_update_teacher(
  p_teacher_id uuid,
  p_expected_updated_at timestamptz,
  p_name text,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS TABLE (
  teacher_id uuid,
  teacher_code text,
  teacher_name text,
  is_active boolean,
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
  v_row public.teachers%ROWTYPE;
  v_name text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_name := NULLIF(btrim(COALESCE(p_name, '')), '');

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  SELECT *
  INTO v_row
  FROM public.teachers AS t
  WHERE t.id = p_teacher_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  v_previous := jsonb_build_object(
    'name', v_row.name,
    'phone', v_row.phone,
    'email', v_row.email
  );

  UPDATE public.teachers AS t
  SET
    name = v_name,
    phone = reve_private.normalize_optional_text(p_phone),
    email = reve_private.normalize_optional_text(p_email)
  WHERE t.id = p_teacher_id
  RETURNING
    t.id, t.teacher_code, t.name, t.is_active, t.profile_id, t.created_at, t.updated_at
  INTO teacher_id, teacher_code, teacher_name, is_active, linked_profile_id, created_at, updated_at;

  v_new := jsonb_build_object(
    'name', teacher_name,
    'phone', (SELECT t.phone FROM public.teachers AS t WHERE t.id = p_teacher_id),
    'email', (SELECT t.email FROM public.teachers AS t WHERE t.id = p_teacher_id)
  );

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'teacher.updated',
    'teachers',
    p_teacher_id,
    v_previous,
    v_new,
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_set_teacher_active(
  p_teacher_id uuid,
  p_is_active boolean,
  p_reason text,
  p_expected_updated_at timestamptz
)
RETURNS TABLE (
  teacher_id uuid,
  teacher_code text,
  teacher_name text,
  is_active boolean,
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
  v_row public.teachers%ROWTYPE;
  v_reason text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb;
  v_new jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');

  IF v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_REASON_REQUIRED';
  END IF;

  SELECT *
  INTO v_row
  FROM public.teachers AS t
  WHERE t.id = p_teacher_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF NOT p_is_active THEN
    IF reve_private.teacher_has_future_active_assignments(p_teacher_id) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVE_ASSIGNMENTS_EXIST';
    END IF;
    IF v_row.profile_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.profiles AS p
        WHERE p.id = v_row.profile_id
          AND p.account_state = 'active'
      ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PROFILE_LINK_CONFLICT';
    END IF;
  END IF;

  v_previous := jsonb_build_object('is_active', v_row.is_active);

  UPDATE public.teachers AS t
  SET is_active = p_is_active
  WHERE t.id = p_teacher_id
  RETURNING
    t.id, t.teacher_code, t.name, t.is_active, t.profile_id, t.created_at, t.updated_at
  INTO teacher_id, teacher_code, teacher_name, is_active, linked_profile_id, created_at, updated_at;

  v_new := jsonb_build_object('is_active', is_active);

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'teacher.status_changed',
    'teachers',
    p_teacher_id,
    v_previous,
    v_new,
    v_reason,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Security grants
-- ===========================================================================

REVOKE ALL ON FUNCTION reve_private.auth_user_exists(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.assert_active_owner_caller() FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.count_active_owners() FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.assert_not_last_active_owner(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.validate_profile_role_links(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.teacher_has_future_active_assignments(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.normalize_optional_text(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.validate_person_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.clear_profile_entity_links(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reve_bootstrap_first_owner(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_bootstrap_first_owner(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reve_bootstrap_first_owner(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.reve_owner_provision_profile(uuid, text, text, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_provision_profile(uuid, text, text, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_provision_profile(uuid, text, text, uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_set_profile_role(uuid, text, text, timestamptz, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_set_profile_role(uuid, text, text, timestamptz, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_set_profile_role(uuid, text, text, timestamptz, uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_set_profile_active(uuid, text, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_set_profile_active(uuid, text, text, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_set_profile_active(uuid, text, text, timestamptz) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_create_student(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_create_student(text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_create_student(text, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_update_student(uuid, timestamptz, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_update_student(uuid, timestamptz, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_update_student(uuid, timestamptz, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_set_student_active(uuid, text, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_set_student_active(uuid, text, text, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_set_student_active(uuid, text, text, timestamptz) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_create_teacher(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_create_teacher(text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_create_teacher(text, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_update_teacher(uuid, timestamptz, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_update_teacher(uuid, timestamptz, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_update_teacher(uuid, timestamptz, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_set_teacher_active(uuid, boolean, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_set_teacher_active(uuid, boolean, text, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_set_teacher_active(uuid, boolean, text, timestamptz) TO authenticated;

-- REVE ACADEMY OS Phase 0B-3B-2B-3B — course and course product master data
-- Owner-only RPCs; no direct authenticated writes to courses / course_products

-- ===========================================================================
-- Lint fix — remove unused variable from student create
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

-- ===========================================================================
-- Internal helpers
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.normalize_catalog_code(p_code text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_code text := upper(btrim(COALESCE(p_code, '')));
BEGIN
  IF v_code = '' OR char_length(v_code) > 32 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_CODE';
  END IF;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.product_has_pending_payments(p_course_product_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.payments AS pay
    WHERE pay.course_product_id = p_course_product_id
      AND pay.status = 'pending'
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.course_has_active_products(p_course_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.course_products AS cp
    WHERE cp.course_id = p_course_id
      AND cp.is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.course_has_active_operational_dependencies(p_course_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.passes AS p
    WHERE p.course_id = p_course_id
      AND p.status IN ('active', 'reserved')
  )
  OR EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.course_id = p_course_id
      AND l.status = 'scheduled'
      AND l.scheduled_at IS NOT NULL
      AND l.scheduled_at > now()
  )
  OR EXISTS (
    SELECT 1
    FROM public.payments AS pay
    WHERE pay.course_id = p_course_id
      AND pay.status = 'pending'
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.course_has_blocking_dependencies(p_course_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT reve_private.course_has_active_products(p_course_id)
    OR reve_private.course_has_active_operational_dependencies(p_course_id);
$$;

CREATE OR REPLACE FUNCTION reve_private.assert_course_deactivation_allowed(p_course_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF reve_private.course_has_active_products(p_course_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_HAS_ACTIVE_PRODUCTS';
  END IF;

  IF reve_private.course_has_active_operational_dependencies(p_course_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVE_DEPENDENCIES_EXIST';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION reve_private.trg_deferred_validate_active_product_course()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.is_active = true THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.courses AS c
      WHERE c.id = NEW.course_id
        AND c.is_active = true
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_INACTIVE';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_course_products_validate_active_course
  AFTER INSERT OR UPDATE OF is_active, course_id ON public.course_products
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION reve_private.trg_deferred_validate_active_product_course();

-- ===========================================================================
-- Course master data
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
  v_code := reve_private.normalize_catalog_code(p_course_code);
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

CREATE OR REPLACE FUNCTION public.reve_owner_update_course(
  p_course_id uuid,
  p_expected_updated_at timestamptz,
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
  v_row public.courses%ROWTYPE;
  v_name text;
  v_description text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb := '{}'::jsonb;
  v_new jsonb := '{}'::jsonb;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_name := NULLIF(btrim(COALESCE(p_name, '')), '');
  v_description := reve_private.normalize_optional_text(p_description);

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  SELECT *
  INTO v_row
  FROM public.courses AS c
  WHERE c.id = p_course_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_NOT_FOUND';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_row.name = v_name
    AND v_row.description IS NOT DISTINCT FROM v_description THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_CHANGES';
  END IF;

  IF v_row.name IS DISTINCT FROM v_name THEN
    v_previous := v_previous || jsonb_build_object('name', v_row.name);
    v_new := v_new || jsonb_build_object('name', v_name);
  END IF;

  IF v_row.description IS DISTINCT FROM v_description THEN
    v_previous := v_previous || jsonb_build_object('description', v_row.description);
    v_new := v_new || jsonb_build_object('description', v_description);
  END IF;

  UPDATE public.courses AS c
  SET
    name = v_name,
    description = v_description
  WHERE c.id = p_course_id
  RETURNING
    c.id, c.course_code, c.name, c.is_active, c.description, c.created_at, c.updated_at
  INTO course_id, course_code, course_name, is_active, description, created_at, updated_at;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'course.updated',
    'courses',
    p_course_id,
    v_previous,
    v_new,
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_set_course_active(
  p_course_id uuid,
  p_is_active boolean,
  p_reason text,
  p_expected_updated_at timestamptz
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
  v_row public.courses%ROWTYPE;
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
  FROM public.courses AS c
  WHERE c.id = p_course_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_NOT_FOUND';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_row.is_active IS NOT DISTINCT FROM p_is_active THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_CHANGES';
  END IF;

  IF NOT p_is_active THEN
    PERFORM reve_private.assert_course_deactivation_allowed(p_course_id);
  END IF;

  v_previous := jsonb_build_object('is_active', v_row.is_active);

  UPDATE public.courses AS c
  SET is_active = p_is_active
  WHERE c.id = p_course_id
  RETURNING
    c.id, c.course_code, c.name, c.is_active, c.description, c.created_at, c.updated_at
  INTO course_id, course_code, course_name, is_active, description, created_at, updated_at;

  v_new := jsonb_build_object('is_active', is_active);

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'course.status_changed',
    'courses',
    p_course_id,
    v_previous,
    v_new,
    v_reason,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Course product master data
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_owner_create_course_product(
  p_course_id uuid,
  p_product_code text,
  p_product_name text,
  p_default_lesson_count integer,
  p_weekly_frequency integer,
  p_default_tuition_krw integer,
  p_expiration_policy text DEFAULT NULL
)
RETURNS TABLE (
  course_product_id uuid,
  course_id uuid,
  product_code text,
  product_name text,
  default_lesson_count integer,
  weekly_frequency integer,
  default_tuition_krw integer,
  expiration_policy text,
  is_active boolean,
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
  v_course public.courses%ROWTYPE;
  v_code text;
  v_name text;
  v_expiration text;
  v_correlation_id uuid := gen_random_uuid();
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_code := reve_private.normalize_catalog_code(p_product_code);
  v_name := NULLIF(btrim(COALESCE(p_product_name, '')), '');
  v_expiration := reve_private.normalize_optional_text(p_expiration_policy);

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  IF p_default_lesson_count IS NULL OR p_default_lesson_count <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_REGISTERED_COUNT';
  END IF;

  IF p_weekly_frequency IS NULL OR p_weekly_frequency <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_REGISTERED_COUNT';
  END IF;

  IF p_default_tuition_krw IS NULL OR p_default_tuition_krw < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_PRICE';
  END IF;

  SELECT *
  INTO v_course
  FROM public.courses AS c
  WHERE c.id = p_course_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_NOT_FOUND';
  END IF;

  IF NOT v_course.is_active THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_INACTIVE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.course_products AS cp WHERE cp.product_code = v_code
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PRODUCT_CODE_EXISTS';
  END IF;

  INSERT INTO public.course_products AS ins (
    course_id,
    product_code,
    product_name,
    default_lesson_count,
    weekly_frequency,
    default_tuition_krw,
    expiration_policy,
    is_active
  ) VALUES (
    p_course_id,
    v_code,
    v_name,
    p_default_lesson_count,
    p_weekly_frequency,
    p_default_tuition_krw,
    v_expiration,
    true
  )
  RETURNING
    ins.id,
    ins.course_id,
    ins.product_code,
    ins.product_name,
    ins.default_lesson_count,
    ins.weekly_frequency,
    ins.default_tuition_krw,
    ins.expiration_policy,
    ins.is_active,
    ins.created_at,
    ins.updated_at
  INTO
    course_product_id,
    course_id,
    product_code,
    product_name,
    default_lesson_count,
    weekly_frequency,
    default_tuition_krw,
    expiration_policy,
    is_active,
    created_at,
    updated_at;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'course_product.created',
    'course_products',
    course_product_id,
    NULL,
    jsonb_build_object(
      'course_id', course_id,
      'product_code', product_code,
      'product_name', product_name,
      'default_lesson_count', default_lesson_count,
      'weekly_frequency', weekly_frequency,
      'default_tuition_krw', default_tuition_krw,
      'expiration_policy', expiration_policy,
      'is_active', is_active
    ),
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_update_course_product(
  p_course_product_id uuid,
  p_expected_updated_at timestamptz,
  p_product_name text,
  p_default_lesson_count integer,
  p_weekly_frequency integer,
  p_default_tuition_krw integer,
  p_expiration_policy text DEFAULT NULL
)
RETURNS TABLE (
  course_product_id uuid,
  course_id uuid,
  product_code text,
  product_name text,
  default_lesson_count integer,
  weekly_frequency integer,
  default_tuition_krw integer,
  expiration_policy text,
  is_active boolean,
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
  v_row public.course_products%ROWTYPE;
  v_name text;
  v_expiration text;
  v_correlation_id uuid := gen_random_uuid();
  v_previous jsonb := '{}'::jsonb;
  v_new jsonb := '{}'::jsonb;
  v_pricing_change boolean;
BEGIN
  v_actor := reve_private.assert_active_owner_caller();
  v_actor_role := reve_private.current_app_role();
  v_name := NULLIF(btrim(COALESCE(p_product_name, '')), '');
  v_expiration := reve_private.normalize_optional_text(p_expiration_policy);

  IF v_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_NAME';
  END IF;

  IF p_default_lesson_count IS NULL OR p_default_lesson_count <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_REGISTERED_COUNT';
  END IF;

  IF p_weekly_frequency IS NULL OR p_weekly_frequency <= 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_REGISTERED_COUNT';
  END IF;

  IF p_default_tuition_krw IS NULL OR p_default_tuition_krw < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_PRICE';
  END IF;

  SELECT *
  INTO v_row
  FROM public.course_products AS cp
  WHERE cp.id = p_course_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PRODUCT_NOT_FOUND';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_row.product_name = v_name
    AND v_row.default_lesson_count = p_default_lesson_count
    AND v_row.weekly_frequency = p_weekly_frequency
    AND v_row.default_tuition_krw = p_default_tuition_krw
    AND v_row.expiration_policy IS NOT DISTINCT FROM v_expiration THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_CHANGES';
  END IF;

  v_pricing_change :=
    v_row.default_lesson_count IS DISTINCT FROM p_default_lesson_count
    OR v_row.weekly_frequency IS DISTINCT FROM p_weekly_frequency
    OR v_row.default_tuition_krw IS DISTINCT FROM p_default_tuition_krw;

  IF v_pricing_change AND reve_private.product_has_pending_payments(p_course_product_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PENDING_PAYMENT_EXISTS';
  END IF;

  IF v_row.product_name IS DISTINCT FROM v_name THEN
    v_previous := v_previous || jsonb_build_object('product_name', v_row.product_name);
    v_new := v_new || jsonb_build_object('product_name', v_name);
  END IF;

  IF v_row.default_lesson_count IS DISTINCT FROM p_default_lesson_count THEN
    v_previous := v_previous || jsonb_build_object('default_lesson_count', v_row.default_lesson_count);
    v_new := v_new || jsonb_build_object('default_lesson_count', p_default_lesson_count);
  END IF;

  IF v_row.weekly_frequency IS DISTINCT FROM p_weekly_frequency THEN
    v_previous := v_previous || jsonb_build_object('weekly_frequency', v_row.weekly_frequency);
    v_new := v_new || jsonb_build_object('weekly_frequency', p_weekly_frequency);
  END IF;

  IF v_row.default_tuition_krw IS DISTINCT FROM p_default_tuition_krw THEN
    v_previous := v_previous || jsonb_build_object('default_tuition_krw', v_row.default_tuition_krw);
    v_new := v_new || jsonb_build_object('default_tuition_krw', p_default_tuition_krw);
  END IF;

  IF v_row.expiration_policy IS DISTINCT FROM v_expiration THEN
    v_previous := v_previous || jsonb_build_object('expiration_policy', v_row.expiration_policy);
    v_new := v_new || jsonb_build_object('expiration_policy', v_expiration);
  END IF;

  UPDATE public.course_products AS cp
  SET
    product_name = v_name,
    default_lesson_count = p_default_lesson_count,
    weekly_frequency = p_weekly_frequency,
    default_tuition_krw = p_default_tuition_krw,
    expiration_policy = v_expiration
  WHERE cp.id = p_course_product_id
  RETURNING
    cp.id,
    cp.course_id,
    cp.product_code,
    cp.product_name,
    cp.default_lesson_count,
    cp.weekly_frequency,
    cp.default_tuition_krw,
    cp.expiration_policy,
    cp.is_active,
    cp.created_at,
    cp.updated_at
  INTO
    course_product_id,
    course_id,
    product_code,
    product_name,
    default_lesson_count,
    weekly_frequency,
    default_tuition_krw,
    expiration_policy,
    is_active,
    created_at,
    updated_at;

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'course_product.updated',
    'course_products',
    p_course_product_id,
    v_previous,
    v_new,
    NULL,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.reve_owner_set_course_product_active(
  p_course_product_id uuid,
  p_is_active boolean,
  p_reason text,
  p_expected_updated_at timestamptz
)
RETURNS TABLE (
  course_product_id uuid,
  course_id uuid,
  product_code text,
  product_name text,
  default_lesson_count integer,
  weekly_frequency integer,
  default_tuition_krw integer,
  expiration_policy text,
  is_active boolean,
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
  v_row public.course_products%ROWTYPE;
  v_course public.courses%ROWTYPE;
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
  FROM public.course_products AS cp
  WHERE cp.id = p_course_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PRODUCT_NOT_FOUND';
  END IF;

  IF v_row.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF v_row.is_active IS NOT DISTINCT FROM p_is_active THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_CHANGES';
  END IF;

  IF NOT p_is_active THEN
    IF reve_private.product_has_pending_payments(p_course_product_id) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PENDING_PAYMENT_EXISTS';
    END IF;
  ELSE
    SELECT *
    INTO v_course
    FROM public.courses AS c
    WHERE c.id = v_row.course_id;

    IF NOT FOUND OR NOT v_course.is_active THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_COURSE_INACTIVE';
    END IF;
  END IF;

  v_previous := jsonb_build_object('is_active', v_row.is_active);

  UPDATE public.course_products AS cp
  SET is_active = p_is_active
  WHERE cp.id = p_course_product_id
  RETURNING
    cp.id,
    cp.course_id,
    cp.product_code,
    cp.product_name,
    cp.default_lesson_count,
    cp.weekly_frequency,
    cp.default_tuition_krw,
    cp.expiration_policy,
    cp.is_active,
    cp.created_at,
    cp.updated_at
  INTO
    course_product_id,
    course_id,
    product_code,
    product_name,
    default_lesson_count,
    weekly_frequency,
    default_tuition_krw,
    expiration_policy,
    is_active,
    created_at,
    updated_at;

  v_new := jsonb_build_object('is_active', is_active);

  PERFORM reve_private.append_audit_log(
    v_actor,
    v_actor_role,
    'course_product.status_changed',
    'course_products',
    p_course_product_id,
    v_previous,
    v_new,
    v_reason,
    v_correlation_id
  );

  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Renewal integration — require active parent course at payment completion
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.complete_payment_and_renew_pass_internal(
  p_payment_id uuid,
  p_expected_payment_updated_at timestamptz,
  p_paid_amount_krw integer,
  p_payment_method text,
  p_paid_at timestamptz,
  p_idempotency_key text,
  p_actor_profile_id uuid,
  p_actor_role text
)
RETURNS TABLE (
  payment_id uuid,
  payment_status text,
  payment_updated_at timestamptz,
  new_pass_id uuid,
  new_pass_public_code text,
  new_pass_sequence integer,
  new_pass_status text,
  registered_lesson_count integer,
  lesson_rows_created integer,
  schedule_slots_copied integer,
  activation_required boolean,
  activated_at timestamptz,
  first_lesson_at timestamptz,
  idempotent_replay boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_student public.students%ROWTYPE;
  v_course public.courses%ROWTYPE;
  v_product public.course_products%ROWTYPE;
  v_active_pass public.passes%ROWTYPE;
  v_correlation_id uuid := gen_random_uuid();
  v_new_pass_id uuid;
  v_source_pass_id uuid;
  v_sequence integer;
  v_pass_code text;
  v_new_status text;
  v_previous_pass_id uuid;
  v_registered integer;
  v_lessons_created integer := 0;
  v_first_lesson timestamptz;
  v_activated timestamptz;
  v_remaining integer;
  v_gen record;
  v_pass_new jsonb;
  v_payment_previous jsonb;
  v_payment_new jsonb;
  v_slots_copied integer;
BEGIN
  IF NOT reve_private.is_owner() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.payments AS pay
  WHERE pay.id = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'REVE_UNAUTHORIZED';
  END IF;

  IF v_payment.idempotency_key IS DISTINCT FROM p_idempotency_key THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
  END IF;

  IF v_payment.status = 'completed' AND v_payment.renewed_pass_id IS NOT NULL THEN
    IF v_payment.paid_amount_krw IS DISTINCT FROM p_paid_amount_krw
      OR v_payment.payment_method IS DISTINCT FROM p_payment_method THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_IDEMPOTENCY_CONFLICT';
    END IF;

    payment_id := v_payment.id;
    payment_status := v_payment.status;
    payment_updated_at := v_payment.updated_at;
    new_pass_id := v_payment.renewed_pass_id;
    SELECT p.pass_code, p.sequence_number, p.status, p.registered_lesson_count_snapshot,
           p.activated_at
    INTO new_pass_public_code, new_pass_sequence, new_pass_status, registered_lesson_count,
         v_activated
    FROM public.passes AS p
    WHERE p.id = v_payment.renewed_pass_id;
    SELECT count(*)::integer INTO lesson_rows_created
    FROM public.lessons AS l WHERE l.pass_id = v_payment.renewed_pass_id;
    SELECT count(*)::integer INTO schedule_slots_copied
    FROM public.schedule_slots AS ss WHERE ss.pass_id = v_payment.renewed_pass_id;
    activation_required := (new_pass_status = 'reserved');
    activated_at := v_activated;
    first_lesson_at := (
      SELECT min(l.scheduled_at) FROM public.lessons AS l WHERE l.pass_id = v_payment.renewed_pass_id
    );
    idempotent_replay := true;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_payment.status NOT IN ('pending') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
  END IF;

  IF v_payment.updated_at IS DISTINCT FROM p_expected_payment_updated_at THEN
    RAISE EXCEPTION USING ERRCODE = '22000', MESSAGE = 'REVE_STALE_STATE';
  END IF;

  IF p_paid_amount_krw IS NULL OR p_paid_amount_krw < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  IF p_paid_amount_krw IS DISTINCT FROM v_payment.paid_amount_krw THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  IF p_payment_method IS NULL
    OR btrim(p_payment_method) = ''
    OR p_payment_method NOT IN ('cash', 'bank_transfer', 'card', 'other') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_INVALID_PAYMENT_METHOD';
  END IF;

  IF p_paid_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
  END IF;

  SELECT * INTO v_student FROM public.students AS s WHERE s.id = v_payment.student_id;
  SELECT * INTO v_course FROM public.courses AS c WHERE c.id = v_payment.course_id;
  SELECT * INTO v_product
  FROM public.course_products AS cp
  WHERE cp.id = v_payment.course_product_id;

  IF NOT v_course.is_active
    OR v_product.course_id <> v_payment.course_id
    OR NOT v_product.is_active THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_NOT_COMPLETABLE';
  END IF;

  IF p_paid_amount_krw <> v_product.default_tuition_krw THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_PAYMENT_AMOUNT_MISMATCH';
  END IF;

  PERFORM reve_private.renewal_advisory_lock(v_payment.student_id, v_payment.course_id);

  PERFORM 1
  FROM public.passes AS p
  WHERE p.student_id = v_payment.student_id
    AND p.course_id = v_payment.course_id
    AND p.status IN ('active', 'reserved')
  FOR UPDATE;

  SELECT *
  INTO v_active_pass
  FROM public.passes AS p
  WHERE p.student_id = v_payment.student_id
    AND p.course_id = v_payment.course_id
    AND p.status = 'active'
  FOR UPDATE;

  IF FOUND THEN
    SELECT u.remaining_lesson_count
    INTO v_remaining
    FROM reve_private.calculate_pass_usage(v_active_pass.id) AS u;

    IF v_remaining > 0 THEN
      v_new_status := 'reserved';
      v_previous_pass_id := v_active_pass.id;
    ELSIF v_remaining = 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_ACTIVE_PASS_NOT_COMPLETE';
    ELSE
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_USAGE_EXCEEDED';
    END IF;
  ELSE
    v_new_status := 'active';
    v_previous_pass_id := (
      SELECT p.id
      FROM public.passes AS p
      WHERE p.student_id = v_payment.student_id
        AND p.course_id = v_payment.course_id
        AND p.status = 'completed'
      ORDER BY p.sequence_number DESC
      LIMIT 1
    );
  END IF;

  IF v_new_status = 'reserved' AND EXISTS (
    SELECT 1
    FROM public.passes AS rp
    WHERE rp.student_id = v_payment.student_id
      AND rp.course_id = v_payment.course_id
      AND rp.status = 'reserved'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_RESERVED_EXISTS';
  END IF;

  v_source_pass_id := reve_private.find_schedule_source_pass_id_fallback(
    v_payment.student_id, v_payment.course_id
  );

  IF v_source_pass_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.schedule_slots AS ss
    WHERE ss.pass_id = v_source_pass_id AND ss.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  v_sequence := reve_private.next_pass_sequence(v_payment.student_id, v_payment.course_id);
  v_pass_code := reve_private.build_pass_public_code(
    v_course.course_code, v_student.student_code, v_sequence
  );
  v_registered := v_product.default_lesson_count;

  INSERT INTO public.passes (
    pass_code, student_id, course_id, course_product_id,
    sequence_number, status, registered_lesson_count_snapshot,
    weekly_frequency_snapshot, product_name_snapshot, tuition_amount_krw_snapshot,
    start_date, previous_pass_id, creation_reason
  ) VALUES (
    v_pass_code,
    v_payment.student_id,
    v_payment.course_id,
    v_payment.course_product_id,
    v_sequence,
    v_new_status,
    v_registered,
    v_product.weekly_frequency,
    v_product.product_name,
    v_product.default_tuition_krw,
    (p_paid_at AT TIME ZONE 'Asia/Seoul')::date,
    v_previous_pass_id,
    'payment_renewal'
  )
  RETURNING id INTO v_new_pass_id;

  v_pass_new := jsonb_build_object(
    'pass_code', v_pass_code,
    'status', v_new_status,
    'sequence_number', v_sequence,
    'registered_lesson_count_snapshot', v_registered
  );

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'pass.created_by_payment',
    'passes',
    v_new_pass_id,
    NULL,
    v_pass_new,
    NULL,
    v_correlation_id
  );

  v_slots_copied := reve_private.copy_schedule_slots_from_pass(v_source_pass_id, v_new_pass_id);

  IF v_slots_copied = 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'REVE_NO_SCHEDULE';
  END IF;

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'schedule_slots.copied_to_pass',
    'passes',
    v_new_pass_id,
    NULL,
    jsonb_build_object('schedule_slots_copied', v_slots_copied, 'source_pass_id', v_source_pass_id),
    NULL,
    v_correlation_id
  );

  IF v_new_status = 'active' THEN
    v_activated := p_paid_at;
    UPDATE public.passes AS p
    SET activated_at = v_activated
    WHERE p.id = v_new_pass_id;

    SELECT g.lessons_created, g.first_lesson_at
    INTO v_gen
    FROM reve_private.generate_pass_lessons(
      v_new_pass_id,
      v_payment.student_id,
      v_payment.course_id,
      p_paid_at,
      v_registered,
      v_correlation_id,
      p_actor_profile_id,
      p_actor_role
    ) AS g;

    v_lessons_created := v_gen.lessons_created;
    v_first_lesson := v_gen.first_lesson_at;

    UPDATE public.passes AS p
    SET start_date = (v_first_lesson AT TIME ZONE 'Asia/Seoul')::date
    WHERE p.id = v_new_pass_id;
  ELSE
    v_activated := NULL;
    v_first_lesson := NULL;
    v_lessons_created := reve_private.create_pass_lesson_shells(
      v_new_pass_id,
      v_payment.student_id,
      v_payment.course_id,
      v_registered,
      v_correlation_id,
      p_actor_profile_id,
      p_actor_role
    );
  END IF;

  PERFORM reve_private.initialize_pass_sms_notification(
    v_new_pass_id,
    v_payment.student_id,
    v_registered,
    v_correlation_id,
    p_actor_profile_id,
    p_actor_role,
    v_new_status = 'reserved'
  );

  v_payment_previous := jsonb_build_object(
    'status', v_payment.status,
    'renewed_pass_id', v_payment.renewed_pass_id,
    'payment_method', v_payment.payment_method,
    'paid_at', v_payment.paid_at
  );

  UPDATE public.payments AS pay
  SET
    status = 'completed',
    payment_method = p_payment_method,
    paid_at = p_paid_at,
    processed_at = now(),
    renewed_pass_id = v_new_pass_id,
    related_pass_id = COALESCE(pay.related_pass_id, v_previous_pass_id)
  WHERE pay.id = p_payment_id
  RETURNING pay.updated_at INTO payment_updated_at;

  v_payment_new := jsonb_build_object(
    'status', 'completed',
    'renewed_pass_id', v_new_pass_id,
    'payment_method', p_payment_method,
    'paid_at', p_paid_at
  );

  PERFORM reve_private.append_audit_log(
    p_actor_profile_id,
    p_actor_role,
    'payment.completed',
    'payments',
    p_payment_id,
    v_payment_previous,
    v_payment_new,
    NULL,
    v_correlation_id
  );

  payment_id := p_payment_id;
  payment_status := 'completed';
  new_pass_id := v_new_pass_id;
  new_pass_public_code := v_pass_code;
  new_pass_sequence := v_sequence;
  new_pass_status := v_new_status;
  registered_lesson_count := v_registered;
  lesson_rows_created := v_lessons_created;
  schedule_slots_copied := v_slots_copied;
  activation_required := (v_new_status = 'reserved');
  activated_at := v_activated;
  first_lesson_at := v_first_lesson;
  idempotent_replay := false;
  RETURN NEXT;
END;
$$;

-- ===========================================================================
-- Security grants
-- ===========================================================================

REVOKE ALL ON FUNCTION reve_private.normalize_catalog_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.product_has_pending_payments(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.course_has_active_products(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.course_has_active_operational_dependencies(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.course_has_blocking_dependencies(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION reve_private.assert_course_deactivation_allowed(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.reve_owner_create_course(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_create_course(text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_create_course(text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_update_course(uuid, timestamptz, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_update_course(uuid, timestamptz, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_update_course(uuid, timestamptz, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_set_course_active(uuid, boolean, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_set_course_active(uuid, boolean, text, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_set_course_active(uuid, boolean, text, timestamptz) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_create_course_product(uuid, text, text, integer, integer, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_create_course_product(uuid, text, text, integer, integer, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_create_course_product(uuid, text, text, integer, integer, integer, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_update_course_product(uuid, timestamptz, text, integer, integer, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_update_course_product(uuid, timestamptz, text, integer, integer, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_update_course_product(uuid, timestamptz, text, integer, integer, integer, text) TO authenticated;

REVOKE ALL ON FUNCTION public.reve_owner_set_course_product_active(uuid, boolean, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reve_owner_set_course_product_active(uuid, boolean, text, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.reve_owner_set_course_product_active(uuid, boolean, text, timestamptz) TO authenticated;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE (n.nspname = 'reve_private' AND p.proname IN (
      'normalize_catalog_code',
      'product_has_pending_payments',
      'course_has_active_products',
      'course_has_active_operational_dependencies',
      'course_has_blocking_dependencies',
      'assert_course_deactivation_allowed',
      'complete_payment_and_renew_pass_internal'
    ))
    OR (n.nspname = 'public' AND p.proname IN (
      'reve_owner_create_course',
      'reve_owner_update_course',
      'reve_owner_set_course_active',
      'reve_owner_create_course_product',
      'reve_owner_update_course_product',
      'reve_owner_set_course_product_active',
      'reve_owner_create_student'
    ))
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.reve_owner_create_course IS
  'Phase 0B-3B-2B-3B owner-only course creation with immutable course_code.';

COMMENT ON FUNCTION public.reve_owner_update_course IS
  'Phase 0B-3B-2B-3B owner-only course metadata update (name, description).';

COMMENT ON FUNCTION public.reve_owner_set_course_active IS
  'Phase 0B-3B-2B-3B owner-only course activation toggle; deactivation blocked by dependencies.';

COMMENT ON FUNCTION public.reve_owner_create_course_product IS
  'Phase 0B-3B-2B-3B owner-only commercial product creation under an active course.';

COMMENT ON FUNCTION public.reve_owner_update_course_product IS
  'Phase 0B-3B-2B-3B owner-only product update; pricing fields blocked when pending payments exist.';

COMMENT ON FUNCTION public.reve_owner_set_course_product_active IS
  'Phase 0B-3B-2B-3B owner-only product activation toggle.';

-- REVE ACADEMY OS Phase 0B-3B-1 — identity helpers, least-privilege grants, role-scoped RLS
-- Source: docs/rls-policy-design.md, docs/permissions-matrix.md

-- ===========================================================================
-- Private authorization schema (not exposed via Supabase API)
-- ===========================================================================

CREATE SCHEMA reve_private;

COMMENT ON SCHEMA reve_private IS
  'Private authorization helpers for RLS evaluation; not exposed via Supabase Data API.';

REVOKE ALL ON SCHEMA reve_private FROM PUBLIC;
REVOKE ALL ON SCHEMA reve_private FROM anon, authenticated;

-- ===========================================================================
-- Identity and access helper functions
-- ===========================================================================

CREATE OR REPLACE FUNCTION reve_private.current_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT auth.uid();
$$;

CREATE OR REPLACE FUNCTION reve_private.current_app_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p.role
  FROM public.profiles AS p
  WHERE p.id = auth.uid()
    AND p.account_state = 'active';
$$;

CREATE OR REPLACE FUNCTION reve_private.is_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(reve_private.current_app_role() = 'owner', false);
$$;

CREATE OR REPLACE FUNCTION reve_private.current_teacher_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT t.id
  FROM public.teachers AS t
  INNER JOIN public.profiles AS p ON p.id = t.profile_id
  WHERE t.profile_id = auth.uid()
    AND p.account_state = 'active'
    AND p.role = 'teacher';
$$;

CREATE OR REPLACE FUNCTION reve_private.current_student_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT s.id
  FROM public.students AS s
  INNER JOIN public.profiles AS p ON p.id = s.profile_id
  WHERE s.profile_id = auth.uid()
    AND p.account_state = 'active'
    AND p.role = 'student';
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_can_access_lesson(p_lesson_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.id = p_lesson_id
      AND l.assigned_teacher_id = reve_private.current_teacher_id()
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_can_access_student(p_student_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT reve_private.current_teacher_id() IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.lessons AS l
        WHERE l.student_id = p_student_id
          AND l.assigned_teacher_id = reve_private.current_teacher_id()
      )
      OR EXISTS (
        SELECT 1
        FROM public.schedule_slots AS ss
        INNER JOIN public.passes AS p ON p.id = ss.pass_id
        WHERE p.student_id = p_student_id
          AND p.status IN ('active', 'reserved')
          AND ss.teacher_id = reve_private.current_teacher_id()
          AND ss.is_active = true
      )
    );
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_can_access_schedule_slot(p_slot_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    WHERE ss.id = p_slot_id
      AND ss.teacher_id = reve_private.current_teacher_id()
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.teacher_can_access_schedule_request(p_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.schedule_change_requests AS scr
    WHERE scr.id = p_request_id
      AND (
        scr.requesting_profile_id = auth.uid()
        OR reve_private.teacher_can_access_lesson(scr.target_lesson_id)
      )
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.student_owns_lesson(p_lesson_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.lessons AS l
    WHERE l.id = p_lesson_id
      AND l.student_id = reve_private.current_student_id()
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.student_owns_schedule_slot(p_slot_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.schedule_slots AS ss
    INNER JOIN public.passes AS p ON p.id = ss.pass_id
    WHERE ss.id = p_slot_id
      AND p.student_id = reve_private.current_student_id()
      AND p.status IN ('active', 'reserved')
  );
$$;

CREATE OR REPLACE FUNCTION reve_private.student_owns_schedule_request(p_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.schedule_change_requests AS scr
    WHERE scr.id = p_request_id
      AND scr.student_id = reve_private.current_student_id()
  );
$$;

-- Lock down helper ownership and execution
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'reve_private'
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;

GRANT USAGE ON SCHEMA reve_private TO postgres, service_role, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA reve_private
  REVOKE ALL ON FUNCTIONS FROM PUBLIC;

-- ===========================================================================
-- Row Level Security policies (authenticated only; no anon; no DELETE)
-- ===========================================================================

-- profiles -------------------------------------------------------------------
CREATE POLICY profiles_owner_select ON public.profiles
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY profiles_self_select ON public.profiles
  FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()));

-- students -------------------------------------------------------------------
CREATE POLICY students_owner_select ON public.students
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY students_teacher_select ON public.students
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND reve_private.teacher_can_access_student(id)
  );

CREATE POLICY students_self_select ON public.students
  FOR SELECT TO authenticated
  USING (profile_id = (SELECT auth.uid()));

-- teachers -------------------------------------------------------------------
CREATE POLICY teachers_owner_select ON public.teachers
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY teachers_self_select ON public.teachers
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND profile_id = (SELECT auth.uid())
  );

-- courses --------------------------------------------------------------------
CREATE POLICY courses_owner_select ON public.courses
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY courses_teacher_select ON public.courses
  FOR SELECT TO authenticated
  USING (reve_private.current_app_role() = 'teacher' AND is_active = true);

CREATE POLICY courses_student_select ON public.courses
  FOR SELECT TO authenticated
  USING (reve_private.current_app_role() = 'student' AND is_active = true);

-- course_products ------------------------------------------------------------
CREATE POLICY course_products_owner_select ON public.course_products
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

-- passes ---------------------------------------------------------------------
CREATE POLICY passes_owner_select ON public.passes
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

-- schedule_slots -------------------------------------------------------------
CREATE POLICY schedule_slots_owner_select ON public.schedule_slots
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY schedule_slots_teacher_select ON public.schedule_slots
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND reve_private.teacher_can_access_schedule_slot(id)
  );

CREATE POLICY schedule_slots_student_select ON public.schedule_slots
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'student'
    AND reve_private.student_owns_schedule_slot(id)
  );

-- lessons --------------------------------------------------------------------
CREATE POLICY lessons_owner_select ON public.lessons
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY lessons_teacher_select ON public.lessons
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND reve_private.teacher_can_access_lesson(id)
  );

CREATE POLICY lessons_student_select ON public.lessons
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'student'
    AND reve_private.student_owns_lesson(id)
  );

-- payments -------------------------------------------------------------------
CREATE POLICY payments_owner_select ON public.payments
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

-- payment_refunds ------------------------------------------------------------
CREATE POLICY payment_refunds_owner_select ON public.payment_refunds
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

-- sms_notifications ----------------------------------------------------------
CREATE POLICY sms_notifications_owner_select ON public.sms_notifications
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

-- schedule_change_requests ---------------------------------------------------
CREATE POLICY schedule_change_requests_owner_select ON public.schedule_change_requests
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY schedule_change_requests_teacher_select ON public.schedule_change_requests
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND reve_private.teacher_can_access_schedule_request(id)
  );

CREATE POLICY schedule_change_requests_student_select ON public.schedule_change_requests
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'student'
    AND reve_private.student_owns_schedule_request(id)
  );

CREATE POLICY schedule_change_requests_teacher_insert ON public.schedule_change_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    reve_private.current_app_role() = 'teacher'
    AND requesting_profile_id = (SELECT auth.uid())
    AND request_source_role = 'teacher'
    AND status = 'submitted'
    AND decided_by_profile_id IS NULL
    AND decided_at IS NULL
    AND applied_at IS NULL
    AND teacher_suggestion_note IS NULL
    AND owner_decision_note IS NULL
    AND reve_private.teacher_can_access_lesson(target_lesson_id)
    AND student_id = (
      SELECT l.student_id
      FROM public.lessons AS l
      WHERE l.id = target_lesson_id
    )
  );

CREATE POLICY schedule_change_requests_student_insert ON public.schedule_change_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    reve_private.current_app_role() = 'student'
    AND requesting_profile_id = (SELECT auth.uid())
    AND request_source_role = 'student'
    AND status = 'submitted'
    AND decided_by_profile_id IS NULL
    AND decided_at IS NULL
    AND applied_at IS NULL
    AND teacher_suggestion_note IS NULL
    AND owner_decision_note IS NULL
    AND student_id = reve_private.current_student_id()
    AND reve_private.student_owns_lesson(target_lesson_id)
  );

-- lesson_schedule_changes ----------------------------------------------------
CREATE POLICY lesson_schedule_changes_owner_select ON public.lesson_schedule_changes
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY lesson_schedule_changes_teacher_select ON public.lesson_schedule_changes
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND reve_private.teacher_can_access_lesson(lesson_id)
  );

CREATE POLICY lesson_schedule_changes_student_select ON public.lesson_schedule_changes
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'student'
    AND reve_private.student_owns_lesson(lesson_id)
  );

-- lesson_notes ---------------------------------------------------------------
CREATE POLICY lesson_notes_owner_select ON public.lesson_notes
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

CREATE POLICY lesson_notes_teacher_select ON public.lesson_notes
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND reve_private.teacher_can_access_lesson(lesson_id)
  );

CREATE POLICY lesson_notes_student_select ON public.lesson_notes
  FOR SELECT TO authenticated
  USING (
    reve_private.current_app_role() = 'student'
    AND visibility = 'student_visible'
    AND reve_private.student_owns_lesson(lesson_id)
  );

CREATE POLICY lesson_notes_teacher_insert ON public.lesson_notes
  FOR INSERT TO authenticated
  WITH CHECK (
    reve_private.current_app_role() = 'teacher'
    AND author_profile_id = (SELECT auth.uid())
    AND reve_private.teacher_can_access_lesson(lesson_id)
    AND visibility IN ('internal', 'student_visible')
  );

CREATE POLICY lesson_notes_teacher_update ON public.lesson_notes
  FOR UPDATE TO authenticated
  USING (
    reve_private.current_app_role() = 'teacher'
    AND author_profile_id = (SELECT auth.uid())
    AND reve_private.teacher_can_access_lesson(lesson_id)
  )
  WITH CHECK (
    author_profile_id = (SELECT auth.uid())
    AND reve_private.teacher_can_access_lesson(lesson_id)
    AND visibility IN ('internal', 'student_visible')
  );

-- audit_logs -----------------------------------------------------------------
CREATE POLICY audit_logs_owner_select ON public.audit_logs
  FOR SELECT TO authenticated
  USING (reve_private.is_owner());

-- ===========================================================================
-- Least-privilege table grants for authenticated role
-- ===========================================================================

GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT SELECT ON TABLE public.students TO authenticated;
GRANT SELECT ON TABLE public.teachers TO authenticated;
GRANT SELECT ON TABLE public.courses TO authenticated;
GRANT SELECT ON TABLE public.course_products TO authenticated;
GRANT SELECT ON TABLE public.passes TO authenticated;
GRANT SELECT ON TABLE public.schedule_slots TO authenticated;
GRANT SELECT ON TABLE public.lessons TO authenticated;
GRANT SELECT ON TABLE public.payments TO authenticated;
GRANT SELECT ON TABLE public.payment_refunds TO authenticated;
GRANT SELECT ON TABLE public.sms_notifications TO authenticated;
GRANT SELECT ON TABLE public.schedule_change_requests TO authenticated;
GRANT SELECT ON TABLE public.lesson_schedule_changes TO authenticated;
GRANT SELECT ON TABLE public.lesson_notes TO authenticated;
GRANT SELECT ON TABLE public.audit_logs TO authenticated;

GRANT INSERT (
  student_id,
  target_lesson_id,
  requesting_profile_id,
  request_source_role,
  requested_reason,
  proposed_scheduled_at
) ON TABLE public.schedule_change_requests TO authenticated;

GRANT INSERT (
  lesson_id,
  author_profile_id,
  body,
  visibility
) ON TABLE public.lesson_notes TO authenticated;

GRANT UPDATE (body, visibility) ON TABLE public.lesson_notes TO authenticated;

-- anon retains no application-table privileges (Phase 0B-3A revoke preserved)

COMMENT ON SCHEMA public IS
  'REVE ACADEMY OS application schema. RLS enabled with Phase 0B-3B-1 role policies.';

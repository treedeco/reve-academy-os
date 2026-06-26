-- REVE ACADEMY OS Phase 0B-3B-2A — safe student/teacher read RPC projections
-- Source: docs/rls-policy-design.md, docs/trusted-operation-contracts.md, docs/permissions-matrix.md

-- ===========================================================================
-- Student pass and lesson-usage summary
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_get_my_pass_summary()
RETURNS TABLE (
  pass_id uuid,
  pass_code text,
  pass_status text,
  course_id uuid,
  course_code text,
  course_name text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_scheduled_at timestamptz,
  start_date date,
  expires_on date,
  assigned_teacher_display_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.id AS pass_id,
    p.pass_code,
    p.status AS pass_status,
    c.id AS course_id,
    c.course_code,
    c.name AS course_name,
    p.registered_lesson_count_snapshot AS registered_lesson_count,
    COALESCE(usage.used_lesson_count, 0) AS used_lesson_count,
    p.registered_lesson_count_snapshot - COALESCE(usage.used_lesson_count, 0) AS remaining_lesson_count,
    next_lesson.next_scheduled_at,
    p.start_date,
    p.expires_on,
    COALESCE(next_lesson.teacher_name, slot_teacher.teacher_name) AS assigned_teacher_display_name
  FROM public.passes AS p
  INNER JOIN public.courses AS c ON c.id = p.course_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS used_lesson_count
    FROM public.lessons AS l
    WHERE l.pass_id = p.id
      AND l.status IN ('completed', 'same_day_cancelled', 'makeup_completed')
  ) AS usage ON true
  LEFT JOIN LATERAL (
    SELECT
      l.scheduled_at AS next_scheduled_at,
      t.name AS teacher_name
    FROM public.lessons AS l
    INNER JOIN public.teachers AS t ON t.id = l.assigned_teacher_id
    WHERE l.pass_id = p.id
      AND l.status = 'scheduled'
      AND l.scheduled_at > now()
    ORDER BY l.scheduled_at ASC
    LIMIT 1
  ) AS next_lesson ON true
  LEFT JOIN LATERAL (
    SELECT t.name AS teacher_name
    FROM public.schedule_slots AS ss
    INNER JOIN public.teachers AS t ON t.id = ss.teacher_id
    WHERE ss.pass_id = p.id
      AND ss.is_active = true
    ORDER BY ss.slot_order ASC, ss.weekday ASC, ss.local_start_time ASC
    LIMIT 1
  ) AS slot_teacher ON true
  WHERE reve_private.current_app_role() = 'student'
    AND p.student_id = reve_private.current_student_id()
    AND p.status IN ('active', 'reserved')
  ORDER BY
    CASE p.status WHEN 'active' THEN 0 WHEN 'reserved' THEN 1 ELSE 2 END,
    c.course_code,
    p.pass_code;
$$;

-- ===========================================================================
-- Teacher assigned-student operational summary
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_get_my_assigned_student_summaries()
RETURNS TABLE (
  student_id uuid,
  student_code text,
  student_name text,
  course_id uuid,
  course_code text,
  course_name text,
  pass_id uuid,
  pass_code text,
  pass_status text,
  registered_lesson_count integer,
  used_lesson_count integer,
  remaining_lesson_count integer,
  next_assigned_lesson_at timestamptz,
  schedule_weekday smallint,
  schedule_local_start_time time
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    s.id AS student_id,
    s.student_code,
    s.name AS student_name,
    c.id AS course_id,
    c.course_code,
    c.name AS course_name,
    p.id AS pass_id,
    p.pass_code,
    p.status AS pass_status,
    p.registered_lesson_count_snapshot AS registered_lesson_count,
    COALESCE(usage.used_lesson_count, 0) AS used_lesson_count,
    p.registered_lesson_count_snapshot - COALESCE(usage.used_lesson_count, 0) AS remaining_lesson_count,
    next_lesson.next_assigned_lesson_at,
    slot_info.schedule_weekday,
    slot_info.schedule_local_start_time
  FROM public.passes AS p
  INNER JOIN public.students AS s ON s.id = p.student_id
  INNER JOIN public.courses AS c ON c.id = p.course_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS used_lesson_count
    FROM public.lessons AS l
    WHERE l.pass_id = p.id
      AND l.status IN ('completed', 'same_day_cancelled', 'makeup_completed')
  ) AS usage ON true
  LEFT JOIN LATERAL (
    SELECT l.scheduled_at AS next_assigned_lesson_at
    FROM public.lessons AS l
    WHERE l.pass_id = p.id
      AND l.assigned_teacher_id = reve_private.current_teacher_id()
      AND l.status = 'scheduled'
      AND l.scheduled_at > now()
    ORDER BY l.scheduled_at ASC
    LIMIT 1
  ) AS next_lesson ON true
  LEFT JOIN LATERAL (
    SELECT ss.weekday AS schedule_weekday, ss.local_start_time AS schedule_local_start_time
    FROM public.schedule_slots AS ss
    WHERE ss.pass_id = p.id
      AND ss.teacher_id = reve_private.current_teacher_id()
      AND ss.is_active = true
    ORDER BY ss.slot_order ASC, ss.weekday ASC, ss.local_start_time ASC
    LIMIT 1
  ) AS slot_info ON true
  WHERE reve_private.current_app_role() = 'teacher'
    AND p.status IN ('active', 'reserved')
    AND (
      EXISTS (
        SELECT 1
        FROM public.schedule_slots AS ss
        WHERE ss.pass_id = p.id
          AND ss.teacher_id = reve_private.current_teacher_id()
          AND ss.is_active = true
      )
      OR EXISTS (
        SELECT 1
        FROM public.lessons AS l
        WHERE l.pass_id = p.id
          AND l.assigned_teacher_id = reve_private.current_teacher_id()
      )
    )
  ORDER BY s.student_code, c.course_code, p.pass_code;
$$;

-- ===========================================================================
-- Student payment-facing history
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_get_my_payment_summary()
RETURNS TABLE (
  payment_id uuid,
  related_pass_code text,
  course_id uuid,
  course_code text,
  course_name text,
  paid_amount_krw integer,
  payment_status text,
  payment_method text,
  paid_at timestamptz,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    pay.id AS payment_id,
    rp.pass_code AS related_pass_code,
    c.id AS course_id,
    c.course_code,
    c.name AS course_name,
    pay.paid_amount_krw,
    pay.status AS payment_status,
    pay.payment_method,
    pay.paid_at,
    pay.created_at
  FROM public.payments AS pay
  INNER JOIN public.courses AS c ON c.id = pay.course_id
  LEFT JOIN public.passes AS rp ON rp.id = pay.related_pass_id
  WHERE reve_private.current_app_role() = 'student'
    AND pay.student_id = reve_private.current_student_id()
  ORDER BY pay.created_at DESC, pay.id;
$$;

-- ===========================================================================
-- Student-facing teacher display
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_get_my_teacher_display()
RETURNS TABLE (
  teacher_id uuid,
  teacher_code text,
  teacher_name text,
  course_id uuid,
  course_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT DISTINCT
    t.id AS teacher_id,
    t.teacher_code,
    t.name AS teacher_name,
    c.id AS course_id,
    c.name AS course_name
  FROM public.passes AS p
  INNER JOIN public.courses AS c ON c.id = p.course_id
  INNER JOIN (
    SELECT ss.pass_id, ss.teacher_id
    FROM public.schedule_slots AS ss
    WHERE ss.is_active = true
    UNION
    SELECT l.pass_id, l.assigned_teacher_id AS teacher_id
    FROM public.lessons AS l
    WHERE l.status = 'scheduled'
      AND l.scheduled_at > now()
  ) AS link ON link.pass_id = p.id
  INNER JOIN public.teachers AS t ON t.id = link.teacher_id
  WHERE reve_private.current_app_role() = 'student'
    AND p.student_id = reve_private.current_student_id()
    AND p.status IN ('active', 'reserved')
  ORDER BY t.teacher_code, c.name;
$$;

-- ===========================================================================
-- Student-facing current SMS/payment notice (OD-20 provisional)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reve_get_my_current_notice()
RETURNS TABLE (
  pass_id uuid,
  pass_code text,
  course_name text,
  message_body_snapshot text,
  target_date date,
  sent_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.id AS pass_id,
    p.pass_code,
    c.name AS course_name,
    sms.message_body_snapshot,
    sms.target_date,
    sms.sent_at
  FROM public.passes AS p
  INNER JOIN public.courses AS c ON c.id = p.course_id
  INNER JOIN LATERAL (
    SELECT
      n.message_body_snapshot,
      n.target_date,
      n.sent_at
    FROM public.sms_notifications AS n
    WHERE n.pass_id = p.id
      AND n.student_id = p.student_id
      AND n.message_body_snapshot IS NOT NULL
      AND btrim(n.message_body_snapshot) <> ''
    ORDER BY
      CASE n.status
        WHEN 'sent' THEN 0
        WHEN 'target' THEN 1
        WHEN 'scheduled' THEN 2
        WHEN 'exhausted_unsent' THEN 3
        ELSE 4
      END,
      n.target_date DESC NULLS LAST,
      n.sent_at DESC NULLS LAST,
      n.created_at DESC
    LIMIT 1
  ) AS sms ON true
  WHERE reve_private.current_app_role() = 'student'
    AND p.student_id = reve_private.current_student_id()
    AND p.status IN ('active', 'reserved')
  ORDER BY
    CASE p.status WHEN 'active' THEN 0 WHEN 'reserved' THEN 1 ELSE 2 END,
    p.pass_code;
$$;

-- ===========================================================================
-- Function ownership and execution grants
-- ===========================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'reve_get_my_pass_summary',
        'reve_get_my_assigned_student_summaries',
        'reve_get_my_payment_summary',
        'reve_get_my_teacher_display',
        'reve_get_my_current_notice'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;

COMMENT ON FUNCTION public.reve_get_my_pass_summary() IS
  'Phase 0B-3B-2A student safe pass usage summary. Read-only; no financial snapshots.';

COMMENT ON FUNCTION public.reve_get_my_assigned_student_summaries() IS
  'Phase 0B-3B-2A teacher safe assigned-student summary. Read-only; no financial or contact fields.';

COMMENT ON FUNCTION public.reve_get_my_payment_summary() IS
  'Phase 0B-3B-2A student payment-facing history. Read-only; no idempotency or actor fields.';

COMMENT ON FUNCTION public.reve_get_my_teacher_display() IS
  'Phase 0B-3B-2A student teacher display projection. Read-only; no private contact fields.';

COMMENT ON FUNCTION public.reve_get_my_current_notice() IS
  'Phase 0B-3B-2A student current-pass notice (OD-20 provisional). Read-only; no internal SMS metadata.';

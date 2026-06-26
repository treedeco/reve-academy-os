-- REVE ACADEMY OS Phase 0B-3A — core application tables (15)
-- Source: docs/schema-dictionary.md, docs/postgresql-physical-design.md

-- ---------------------------------------------------------------------------
-- profiles (id = auth.users.id)
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE RESTRICT,
  role text NOT NULL,
  display_name text NOT NULL,
  account_state text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_display_name_check CHECK (char_length(display_name) > 0)
);

-- ---------------------------------------------------------------------------
-- students
-- ---------------------------------------------------------------------------
CREATE TABLE public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_code text NOT NULL,
  profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  name text NOT NULL,
  phone text,
  email text,
  operational_status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT students_name_check CHECK (char_length(name) > 0)
);

-- ---------------------------------------------------------------------------
-- teachers
-- ---------------------------------------------------------------------------
CREATE TABLE public.teachers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_code text NOT NULL,
  profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  name text NOT NULL,
  phone text,
  email text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT teachers_name_check CHECK (char_length(name) > 0)
);

-- ---------------------------------------------------------------------------
-- courses
-- ---------------------------------------------------------------------------
CREATE TABLE public.courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_code text NOT NULL,
  name text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT courses_name_check CHECK (char_length(name) > 0)
);

-- ---------------------------------------------------------------------------
-- course_products
-- ---------------------------------------------------------------------------
CREATE TABLE public.course_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE RESTRICT,
  product_code text NOT NULL,
  product_name text NOT NULL,
  default_lesson_count integer NOT NULL,
  weekly_frequency integer NOT NULL,
  default_tuition_krw integer NOT NULL,
  expiration_policy text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT course_products_name_check CHECK (char_length(product_name) > 0)
);

-- ---------------------------------------------------------------------------
-- passes
-- OD-14: start_date column exists; automatic start-date / lesson generation deferred to Phase 0B-3B
-- ---------------------------------------------------------------------------
CREATE TABLE public.passes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pass_code text NOT NULL,
  student_id uuid NOT NULL REFERENCES public.students (id) ON DELETE RESTRICT,
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE RESTRICT,
  course_product_id uuid NOT NULL REFERENCES public.course_products (id) ON DELETE RESTRICT,
  sequence_number integer NOT NULL,
  status text NOT NULL,
  registered_lesson_count_snapshot integer NOT NULL,
  weekly_frequency_snapshot integer NOT NULL,
  product_name_snapshot text NOT NULL,
  tuition_amount_krw_snapshot integer NOT NULL,
  discount_adjustment_krw_snapshot integer DEFAULT 0,
  start_date date NOT NULL,
  expires_on date,
  activated_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  previous_pass_id uuid REFERENCES public.passes (id) ON DELETE RESTRICT,
  correction_source_pass_id uuid REFERENCES public.passes (id) ON DELETE RESTRICT,
  creation_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- schedule_slots
-- ---------------------------------------------------------------------------
CREATE TABLE public.schedule_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pass_id uuid NOT NULL REFERENCES public.passes (id) ON DELETE RESTRICT,
  teacher_id uuid NOT NULL REFERENCES public.teachers (id) ON DELETE RESTRICT,
  weekday smallint NOT NULL,
  local_start_time time NOT NULL,
  duration_minutes integer NOT NULL,
  slot_order integer NOT NULL DEFAULT 1,
  is_active boolean NOT NULL DEFAULT true,
  effective_from date NOT NULL,
  effective_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- lessons (no used_count, remaining_count, is_deducted)
-- ---------------------------------------------------------------------------
CREATE TABLE public.lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pass_id uuid NOT NULL,
  student_id uuid NOT NULL,
  course_id uuid NOT NULL,
  assigned_teacher_id uuid NOT NULL REFERENCES public.teachers (id) ON DELETE RESTRICT,
  schedule_slot_id uuid REFERENCES public.schedule_slots (id) ON DELETE SET NULL,
  sequence_number integer NOT NULL,
  scheduled_at timestamptz NOT NULL,
  actual_start_at timestamptz,
  actual_end_at timestamptz,
  status text NOT NULL DEFAULT 'scheduled',
  change_reason text,
  makeup_source_lesson_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- payments
-- OD-18: payment_method nullable for pending; no permanent method CHECK in this phase
-- ---------------------------------------------------------------------------
CREATE TABLE public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students (id) ON DELETE RESTRICT,
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE RESTRICT,
  course_product_id uuid NOT NULL REFERENCES public.course_products (id) ON DELETE RESTRICT,
  related_pass_id uuid REFERENCES public.passes (id) ON DELETE RESTRICT,
  renewed_pass_id uuid REFERENCES public.passes (id) ON DELETE RESTRICT,
  paid_amount_krw integer NOT NULL,
  payment_method text,
  status text NOT NULL DEFAULT 'pending',
  paid_at timestamptz,
  idempotency_key text NOT NULL,
  processed_at timestamptz,
  created_by_profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- payment_refunds (append-only immutable)
-- ---------------------------------------------------------------------------
CREATE TABLE public.payment_refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES public.payments (id) ON DELETE RESTRICT,
  refunded_amount_krw integer NOT NULL,
  refunded_at timestamptz NOT NULL DEFAULT now(),
  reason text NOT NULL,
  actor_profile_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  pass_disposition text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- sms_notifications
-- ---------------------------------------------------------------------------
CREATE TABLE public.sms_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students (id) ON DELETE RESTRICT,
  pass_id uuid NOT NULL REFERENCES public.passes (id) ON DELETE RESTRICT,
  notification_type text NOT NULL DEFAULT 'renewal_reminder',
  status text NOT NULL DEFAULT 'normal',
  message_body_snapshot text,
  target_date date,
  sent_at timestamptz,
  sent_confirmed_by_profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- schedule_change_requests
-- ---------------------------------------------------------------------------
CREATE TABLE public.schedule_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students (id) ON DELETE RESTRICT,
  target_lesson_id uuid NOT NULL REFERENCES public.lessons (id) ON DELETE RESTRICT,
  requesting_profile_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  request_source_role text NOT NULL,
  status text NOT NULL DEFAULT 'submitted',
  requested_reason text NOT NULL,
  proposed_scheduled_at timestamptz,
  teacher_suggestion_note text,
  owner_decision_note text,
  decided_by_profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  decided_at timestamptz,
  applied_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT schedule_change_requests_reason_check CHECK (char_length(requested_reason) > 0)
);

-- ---------------------------------------------------------------------------
-- lesson_schedule_changes (append-only events)
-- ---------------------------------------------------------------------------
CREATE TABLE public.lesson_schedule_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid NOT NULL REFERENCES public.lessons (id) ON DELETE RESTRICT,
  schedule_change_request_id uuid REFERENCES public.schedule_change_requests (id) ON DELETE RESTRICT,
  change_origin text NOT NULL,
  previous_scheduled_at timestamptz NOT NULL,
  new_scheduled_at timestamptz NOT NULL,
  reason text,
  actor_profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- lesson_notes
-- ---------------------------------------------------------------------------
CREATE TABLE public.lesson_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid NOT NULL REFERENCES public.lessons (id) ON DELETE RESTRICT,
  author_profile_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  body text NOT NULL,
  visibility text NOT NULL DEFAULT 'internal',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lesson_notes_body_check CHECK (char_length(body) > 0)
);

-- ---------------------------------------------------------------------------
-- audit_logs (append-only)
-- ---------------------------------------------------------------------------
CREATE TABLE public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_profile_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  actor_role_snapshot text,
  action text NOT NULL,
  resource_table text NOT NULL,
  resource_id uuid NOT NULL,
  previous_value jsonb,
  new_value jsonb,
  reason text,
  correlation_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Self-referencing lesson FK (after lessons table exists)
ALTER TABLE public.lessons
  ADD CONSTRAINT lessons_makeup_source_lesson_id_fkey
  FOREIGN KEY (makeup_source_lesson_id) REFERENCES public.lessons (id) ON DELETE RESTRICT;

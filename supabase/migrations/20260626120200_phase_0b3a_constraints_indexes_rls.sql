-- REVE ACADEMY OS Phase 0B-3A — constraints, indexes, historical protection, RLS enablement
-- Role-specific RLS policies deferred to Phase 0B-3B

-- ===========================================================================
-- Status CHECK constraints (confirmed OD-01 ~ OD-13 values only)
-- OD-18 payment_method: intentionally no enum CHECK (provisional — revisable)
-- ===========================================================================

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
    CHECK (role IN ('owner', 'teacher', 'student')),
  ADD CONSTRAINT profiles_account_state_check
    CHECK (account_state IN ('active', 'inactive', 'suspended'));

ALTER TABLE public.students
  ADD CONSTRAINT students_operational_status_check
    CHECK (operational_status IN ('active', 'inactive', 'archived'));

ALTER TABLE public.passes
  ADD CONSTRAINT passes_status_check
    CHECK (status IN ('reserved', 'active', 'completed', 'expired', 'cancelled')),
  ADD CONSTRAINT passes_registered_lesson_count_positive
    CHECK (registered_lesson_count_snapshot > 0),
  ADD CONSTRAINT passes_weekly_frequency_positive
    CHECK (weekly_frequency_snapshot > 0),
  ADD CONSTRAINT passes_tuition_non_negative
    CHECK (tuition_amount_krw_snapshot >= 0),
  ADD CONSTRAINT passes_discount_non_negative
    CHECK (discount_adjustment_krw_snapshot IS NULL OR discount_adjustment_krw_snapshot >= 0),
  ADD CONSTRAINT passes_sequence_positive
    CHECK (sequence_number > 0),
  ADD CONSTRAINT passes_expires_on_after_start
    CHECK (expires_on IS NULL OR expires_on >= start_date);

ALTER TABLE public.course_products
  ADD CONSTRAINT course_products_lesson_count_positive
    CHECK (default_lesson_count > 0),
  ADD CONSTRAINT course_products_weekly_frequency_positive
    CHECK (weekly_frequency > 0),
  ADD CONSTRAINT course_products_tuition_non_negative
    CHECK (default_tuition_krw >= 0);

ALTER TABLE public.schedule_slots
  ADD CONSTRAINT schedule_slots_weekday_range
    CHECK (weekday >= 0 AND weekday <= 6),
  ADD CONSTRAINT schedule_slots_duration_positive
    CHECK (duration_minutes > 0),
  ADD CONSTRAINT schedule_slots_slot_order_positive
    CHECK (slot_order >= 1),
  ADD CONSTRAINT schedule_slots_effective_until_check
    CHECK (effective_until IS NULL OR effective_until >= effective_from);

ALTER TABLE public.lessons
  ADD CONSTRAINT lessons_status_check
    CHECK (status IN (
      'scheduled', 'completed', 'same_day_cancelled', 'makeup_completed',
      'postponed', 'advance_cancelled', 'teacher_cancelled', 'academy_closed'
    )),
  ADD CONSTRAINT lessons_sequence_positive
    CHECK (sequence_number >= 1),
  ADD CONSTRAINT lessons_actual_end_after_start
    CHECK (
      actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at >= actual_start_at
    ),
  ADD CONSTRAINT lessons_makeup_not_self
    CHECK (makeup_source_lesson_id IS NULL OR makeup_source_lesson_id <> id);

ALTER TABLE public.payments
  ADD CONSTRAINT payments_status_check
    CHECK (status IN ('pending', 'completed', 'cancelled', 'refunded')),
  ADD CONSTRAINT payments_paid_amount_non_negative
    CHECK (paid_amount_krw >= 0);

ALTER TABLE public.payment_refunds
  ADD CONSTRAINT payment_refunds_amount_positive
    CHECK (refunded_amount_krw > 0),
  ADD CONSTRAINT payment_refunds_reason_check
    CHECK (char_length(reason) > 0),
  ADD CONSTRAINT payment_refunds_pass_disposition_check
    CHECK (pass_disposition IN ('reserved_cancelled', 'active_cancelled_future_advance_cancelled'));

ALTER TABLE public.sms_notifications
  ADD CONSTRAINT sms_notifications_status_check
    CHECK (status IN ('normal', 'scheduled', 'target', 'exhausted_unsent', 'sent'));

ALTER TABLE public.schedule_change_requests
  ADD CONSTRAINT schedule_change_requests_status_check
    CHECK (status IN ('submitted', 'under_review', 'approved', 'rejected', 'cancelled', 'applied')),
  ADD CONSTRAINT schedule_change_requests_source_role_check
    CHECK (request_source_role IN ('teacher', 'student', 'owner'));

ALTER TABLE public.lesson_schedule_changes
  ADD CONSTRAINT lesson_schedule_changes_origin_check
    CHECK (change_origin IN ('direct_user', 'cascade_auto', 'trusted_system', 'correction'));

ALTER TABLE public.lesson_notes
  ADD CONSTRAINT lesson_notes_visibility_check
    CHECK (visibility IN ('internal', 'student_visible'));

-- ===========================================================================
-- Unique constraints and composite parent key for lessons
-- ===========================================================================

ALTER TABLE public.students
  ADD CONSTRAINT students_student_code_key UNIQUE (student_code);

ALTER TABLE public.teachers
  ADD CONSTRAINT teachers_teacher_code_key UNIQUE (teacher_code);

ALTER TABLE public.courses
  ADD CONSTRAINT courses_course_code_key UNIQUE (course_code);

ALTER TABLE public.course_products
  ADD CONSTRAINT course_products_product_code_key UNIQUE (product_code);

ALTER TABLE public.passes
  ADD CONSTRAINT passes_pass_code_key UNIQUE (pass_code),
  ADD CONSTRAINT passes_student_course_sequence_key
    UNIQUE (student_id, course_id, sequence_number),
  ADD CONSTRAINT passes_id_student_course_key
    UNIQUE (id, student_id, course_id);

ALTER TABLE public.lessons
  ADD CONSTRAINT lessons_pass_sequence_key UNIQUE (pass_id, sequence_number),
  ADD CONSTRAINT lessons_pass_student_course_fkey
    FOREIGN KEY (pass_id, student_id, course_id)
    REFERENCES public.passes (id, student_id, course_id)
    ON DELETE RESTRICT;

ALTER TABLE public.payments
  ADD CONSTRAINT payments_idempotency_key_key UNIQUE (idempotency_key);

ALTER TABLE public.payment_refunds
  ADD CONSTRAINT payment_refunds_payment_id_key UNIQUE (payment_id);

CREATE UNIQUE INDEX payments_renewed_pass_id_key
  ON public.payments (renewed_pass_id)
  WHERE renewed_pass_id IS NOT NULL;

CREATE UNIQUE INDEX students_profile_id_unique
  ON public.students (profile_id)
  WHERE profile_id IS NOT NULL;

CREATE UNIQUE INDEX teachers_profile_id_unique
  ON public.teachers (profile_id)
  WHERE profile_id IS NOT NULL;

-- Pass partial uniques (OD-07, OD-10)
CREATE UNIQUE INDEX passes_one_active_per_student_course
  ON public.passes (student_id, course_id)
  WHERE status = 'active';

CREATE UNIQUE INDEX passes_one_reserved_per_student_course
  ON public.passes (student_id, course_id)
  WHERE status = 'reserved';

-- Schedule slot duplicate active prevention (OD-04)
CREATE UNIQUE INDEX schedule_slots_no_duplicate_active
  ON public.schedule_slots (pass_id, weekday, local_start_time, teacher_id)
  WHERE is_active = true;

-- Makeup completed once per source (OD-05)
CREATE UNIQUE INDEX lessons_one_makeup_completed_per_source
  ON public.lessons (makeup_source_lesson_id)
  WHERE status = 'makeup_completed';

-- SMS one renewal row per pass (MVP)
CREATE UNIQUE INDEX sms_notifications_pass_type_key
  ON public.sms_notifications (pass_id, notification_type)
  WHERE notification_type = 'renewal_reminder';

-- ===========================================================================
-- Operational indexes (non-redundant with uniques above)
-- ===========================================================================

CREATE INDEX passes_student_course_status_idx
  ON public.passes (student_id, course_id, status);

CREATE INDEX lessons_scheduled_at_idx
  ON public.lessons (scheduled_at);

CREATE INDEX lessons_teacher_scheduled_idx
  ON public.lessons (assigned_teacher_id, scheduled_at);

CREATE INDEX lessons_student_scheduled_idx
  ON public.lessons (student_id, scheduled_at DESC);

CREATE INDEX lessons_makeup_source_idx
  ON public.lessons (makeup_source_lesson_id)
  WHERE makeup_source_lesson_id IS NOT NULL;

CREATE INDEX payments_student_paid_at_idx
  ON public.payments (student_id, paid_at DESC NULLS LAST);

CREATE INDEX sms_status_target_date_idx
  ON public.sms_notifications (status, target_date);

CREATE INDEX schedule_change_requests_status_idx
  ON public.schedule_change_requests (status);

CREATE INDEX audit_logs_resource_created_idx
  ON public.audit_logs (resource_table, resource_id, created_at DESC);

CREATE INDEX audit_logs_correlation_id_idx
  ON public.audit_logs (correlation_id)
  WHERE correlation_id IS NOT NULL;

CREATE INDEX lesson_notes_lesson_id_idx
  ON public.lesson_notes (lesson_id);

CREATE INDEX schedule_slots_pass_active_idx
  ON public.schedule_slots (pass_id, is_active);

CREATE INDEX profiles_role_idx
  ON public.profiles (role);

CREATE INDEX course_products_course_id_idx
  ON public.course_products (course_id);

-- ===========================================================================
-- updated_at triggers (mutable business tables)
-- ===========================================================================

CREATE TRIGGER trg_profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_students_set_updated_at
  BEFORE UPDATE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_teachers_set_updated_at
  BEFORE UPDATE ON public.teachers
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_courses_set_updated_at
  BEFORE UPDATE ON public.courses
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_course_products_set_updated_at
  BEFORE UPDATE ON public.course_products
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_passes_set_updated_at
  BEFORE UPDATE ON public.passes
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_schedule_slots_set_updated_at
  BEFORE UPDATE ON public.schedule_slots
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_lessons_set_updated_at
  BEFORE UPDATE ON public.lessons
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_payments_set_updated_at
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_sms_notifications_set_updated_at
  BEFORE UPDATE ON public.sms_notifications
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_schedule_change_requests_set_updated_at
  BEFORE UPDATE ON public.schedule_change_requests
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

CREATE TRIGGER trg_lesson_notes_set_updated_at
  BEFORE UPDATE ON public.lesson_notes
  FOR EACH ROW EXECUTE FUNCTION public.reve_set_updated_at();

-- ===========================================================================
-- Historical protection triggers
-- DELETE blocked: passes, lessons, payments, sms_notifications
-- UPDATE+DELETE blocked: payment_refunds, lesson_schedule_changes, audit_logs
-- Cancelled-pass terminal / lifecycle UPDATE rules deferred to Phase 0B-3B
-- ===========================================================================

CREATE TRIGGER trg_passes_block_delete
  BEFORE DELETE ON public.passes
  FOR EACH ROW EXECUTE FUNCTION public.reve_block_row_delete();

CREATE TRIGGER trg_lessons_block_delete
  BEFORE DELETE ON public.lessons
  FOR EACH ROW EXECUTE FUNCTION public.reve_block_row_delete();

CREATE TRIGGER trg_payments_block_delete
  BEFORE DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.reve_block_row_delete();

CREATE TRIGGER trg_sms_notifications_block_delete
  BEFORE DELETE ON public.sms_notifications
  FOR EACH ROW EXECUTE FUNCTION public.reve_block_row_delete();

CREATE TRIGGER trg_payment_refunds_block_mutation
  BEFORE UPDATE OR DELETE ON public.payment_refunds
  FOR EACH ROW EXECUTE FUNCTION public.reve_block_row_mutation();

CREATE TRIGGER trg_lesson_schedule_changes_block_mutation
  BEFORE UPDATE OR DELETE ON public.lesson_schedule_changes
  FOR EACH ROW EXECUTE FUNCTION public.reve_block_row_mutation();

CREATE TRIGGER trg_audit_logs_block_mutation
  BEFORE UPDATE OR DELETE ON public.audit_logs
  FOR EACH ROW EXECUTE FUNCTION public.reve_block_row_mutation();

-- ===========================================================================
-- Row Level Security — enable only (default deny; policies in Phase 0B-3B)
-- ===========================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lessons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lesson_schedule_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lesson_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- Least-privilege grants — no broad anon/authenticated table access
-- ===========================================================================

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated;

GRANT USAGE ON SCHEMA public TO postgres, service_role, authenticated, anon;

COMMENT ON SCHEMA public IS
  'REVE ACADEMY OS application schema. RLS enabled; role policies Phase 0B-3B.';

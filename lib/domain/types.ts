export type LessonStatus =
  | 'scheduled'
  | 'completed'
  | 'same_day_cancelled'
  | 'makeup_completed'
  | 'postponed'
  | 'advance_cancelled'
  | 'teacher_cancelled'
  | 'academy_closed';

export type ProfileRole = 'owner' | 'teacher' | 'student';

export type PassStatus = 'reserved' | 'active' | 'completed' | 'expired' | 'cancelled';

export interface OwnerProfile {
  id: string;
  role: ProfileRole;
  display_name: string;
  account_state: string;
}

export interface TodayLessonRow {
  id: string;
  scheduled_at: string;
  status: LessonStatus;
  updated_at: string;
  sequence_number: number;
  registered_lesson_count: number;
  duration_minutes: number;
  student_id: string;
  student_name: string;
  course_id: string;
  course_name: string;
  teacher_id: string;
  teacher_name: string;
  pass_id: string;
  pass_updated_at: string;
  memo_summary: string | null;
}

export interface OwnerLessonOperationsRow {
  id: string;
  sequence_number: number;
  scheduled_at: string;
  status: LessonStatus;
  updated_at: string;
  registered_lesson_count: number;
  duration_minutes: number;
  pass_id: string;
  pass_updated_at: string;
  course_id: string;
  course_name: string;
  student_name: string;
}

export interface StudentListRow {
  id: string;
  name: string;
  student_code: string;
  operational_status: string;
  course_id: string | null;
  course_name: string | null;
  teacher_name: string | null;
  next_lesson_at: string | null;
  remaining_lesson_count: number | null;
  pass_id: string | null;
}

export interface PassUsageSummary {
  pass_id: string;
  pass_code: string;
  pass_status: PassStatus;
  registered_lesson_count: number;
  used_lesson_count: number;
  remaining_lesson_count: number;
  next_lesson_at: string | null;
}

export interface StudentDetailData {
  student: {
    id: string;
    name: string;
    student_code: string;
    operational_status: string;
  };
  teacher_name: string | null;
  current_pass: PassUsageSummary | null;
  schedule_slots: Array<{
    id: string;
    weekday: number;
    local_start_time: string;
    duration_minutes: number;
    teacher_name: string;
  }>;
  lessons: Array<{
    id: string;
    sequence_number: number;
    scheduled_at: string;
    status: LessonStatus;
    updated_at: string;
    registered_lesson_count: number;
    duration_minutes: number;
    pass_id: string;
    pass_updated_at: string;
    course_id: string;
    course_name: string;
  }>;
  lesson_notes: Array<{
    id: string;
    lesson_id: string;
    body: string;
    visibility: string;
    created_at: string;
  }>;
  previous_passes: Array<{
    id: string;
    pass_code: string;
    status: PassStatus;
    sequence_number: number;
  }>;
}

export interface StudentPaymentHistoryRow {
  id: string;
  status: string;
  paid_amount_krw: number;
  paid_at: string | null;
  created_at: string;
  pass_code: string | null;
  product_name: string | null;
  course_name: string | null;
}

export interface StudentRefundHistoryRow {
  id: string;
  payment_id: string;
  refunded_amount_krw: number;
  refunded_at: string;
  reason: string;
  pass_disposition: string;
  payment_paid_at: string | null;
  pass_code: string | null;
  course_name: string | null;
}

export interface StudentScheduleRequestHistoryRow {
  id: string;
  status: string;
  requested_reason: string;
  lesson_sequence_number: number;
  lesson_scheduled_at: string;
  proposed_scheduled_at: string | null;
  approved_scheduled_at: string | null;
  applied_at: string | null;
  cascade_completed_at: string | null;
  cascaded_lesson_count: number | null;
  pass_code: string;
  course_name: string;
  created_at: string;
  updated_at: string;
}

export interface StudentOperationalHistory {
  payments: StudentPaymentHistoryRow[];
  refunds: StudentRefundHistoryRow[];
  schedule_requests: StudentScheduleRequestHistoryRow[];
}

export interface OwnerTeacherRow {
  id: string;
  teacher_code: string;
  name: string;
  phone: string | null;
  email: string | null;
  is_active: boolean;
  updated_at: string;
}

export interface OwnerTeacherMutationResult {
  id: string;
  teacher_code: string;
  name: string;
  phone: string | null;
  email: string | null;
  is_active: boolean;
  updated_at: string;
}

export interface OwnerStudentRow {
  id: string;
  student_code: string;
  name: string;
  phone: string | null;
  email: string | null;
  operational_status: string;
  updated_at: string;
}

export interface OwnerStudentMutationResult {
  id: string;
  student_code: string;
  name: string;
  phone: string | null;
  email: string | null;
  operational_status: string;
  updated_at: string;
}

export interface OwnerEnrollmentTeacherOption {
  id: string;
  teacher_code: string;
  name: string;
}

export interface OwnerEnrollmentCourseOption {
  id: string;
  course_code: string;
  name: string;
}

export interface OwnerEnrollmentProductOption {
  id: string;
  course_id: string;
  product_code: string;
  product_name: string;
  default_lesson_count: number;
  weekly_frequency: number;
  default_tuition_krw: number;
}

export interface EnrollmentScheduleSlotInput {
  teacherId: string;
  weekday: number;
  localTime: string;
  durationMinutes: number;
  slotOrder: number;
}

export interface OwnerInitialEnrollmentResult {
  payment_id: string;
  payment_status: string;
  pass_id: string;
  pass_public_code: string;
  pass_sequence_number: number;
  pass_status: string;
  registered_lesson_count: number;
  schedule_slots_created: number;
  lesson_rows_created: number;
  first_lesson_at: string | null;
  last_lesson_at: string | null;
  sms_notification_status: string | null;
  idempotent_replay: boolean;
}

export interface OwnerEnrollmentCatalog {
  teachers: OwnerEnrollmentTeacherOption[];
  courses: OwnerEnrollmentCourseOption[];
  products: OwnerEnrollmentProductOption[];
}

export interface OwnerCourseProductRow {
  id: string;
  course_id: string;
  course_code: string;
  course_name: string;
  product_code: string;
  product_name: string;
  default_lesson_count: number;
  weekly_frequency: number;
  default_tuition_krw: number;
  expiration_policy: string | null;
  is_active: boolean;
  updated_at: string;
}

export interface OwnerCourseProductMutationResult {
  id: string;
  course_id: string;
  course_code: string;
  course_name: string;
  product_code: string;
  product_name: string;
  default_lesson_count: number;
  weekly_frequency: number;
  default_tuition_krw: number;
  expiration_policy: string | null;
  is_active: boolean;
  updated_at: string;
}

export interface DashboardSummary {
  total_today: number;
  scheduled_count: number;
  completed_count: number;
  cancelled_or_postponed_count: number;
  students_with_lesson_today: number;
}

export interface LessonTransitionResult {
  lesson_id: string;
  previous_status: string;
  new_status: string;
  lesson_updated_at: string;
  pass_id: string;
  pass_status: string;
  registered_lesson_count: number;
  used_lesson_count: number;
  remaining_lesson_count: number;
  next_lesson_at: string | null;
  sms_notification_status: string | null;
  reserved_pass_activation_pending: boolean;
}

export interface DirectRescheduleResult {
  lesson_id: string;
  previous_lesson_status: string;
  new_lesson_status: string;
  previous_scheduled_at: string;
  new_scheduled_at: string;
  lesson_updated_at: string;
  pass_id: string;
  pass_updated_at: string;
  schedule_change_event_id: string;
  cascaded_lesson_count: number;
  sms_notification_status: string | null;
  no_change: boolean;
}

export const ORDINARY_TRANSITION_TARGETS: Record<LessonStatus, LessonStatus[]> = {
  scheduled: [
    'completed',
    'same_day_cancelled',
    'postponed',
    'advance_cancelled',
    'teacher_cancelled',
    'academy_closed',
  ],
  postponed: [
    'scheduled',
    'completed',
    'same_day_cancelled',
    'advance_cancelled',
    'teacher_cancelled',
    'academy_closed',
  ],
  advance_cancelled: ['scheduled', 'completed'],
  teacher_cancelled: ['scheduled', 'makeup_completed'],
  academy_closed: ['scheduled', 'postponed'],
  completed: [],
  same_day_cancelled: [],
  makeup_completed: [],
};

export const STATUS_REQUIRES_REASON = new Set<LessonStatus>([
  'same_day_cancelled',
  'postponed',
  'advance_cancelled',
  'teacher_cancelled',
  'academy_closed',
  'makeup_completed',
]);

export const STATUS_LABELS: Record<LessonStatus, string> = {
  scheduled: '예정',
  completed: '완료',
  same_day_cancelled: '당일 취소',
  makeup_completed: '보강 완료',
  postponed: '연기',
  advance_cancelled: '사전 취소',
  teacher_cancelled: '강사 취소',
  academy_closed: '학원 휴무',
};

export const WEEKDAY_LABELS = ['일', '월', '화', '수', '목', '금', '토'] as const;

export interface OwnerSmsNotificationRow {
  id: string;
  status: string;
  message_body_snapshot: string | null;
  target_date: string | null;
  notification_type: string;
  student_id: string;
  student_name: string;
  pass_id: string;
  pass_code: string;
  pass_status: PassStatus;
  product_name: string | null;
  course_name: string | null;
}

export interface SmsConfirmResult {
  sms_notification_id: string;
  student_id: string;
  pass_id: string;
  previous_status: string;
  new_status: string;
  sent_at: string | null;
  sent_confirmed_by_profile_id: string | null;
  no_change: boolean;
}

export interface OwnerRefundablePaymentRow {
  id: string;
  paid_amount_krw: number;
  paid_at: string | null;
  payment_status: string;
  student_id: string;
  student_name: string;
  course_id: string;
  course_name: string;
  pass_id: string;
  pass_code: string;
  pass_status: PassStatus;
  product_name: string | null;
}

export interface PaymentRefundResult {
  refund_id: string;
  payment_id: string;
  pass_id: string;
  payment_status: string;
  pass_status: string;
  pass_disposition: string;
  refunded_amount_krw: number;
  lessons_advanced_cancelled: number;
  correlation_id: string;
}

export interface OwnerScheduleChangeRequestRow {
  id: string;
  status: string;
  updated_at: string;
  requested_reason: string;
  proposed_scheduled_at: string | null;
  approved_scheduled_at: string | null;
  request_source_role: string;
  applied_at: string | null;
  cascade_completed_at: string | null;
  cascaded_lesson_count: number | null;
  student_id: string;
  student_name: string;
  lesson_id: string;
  lesson_sequence_number: number;
  lesson_scheduled_at: string;
  lesson_status: LessonStatus;
  lesson_updated_at: string;
  pass_id: string;
  pass_code: string;
  pass_status: PassStatus;
  pass_updated_at: string;
  course_id: string;
  course_name: string;
  product_name: string | null;
}

export interface OwnerScheduleChangeQueue {
  reviewRequests: OwnerScheduleChangeRequestRow[];
  cascadePendingRequests: OwnerScheduleChangeRequestRow[];
}

export interface ScheduleChangeReviewResult {
  request_id: string;
  previous_request_status: string;
  new_request_status: string;
  request_updated_at: string;
  approved_scheduled_at: string | null;
  decision: string;
  no_change: boolean;
}

export interface ScheduleChangeApplyResult {
  request_id: string;
  request_status: string;
  request_updated_at: string;
  lesson_id: string;
  previous_lesson_status: string;
  new_lesson_status: string;
  previous_scheduled_at: string;
  new_scheduled_at: string;
  lesson_updated_at: string;
  schedule_change_event_id: string;
  cascaded_lesson_count: number;
  no_change: boolean;
}

export interface ScheduleChangeCascadeResult {
  request_id: string;
  request_status: string;
  request_updated_at: string;
  anchor_lesson_id: string;
  pass_id: string;
  pass_updated_at: string;
  eligible_lesson_count: number;
  cascaded_lesson_count: number;
  skipped_immutable_lesson_count: number;
  first_cascaded_lesson_at: string | null;
  last_cascaded_lesson_at: string | null;
  sms_notification_status: string | null;
  cascade_completed_at: string;
  no_change: boolean;
}

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
  student_id: string;
  student_name: string;
  course_id: string;
  course_name: string;
  teacher_id: string;
  teacher_name: string;
  pass_id: string;
  memo_summary: string | null;
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

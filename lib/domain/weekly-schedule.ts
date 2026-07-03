import type { LessonStatus, PassStatus } from '@/lib/domain/types';
import { STATUS_LABELS } from '@/lib/domain/types';

/** PostgreSQL `dow`: 0=Sunday … 6=Saturday. Display order: Monday → Sunday. */
export const WEEKDAY_LABELS_MON_FIRST = ['월', '화', '수', '목', '금', '토', '일'] as const;

export const WEEKDAY_ORDER_MON_FIRST = [1, 2, 3, 4, 5, 6, 0] as const;

export interface WeeklyScheduleEntry {
  slot_id: string;
  pass_id: string;
  pass_code: string;
  pass_status: PassStatus;
  weekday: number;
  local_start_time: string;
  duration_minutes: number;
  slot_order: number;
  student_id: string;
  student_name: string;
  teacher_id: string;
  teacher_name: string;
  course_id: string;
  course_name: string;
  weekly_frequency: number;
  registered_lesson_count: number;
  next_lesson_id: string | null;
  next_lesson_scheduled_at: string | null;
  next_lesson_status: LessonStatus | null;
}

export interface WeeklyScheduleDayGroup {
  weekday: number;
  weekday_label: string;
  entries: WeeklyScheduleEntry[];
}

export function weekdaySortKey(weekday: number): number {
  return weekday === 0 ? 7 : weekday;
}

export function weekdayLabelMonFirst(weekday: number): string {
  const index = WEEKDAY_ORDER_MON_FIRST.indexOf(weekday as (typeof WEEKDAY_ORDER_MON_FIRST)[number]);
  return index >= 0 ? WEEKDAY_LABELS_MON_FIRST[index] : String(weekday);
}

export function formatLocalTime(time: string): string {
  const parts = time.split(':');
  if (parts.length < 2) {
    return time;
  }
  return `${parts[0].padStart(2, '0')}:${parts[1].padStart(2, '0')}`;
}

export function formatPassStatusLabel(status: PassStatus): string {
  const labels: Record<PassStatus, string> = {
    active: '활성',
    reserved: '예약',
    completed: '완료',
    expired: '만료',
    cancelled: '취소',
  };
  return labels[status];
}

export function formatNextLessonLabel(
  scheduledAt: string | null,
  status: LessonStatus | null,
): string {
  if (!scheduledAt || !status) {
    return '예정 수업 없음';
  }
  const statusLabel = STATUS_LABELS[status] ?? status;
  const dateLabel = new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    month: 'numeric',
    day: 'numeric',
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(scheduledAt));
  return `${dateLabel} · ${statusLabel}`;
}

export function shouldIncludePassSlot(
  passStatus: PassStatus,
  studentId: string,
  courseId: string,
  activeStudentCourseKeys: ReadonlySet<string>,
): boolean {
  if (passStatus === 'active') {
    return true;
  }
  if (passStatus === 'reserved') {
    return !activeStudentCourseKeys.has(`${studentId}:${courseId}`);
  }
  return false;
}

export function buildActiveStudentCourseKeys(
  rows: ReadonlyArray<{ student_id: string; course_id: string; pass_status: PassStatus }>,
): Set<string> {
  const keys = new Set<string>();
  for (const row of rows) {
    if (row.pass_status === 'active') {
      keys.add(`${row.student_id}:${row.course_id}`);
    }
  }
  return keys;
}

export function compareWeeklyScheduleEntries(a: WeeklyScheduleEntry, b: WeeklyScheduleEntry): number {
  const weekdayDiff = weekdaySortKey(a.weekday) - weekdaySortKey(b.weekday);
  if (weekdayDiff !== 0) {
    return weekdayDiff;
  }

  const timeDiff = a.local_start_time.localeCompare(b.local_start_time);
  if (timeDiff !== 0) {
    return timeDiff;
  }

  const teacherDiff = a.teacher_name.localeCompare(b.teacher_name, 'ko');
  if (teacherDiff !== 0) {
    return teacherDiff;
  }

  const studentDiff = a.student_name.localeCompare(b.student_name, 'ko');
  if (studentDiff !== 0) {
    return studentDiff;
  }

  return a.slot_id.localeCompare(b.slot_id);
}

export function groupWeeklyScheduleEntries(entries: WeeklyScheduleEntry[]): WeeklyScheduleDayGroup[] {
  const sorted = [...entries].sort(compareWeeklyScheduleEntries);
  const byWeekday = new Map<number, WeeklyScheduleEntry[]>();

  for (const entry of sorted) {
    const list = byWeekday.get(entry.weekday) ?? [];
    list.push(entry);
    byWeekday.set(entry.weekday, list);
  }

  return WEEKDAY_ORDER_MON_FIRST.filter((weekday) => byWeekday.has(weekday)).map((weekday) => ({
    weekday,
    weekday_label: weekdayLabelMonFirst(weekday),
    entries: byWeekday.get(weekday) ?? [],
  }));
}

export function pickNextLessonForSlot<
  T extends { schedule_slot_id: string | null; scheduled_at: string; status: LessonStatus; id: string },
>(lessons: readonly T[], slotId: string, referenceIso: string): T | null {
  const eligible = lessons
    .filter((lesson) => lesson.schedule_slot_id === slotId && lesson.scheduled_at >= referenceIso)
    .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));

  return eligible[0] ?? null;
}

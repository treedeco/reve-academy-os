import type { LessonStatus } from '@/lib/domain/types';
import {
  ACADEMY_FIRST_START_MINUTES,
  ACADEMY_LAST_END_MINUTES,
  formatMinutesAsLocalTime,
} from '@/lib/domain/academy-hours';
import { formatLessonProgress } from '@/lib/domain/lesson-correction';
import { weekdayLabelMonFirst, WEEKDAY_ORDER_MON_FIRST } from '@/lib/domain/weekly-schedule';

export const TIMETABLE_INTERVAL_MINUTES = 30;

export const TIMETABLE_START_MINUTES = ACADEMY_FIRST_START_MINUTES;
export const TIMETABLE_END_MINUTES = ACADEMY_LAST_END_MINUTES;

export interface WeeklyTimetableLesson {
  lesson_id: string;
  scheduled_at: string;
  duration_minutes: number;
  weekday: number;
  local_start_minutes: number;
  student_id: string;
  student_name: string;
  teacher_id: string;
  teacher_name: string;
  course_id: string;
  course_name: string;
  lesson_status: LessonStatus;
  sequence_number: number;
  registered_lesson_count: number;
  lesson_progress: string;
}

export interface WeeklyTimetableDayColumn {
  weekday: number;
  weekday_label: string;
  lessons: WeeklyTimetableLesson[];
}

export interface WeeklyTimetableRow {
  start_minutes: number;
  end_minutes: number;
  label: string;
}

export function buildTimetableRows(): WeeklyTimetableRow[] {
  const rows: WeeklyTimetableRow[] = [];
  for (
    let start = TIMETABLE_START_MINUTES;
    start < TIMETABLE_END_MINUTES;
    start += TIMETABLE_INTERVAL_MINUTES
  ) {
    const end = start + TIMETABLE_INTERVAL_MINUTES;
    rows.push({
      start_minutes: start,
      end_minutes: end,
      label: formatMinutesAsLocalTime(start),
    });
  }
  return rows;
}

export function getSeoulWeekBounds(reference = new Date()): { startIso: string; endIso: string } {
  const seoulDateParts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(reference);

  const ref = new Date(`${seoulDateParts}T12:00:00+09:00`);
  const day = ref.getUTCDay();
  const mondayOffset = day === 0 ? -6 : 1 - day;
  const monday = new Date(ref);
  monday.setUTCDate(ref.getUTCDate() + mondayOffset);
  monday.setUTCHours(0, 0, 0, 0);

  const sunday = new Date(monday);
  sunday.setUTCDate(monday.getUTCDate() + 6);
  sunday.setUTCHours(23, 59, 59, 999);

  return {
    startIso: monday.toISOString(),
    endIso: sunday.toISOString(),
  };
}

export function seoulWeekdayFromIso(iso: string): number {
  const weekday = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    weekday: 'short',
  }).format(new Date(iso));
  const map: Record<string, number> = {
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
  };
  return map[weekday] ?? 0;
}

export function seoulLocalStartMinutes(iso: string): number {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Seoul',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const parts = formatter.formatToParts(new Date(iso));
  const hour = Number.parseInt(parts.find((part) => part.type === 'hour')?.value ?? '0', 10);
  const minute = Number.parseInt(parts.find((part) => part.type === 'minute')?.value ?? '0', 10);
  return hour * 60 + minute;
}

export function computeTimetablePlacement(
  startMinutes: number,
  durationMinutes: number,
): { rowStart: number; rowSpan: number } | null {
  if (startMinutes < TIMETABLE_START_MINUTES || startMinutes >= TIMETABLE_END_MINUTES) {
    return null;
  }
  const rowStart = Math.floor((startMinutes - TIMETABLE_START_MINUTES) / TIMETABLE_INTERVAL_MINUTES);
  const rowSpan = Math.max(1, Math.ceil(durationMinutes / TIMETABLE_INTERVAL_MINUTES));
  return { rowStart, rowSpan };
}

export function groupTimetableLessonsByWeekday(
  lessons: WeeklyTimetableLesson[],
): WeeklyTimetableDayColumn[] {
  const byWeekday = new Map<number, WeeklyTimetableLesson[]>();
  for (const lesson of lessons) {
    const list = byWeekday.get(lesson.weekday) ?? [];
    list.push(lesson);
    byWeekday.set(lesson.weekday, list);
  }

  return WEEKDAY_ORDER_MON_FIRST.map((weekday) => ({
    weekday,
    weekday_label: weekdayLabelMonFirst(weekday),
    lessons: (byWeekday.get(weekday) ?? []).sort(
      (a, b) =>
        a.local_start_minutes - b.local_start_minutes ||
        a.student_name.localeCompare(b.student_name, 'ko'),
    ),
  }));
}

export function mapLessonToTimetableEntry(input: {
  lesson_id: string;
  scheduled_at: string;
  duration_minutes: number;
  student_id: string;
  student_name: string;
  teacher_id: string;
  teacher_name: string;
  course_id: string;
  course_name: string;
  lesson_status: LessonStatus;
  sequence_number: number;
  registered_lesson_count: number;
}): WeeklyTimetableLesson {
  return {
    ...input,
    weekday: seoulWeekdayFromIso(input.scheduled_at),
    local_start_minutes: seoulLocalStartMinutes(input.scheduled_at),
    lesson_progress: formatLessonProgress(input.registered_lesson_count, input.sequence_number),
  };
}

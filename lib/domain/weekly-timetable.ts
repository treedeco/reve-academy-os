import type { LessonStatus } from '@/lib/domain/types';
import {
  ACADEMY_FIRST_START_MINUTES,
  ACADEMY_LAST_END_MINUTES,
  formatMinutesAsLocalTime,
} from '@/lib/domain/academy-hours';
import { formatLessonProgress } from '@/lib/domain/lesson-correction';
import { weekdayLabelMonFirst, WEEKDAY_ORDER_MON_FIRST } from '@/lib/domain/weekly-schedule';

export const TIMETABLE_INTERVAL_MINUTES = 30;

/** Fixed visual height of one 30-minute grid row (px). Shared by overlay math and CSS. */
export const WEEKLY_TIMETABLE_ROW_HEIGHT_PX = 32;

/** Timetable grid displays rows from 10:00 through the 22:00 closing boundary. */
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
  header_label: string;
  date_key: string;
  lessons: WeeklyTimetableLesson[];
}

export interface WeeklyTimetableRow {
  start_minutes: number;
  end_minutes: number;
  label: string;
}

export interface SeoulWeekBounds {
  startIso: string;
  endIso: string;
  mondayDateKey: string;
  sundayDateKey: string;
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

function seoulDateKeyFromReference(reference: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(reference);
}

function addDaysToDateKey(dateKey: string, days: number): string {
  const base = new Date(`${dateKey}T12:00:00+09:00`);
  base.setUTCDate(base.getUTCDate() + days);
  return base.toISOString().slice(0, 10);
}

export function parseWeekReference(weekParam?: string | null): Date {
  const trimmed = weekParam?.trim();
  if (!trimmed || !/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return new Date();
  }
  return new Date(`${trimmed}T12:00:00+09:00`);
}

function seoulWeekdayFromDateKey(dateKey: string): number {
  const weekday = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    weekday: 'short',
  }).format(new Date(`${dateKey}T12:00:00+09:00`));
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

export function getSeoulWeekBounds(reference = new Date()): SeoulWeekBounds {
  const seoulDateKey = seoulDateKeyFromReference(reference);
  const weekday = seoulWeekdayFromDateKey(seoulDateKey);
  const mondayOffset = weekday === 0 ? -6 : 1 - weekday;
  const mondayDateKey = addDaysToDateKey(seoulDateKey, mondayOffset);
  const sundayDateKey = addDaysToDateKey(mondayDateKey, 6);
  const startIso = new Date(`${mondayDateKey}T00:00:00+09:00`).toISOString();
  const endIso = new Date(`${sundayDateKey}T23:59:59.999+09:00`).toISOString();

  return {
    startIso,
    endIso,
    mondayDateKey,
    sundayDateKey,
  };
}

export function shiftWeekReference(reference: Date, weekDelta: number): Date {
  if (weekDelta === 0) {
    return reference;
  }
  const dateKey = seoulDateKeyFromReference(reference);
  return new Date(`${addDaysToDateKey(dateKey, weekDelta * 7)}T12:00:00+09:00`);
}

export function isSameSeoulWeek(a: Date, b: Date): boolean {
  return getSeoulWeekBounds(a).mondayDateKey === getSeoulWeekBounds(b).mondayDateKey;
}

export function formatWeekdayDateHeader(dateKey: string): string {
  const date = new Date(`${dateKey}T12:00:00+09:00`);
  const weekday = new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    weekday: 'short',
  })
    .format(date)
    .replace(/\./g, '')
    .trim();
  const month = Number.parseInt(
    new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Seoul', month: 'numeric' }).format(date),
    10,
  );
  const day = Number.parseInt(
    new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Seoul', day: 'numeric' }).format(date),
    10,
  );
  return `${weekday} ${month}/${day}`;
}

export function buildSeoulWeekDayHeaders(reference = new Date()): Array<{
  weekday: number;
  weekday_label: string;
  header_label: string;
  date_key: string;
}> {
  const { mondayDateKey } = getSeoulWeekBounds(reference);
  return WEEKDAY_ORDER_MON_FIRST.map((weekday, index) => {
    const dateKey = addDaysToDateKey(mondayDateKey, index);
    return {
      weekday,
      weekday_label: weekdayLabelMonFirst(weekday),
      header_label: formatWeekdayDateHeader(dateKey),
      date_key: dateKey,
    };
  });
}

export function buildWeekContextLabel(reference = new Date()): string {
  const { mondayDateKey, sundayDateKey } = getSeoulWeekBounds(reference);
  const startLabel = formatWeekdayDateHeader(mondayDateKey);
  const endLabel = formatWeekdayDateHeader(sundayDateKey);
  return `${startLabel} – ${endLabel} (Asia/Seoul)`;
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

/**
 * Place a lesson on the fixed 30-minute grid.
 * End time is an exclusive visual boundary: 14:00–15:00 occupies rows
 * [14:00–14:30) and [14:30–15:00) only — never the 15:00–15:30 row.
 */
export function computeTimetablePlacement(
  startMinutes: number,
  durationMinutes: number,
): { rowStart: number; rowSpan: number } | null {
  if (
    !Number.isFinite(startMinutes) ||
    !Number.isFinite(durationMinutes) ||
    durationMinutes <= 0 ||
    startMinutes < TIMETABLE_START_MINUTES ||
    startMinutes >= TIMETABLE_END_MINUTES
  ) {
    return null;
  }

  const endMinutes = startMinutes + durationMinutes;
  const rowStart = Math.floor((startMinutes - TIMETABLE_START_MINUTES) / TIMETABLE_INTERVAL_MINUTES);
  const rowEnd = Math.ceil((endMinutes - TIMETABLE_START_MINUTES) / TIMETABLE_INTERVAL_MINUTES);
  const rowSpan = Math.max(1, rowEnd - rowStart);
  return { rowStart, rowSpan };
}

/** Pixel box for absolute overlay on the fixed-height 30-minute grid. */
export function computeTimetableEventBox(
  startMinutes: number,
  durationMinutes: number,
  rowHeightPx: number,
): { top: number; height: number } | null {
  const placement = computeTimetablePlacement(startMinutes, durationMinutes);
  if (!placement || rowHeightPx <= 0) {
    return null;
  }
  return {
    top: placement.rowStart * rowHeightPx,
    height: placement.rowSpan * rowHeightPx,
  };
}

export function buildWeeklyTimetableColumns(
  lessons: WeeklyTimetableLesson[],
  reference = new Date(),
): WeeklyTimetableDayColumn[] {
  const byWeekday = new Map<number, WeeklyTimetableLesson[]>();
  for (const lesson of lessons) {
    const list = byWeekday.get(lesson.weekday) ?? [];
    list.push(lesson);
    byWeekday.set(lesson.weekday, list);
  }

  return buildSeoulWeekDayHeaders(reference).map((header) => ({
    ...header,
    lessons: (byWeekday.get(header.weekday) ?? []).sort(
      (a, b) =>
        a.local_start_minutes - b.local_start_minutes ||
        a.student_name.localeCompare(b.student_name, 'ko'),
    ),
  }));
}

/** @deprecated Use buildWeeklyTimetableColumns for week-aware headers. */
export function groupTimetableLessonsByWeekday(
  lessons: WeeklyTimetableLesson[],
): WeeklyTimetableDayColumn[] {
  return buildWeeklyTimetableColumns(lessons);
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

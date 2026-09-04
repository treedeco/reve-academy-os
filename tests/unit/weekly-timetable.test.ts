import { describe, expect, it } from 'vitest';
import {
  buildSeoulWeekDayHeaders,
  buildTimetableRows,
  buildWeeklyTimetableColumns,
  computeTimetableEventBox,
  computeTimetablePlacement,
  formatWeekdayDateHeader,
  getSeoulWeekBounds,
  mapLessonToTimetableEntry,
  TIMETABLE_END_MINUTES,
  TIMETABLE_INTERVAL_MINUTES,
  TIMETABLE_START_MINUTES,
  WEEKLY_TIMETABLE_ROW_HEIGHT_PX,
} from '@/lib/domain/weekly-timetable';
import { formatLessonProgress } from '@/lib/domain/lesson-correction';

describe('weekly timetable grid', () => {
  it('builds 30-minute rows from 10:00 through 22:00 boundary', () => {
    const rows = buildTimetableRows();
    expect(rows[0]?.start_minutes).toBe(TIMETABLE_START_MINUTES);
    expect(rows[0]?.start_minutes).toBe(10 * 60);
    expect(rows[rows.length - 1]?.end_minutes).toBe(TIMETABLE_END_MINUTES);
    expect(rows.every((row) => row.end_minutes - row.start_minutes === TIMETABLE_INTERVAL_MINUTES)).toBe(
      true,
    );
    expect(rows.some((row) => row.start_minutes === 22 * 60)).toBe(false);
    expect(rows[rows.length - 1]?.end_minutes).toBe(TIMETABLE_END_MINUTES);
    expect(rows[rows.length - 1]?.start_minutes).toBe(TIMETABLE_END_MINUTES - TIMETABLE_INTERVAL_MINUTES);
  });

  it('A: 14:00–14:30 occupies exactly 1 row', () => {
    expect(computeTimetablePlacement(14 * 60, 30)).toEqual({ rowStart: 8, rowSpan: 1 });
  });

  it('B: 14:00–15:00 occupies exactly 2 rows and ends on the 15:00 boundary', () => {
    expect(computeTimetablePlacement(14 * 60, 60)).toEqual({ rowStart: 8, rowSpan: 2 });
    const box = computeTimetableEventBox(14 * 60, 60, WEEKLY_TIMETABLE_ROW_HEIGHT_PX);
    expect(box).toEqual({ top: 8 * WEEKLY_TIMETABLE_ROW_HEIGHT_PX, height: 2 * WEEKLY_TIMETABLE_ROW_HEIGHT_PX });
    const fifteenOClockTop = ((15 * 60 - TIMETABLE_START_MINUTES) / TIMETABLE_INTERVAL_MINUTES) *
      WEEKLY_TIMETABLE_ROW_HEIGHT_PX;
    expect((box?.top ?? 0) + (box?.height ?? 0)).toBe(fifteenOClockTop);
  });

  it('C: 14:00–15:30 occupies exactly 3 rows', () => {
    expect(computeTimetablePlacement(14 * 60, 90)).toEqual({ rowStart: 8, rowSpan: 3 });
  });

  it('D: 14:30–15:30 starts at 14:30 and ends exactly at 15:30', () => {
    expect(computeTimetablePlacement(14 * 60 + 30, 60)).toEqual({ rowStart: 9, rowSpan: 2 });
    const box = computeTimetableEventBox(14 * 60 + 30, 60, WEEKLY_TIMETABLE_ROW_HEIGHT_PX);
    const fifteenThirtyTop =
      ((15 * 60 + 30 - TIMETABLE_START_MINUTES) / TIMETABLE_INTERVAL_MINUTES) *
      WEEKLY_TIMETABLE_ROW_HEIGHT_PX;
    expect((box?.top ?? 0) + (box?.height ?? 0)).toBe(fifteenThirtyTop);
  });

  it('E: pixel height depends only on duration, not content volume', () => {
    const shortLabel = computeTimetableEventBox(14 * 60, 60, WEEKLY_TIMETABLE_ROW_HEIGHT_PX);
    const longLabel = computeTimetableEventBox(14 * 60, 60, WEEKLY_TIMETABLE_ROW_HEIGHT_PX);
    expect(shortLabel).toEqual(longLabel);
    expect(shortLabel?.height).toBe(2 * WEEKLY_TIMETABLE_ROW_HEIGHT_PX);
  });

  it('F: adjacent 14:00–15:00 and 15:00–16:00 touch at 15:00 without overlap', () => {
    const first = computeTimetableEventBox(14 * 60, 60, WEEKLY_TIMETABLE_ROW_HEIGHT_PX);
    const second = computeTimetableEventBox(15 * 60, 60, WEEKLY_TIMETABLE_ROW_HEIGHT_PX);
    expect(first && second).toBeTruthy();
    expect((first?.top ?? 0) + (first?.height ?? 0)).toBe(second?.top);
    expect((second?.top ?? 0) + (second?.height ?? 0)).toBe(
      ((16 * 60 - TIMETABLE_START_MINUTES) / TIMETABLE_INTERVAL_MINUTES) * WEEKLY_TIMETABLE_ROW_HEIGHT_PX,
    );
  });

  it('places 60-minute lessons across two rows from 10:00', () => {
    const placement = computeTimetablePlacement(10 * 60, 60);
    expect(placement).toEqual({ rowStart: 0, rowSpan: 2 });
  });

  it('places 21:00 lesson through 22:00 boundary', () => {
    const placement = computeTimetablePlacement(21 * 60, 60);
    expect(placement).toEqual({ rowStart: 22, rowSpan: 2 });
  });

  it('rejects placements outside operating window', () => {
    expect(computeTimetablePlacement(22 * 60, 30)).toBeNull();
    expect(computeTimetablePlacement(9 * 60 + 30, 60)).toBeNull();
  });

  it('formats lesson progress as total-sequence', () => {
    expect(formatLessonProgress(4, 2)).toBe('4-2');
    expect(formatLessonProgress(8, 5)).toBe('8-5');
  });

  it('G: maps lesson entries with Seoul weekday and progress label', () => {
    const entry = mapLessonToTimetableEntry({
      lesson_id: 'lesson-1',
      scheduled_at: '2026-07-28T01:00:00.000Z',
      duration_minutes: 60,
      student_id: 'student',
      student_name: 'Student',
      teacher_id: 'teacher',
      teacher_name: 'Teacher',
      course_id: 'course',
      course_name: 'Course',
      lesson_status: 'scheduled',
      sequence_number: 2,
      registered_lesson_count: 4,
    });

    expect(entry.weekday).toBe(2);
    expect(entry.local_start_minutes).toBe(10 * 60);
    expect(entry.lesson_progress).toBe(formatLessonProgress(4, 2));
  });

  it('builds weekday date headers for a Seoul week with month boundary labels', () => {
    const reference = new Date('2026-07-30T12:00:00+09:00');
    const headers = buildSeoulWeekDayHeaders(reference);
    expect(headers).toHaveLength(7);
    expect(headers[0]?.header_label).toBe('월 7/27');
    expect(headers[4]?.header_label).toBe('금 7/31');
    expect(headers[5]?.header_label).toBe('토 8/1');
    expect(formatWeekdayDateHeader('2026-07-28')).toBe('화 7/28');
  });

  it('excludes next Monday from the current Seoul week bounds', () => {
    const reference = new Date('2026-07-28T12:00:00+09:00');
    const bounds = getSeoulWeekBounds(reference);
    expect(bounds.mondayDateKey).toBe('2026-07-27');
    expect(bounds.sundayDateKey).toBe('2026-08-02');
    expect(new Date(bounds.endIso).getTime()).toBeLessThan(
      new Date('2026-08-03T00:00:00+09:00').getTime(),
    );
  });

  it('groups lessons under week-aware headers', () => {
    const reference = new Date('2026-07-28T12:00:00+09:00');
    const lesson = mapLessonToTimetableEntry({
      lesson_id: 'lesson-tue',
      scheduled_at: '2026-07-28T01:00:00.000Z',
      duration_minutes: 60,
      student_id: 'student',
      student_name: 'Alpha Student',
      teacher_id: 'teacher',
      teacher_name: 'Teacher',
      course_id: 'course',
      course_name: 'Course',
      lesson_status: 'scheduled',
      sequence_number: 1,
      registered_lesson_count: 4,
    });
    const columns = buildWeeklyTimetableColumns([lesson], reference);
    const tuesday = columns.find((column) => column.weekday === 2);
    expect(tuesday?.header_label).toBe('화 7/28');
    expect(tuesday?.lessons).toHaveLength(1);
  });
});

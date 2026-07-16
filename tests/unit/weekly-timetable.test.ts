import { describe, expect, it } from 'vitest';
import {
  buildTimetableRows,
  computeTimetablePlacement,
  mapLessonToTimetableEntry,
  TIMETABLE_END_MINUTES,
  TIMETABLE_INTERVAL_MINUTES,
  TIMETABLE_START_MINUTES,
} from '@/lib/domain/weekly-timetable';
import { formatLessonProgress } from '@/lib/domain/lesson-correction';

describe('weekly timetable grid', () => {
  it('builds 30-minute rows from 13:00 through 22:00 boundary', () => {
    const rows = buildTimetableRows();
    expect(rows[0]?.start_minutes).toBe(TIMETABLE_START_MINUTES);
    expect(rows[rows.length - 1]?.end_minutes).toBe(TIMETABLE_END_MINUTES);
    expect(rows.every((row) => row.end_minutes - row.start_minutes === TIMETABLE_INTERVAL_MINUTES)).toBe(
      true,
    );
    expect(rows.some((row) => row.start_minutes === 22 * 60)).toBe(false);
    expect(rows[rows.length - 1]?.end_minutes).toBe(TIMETABLE_END_MINUTES);
    expect(rows[rows.length - 1]?.start_minutes).toBe(TIMETABLE_END_MINUTES - TIMETABLE_INTERVAL_MINUTES);
  });

  it('places 60-minute lessons across two rows', () => {
    const placement = computeTimetablePlacement(13 * 60, 60);
    expect(placement).toEqual({ rowStart: 0, rowSpan: 2 });
  });

  it('places 21:00 lesson through 22:00 boundary', () => {
    const placement = computeTimetablePlacement(21 * 60, 60);
    expect(placement).toEqual({ rowStart: 16, rowSpan: 2 });
  });

  it('rejects placements outside operating window', () => {
    expect(computeTimetablePlacement(22 * 60, 30)).toBeNull();
    expect(computeTimetablePlacement(12 * 60, 60)).toBeNull();
  });

  it('formats lesson progress as total-sequence', () => {
    expect(formatLessonProgress(4, 2)).toBe('4-2');
    expect(formatLessonProgress(8, 5)).toBe('8-5');
  });

  it('maps lesson entries with Seoul weekday and progress label', () => {
    const entry = mapLessonToTimetableEntry({
      lesson_id: 'lesson-1',
      scheduled_at: '2026-07-15T04:00:00.000Z',
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

    expect(entry.weekday).toBe(3);
    expect(entry.local_start_minutes).toBe(13 * 60);
    expect(entry.lesson_progress).toBe(formatLessonProgress(4, 2));
  });
});

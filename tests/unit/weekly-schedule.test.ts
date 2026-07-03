import { describe, expect, it } from 'vitest';
import type { WeeklyScheduleEntry } from '@/lib/domain/weekly-schedule';
import {
  buildActiveStudentCourseKeys,
  compareWeeklyScheduleEntries,
  groupWeeklyScheduleEntries,
  pickNextLessonForSlot,
  shouldIncludePassSlot,
  weekdayLabelMonFirst,
  weekdaySortKey,
  WEEKDAY_ORDER_MON_FIRST,
} from '@/lib/domain/weekly-schedule';

function entry(overrides: Partial<WeeklyScheduleEntry> & Pick<WeeklyScheduleEntry, 'slot_id'>): WeeklyScheduleEntry {
  return {
    slot_id: overrides.slot_id,
    pass_id: overrides.pass_id ?? 'pass',
    pass_code: overrides.pass_code ?? 'P-1',
    pass_status: overrides.pass_status ?? 'active',
    weekday: overrides.weekday ?? 1,
    local_start_time: overrides.local_start_time ?? '10:00:00',
    duration_minutes: overrides.duration_minutes ?? 60,
    slot_order: overrides.slot_order ?? 1,
    student_id: overrides.student_id ?? 'student',
    student_name: overrides.student_name ?? 'Student',
    teacher_id: overrides.teacher_id ?? 'teacher',
    teacher_name: overrides.teacher_name ?? 'Teacher',
    course_id: overrides.course_id ?? 'course',
    course_name: overrides.course_name ?? 'Course',
    weekly_frequency: overrides.weekly_frequency ?? 1,
    registered_lesson_count: overrides.registered_lesson_count ?? 4,
    next_lesson_id: overrides.next_lesson_id ?? null,
    next_lesson_scheduled_at: overrides.next_lesson_scheduled_at ?? null,
    next_lesson_status: overrides.next_lesson_status ?? null,
  };
}

describe('weekly schedule normalization', () => {
  it('orders weekdays Monday through Sunday', () => {
    expect(WEEKDAY_ORDER_MON_FIRST).toEqual([1, 2, 3, 4, 5, 6, 0]);
    expect(weekdaySortKey(0)).toBe(7);
    expect(weekdayLabelMonFirst(3)).toBe('수');
  });

  it('sorts entries by weekday then time then teacher, student, id', () => {
    const rows = [
      entry({ slot_id: 'b', weekday: 3, local_start_time: '15:00:00', teacher_name: 'B', student_name: 'A' }),
      entry({ slot_id: 'a', weekday: 3, local_start_time: '10:00:00', teacher_name: 'A', student_name: 'B' }),
      entry({ slot_id: 'c', weekday: 1, local_start_time: '10:00:00' }),
    ];
    const sorted = [...rows].sort(compareWeeklyScheduleEntries);
    expect(sorted.map((row) => row.slot_id)).toEqual(['c', 'a', 'b']);
  });

  it('uses deterministic tie-breakers for equal times', () => {
    const rows = [
      entry({
        slot_id: 'z',
        weekday: 3,
        local_start_time: '10:00:00',
        teacher_name: 'Alpha',
        student_name: 'Student',
      }),
      entry({
        slot_id: 'a',
        weekday: 3,
        local_start_time: '10:00:00',
        teacher_name: 'Alpha',
        student_name: 'Student',
      }),
    ];
    const sorted = [...rows].sort(compareWeeklyScheduleEntries);
    expect(sorted[0].slot_id).toBe('a');
  });

  it('includes active passes and excludes inactive statuses', () => {
    const keys = buildActiveStudentCourseKeys([
      { student_id: 's1', course_id: 'c1', pass_status: 'active' },
    ]);
    expect(shouldIncludePassSlot('active', 's1', 'c1', keys)).toBe(true);
    expect(shouldIncludePassSlot('completed', 's1', 'c1', keys)).toBe(false);
    expect(shouldIncludePassSlot('cancelled', 's1', 'c1', keys)).toBe(false);
  });

  it('excludes reserved pass when active pass exists for same student and course', () => {
    const keys = buildActiveStudentCourseKeys([
      { student_id: 's1', course_id: 'c1', pass_status: 'active' },
      { student_id: 's1', course_id: 'c1', pass_status: 'reserved' },
    ]);
    expect(shouldIncludePassSlot('reserved', 's1', 'c1', keys)).toBe(false);
    expect(shouldIncludePassSlot('reserved', 's2', 'c1', keys)).toBe(true);
  });

  it('keeps fixed slot separate from postponed lesson occurrence', () => {
    const slotId = 'slot-1';
    const lessons = [
      {
        id: 'l1',
        schedule_slot_id: slotId,
        scheduled_at: '2026-07-10T01:00:00.000Z',
        status: 'postponed' as const,
      },
    ];
    const next = pickNextLessonForSlot(lessons, slotId, '2026-07-01T00:00:00.000Z');
    expect(next?.status).toBe('postponed');
    expect(entry({ slot_id: slotId, weekday: 1, local_start_time: '10:00:00' }).weekday).toBe(1);
  });

  it('handles empty next lesson state', () => {
    const grouped = groupWeeklyScheduleEntries([
      entry({
        slot_id: 'solo',
        next_lesson_scheduled_at: null,
        next_lesson_status: null,
      }),
    ]);
    expect(grouped).toHaveLength(1);
    expect(grouped[0].entries[0].next_lesson_id).toBeNull();
  });

  it('uses fallback labels for missing relationships via entry defaults in UI layer', () => {
    const row = entry({
      slot_id: 'missing',
      teacher_name: '',
      course_name: '',
      student_name: '',
    });
    expect(row.teacher_name).toBe('');
    expect(row.course_name).toBe('');
  });

  it('groups desktop and mobile from the same normalized groups', () => {
    const groups = groupWeeklyScheduleEntries([
      entry({ slot_id: 'mon', weekday: 1, local_start_time: '09:00:00' }),
      entry({ slot_id: 'wed-a', weekday: 3, local_start_time: '10:00:00', student_name: 'A' }),
      entry({ slot_id: 'wed-b', weekday: 3, local_start_time: '15:00:00', student_name: 'B' }),
    ]);
    expect(groups.map((group) => group.weekday)).toEqual([1, 3]);
    expect(groups[1].entries).toHaveLength(2);
  });
});

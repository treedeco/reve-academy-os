import { describe, expect, it } from 'vitest';
import {
  buildAcademyTimeOptions,
  buildEmptyFixedScheduleSlotInputs,
  formatFixedWeeklyScheduleLabel,
  formatScheduleCollisionSummary,
  formatSeoulWeekdayLabel,
  validateRecurringScheduleChange,
  validateSingleScheduleChange,
} from '@/lib/domain/owner-schedule-edit';

describe('owner schedule edit domain', () => {
  it('builds 30-minute academy time options from 10:00 through 21:00', () => {
    const options = buildAcademyTimeOptions();
    expect(options[0]).toBe('10:00');
    expect(options[1]).toBe('10:30');
    expect(options[options.length - 1]).toBe('21:00');
    expect(options).toContain('14:00');
    expect(options).toContain('20:30');
  });

  it('formats fixed weekly schedule labels in Korean', () => {
    expect(formatFixedWeeklyScheduleLabel({ weekday: 2, localTime: '10:00:00' })).toBe(
      '매주 화요일 10:00',
    );
  });

  it('derives Seoul weekday labels from date keys', () => {
    expect(formatSeoulWeekdayLabel('2026-07-28')).toBe('화');
  });

  it('rejects single schedule change without reason', () => {
    expect(
      validateSingleScheduleChange({
        dateKey: '2026-07-30',
        timeValue: '14:00',
        durationMinutes: 60,
        reason: '   ',
      }),
    ).toBe('변경 사유를 입력해 주세요.');
  });

  it('accepts 10:00 start within academy hours', () => {
    expect(
      validateSingleScheduleChange({
        dateKey: '2026-07-30',
        timeValue: '10:00',
        durationMinutes: 60,
        reason: 'test',
      }),
    ).toBeNull();
  });

  it('seeds empty fixed-schedule editors for re-register flow', () => {
    expect(
      buildEmptyFixedScheduleSlotInputs({
        weeklyFrequency: 1,
        teacherId: 'teacher-1',
        durationMinutes: 60,
        weekday: 2,
        localTime: '19:00',
      }),
    ).toEqual([
      {
        teacherId: 'teacher-1',
        weekday: 2,
        localTime: '19:00',
        durationMinutes: 60,
        slotOrder: 1,
      },
    ]);
  });

  it('validates recurring create requires weeklyFrequency slot count', () => {
    expect(
      validateRecurringScheduleChange({
        effectiveDateKey: '2026-09-10',
        slots: [],
        reason: '재등록',
        weeklyFrequency: 1,
      }),
    ).toBe('고정 일정 개수가 상품 주당 횟수와 일치하지 않습니다.');
  });

  it('formats conflict preview rows for Owner warning UI', () => {
    expect(
      formatScheduleCollisionSummary({
        weekday: 2,
        local_start_time: '19:00:00',
        duration_minutes: 60,
        student_name: '김학생',
        teacher_name: '이강사',
        course_name: '보컬',
        conflicting_pass_code: 'V-S0001-001',
      }),
    ).toContain('화');
  });
});

describe('과목 추가 등록 exclusion (active course keep-out)', () => {
  it('excludes courses that already have any pass for the student', () => {
    const enrolledCourseIds = ['course-vocal'];
    const courses = [
      { id: 'course-vocal', name: '보컬' },
      { id: 'course-piano', name: '피아노' },
    ];
    const available = courses.filter((course) => !enrolledCourseIds.includes(course.id));
    expect(available.map((row) => row.name)).toEqual(['피아노']);
  });
});

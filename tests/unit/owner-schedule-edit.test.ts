import { describe, expect, it } from 'vitest';
import {
  buildAcademyTimeOptions,
  formatFixedWeeklyScheduleLabel,
  formatSeoulWeekdayLabel,
  validateSingleScheduleChange,
} from '@/lib/domain/owner-schedule-edit';

describe('owner schedule edit domain', () => {
  it('builds 30-minute academy time options from 13:00 through 21:00', () => {
    const options = buildAcademyTimeOptions();
    expect(options[0]).toBe('13:00');
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

  it('rejects academy hours before 13:00', () => {
    expect(
      validateSingleScheduleChange({
        dateKey: '2026-07-30',
        timeValue: '10:00',
        durationMinutes: 60,
        reason: 'test',
      }),
    ).toMatch(/13:00/);
  });
});

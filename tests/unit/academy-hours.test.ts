import { describe, expect, it } from 'vitest';
import {
  ACADEMY_FIRST_START_MINUTES,
  ACADEMY_LAST_END_MINUTES,
  ACADEMY_LAST_START_MINUTES,
  formatMinutesAsLocalTime,
  parseLocalTimeToMinutes,
  validateAcademyLessonWindow,
} from '@/lib/domain/academy-hours';

describe('academy operating hours', () => {
  it('defines 10:00 through 22:00 window', () => {
    expect(ACADEMY_FIRST_START_MINUTES).toBe(10 * 60);
    expect(ACADEMY_LAST_START_MINUTES).toBe(21 * 60);
    expect(ACADEMY_LAST_END_MINUTES).toBe(22 * 60);
  });

  it('parses and formats local times', () => {
    expect(parseLocalTimeToMinutes('10:30')).toBe(630);
    expect(formatMinutesAsLocalTime(630)).toBe('10:30');
  });

  it('accepts 10:00 and 10:30 lesson starts', () => {
    expect(validateAcademyLessonWindow(10 * 60, 60)).toBeNull();
    expect(validateAcademyLessonWindow(10 * 60 + 30, 60)).toBeNull();
  });

  it('accepts 21:00 one-hour lesson ending at 22:00', () => {
    expect(validateAcademyLessonWindow(21 * 60, 60)).toBeNull();
  });

  it('rejects start before 10:00', () => {
    expect(validateAcademyLessonWindow(9 * 60 + 30, 60)).toMatch(/10:00/);
  });

  it('rejects start at or after 22:00', () => {
    expect(validateAcademyLessonWindow(22 * 60, 30)).toMatch(/22:00/);
  });

  it('rejects end after 22:00', () => {
    expect(validateAcademyLessonWindow(21 * 60 + 30, 60)).toMatch(/22:00/);
  });
});

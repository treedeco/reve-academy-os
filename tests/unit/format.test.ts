import { describe, expect, it } from 'vitest';
import {
  formatLessonScheduledAtSeoul,
  formatLessonStatus,
  getSeoulDayBounds,
  mapDatabaseError,
} from '@/lib/domain/format';

describe('mapDatabaseError', () => {
  it('maps unauthorized database errors', () => {
    expect(mapDatabaseError({ message: 'REVE_UNAUTHORIZED' })).toContain('권한');
  });

  it('maps stale state errors', () => {
    expect(mapDatabaseError({ message: 'REVE_STALE_STATE' })).toContain('새로고침');
  });

  it('maps invalid login credentials', () => {
    expect(mapDatabaseError({ message: 'Invalid login credentials' })).toContain(
      '사용자 이름 또는 비밀번호',
    );
  });
});

describe('formatLessonStatus', () => {
  it('returns Korean label for scheduled', () => {
    expect(formatLessonStatus('scheduled')).toBe('예정');
  });
});

describe('formatLessonScheduledAtSeoul', () => {
  it('shows 일정 미정 for null or undefined', () => {
    expect(formatLessonScheduledAtSeoul(null)).toBe('일정 미정');
    expect(formatLessonScheduledAtSeoul(undefined)).toBe('일정 미정');
    expect(formatLessonScheduledAtSeoul('')).toBe('일정 미정');
  });

  it('formats a real Asia/Seoul instant', () => {
    const label = formatLessonScheduledAtSeoul('2026-09-08T07:00:00.000Z');
    expect(label).toMatch(/9/);
    expect(label).not.toBe('일정 미정');
  });
});

describe('teacher today scheduled_at source-of-truth', () => {
  it('excludes null scheduled_at from Seoul day bounds filter', () => {
    const { startIso, endIso } = getSeoulDayBounds(new Date('2026-09-10T12:00:00+09:00'));
    const lessons = [
      { id: 'a', scheduled_at: null as string | null },
      { id: 'b', scheduled_at: '2026-09-10T01:00:00.000Z' }, // 10:00 KST same day
      { id: 'c', scheduled_at: '2026-09-11T01:00:00.000Z' }, // next calendar day KST
      { id: 'd', scheduled_at: '2026-09-08T15:00:00.000Z' }, // previous calendar day KST
    ];
    const today = lessons.filter(
      (lesson) =>
        lesson.scheduled_at != null &&
        lesson.scheduled_at >= startIso &&
        lesson.scheduled_at <= endIso,
    );
    expect(today.map((row) => row.id)).toEqual(['b']);
  });

  it('respects Asia/Seoul date boundary around midnight', () => {
    // 2026-09-09 23:30 KST = 2026-09-09T14:30:00.000Z
    // 2026-09-10 00:30 KST = 2026-09-09T15:30:00.000Z
    const { startIso, endIso, dateKey } = getSeoulDayBounds(
      new Date('2026-09-10T00:30:00+09:00'),
    );
    expect(dateKey).toBe('2026-09-10');
    expect('2026-09-09T14:30:00.000Z' < startIso).toBe(true);
    expect('2026-09-09T15:30:00.000Z' >= startIso).toBe(true);
    expect('2026-09-09T15:30:00.000Z' <= endIso).toBe(true);
  });
});

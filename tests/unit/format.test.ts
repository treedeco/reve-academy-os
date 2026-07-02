import { describe, expect, it } from 'vitest';
import { mapDatabaseError, formatLessonStatus } from '@/lib/domain/format';

describe('mapDatabaseError', () => {
  it('maps unauthorized database errors', () => {
    expect(mapDatabaseError({ message: 'REVE_UNAUTHORIZED' })).toContain('권한');
  });

  it('maps stale state errors', () => {
    expect(mapDatabaseError({ message: 'REVE_STALE_STATE' })).toContain('새로고침');
  });

  it('maps invalid login credentials', () => {
    expect(mapDatabaseError({ message: 'Invalid login credentials' })).toContain('이메일 또는 비밀번호');
  });
});

describe('formatLessonStatus', () => {
  it('returns Korean label for scheduled', () => {
    expect(formatLessonStatus('scheduled')).toBe('예정');
  });
});

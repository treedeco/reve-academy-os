import { describe, expect, it } from 'vitest';
import {
  formatTeacherStatusLabel,
  mapTeacherMasterDataError,
} from '@/lib/domain/teacher-master-data';
import { mapDatabaseError } from '@/lib/domain/format';

describe('teacher master data helpers', () => {
  it('formats active and inactive status labels', () => {
    expect(formatTeacherStatusLabel(true)).toBe('활성');
    expect(formatTeacherStatusLabel(false)).toBe('비활성');
  });

  it('maps assignment blocking errors', () => {
    expect(mapTeacherMasterDataError({ message: 'REVE_ACTIVE_ASSIGNMENTS_EXIST' })).toMatch(
      /배정/,
    );
  });

  it('maps profile link conflict errors', () => {
    expect(mapTeacherMasterDataError({ message: 'REVE_PROFILE_LINK_CONFLICT' })).toMatch(/프로필/);
  });

  it('maps validation errors', () => {
    expect(mapTeacherMasterDataError({ message: 'REVE_INVALID_NAME' })).toMatch(/이름/);
    expect(mapTeacherMasterDataError({ message: 'REVE_INVALID_CODE' })).toMatch(/코드/);
    expect(mapTeacherMasterDataError({ message: 'REVE_REASON_REQUIRED' })).toMatch(/사유/);
  });

  it('maps duplicate teacher code errors', () => {
    expect(mapTeacherMasterDataError({ message: 'duplicate key value violates unique constraint "teachers_teacher_code_key"' })).toMatch(
      /이미 사용/,
    );
  });

  it('maps stale state through shared database helper', () => {
    expect(mapTeacherMasterDataError({ message: 'REVE_STALE_STATE' })).toBe(
      mapDatabaseError({ message: 'REVE_STALE_STATE' }),
    );
  });

  it('falls back for unknown errors', () => {
    expect(mapTeacherMasterDataError(null)).toMatch(/실패/);
    expect(mapTeacherMasterDataError({ message: 'unexpected database fault' })).toBe(
      'unexpected database fault',
    );
  });
});

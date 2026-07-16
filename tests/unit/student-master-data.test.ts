import { describe, expect, it } from 'vitest';
import {
  formatStudentStatusLabel,
  mapStudentMasterDataError,
} from '@/lib/domain/student-master-data';
import { mapDatabaseError } from '@/lib/domain/format';

describe('student master data helpers', () => {
  it('formats student status labels', () => {
    expect(formatStudentStatusLabel('active')).toBe('활성');
    expect(formatStudentStatusLabel('inactive')).toBe('비활성');
    expect(formatStudentStatusLabel('archived')).toBe('보관');
  });

  it('maps profile link conflict errors', () => {
    expect(mapStudentMasterDataError({ message: 'REVE_PROFILE_LINK_CONFLICT' })).toMatch(/프로필/);
  });

  it('maps validation errors', () => {
    expect(mapStudentMasterDataError({ message: 'REVE_INVALID_NAME' })).toMatch(/이름/);
    expect(mapStudentMasterDataError({ message: 'REVE_INVALID_CODE' })).toMatch(/코드/);
    expect(mapStudentMasterDataError({ message: 'REVE_REASON_REQUIRED' })).toMatch(/사유/);
  });

  it('maps duplicate student code errors', () => {
    expect(
      mapStudentMasterDataError({
        message: 'duplicate key value violates unique constraint "students_student_code_key"',
      }),
    ).toMatch(/이미 사용/);
  });

  it('maps stale state through shared database helper', () => {
    expect(mapStudentMasterDataError({ message: 'REVE_STALE_STATE' })).toBe(
      mapDatabaseError({ message: 'REVE_STALE_STATE' }),
    );
  });
});

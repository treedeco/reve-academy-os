import { describe, expect, it } from 'vitest';
import {
  buildScheduleRemovalConfirmationPhrase,
  buildStudentDeleteConfirmationPhrase,
  buildTeacherDeleteConfirmationPhrase,
  formatCountLabel,
  mapOwnerDeletionError,
  validateConfirmationPhrase,
  validateDeleteReason,
  validateEffectiveFromDate,
  validateReplacementTeacher,
} from '@/lib/domain/owner-deletion';

describe('owner deletion confirmation phrases', () => {
  it('builds student delete phrase', () => {
    expect(buildStudentDeleteConfirmationPhrase('S0001')).toBe('S0001 영구삭제');
  });

  it('builds teacher delete phrase from code', () => {
    expect(buildTeacherDeleteConfirmationPhrase('T-A001', '홍길동')).toBe('T-A001 영구삭제');
  });

  it('falls back to teacher name when code empty', () => {
    expect(buildTeacherDeleteConfirmationPhrase('', '홍길동')).toBe('홍길동 영구삭제');
  });

  it('builds schedule removal phrase', () => {
    expect(buildScheduleRemovalConfirmationPhrase('V-S001-001')).toBe('V-S001-001 스케줄삭제');
  });
});

describe('owner deletion validation', () => {
  it('requires delete reason', () => {
    expect(validateDeleteReason('')).toBe('삭제 사유를 입력해 주세요.');
    expect(validateDeleteReason('  ')).toBe('삭제 사유를 입력해 주세요.');
    expect(validateDeleteReason('운영 종료')).toBeNull();
  });

  it('validates confirmation phrase exactly', () => {
    expect(validateConfirmationPhrase('S0001 영구삭제', 'S0001 영구삭제')).toBeNull();
    expect(validateConfirmationPhrase('S0001', 'S0001 영구삭제')).toMatch(/확인 문구/);
  });

  it('validates effective from date', () => {
    expect(validateEffectiveFromDate('')).toMatch(/적용 시작일/);
    expect(validateEffectiveFromDate('2026-09-01')).toBeNull();
  });

  it('validates replacement teacher for reassign mode', () => {
    expect(validateReplacementTeacher('reassign', '', 'teacher-a')).toMatch(/재배정/);
    expect(validateReplacementTeacher('reassign', 'teacher-a', 'teacher-a')).toMatch(/다른 강사/);
    expect(validateReplacementTeacher('reassign', 'teacher-b', 'teacher-a')).toBeNull();
    expect(validateReplacementTeacher('remove_future_schedule', '', 'teacher-a')).toBeNull();
  });
});

describe('owner deletion formatting and errors', () => {
  it('formats Korean count labels', () => {
    expect(formatCountLabel(3000, '건')).toBe('3,000건');
  });

  it('maps deletion error codes to Korean messages', () => {
    expect(mapOwnerDeletionError({ message: 'REVE_CONFIRMATION_MISMATCH' })).toMatch(/확인 문구/);
    expect(mapOwnerDeletionError({ message: 'REVE_PREFLIGHT_MISMATCH' })).toMatch(/변경/);
    expect(mapOwnerDeletionError({ message: 'REVE_STALE_STATE' })).toMatch(/새로고침/);
    expect(mapOwnerDeletionError({ message: 'REVE_REPLACEMENT_TEACHER_INVALID' })).toMatch(/재배정/);
    expect(mapOwnerDeletionError({ message: 'REVE_DELETION_BLOCKED' })).toMatch(/차단/);
    expect(mapOwnerDeletionError({ message: 'REVE_INVALID_LINK_HANDLING' })).toMatch(/처리 방식/);
    expect(mapOwnerDeletionError({ message: 'REVE_ALREADY_DELETED' })).toMatch(/이미 삭제/);
    expect(mapOwnerDeletionError({ message: 'REVE_REASON_REQUIRED' })).toMatch(/삭제 사유/);
    expect(mapOwnerDeletionError({ message: 'REVE_PASS_SCHEDULE_IMMUTABLE' })).toMatch(/고정 일정/);
    expect(mapOwnerDeletionError({ message: 'REVE_UNAUTHORIZED' })).toMatch(/권한/);
    expect(mapOwnerDeletionError(null)).toMatch(/잠시 후/);
  });
});

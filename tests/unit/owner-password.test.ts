import { describe, expect, it } from 'vitest';
import {
  countPasswordCharacterClasses,
  mapOwnerPasswordAuthError,
  validateOwnerPasswordChangeInput,
} from '@/lib/domain/owner-password';

describe('owner password validation', () => {
  it('rejects empty fields', () => {
    expect(validateOwnerPasswordChangeInput({
      currentPassword: '',
      newPassword: '',
      confirmPassword: '',
    })).toEqual({
      ok: false,
      message: '모든 비밀번호 입력란을 채워 주세요.',
    });
  });

  it('rejects passwords shorter than 12 characters', () => {
    expect(validateOwnerPasswordChangeInput({
      currentPassword: 'CurrentPass123!',
      newPassword: 'Short1!',
      confirmPassword: 'Short1!',
    })).toEqual({
      ok: false,
      message: '새 비밀번호는 12자 이상이어야 합니다.',
    });
  });

  it('rejects passwords with insufficient character classes', () => {
    expect(validateOwnerPasswordChangeInput({
      currentPassword: 'CurrentPass123!',
      newPassword: 'alllowercase',
      confirmPassword: 'alllowercase',
    })).toEqual({
      ok: false,
      message:
        '새 비밀번호는 영문 소문자·대문자·숫자·특수문자 중 최소 3종류를 포함해야 합니다.',
    });
  });

  it('rejects when new password equals current password', () => {
    const password = 'SamePassword123!';
    expect(validateOwnerPasswordChangeInput({
      currentPassword: password,
      newPassword: password,
      confirmPassword: password,
    })).toEqual({
      ok: false,
      message: '새 비밀번호는 현재 비밀번호와 달라야 합니다.',
    });
  });

  it('rejects confirmation mismatch', () => {
    expect(validateOwnerPasswordChangeInput({
      currentPassword: 'CurrentPass123!',
      newPassword: 'NewPassword123!',
      confirmPassword: 'DifferentPassword123!',
    })).toEqual({
      ok: false,
      message: '새 비밀번호 확인이 일치하지 않습니다.',
    });
  });

  it('does not trim leading or trailing spaces from password values', () => {
    expect(validateOwnerPasswordChangeInput({
      currentPassword: ' CurrentPass123! ',
      newPassword: ' NewPassword123! ',
      confirmPassword: ' NewPassword123! ',
    })).toEqual({ ok: true });
    expect(countPasswordCharacterClasses(' NewPassword123! ')).toBeGreaterThanOrEqual(3);
  });

  it('accepts valid password change input', () => {
    expect(validateOwnerPasswordChangeInput({
      currentPassword: 'CurrentPass123!',
      newPassword: 'NewPassword123!',
      confirmPassword: 'NewPassword123!',
    })).toEqual({ ok: true });
  });

  it('maps invalid login credentials to current password message', () => {
    expect(
      mapOwnerPasswordAuthError({ message: 'Invalid login credentials' }),
    ).toBe('현재 비밀번호가 올바르지 않습니다.');
  });

  it('maps weak password responses without leaking internal details', () => {
    expect(mapOwnerPasswordAuthError({ message: 'Password is too weak' })).toBe(
      '새 비밀번호가 보안 정책을 충족하지 않습니다. 더 강력한 비밀번호를 사용해 주세요.',
    );
  });
});

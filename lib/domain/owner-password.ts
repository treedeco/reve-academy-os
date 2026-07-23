export const OWNER_PASSWORD_MIN_LENGTH = 12;
export const OWNER_PASSWORD_REQUIRED_CLASSES = 3;

export type OwnerPasswordValidationResult =
  | { ok: true }
  | { ok: false; message: string };

export function countPasswordCharacterClasses(password: string): number {
  let classes = 0;
  if (/[a-z]/.test(password)) classes += 1;
  if (/[A-Z]/.test(password)) classes += 1;
  if (/[0-9]/.test(password)) classes += 1;
  if (/[^A-Za-z0-9]/.test(password)) classes += 1;
  return classes;
}

export function validateOwnerPasswordChangeInput(input: {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
}): OwnerPasswordValidationResult {
  if (!input.currentPassword || !input.newPassword || !input.confirmPassword) {
    return { ok: false, message: '모든 비밀번호 입력란을 채워 주세요.' };
  }

  if (input.newPassword.length < OWNER_PASSWORD_MIN_LENGTH) {
    return {
      ok: false,
      message: `새 비밀번호는 ${OWNER_PASSWORD_MIN_LENGTH}자 이상이어야 합니다.`,
    };
  }

  if (countPasswordCharacterClasses(input.newPassword) < OWNER_PASSWORD_REQUIRED_CLASSES) {
    return {
      ok: false,
      message:
        '새 비밀번호는 영문 소문자·대문자·숫자·특수문자 중 최소 3종류를 포함해야 합니다.',
    };
  }

  if (input.newPassword === input.currentPassword) {
    return {
      ok: false,
      message: '새 비밀번호는 현재 비밀번호와 달라야 합니다.',
    };
  }

  if (input.newPassword !== input.confirmPassword) {
    return {
      ok: false,
      message: '새 비밀번호 확인이 일치하지 않습니다.',
    };
  }

  return { ok: true };
}

export function mapOwnerPasswordAuthError(error: { message?: string } | null): string {
  const message = error?.message?.toLowerCase() ?? '';

  if (!message) {
    return '비밀번호 변경에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  if (message.includes('invalid login credentials')) {
    return '현재 비밀번호가 올바르지 않습니다.';
  }

  if (
    message.includes('weak') ||
    message.includes('password') && message.includes('short') ||
    message.includes('pwned') ||
    message.includes('easy to guess')
  ) {
    return '새 비밀번호가 보안 정책을 충족하지 않습니다. 더 강력한 비밀번호를 사용해 주세요.';
  }

  if (message.includes('session') || message.includes('jwt') || message.includes('token')) {
    return '세션이 만료되었습니다. 다시 로그인해 주세요.';
  }

  return '비밀번호 변경에 실패했습니다. 잠시 후 다시 시도해 주세요.';
}

export const OWNER_PASSWORD_CHANGED_LOGIN_MESSAGE =
  '비밀번호가 변경되었습니다. 새 비밀번호로 다시 로그인해 주세요.';

export const OWNER_PASSWORD_AUDIT_RETRY_MESSAGE =
  '비밀번호는 변경되었지만 완료 기록 저장에 실패했습니다. 아래 버튼으로 완료 처리를 다시 시도해 주세요.';

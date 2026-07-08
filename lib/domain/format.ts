import { STATUS_LABELS, type LessonStatus } from '@/lib/domain/types';

const ERROR_MESSAGES: Record<string, string> = {
  REVE_UNAUTHORIZED: '권한이 없습니다. 다시 로그인해 주세요.',
  REVE_STALE_STATE: '다른 사용자가 먼저 변경했습니다. 새로고침 후 다시 시도해 주세요.',
  REVE_INVALID_TRANSITION: '허용되지 않는 상태 변경입니다.',
  REVE_REASON_REQUIRED: '변경 사유를 입력해 주세요.',
  REVE_INVALID_PROFILE: '활성 Owner 계정이 아닙니다.',
  REVE_SMS_NOT_CONFIRMABLE: '발송 확인할 수 없는 SMS 상태입니다.',
  REVE_REFUND_ALREADY_EXISTS: '이미 환불 처리된 결제입니다.',
  REVE_PAYMENT_NOT_REFUNDABLE: '환불할 수 없는 결제입니다.',
  REVE_REFUND_AMOUNT_MISMATCH: '환불 금액이 결제 금액과 일치하지 않습니다.',
  REVE_SCHEDULE_COLLISION: '강사 일정이 겹칩니다. 다른 시간을 선택해 주세요.',
  REVE_REQUEST_NOT_REVIEWABLE: '검토할 수 없는 요청 상태입니다.',
  REVE_REQUEST_NOT_APPLICABLE: '적용할 수 없는 요청 상태입니다.',
  REVE_APPROVED_TIME_REQUIRED: '승인 일시를 입력해 주세요.',
  REVE_INVALID_DECISION: '허용되지 않는 검토 결정입니다.',
};

export function mapDatabaseError(error: { message?: string; code?: string } | null): string {
  if (!error?.message) {
    return '저장에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  for (const [code, message] of Object.entries(ERROR_MESSAGES)) {
    if (error.message.includes(code)) {
      return message;
    }
  }

  if (error.message.toLowerCase().includes('invalid login credentials')) {
    return '이메일 또는 비밀번호가 올바르지 않습니다.';
  }

  return error.message;
}

export function formatLessonStatus(status: LessonStatus): string {
  return STATUS_LABELS[status] ?? status;
}

export function formatDateTimeSeoul(iso: string): string {
  return new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    month: 'numeric',
    day: 'numeric',
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
}

export function formatTimeSeoul(iso: string): string {
  return new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
}

export function formatDateSeoul(dateKey: string): string {
  return new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(new Date(`${dateKey}T12:00:00+09:00`));
}

export function getSeoulDayBounds(reference = new Date()): { startIso: string; endIso: string; dateKey: string } {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const dateKey = formatter.format(reference);
  const startIso = new Date(`${dateKey}T00:00:00+09:00`).toISOString();
  const endIso = new Date(`${dateKey}T23:59:59.999+09:00`).toISOString();
  return { startIso, endIso, dateKey };
}

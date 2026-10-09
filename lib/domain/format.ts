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
  REVE_SCHEDULE_COLLISION: '현재 같은 시간에 다른 일정이 있습니다. 원장 권한으로 저장할 수 있습니다.',
  REVE_NO_PREVIOUS_PASS: '갱신할 이전 회차권이 없습니다. 초기 등록을 이용해 주세요.',
  REVE_NO_SCHEDULE: '이전 회차의 고정 일정이 없어 다음 회차를 등록할 수 없습니다.',
  REVE_RESERVED_EXISTS: '이미 예약(선결제) 회차권이 있어 추가 갱신할 수 없습니다.',
  REVE_ACTIVE_PASS_NOT_COMPLETE: '현재 회차권이 아직 완료되지 않아 갱신할 수 없습니다.',
  REVE_PAYMENT_AMOUNT_MISMATCH: '결제 금액이 상품 수강료와 일치하지 않습니다.',
  REVE_INVALID_PAYMENT_METHOD: '결제 수단을 선택해 주세요.',
  REVE_PAYMENT_NOT_COMPLETABLE: '완료할 수 없는 결제 상태입니다.',
  REVE_PRODUCT_NOT_FOUND: '선택한 상품을 찾을 수 없습니다.',
  REVE_COURSE_NOT_FOUND: '선택한 과목을 찾을 수 없습니다.',
  REVE_STUDENT_NOT_FOUND: '학생 정보를 찾을 수 없습니다.',
  REVE_ENTITY_INACTIVE: '비활성 상태의 학생, 과목, 또는 상품은 사용할 수 없습니다.',
  REVE_IDEMPOTENCY_CONFLICT: '동일한 요청이 이미 다른 내용으로 처리되었습니다.',
  REVE_REQUEST_NOT_REVIEWABLE: '검토할 수 없는 요청 상태입니다.',
  REVE_REQUEST_NOT_APPLICABLE: '적용할 수 없는 요청 상태입니다.',
  REVE_APPROVED_TIME_REQUIRED: '승인 일시를 입력해 주세요.',
  REVE_INVALID_DECISION: '허용되지 않는 검토 결정입니다.',
  REVE_LESSON_NOT_CHANGEABLE: '일정을 변경할 수 없는 수업입니다.',
  REVE_SCHEDULE_CHANGE_DENIED: '일정을 변경할 수 없는 수업입니다.',
  REVE_ACADEMY_HOURS_BEFORE_OPEN: '수업 시작은 10:00 이후여야 합니다.',
  REVE_ACADEMY_HOURS_AFTER_CLOSE: '수업 시작은 22:00 이전이어야 합니다.',
  REVE_ACADEMY_HOURS_END_AFTER_CLOSE: '수업 종료는 22:00을 넘을 수 없습니다.',
  REVE_STUDENT_SCHEDULE_COLLISION: '현재 같은 시간에 다른 일정이 있습니다. 원장 권한으로 저장할 수 있습니다.',
  REVE_LESSON_NOTE_EMPTY: '수업 내용을 입력해 주세요.',
  REVE_LESSON_NOTE_NOT_FOUND: '수업 메모를 찾을 수 없습니다. 새로고침 후 다시 시도해 주세요.',
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
    return '사용자 이름 또는 비밀번호가 올바르지 않습니다.';
  }

  return error.message;
}

export function formatLessonStatus(status: LessonStatus): string {
  return STATUS_LABELS[status] ?? status;
}

export { formatPaymentStatusLabel } from '@/lib/domain/student-history';

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

/** Displays a lesson schedule instant, or "일정 미정" when unscheduled. */
export function formatLessonScheduledAtSeoul(iso: string | null | undefined): string {
  if (!iso) {
    return '일정 미정';
  }
  return formatDateTimeSeoul(iso);
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

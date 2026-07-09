import type { LessonStatus, PassStatus } from '@/lib/domain/types';

export const ACTIONABLE_SCHEDULE_REQUEST_STATUSES = ['submitted', 'approved'] as const;

export type ActionableScheduleRequestStatus = (typeof ACTIONABLE_SCHEDULE_REQUEST_STATUSES)[number];

export const SCHEDULE_REQUEST_STATUS_LABELS: Record<string, string> = {
  submitted: '검토 대기',
  approved: '승인됨 (적용 전)',
  rejected: '거절됨',
  applied: '적용됨',
};

export const SCHEDULE_REQUEST_SOURCE_ROLE_LABELS: Record<string, string> = {
  teacher: '강사',
  student: '학생',
  owner: '원장',
};

export function isActionableScheduleRequestStatus(status: string): status is ActionableScheduleRequestStatus {
  return (ACTIONABLE_SCHEDULE_REQUEST_STATUSES as readonly string[]).includes(status);
}

export function isActionableScheduleChangeRequest(input: {
  status: string;
  applied_at: string | null;
}): boolean {
  if (input.status === 'submitted') {
    return true;
  }
  return input.status === 'approved' && input.applied_at === null;
}

export function canApproveScheduleRequest(status: string): boolean {
  return status === 'submitted';
}

export function canApplyScheduleRequest(status: string, appliedAt: string | null): boolean {
  return status === 'approved' && appliedAt === null;
}

export function isCascadePendingScheduleChangeRequest(input: {
  status: string;
  applied_at: string | null;
  cascade_completed_at: string | null;
}): boolean {
  return input.status === 'applied' && input.applied_at !== null && input.cascade_completed_at === null;
}

export function canCascadeScheduleRequest(input: {
  status: string;
  applied_at: string | null;
  cascade_completed_at: string | null;
}): boolean {
  return isCascadePendingScheduleChangeRequest(input);
}

export function formatScheduleRequestStatusLabel(status: string): string {
  return SCHEDULE_REQUEST_STATUS_LABELS[status] ?? status;
}

export function formatScheduleRequestSourceRoleLabel(role: string): string {
  return SCHEDULE_REQUEST_SOURCE_ROLE_LABELS[role] ?? role;
}

export function formatPassStatusLabel(status: PassStatus | string): string {
  const labels: Record<string, string> = {
    reserved: '예약',
    active: '활성',
    completed: '완료',
    expired: '만료',
    cancelled: '취소',
  };
  return labels[status] ?? status;
}

/** Interpret datetime-local input as Asia/Seoul and return ISO string. */
export function parseSeoulDateTimeLocal(value: string): string | null {
  const trimmed = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(trimmed)) {
    return null;
  }
  const parsed = new Date(`${trimmed}:00+09:00`);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed.toISOString();
}

export function toDateTimeLocalSeoul(iso: string | null): string {
  if (!iso) {
    return '';
  }
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const parts = formatter.formatToParts(new Date(iso));
  const get = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}`;
}

export function defaultApprovedTimeLocal(input: {
  proposed_scheduled_at: string | null;
  lesson_scheduled_at: string;
}): string {
  return toDateTimeLocalSeoul(input.proposed_scheduled_at ?? input.lesson_scheduled_at);
}

export function mapScheduleChangeError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '일정 변경 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  if (error.message.includes('REVE_SCHEDULE_COLLISION')) {
    return '강사 일정이 겹칩니다. 다른 시간을 선택해 주세요.';
  }
  if (error.message.includes('REVE_UNAUTHORIZED')) {
    return '권한이 없습니다. 다시 로그인해 주세요.';
  }
  if (error.message.includes('REVE_REQUEST_NOT_REVIEWABLE')) {
    return '검토할 수 없는 요청 상태입니다.';
  }
  if (error.message.includes('REVE_REQUEST_NOT_APPLICABLE')) {
    return '적용할 수 없는 요청 상태입니다.';
  }
  if (error.message.includes('REVE_APPROVED_TIME_REQUIRED')) {
    return '승인 일시를 입력해 주세요.';
  }
  if (error.message.includes('REVE_REASON_REQUIRED')) {
    return '사유를 입력해 주세요.';
  }
  if (error.message.includes('REVE_STALE_STATE')) {
    return '다른 사용자가 먼저 변경했습니다. 새로고침 후 다시 시도해 주세요.';
  }
  if (error.message.includes('REVE_INVALID_DECISION')) {
    return '허용되지 않는 검토 결정입니다.';
  }
  if (error.message.includes('REVE_CASCADE_NOT_READY')) {
    return '연쇄 재배치할 수 없는 요청 상태입니다.';
  }
  if (error.message.includes('REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON')) {
    return '완료된 수업이 있어 연쇄 재배치를 진행할 수 없습니다.';
  }
  if (error.message.includes('REVE_CASCADE_ANCHOR_CHANGED')) {
    return '기준 수업 일정이 변경되어 연쇄 재배치를 진행할 수 없습니다.';
  }
  if (error.message.includes('REVE_PASS_SCHEDULE_IMMUTABLE')) {
    return '종료된 회차권은 연쇄 재배치할 수 없습니다.';
  }

  return error.message;
}

export function formatLessonStatusLabel(status: LessonStatus | string): string {
  const labels: Record<string, string> = {
    scheduled: '예정',
    completed: '완료',
    same_day_cancelled: '당일 취소',
    makeup_completed: '보강 완료',
    postponed: '연기',
    advance_cancelled: '사전 취소',
    teacher_cancelled: '강사 취소',
    academy_closed: '학원 휴무',
  };
  return labels[status] ?? status;
}

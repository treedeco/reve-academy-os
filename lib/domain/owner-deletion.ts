import { mapDatabaseError } from '@/lib/domain/format';

export type TeacherLinkHandlingMode = 'reassign' | 'remove_future_schedule';

export const TEACHER_LINK_HANDLING_OPTIONS: {
  value: TeacherLinkHandlingMode;
  label: string;
  description: string;
}[] = [
  {
    value: 'reassign',
    label: '다른 강사에게 재배정',
    description: '향후 고정 일정과 미래 수업을 선택한 강사에게 옮깁니다. 과거 수업 이력은 강사명 스냅샷으로 보존됩니다.',
  },
  {
    value: 'remove_future_schedule',
    label: '미래 고정 일정·수업 제거',
    description: '해당 강사의 활성 고정 일정을 비활성화하고, 미래 예정 수업을 사전 취소 처리합니다.',
  },
];

export function buildStudentDeleteConfirmationPhrase(studentCode: string): string {
  return `${studentCode} 영구삭제`;
}

export function buildTeacherDeleteConfirmationPhrase(teacherCode: string, teacherName: string): string {
  if (teacherCode.trim()) {
    return `${teacherCode} 영구삭제`;
  }
  return `${teacherName} 영구삭제`;
}

export function buildScheduleRemovalConfirmationPhrase(passCode: string): string {
  return `${passCode} 스케줄삭제`;
}

export function validateDeleteReason(reason: string): string | null {
  if (!reason.trim()) {
    return '삭제 사유를 입력해 주세요.';
  }
  return null;
}

export function validateConfirmationPhrase(input: string, expected: string): string | null {
  if (input.trim() !== expected) {
    return `확인 문구를 정확히 입력해 주세요. (${expected})`;
  }
  return null;
}

export function validateEffectiveFromDate(value: string): string | null {
  if (!value.trim()) {
    return '적용 시작일을 선택해 주세요.';
  }
  const parsed = Date.parse(`${value}T00:00:00+09:00`);
  if (Number.isNaN(parsed)) {
    return '적용 시작일이 올바르지 않습니다.';
  }
  return null;
}

export function validateReplacementTeacher(
  mode: TeacherLinkHandlingMode,
  replacementTeacherId: string,
  targetTeacherId: string,
): string | null {
  if (mode !== 'reassign') {
    return null;
  }
  if (!replacementTeacherId) {
    return '재배정할 강사를 선택해 주세요.';
  }
  if (replacementTeacherId === targetTeacherId) {
    return '삭제 대상 강사와 다른 강사를 선택해 주세요.';
  }
  return null;
}

export function formatCountLabel(count: number, unit: string): string {
  return `${count.toLocaleString('ko-KR')}${unit}`;
}

export function mapOwnerDeletionError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }

  const message = error.message;
  if (message.includes('REVE_CONFIRMATION_MISMATCH')) {
    return '확인 문구가 일치하지 않습니다.';
  }
  if (message.includes('REVE_PREFLIGHT_MISMATCH')) {
    return '삭제 대상 정보가 변경되었습니다. 미리보기를 다시 확인해 주세요.';
  }
  if (message.includes('REVE_DELETION_BLOCKED')) {
    return '연결 데이터 때문에 삭제할 수 없습니다. 미리보기의 차단 항목을 확인해 주세요.';
  }
  if (message.includes('REVE_INVALID_LINK_HANDLING')) {
    return '연결 데이터 처리 방식이 올바르지 않습니다.';
  }
  if (message.includes('REVE_REPLACEMENT_TEACHER_INVALID')) {
    return '재배정 강사를 선택할 수 없습니다. 활성 강사인지 확인해 주세요.';
  }
  if (message.includes('REVE_ALREADY_DELETED')) {
    return '이미 삭제된 대상입니다.';
  }
  if (message.includes('REVE_REASON_REQUIRED')) {
    return '삭제 사유를 입력해 주세요.';
  }
  if (message.includes('REVE_PASS_SCHEDULE_IMMUTABLE')) {
    return '현재 회차권 상태에서는 고정 일정을 삭제할 수 없습니다.';
  }

  return mapDatabaseError(error);
}

import { mapDatabaseError } from '@/lib/domain/format';

export const STUDENT_STATUS_LABELS = {
  active: '활성',
  inactive: '비활성',
  archived: '보관',
} as const;

export function formatStudentStatusLabel(status: string): string {
  if (status === 'active') {
    return STUDENT_STATUS_LABELS.active;
  }
  if (status === 'inactive') {
    return STUDENT_STATUS_LABELS.inactive;
  }
  if (status === 'archived') {
    return STUDENT_STATUS_LABELS.archived;
  }
  return status;
}

export function mapStudentMasterDataError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '저장에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  if (error.message.includes('REVE_PROFILE_LINK_CONFLICT')) {
    return '연결된 활성 프로필이 있어 상태를 변경할 수 없습니다.';
  }
  if (error.message.includes('REVE_INVALID_NAME')) {
    return '이름을 입력해 주세요.';
  }
  if (error.message.includes('REVE_INVALID_CODE')) {
    return '학생 코드 형식이 올바르지 않습니다.';
  }
  if (error.message.includes('REVE_REASON_REQUIRED')) {
    return '상태 변경 사유를 입력해 주세요.';
  }
  if (error.message.includes('REVE_INVALID_STATUS')) {
    return '허용되지 않는 학생 상태입니다.';
  }
  if (error.message.includes('students_student_code_key') || error.message.includes('23505')) {
    return '이미 사용 중인 학생 코드입니다.';
  }
  if (error.message.includes('REVE_STALE_STATE')) {
    return mapDatabaseError(error);
  }

  return mapDatabaseError(error);
}

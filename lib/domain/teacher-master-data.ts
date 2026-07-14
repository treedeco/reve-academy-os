import { mapDatabaseError } from '@/lib/domain/format';

export const TEACHER_STATUS_LABELS = {
  active: '활성',
  inactive: '비활성',
} as const;

export function formatTeacherStatusLabel(isActive: boolean): string {
  return isActive ? TEACHER_STATUS_LABELS.active : TEACHER_STATUS_LABELS.inactive;
}

export function mapTeacherMasterDataError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '저장에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  if (error.message.includes('REVE_ACTIVE_ASSIGNMENTS_EXIST')) {
    return '예정된 수업 또는 고정 일정 배정이 있어 비활성화할 수 없습니다.';
  }
  if (error.message.includes('REVE_PROFILE_LINK_CONFLICT')) {
    return '연결된 활성 프로필이 있어 비활성화할 수 없습니다.';
  }
  if (error.message.includes('REVE_INVALID_NAME')) {
    return '이름을 입력해 주세요.';
  }
  if (error.message.includes('REVE_INVALID_CODE')) {
    return '강사 코드 형식이 올바르지 않습니다.';
  }
  if (error.message.includes('teachers_teacher_code_key') || error.message.includes('23505')) {
    return '이미 사용 중인 강사 코드입니다.';
  }

  return mapDatabaseError(error);
}

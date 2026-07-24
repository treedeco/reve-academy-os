import { mapDatabaseError } from '@/lib/domain/format';

export const COURSE_PRODUCT_STATUS_LABELS = {
  active: '활성',
  inactive: '비활성',
} as const;

export function formatCourseProductStatusLabel(isActive: boolean): string {
  return isActive ? COURSE_PRODUCT_STATUS_LABELS.active : COURSE_PRODUCT_STATUS_LABELS.inactive;
}

export function formatTuitionKrw(amount: number): string {
  return `${amount.toLocaleString('ko-KR')}원`;
}

export type CourseProductFormInput = {
  productCode: string;
  productName: string;
  defaultLessonCount: string;
  weeklyFrequency: string;
  defaultTuitionKrw: string;
  expirationPolicy: string;
};

export function validateCourseProductForm(
  form: CourseProductFormInput,
  options: { requireCode: boolean },
): string | null {
  if (options.requireCode && !form.productCode.trim()) {
    return '상품 코드를 입력해 주세요.';
  }
  if (!form.productName.trim()) {
    return '상품명을 입력해 주세요.';
  }

  const lessonCount = Number(form.defaultLessonCount);
  if (!Number.isInteger(lessonCount) || lessonCount <= 0) {
    return '등록 회차는 1 이상의 정수로 입력해 주세요.';
  }

  const weeklyFrequency = Number(form.weeklyFrequency);
  if (!Number.isInteger(weeklyFrequency) || weeklyFrequency <= 0) {
    return '주당 수업 횟수는 1 이상의 정수로 입력해 주세요.';
  }

  const tuition = Number(form.defaultTuitionKrw);
  if (!Number.isInteger(tuition) || tuition < 0) {
    return '수강료는 0 이상의 정수로 입력해 주세요.';
  }

  return null;
}

export function mapCourseProductMasterDataError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '저장에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  if (error.message.includes('REVE_INVALID_NAME')) {
    return '상품명을 입력해 주세요.';
  }
  if (error.message.includes('REVE_INVALID_CODE')) {
    return '상품 코드 형식이 올바르지 않습니다.';
  }
  if (error.message.includes('REVE_PRODUCT_CODE_EXISTS')) {
    return '이미 사용 중인 상품 코드입니다.';
  }
  if (error.message.includes('REVE_INVALID_REGISTERED_COUNT')) {
    return '등록 회차와 주당 수업 횟수는 1 이상의 정수여야 합니다.';
  }
  if (error.message.includes('REVE_INVALID_PRICE')) {
    return '수강료는 0 이상의 정수로 입력해 주세요.';
  }
  if (error.message.includes('REVE_COURSE_NOT_FOUND')) {
    return '선택한 과목을 찾을 수 없습니다.';
  }
  if (error.message.includes('REVE_COURSE_INACTIVE')) {
    return '비활성 과목에는 상품을 등록할 수 없습니다.';
  }
  if (error.message.includes('REVE_PRODUCT_NOT_FOUND')) {
    return '상품을 찾을 수 없습니다.';
  }
  if (error.message.includes('REVE_PENDING_PAYMENT_EXISTS')) {
    return '대기 중인 결제가 있어 변경할 수 없습니다.';
  }
  if (error.message.includes('REVE_REASON_REQUIRED')) {
    return '상태 변경 사유를 입력해 주세요.';
  }
  if (error.message.includes('REVE_NO_CHANGES')) {
    return '변경된 내용이 없습니다.';
  }
  if (error.message.includes('REVE_STALE_STATE')) {
    return mapDatabaseError(error);
  }

  return mapDatabaseError(error);
}

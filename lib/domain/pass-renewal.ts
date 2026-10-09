import { mapDatabaseError } from '@/lib/domain/format';
import { ENROLLMENT_PAYMENT_METHODS, type EnrollmentPaymentMethod } from '@/lib/domain/initial-enrollment';
import type { OwnerEnrollmentProductOption, PassStatus } from '@/lib/domain/types';

export { ENROLLMENT_PAYMENT_METHODS };
export type { EnrollmentPaymentMethod };

export type RenewalMode = 'completed_renewal' | 'prepaid_renewal';

export interface RenewablePassTarget {
  source_pass_id: string;
  pass_code: string;
  status: PassStatus;
  sequence_number: number;
  course_id: string;
  course_name: string;
  course_product_id: string | null;
  mode: RenewalMode;
  teacher_id: string | null;
  teacher_name: string | null;
  schedule_slots: Array<{
    id: string;
    weekday: number;
    local_start_time: string;
    duration_minutes: number;
    teacher_id: string;
    teacher_name: string;
  }>;
}

export function validatePassRenewalForm(input: {
  courseProductId: string;
  paymentMethod: string;
  paidAmountKrw: number;
  product: OwnerEnrollmentProductOption | null;
}): string | null {
  if (!input.courseProductId) {
    return '상품을 선택해 주세요.';
  }
  if (!input.product) {
    return '선택한 상품을 찾을 수 없습니다.';
  }
  if (!input.paymentMethod) {
    return '결제 수단을 선택해 주세요.';
  }
  if (
    !ENROLLMENT_PAYMENT_METHODS.some((method) => method.value === input.paymentMethod)
  ) {
    return '결제 수단을 선택해 주세요.';
  }
  if (input.paidAmountKrw !== input.product.default_tuition_krw) {
    return '결제 금액이 상품 수강료와 일치하지 않습니다.';
  }
  return null;
}

export function mapPassRenewalError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '다음 회차 등록에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  const message = error.message;

  if (message.includes('REVE_NO_PREVIOUS_PASS')) {
    return '갱신할 이전 회차권이 없습니다. 초기 등록을 이용해 주세요.';
  }
  if (message.includes('REVE_NO_SCHEDULE')) {
    return '이전 회차의 고정 일정이 없어 다음 회차를 등록할 수 없습니다.';
  }
  if (message.includes('REVE_RESERVED_EXISTS')) {
    return '이미 예약(선결제) 회차권이 있어 추가 갱신할 수 없습니다.';
  }
  if (message.includes('REVE_ACTIVE_PASS_NOT_COMPLETE')) {
    return '현재 회차권이 아직 완료되지 않아 갱신할 수 없습니다.';
  }
  if (message.includes('REVE_PAYMENT_AMOUNT_MISMATCH')) {
    return '결제 금액이 상품 수강료와 일치하지 않습니다.';
  }
  if (message.includes('REVE_INVALID_PAYMENT_METHOD')) {
    return '결제 수단을 선택해 주세요.';
  }
  if (message.includes('REVE_PRODUCT_NOT_FOUND') || message.includes('REVE_COURSE_NOT_FOUND')) {
    return '선택한 과목 또는 상품을 찾을 수 없습니다.';
  }
  if (message.includes('REVE_STUDENT_NOT_FOUND')) {
    return '학생 정보를 찾을 수 없습니다.';
  }
  if (message.includes('REVE_ENTITY_INACTIVE')) {
    return '비활성 상태의 학생, 과목, 또는 상품은 사용할 수 없습니다.';
  }
  if (message.includes('REVE_IDEMPOTENCY_CONFLICT')) {
    return '동일한 결제 요청이 이미 다른 내용으로 처리되었습니다.';
  }
  if (message.includes('REVE_PAYMENT_NOT_COMPLETABLE')) {
    return '완료할 수 없는 결제 상태입니다.';
  }
  if (message.includes('REVE_SCHEDULE_COLLISION')) {
    return '강사 일정과 충돌합니다. 고정 일정을 확인한 뒤 다시 시도해 주세요.';
  }
  if (message.includes('REVE_UNAUTHORIZED') || message.includes('42501')) {
    return '권한이 없습니다. Owner 계정으로 다시 로그인해 주세요.';
  }

  return mapDatabaseError(error);
}

export function resolvePreferredProductId(
  products: OwnerEnrollmentProductOption[],
  courseId: string,
  preferredProductId: string | null,
): string {
  const forCourse = products.filter((product) => product.course_id === courseId);
  if (preferredProductId && forCourse.some((product) => product.id === preferredProductId)) {
    return preferredProductId;
  }
  if (forCourse.length === 1) {
    return forCourse[0].id;
  }
  return '';
}

export function paidAtFromDateInput(dateInput: string): string {
  const [year, month, day] = dateInput.split('-').map(Number);
  if (!year || !month || !day) {
    return new Date().toISOString();
  }
  // Noon KST avoids timezone day-boundary drift for paid_at date selection.
  const utcMs = Date.UTC(year, month - 1, day, 3, 0, 0);
  return new Date(utcMs).toISOString();
}

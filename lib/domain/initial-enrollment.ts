import { mapDatabaseError } from '@/lib/domain/format';
import type {
  EnrollmentScheduleSlotInput,
  OwnerEnrollmentProductOption,
} from '@/lib/domain/types';

export const ENROLLMENT_PAYMENT_METHODS = [
  { value: 'cash', label: '현금' },
  { value: 'bank_transfer', label: '계좌이체' },
  { value: 'card', label: '카드' },
  { value: 'other', label: '기타' },
] as const;

export type EnrollmentPaymentMethod = (typeof ENROLLMENT_PAYMENT_METHODS)[number]['value'];

export function buildDefaultScheduleSlots(
  product: OwnerEnrollmentProductOption,
  teacherId: string,
): EnrollmentScheduleSlotInput[] {
  const slots: EnrollmentScheduleSlotInput[] = [];
  for (let slotOrder = 1; slotOrder <= product.weekly_frequency; slotOrder += 1) {
    slots.push({
      teacherId,
      weekday: slotOrder === 1 ? 1 : 3,
      localTime: slotOrder === 1 ? '10:00' : '14:00',
      durationMinutes: 60,
      slotOrder,
    });
  }
  return slots;
}

export function buildScheduleSlotsPayload(slots: EnrollmentScheduleSlotInput[]): unknown[] {
  return slots.map((slot) => ({
    teacher_id: slot.teacherId,
    weekday: slot.weekday,
    local_time: slot.localTime,
    duration_minutes: slot.durationMinutes,
    slot_order: slot.slotOrder,
  }));
}

export function validateEnrollmentScheduleSlots(
  product: OwnerEnrollmentProductOption | null,
  slots: EnrollmentScheduleSlotInput[],
): string | null {
  if (!product) {
    return '상품을 선택해 주세요.';
  }

  if (slots.length !== product.weekly_frequency) {
    if (product.weekly_frequency === 1) {
      return '주 1회 상품은 고정 일정 1개가 필요합니다.';
    }
    return '주 2회 상품은 고정 일정 2개가 필요합니다.';
  }

  for (const slot of slots) {
    if (!slot.teacherId) {
      return '강사를 선택해 주세요.';
    }
    if (slot.weekday < 0 || slot.weekday > 6) {
      return '요일을 선택해 주세요.';
    }
    if (!slot.localTime.trim()) {
      return '수업 시간을 입력해 주세요.';
    }
    if (!slot.durationMinutes || slot.durationMinutes <= 0) {
      return '수업 시간(분)을 입력해 주세요.';
    }
  }

  const slotOrders = new Set(slots.map((slot) => slot.slotOrder));
  if (slotOrders.size !== slots.length) {
    return '고정 일정 순서가 중복되었습니다.';
  }

  return null;
}

export function validateInitialEnrollmentForm(input: {
  courseProductId: string;
  scheduleStartDate: string;
  paymentMethod: string;
  product: OwnerEnrollmentProductOption | null;
  slots: EnrollmentScheduleSlotInput[];
}): string | null {
  if (!input.courseProductId) {
    return '상품을 선택해 주세요.';
  }
  if (!input.scheduleStartDate) {
    return '일정 시작일을 선택해 주세요.';
  }
  if (!input.paymentMethod) {
    return '결제 수단을 선택해 주세요.';
  }

  return validateEnrollmentScheduleSlots(input.product, input.slots);
}

export function mapInitialEnrollmentError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '초기 등록에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  if (error.message.includes('REVE_NOT_INITIAL_ENROLLMENT')) {
    return '이미 해당 과목에 등록된 회차권이 있어 초기 등록할 수 없습니다.';
  }
  if (error.message.includes('REVE_INVALID_SCHEDULE')) {
    return '고정 일정 형식 또는 개수가 상품과 일치하지 않습니다.';
  }
  if (error.message.includes('REVE_ENTITY_INACTIVE')) {
    return '비활성 상태의 학생, 강사, 과목, 또는 상품은 사용할 수 없습니다.';
  }
  if (error.message.includes('REVE_PRODUCT_NOT_FOUND') || error.message.includes('REVE_COURSE_NOT_FOUND')) {
    return '선택한 과목 또는 상품을 찾을 수 없습니다.';
  }
  if (error.message.includes('REVE_PAYMENT_AMOUNT_MISMATCH')) {
    return '결제 금액이 상품 수강료와 일치하지 않습니다.';
  }
  if (error.message.includes('REVE_INVALID_PAYMENT_METHOD')) {
    return '결제 수단을 선택해 주세요.';
  }
  if (error.message.includes('REVE_IDEMPOTENCY_CONFLICT')) {
    return '동일한 등록 요청 키가 이미 다른 등록에 사용되었습니다.';
  }
  if (error.message.includes('REVE_TEACHER_SCHEDULE_CONFLICT') || error.message.includes('REVE_SCHEDULE_CONFLICT')) {
    return '선택한 고정 일정이 기존 수업과 충돌합니다.';
  }

  return mapDatabaseError(error);
}

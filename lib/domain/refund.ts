import type { PassStatus } from '@/lib/domain/types';

export const REFUNDABLE_PASS_STATUSES = ['active', 'reserved'] as const;

export type RefundablePassStatus = (typeof REFUNDABLE_PASS_STATUSES)[number];

export const PAYMENT_STATUS_LABELS: Record<string, string> = {
  pending: '대기',
  completed: '완료',
  cancelled: '취소',
  refunded: '환불 완료',
};

export const REFUND_ELIGIBILITY_LABEL = '환불 가능';

export function isRefundablePassStatus(status: string): status is RefundablePassStatus {
  return (REFUNDABLE_PASS_STATUSES as readonly string[]).includes(status);
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

export function formatKrwAmount(amount: number): string {
  return new Intl.NumberFormat('ko-KR', {
    style: 'currency',
    currency: 'KRW',
    maximumFractionDigits: 0,
  }).format(amount);
}

export function mapRefundError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '환불 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  if (error.message.includes('REVE_REFUND_ALREADY_EXISTS')) {
    return '이미 환불 처리된 결제입니다.';
  }
  if (error.message.includes('REVE_UNAUTHORIZED')) {
    return '권한이 없습니다. 다시 로그인해 주세요.';
  }
  if (error.message.includes('REVE_REASON_REQUIRED')) {
    return '환불 사유를 입력해 주세요.';
  }
  if (error.message.includes('REVE_PAYMENT_NOT_REFUNDABLE')) {
    return '환불할 수 없는 결제입니다.';
  }
  if (error.message.includes('REVE_REFUND_AMOUNT_MISMATCH')) {
    return '환불 금액이 결제 금액과 일치하지 않습니다.';
  }

  return error.message;
}

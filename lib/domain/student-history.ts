import { PAYMENT_STATUS_LABELS } from '@/lib/domain/refund';
import { formatScheduleRequestStatusLabel } from '@/lib/domain/schedule-change';
import type {
  StudentOperationalHistory,
  StudentPaymentHistoryRow,
  StudentRefundHistoryRow,
  StudentScheduleRequestHistoryRow,
} from '@/lib/domain/types';

export function formatPaymentStatusLabel(status: string): string {
  return PAYMENT_STATUS_LABELS[status] ?? status;
}

export function formatCascadeStatusLabel(input: {
  status: string;
  applied_at: string | null;
  cascade_completed_at: string | null;
}): string {
  if (input.status !== 'applied' || !input.applied_at) {
    return '-';
  }
  if (input.cascade_completed_at) {
    return '연쇄 완료';
  }
  return '연쇄 대기';
}

export function formatPaymentRecordedAt(input: {
  paid_at: string | null;
  created_at: string;
}): string {
  return input.paid_at ?? input.created_at;
}

export function sortPaymentHistoryRows(rows: StudentPaymentHistoryRow[]): StudentPaymentHistoryRow[] {
  return [...rows].sort((left, right) => {
    const leftAt = formatPaymentRecordedAt(left);
    const rightAt = formatPaymentRecordedAt(right);
    return rightAt.localeCompare(leftAt);
  });
}

export function sortRefundHistoryRows(rows: StudentRefundHistoryRow[]): StudentRefundHistoryRow[] {
  return [...rows].sort((left, right) => right.refunded_at.localeCompare(left.refunded_at));
}

export function sortScheduleRequestHistoryRows(
  rows: StudentScheduleRequestHistoryRow[],
): StudentScheduleRequestHistoryRow[] {
  return [...rows].sort((left, right) => right.created_at.localeCompare(left.created_at));
}

export function buildStudentOperationalHistory(input: {
  payments: StudentPaymentHistoryRow[];
  refunds: StudentRefundHistoryRow[];
  schedule_requests: StudentScheduleRequestHistoryRow[];
}): StudentOperationalHistory {
  return {
    payments: sortPaymentHistoryRows(input.payments),
    refunds: sortRefundHistoryRows(input.refunds),
    schedule_requests: sortScheduleRequestHistoryRows(input.schedule_requests),
  };
}

export {
  formatScheduleRequestStatusLabel,
};

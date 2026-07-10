import { describe, expect, it } from 'vitest';
import {
  buildStudentOperationalHistory,
  formatCascadeStatusLabel,
  formatPaymentRecordedAt,
  formatScheduleRequestStatusLabel,
  sortPaymentHistoryRows,
  sortRefundHistoryRows,
  sortScheduleRequestHistoryRows,
} from '@/lib/domain/student-history';
import { formatPaymentStatusLabel } from '@/lib/domain/format';
import type {
  StudentPaymentHistoryRow,
  StudentRefundHistoryRow,
  StudentScheduleRequestHistoryRow,
} from '@/lib/domain/types';

const paymentOlder: StudentPaymentHistoryRow = {
  id: 'p-old',
  status: 'completed',
  paid_amount_krw: 100000,
  paid_at: '2026-06-01T01:00:00.000Z',
  created_at: '2026-06-01T00:00:00.000Z',
  pass_code: 'V-OLD',
  product_name: 'Old Product',
  course_name: 'Course A',
};

const paymentNewer: StudentPaymentHistoryRow = {
  id: 'p-new',
  status: 'pending',
  paid_amount_krw: 200000,
  paid_at: null,
  created_at: '2026-07-01T00:00:00.000Z',
  pass_code: 'V-NEW',
  product_name: 'New Product',
  course_name: 'Course B',
};

const refundOlder: StudentRefundHistoryRow = {
  id: 'r-old',
  payment_id: 'p-old',
  refunded_amount_krw: 100000,
  refunded_at: '2026-06-02T01:00:00.000Z',
  reason: 'Older refund',
  pass_disposition: 'active_cancelled_future_advance_cancelled',
  payment_paid_at: '2026-06-01T01:00:00.000Z',
  pass_code: 'V-OLD',
  course_name: 'Course A',
};

const refundNewer: StudentRefundHistoryRow = {
  id: 'r-new',
  payment_id: 'p-new',
  refunded_amount_krw: 200000,
  refunded_at: '2026-07-02T01:00:00.000Z',
  reason: 'Newer refund',
  pass_disposition: 'active_cancelled_future_advance_cancelled',
  payment_paid_at: null,
  pass_code: 'V-NEW',
  course_name: 'Course B',
};

const requestOlder: StudentScheduleRequestHistoryRow = {
  id: 'req-old',
  status: 'submitted',
  requested_reason: 'Older request',
  lesson_sequence_number: 1,
  lesson_scheduled_at: '2026-06-10T01:00:00.000Z',
  proposed_scheduled_at: '2026-06-12T01:00:00.000Z',
  approved_scheduled_at: null,
  applied_at: null,
  cascade_completed_at: null,
  cascaded_lesson_count: null,
  pass_code: 'V-OLD',
  course_name: 'Course A',
  created_at: '2026-06-05T00:00:00.000Z',
  updated_at: '2026-06-05T00:00:00.000Z',
};

const requestNewer: StudentScheduleRequestHistoryRow = {
  id: 'req-new',
  status: 'applied',
  requested_reason: 'Newer request',
  lesson_sequence_number: 2,
  lesson_scheduled_at: '2026-07-10T01:00:00.000Z',
  proposed_scheduled_at: '2026-07-12T01:00:00.000Z',
  approved_scheduled_at: '2026-07-12T01:00:00.000Z',
  applied_at: '2026-07-13T01:00:00.000Z',
  cascade_completed_at: null,
  cascaded_lesson_count: null,
  pass_code: 'V-NEW',
  course_name: 'Course B',
  created_at: '2026-07-05T00:00:00.000Z',
  updated_at: '2026-07-05T00:00:00.000Z',
};

describe('student history domain helpers', () => {
  it('formats payment status labels', () => {
    expect(formatPaymentStatusLabel('completed')).toBe('완료');
    expect(formatPaymentStatusLabel('refunded')).toBe('환불 완료');
    expect(formatPaymentStatusLabel('unknown')).toBe('unknown');
  });

  it('formats schedule request status labels', () => {
    expect(formatScheduleRequestStatusLabel('submitted')).toBe('검토 대기');
    expect(formatScheduleRequestStatusLabel('applied')).toBe('적용됨');
  });

  it('formats cascade status labels', () => {
    expect(
      formatCascadeStatusLabel({
        status: 'applied',
        applied_at: '2026-07-01T00:00:00.000Z',
        cascade_completed_at: '2026-07-02T00:00:00.000Z',
      }),
    ).toBe('연쇄 완료');
    expect(
      formatCascadeStatusLabel({
        status: 'applied',
        applied_at: '2026-07-01T00:00:00.000Z',
        cascade_completed_at: null,
      }),
    ).toBe('연쇄 대기');
    expect(
      formatCascadeStatusLabel({
        status: 'submitted',
        applied_at: null,
        cascade_completed_at: null,
      }),
    ).toBe('-');
  });

  it('uses paid_at before created_at for payment recorded time', () => {
    expect(formatPaymentRecordedAt(paymentOlder)).toBe('2026-06-01T01:00:00.000Z');
    expect(formatPaymentRecordedAt(paymentNewer)).toBe('2026-07-01T00:00:00.000Z');
  });

  it('sorts payment, refund, and schedule request rows newest first', () => {
    expect(sortPaymentHistoryRows([paymentOlder, paymentNewer]).map((row) => row.id)).toEqual([
      'p-new',
      'p-old',
    ]);
    expect(sortRefundHistoryRows([refundOlder, refundNewer]).map((row) => row.id)).toEqual([
      'r-new',
      'r-old',
    ]);
    expect(sortScheduleRequestHistoryRows([requestOlder, requestNewer]).map((row) => row.id)).toEqual([
      'req-new',
      'req-old',
    ]);
  });

  it('builds operational history with sorted sections', () => {
    const history = buildStudentOperationalHistory({
      payments: [paymentOlder, paymentNewer],
      refunds: [refundOlder, refundNewer],
      schedule_requests: [requestOlder, requestNewer],
    });

    expect(history.payments[0]?.id).toBe('p-new');
    expect(history.refunds[0]?.id).toBe('r-new');
    expect(history.schedule_requests[0]?.id).toBe('req-new');
  });

  it('handles empty operational history sections', () => {
    const history = buildStudentOperationalHistory({
      payments: [],
      refunds: [],
      schedule_requests: [],
    });

    expect(history.payments).toEqual([]);
    expect(history.refunds).toEqual([]);
    expect(history.schedule_requests).toEqual([]);
  });
});

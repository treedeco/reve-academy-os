import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { StudentOperationalHistoryPanel } from '@/components/owner/student-operational-history-panel';
import type { StudentOperationalHistory } from '@/lib/domain/types';

const populatedHistory: StudentOperationalHistory = {
  payments: [
    {
      id: '12121212-1212-1212-1212-121212121101',
      status: 'completed',
      paid_amount_krw: 200000,
      paid_at: '2026-07-01T01:00:00.000Z',
      created_at: '2026-07-01T00:00:00.000Z',
      pass_code: 'V-S1D1-001',
      product_name: 'Alpha Product',
      course_name: 'Alpha Course',
    },
  ],
  refunds: [
    {
      id: 'abababab-abab-abab-abab-ababababa201',
      payment_id: '12121212-1212-1212-1212-121212121104',
      refunded_amount_krw: 200000,
      refunded_at: '2026-06-20T01:00:00.000Z',
      reason: 'Alpha seed already refunded payment',
      pass_disposition: 'active_cancelled_future_advance_cancelled',
      payment_paid_at: '2026-06-15T01:00:00.000Z',
      pass_code: 'V-S1Z1-001',
      course_name: 'Alpha Course',
    },
  ],
  schedule_requests: [
    {
      id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa302',
      status: 'approved',
      requested_reason: 'Alpha seed Delta pre-approved request',
      lesson_sequence_number: 1,
      lesson_scheduled_at: '2026-07-10T01:00:00.000Z',
      proposed_scheduled_at: '2026-07-11T01:00:00.000Z',
      approved_scheduled_at: '2026-07-12T01:00:00.000Z',
      applied_at: null,
      cascade_completed_at: null,
      cascaded_lesson_count: null,
      pass_code: 'V-S1D1-001',
      course_name: 'Alpha Course',
      created_at: '2026-07-05T00:00:00.000Z',
      updated_at: '2026-07-05T00:00:00.000Z',
    },
  ],
};

const emptyHistory: StudentOperationalHistory = {
  payments: [],
  refunds: [],
  schedule_requests: [],
};

describe('StudentOperationalHistoryPanel', () => {
  afterEach(() => {
    cleanup();
  });

  it('renders payment history rows', () => {
    render(<StudentOperationalHistoryPanel history={populatedHistory} />);

    const section = screen.getByTestId('payment-history-section');
    expect(within(section).getByText('완료')).toBeInTheDocument();
    expect(within(section).getByText('V-S1D1-001')).toBeInTheDocument();
    expect(within(section).getByText('Alpha Course')).toBeInTheDocument();
  });

  it('renders refund history rows', () => {
    render(<StudentOperationalHistoryPanel history={populatedHistory} />);

    const section = screen.getByTestId('refund-history-section');
    expect(within(section).getByText('Alpha seed already refunded payment')).toBeInTheDocument();
    expect(within(section).getByText('V-S1Z1-001')).toBeInTheDocument();
  });

  it('renders schedule request history rows', () => {
    render(<StudentOperationalHistoryPanel history={populatedHistory} />);

    const section = screen.getByTestId('schedule-request-history-section');
    expect(within(section).getByText(/승인됨 \(적용 전\)/)).toBeInTheDocument();
    expect(within(section).getByText('Alpha seed Delta pre-approved request')).toBeInTheDocument();
  });

  it('renders empty states when history is missing', () => {
    render(<StudentOperationalHistoryPanel history={emptyHistory} />);

    expect(screen.getByTestId('payment-history-empty')).toHaveTextContent('결제 이력이 없습니다.');
    expect(screen.getByTestId('refund-history-empty')).toHaveTextContent('환불 이력이 없습니다.');
    expect(screen.getByTestId('schedule-request-history-empty')).toHaveTextContent(
      '일정 변경 요청 이력이 없습니다.',
    );
  });

  it('does not render mutation buttons in operational history sections', () => {
    render(<StudentOperationalHistoryPanel history={populatedHistory} />);

    const panel = screen.getByTestId('student-operational-history');
    expect(within(panel).queryByRole('button')).toBeNull();
    expect(within(panel).queryByRole('link')).toBeNull();
  });
});

import { describe, expect, it } from 'vitest';
import {
  formatKrwAmount,
  formatPassStatusLabel,
  isRefundablePassStatus,
  mapRefundError,
  REFUND_ELIGIBILITY_LABEL,
} from '@/lib/domain/refund';
import { mapDatabaseError } from '@/lib/domain/format';

describe('refund domain helpers', () => {
  it('filters refundable pass statuses', () => {
    expect(isRefundablePassStatus('active')).toBe(true);
    expect(isRefundablePassStatus('reserved')).toBe(true);
    expect(isRefundablePassStatus('completed')).toBe(false);
    expect(isRefundablePassStatus('cancelled')).toBe(false);
  });

  it('maps pass status and eligibility labels', () => {
    expect(formatPassStatusLabel('active')).toBe('활성');
    expect(formatPassStatusLabel('reserved')).toBe('예약');
    expect(REFUND_ELIGIBILITY_LABEL).toBe('환불 가능');
  });

  it('formats KRW amounts', () => {
    expect(formatKrwAmount(200000)).toContain('200,000');
  });

  it('maps refund errors to safe Korean messages', () => {
    expect(mapRefundError({ message: 'REVE_REFUND_ALREADY_EXISTS' })).toMatch(/이미 환불/);
    expect(mapRefundError({ message: 'REVE_UNAUTHORIZED' })).toMatch(/권한/);
    expect(mapRefundError({ message: 'REVE_REASON_REQUIRED' })).toMatch(/사유/);
    expect(mapRefundError({ message: 'REVE_PAYMENT_NOT_REFUNDABLE' })).toMatch(/환불할 수 없는/);
    expect(mapRefundError(null)).toMatch(/실패/);
    expect(mapRefundError({ message: 'unexpected database fault' })).toBe('unexpected database fault');
  });

  it('maps refund errors through shared database error helper', () => {
    expect(mapDatabaseError({ message: 'REVE_REFUND_ALREADY_EXISTS' })).toMatch(/이미 환불/);
    expect(mapDatabaseError({ message: 'REVE_REASON_REQUIRED' })).toMatch(/사유/);
  });
});

import { describe, expect, it } from 'vitest';
import {
  ELIGIBLE_SMS_STATUSES,
  formatSmsStatus,
  isEligibleSmsStatus,
} from '@/lib/domain/sms';

describe('SMS domain helpers', () => {
  it('filters eligible SMS statuses', () => {
    expect(ELIGIBLE_SMS_STATUSES).toEqual(['scheduled', 'target', 'exhausted_unsent']);
    expect(isEligibleSmsStatus('scheduled')).toBe(true);
    expect(isEligibleSmsStatus('target')).toBe(true);
    expect(isEligibleSmsStatus('exhausted_unsent')).toBe(true);
    expect(isEligibleSmsStatus('normal')).toBe(false);
    expect(isEligibleSmsStatus('sent')).toBe(false);
  });

  it('maps SMS status labels for owner UI', () => {
    expect(formatSmsStatus('scheduled')).toBe('발송 예정');
    expect(formatSmsStatus('target')).toBe('발송 대상');
    expect(formatSmsStatus('exhausted_unsent')).toBe('미발송(소진)');
    expect(formatSmsStatus('sent')).toBe('발송 완료');
    expect(formatSmsStatus('normal')).toBe('정상');
  });
});

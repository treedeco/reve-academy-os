import { describe, expect, it } from 'vitest';
import {
  mapPassRenewalError,
  paidAtFromDateInput,
  resolvePreferredProductId,
  validatePassRenewalForm,
} from '@/lib/domain/pass-renewal';
import type { OwnerEnrollmentProductOption } from '@/lib/domain/types';

const vocal4: OwnerEnrollmentProductOption = {
  id: 'ffffffff-ffff-ffff-ffff-fffffffff201',
  course_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee201',
  product_code: 'VOC-4',
  product_name: 'Vocal 4',
  default_lesson_count: 4,
  weekly_frequency: 1,
  default_tuition_krw: 200000,
};

const vocal8: OwnerEnrollmentProductOption = {
  id: 'ffffffff-ffff-ffff-ffff-fffffffff202',
  course_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee201',
  product_code: 'VOC-8',
  product_name: 'Vocal 8',
  default_lesson_count: 8,
  weekly_frequency: 1,
  default_tuition_krw: 400000,
};

describe('pass renewal helpers', () => {
  it('validates renewal form fields', () => {
    expect(
      validatePassRenewalForm({
        courseProductId: vocal4.id,
        paymentMethod: 'cash',
        paidAmountKrw: 200000,
        product: vocal4,
      }),
    ).toBeNull();

    expect(
      validatePassRenewalForm({
        courseProductId: '',
        paymentMethod: 'cash',
        paidAmountKrw: 200000,
        product: vocal4,
      }),
    ).toMatch(/상품/);

    expect(
      validatePassRenewalForm({
        courseProductId: vocal4.id,
        paymentMethod: 'cash',
        paidAmountKrw: 199999,
        product: vocal4,
      }),
    ).toMatch(/금액/);
  });

  it('prefers previous product when uniquely resolvable otherwise', () => {
    expect(resolvePreferredProductId([vocal4, vocal8], vocal4.course_id, vocal8.id)).toBe(vocal8.id);
    expect(resolvePreferredProductId([vocal4], vocal4.course_id, null)).toBe(vocal4.id);
    expect(resolvePreferredProductId([vocal4, vocal8], vocal4.course_id, null)).toBe('');
  });

  it('maps Korean renewal errors', () => {
    expect(mapPassRenewalError({ message: 'REVE_NO_PREVIOUS_PASS' })).toMatch(/이전 회차/);
    expect(mapPassRenewalError({ message: 'REVE_RESERVED_EXISTS' })).toMatch(/예약/);
    expect(mapPassRenewalError({ message: 'REVE_IDEMPOTENCY_CONFLICT' })).toMatch(/동일/);
    expect(mapPassRenewalError({ message: 'REVE_UNAUTHORIZED' })).toMatch(/권한/);
    expect(mapPassRenewalError({ message: 'REVE_SCHEDULE_COLLISION' })).toMatch(/충돌/);
  });

  it('builds paid_at from date input at noon KST', () => {
    expect(paidAtFromDateInput('2026-10-09')).toBe('2026-10-09T03:00:00.000Z');
  });
});

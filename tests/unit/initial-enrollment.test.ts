import { describe, expect, it } from 'vitest';
import {
  buildDefaultScheduleSlots,
  buildScheduleSlotsPayload,
  mapInitialEnrollmentError,
  validateEnrollmentScheduleSlots,
  validateInitialEnrollmentForm,
} from '@/lib/domain/initial-enrollment';
import { mapDatabaseError } from '@/lib/domain/format';
import type { OwnerEnrollmentProductOption } from '@/lib/domain/types';

const weeklyProduct: OwnerEnrollmentProductOption = {
  id: 'ffffffff-ffff-ffff-ffff-fffffffff101',
  course_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee101',
  product_code: 'VOC-4-A1',
  product_name: 'Alpha 4 Lessons',
  default_lesson_count: 4,
  weekly_frequency: 1,
  default_tuition_krw: 200000,
};

const twiceWeeklyProduct: OwnerEnrollmentProductOption = {
  id: 'ffffffff-ffff-ffff-ffff-fffffffff102',
  course_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee102',
  product_code: 'PIA-8-A1',
  product_name: 'Alpha 8 Lessons',
  default_lesson_count: 8,
  weekly_frequency: 2,
  default_tuition_krw: 400000,
};

describe('initial enrollment helpers', () => {
  it('builds default schedule slots from product weekly frequency', () => {
    expect(buildDefaultScheduleSlots(weeklyProduct, 'teacher-a')).toHaveLength(1);
    expect(buildDefaultScheduleSlots(twiceWeeklyProduct, 'teacher-a')).toHaveLength(2);
  });

  it('maps schedule slots to RPC payload keys', () => {
    expect(buildScheduleSlotsPayload(buildDefaultScheduleSlots(weeklyProduct, 'teacher-a'))).toEqual([
      {
        teacher_id: 'teacher-a',
        weekday: 1,
        local_time: '10:00',
        duration_minutes: 60,
        slot_order: 1,
      },
    ]);
  });

  it('validates weekly and twice-weekly slot counts', () => {
    expect(
      validateEnrollmentScheduleSlots(weeklyProduct, buildDefaultScheduleSlots(weeklyProduct, 't1')),
    ).toBeNull();
    expect(
      validateEnrollmentScheduleSlots(
        twiceWeeklyProduct,
        buildDefaultScheduleSlots(twiceWeeklyProduct, 't1'),
      ),
    ).toBeNull();
    expect(
      validateEnrollmentScheduleSlots(
        weeklyProduct,
        buildDefaultScheduleSlots(twiceWeeklyProduct, 't1'),
      ),
    ).toMatch(/1개/);
    expect(
      validateEnrollmentScheduleSlots(
        twiceWeeklyProduct,
        buildDefaultScheduleSlots(weeklyProduct, 't1'),
      ),
    ).toMatch(/2개/);
  });

  it('validates the full enrollment form', () => {
    expect(
      validateInitialEnrollmentForm({
        courseProductId: weeklyProduct.id,
        scheduleStartDate: '2026-08-03',
        paymentMethod: 'cash',
        product: weeklyProduct,
        slots: buildDefaultScheduleSlots(weeklyProduct, 'teacher-a'),
      }),
    ).toBeNull();

    expect(
      validateInitialEnrollmentForm({
        courseProductId: '',
        scheduleStartDate: '2026-08-03',
        paymentMethod: 'cash',
        product: weeklyProduct,
        slots: [],
      }),
    ).toMatch(/상품/);
  });

  it('maps enrollment-specific database errors', () => {
    expect(mapInitialEnrollmentError({ message: 'REVE_NOT_INITIAL_ENROLLMENT' })).toMatch(/초기 등록/);
    expect(mapInitialEnrollmentError({ message: 'REVE_INVALID_SCHEDULE' })).toMatch(/고정 일정/);
    expect(mapInitialEnrollmentError({ message: 'REVE_ENTITY_INACTIVE' })).toMatch(/비활성/);
    expect(mapInitialEnrollmentError({ message: 'REVE_STALE_STATE' })).toBe(
      mapDatabaseError({ message: 'REVE_STALE_STATE' }),
    );
  });
});

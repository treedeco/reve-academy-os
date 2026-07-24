import { describe, expect, it } from 'vitest';
import {
  formatCourseProductStatusLabel,
  mapCourseProductMasterDataError,
  validateCourseProductForm,
} from '@/lib/domain/course-product-master-data';

describe('course product master data helpers', () => {
  it('validates required create fields', () => {
    expect(
      validateCourseProductForm(
        {
          productCode: '',
          productName: '보컬 4회',
          defaultLessonCount: '4',
          weeklyFrequency: '1',
          defaultTuitionKrw: '200000',
          expirationPolicy: '',
        },
        { requireCode: true },
      ),
    ).toBe('상품 코드를 입력해 주세요.');

    expect(
      validateCourseProductForm(
        {
          productCode: 'V-4-001',
          productName: '',
          defaultLessonCount: '4',
          weeklyFrequency: '1',
          defaultTuitionKrw: '200000',
          expirationPolicy: '',
        },
        { requireCode: true },
      ),
    ).toBe('상품명을 입력해 주세요.');
  });

  it('maps duplicate product code errors', () => {
    expect(
      mapCourseProductMasterDataError({ message: 'REVE_PRODUCT_CODE_EXISTS' }),
    ).toContain('이미 사용 중인 상품 코드');
  });

  it('formats active/inactive labels', () => {
    expect(formatCourseProductStatusLabel(true)).toBe('활성');
    expect(formatCourseProductStatusLabel(false)).toBe('비활성');
  });
});

import { describe, expect, it } from 'vitest';
import {
  ENROLLMENT_CATALOG_EMPTY_MESSAGE,
  ENROLLMENT_CATALOG_ERROR_MESSAGE,
  ENROLLMENT_CATALOG_LOADING_MESSAGE,
  ENROLLMENT_PRODUCT_EMPTY_MESSAGE,
} from '@/lib/domain/enrollment-catalog-messages';

describe('enrollment catalog messages', () => {
  it('exposes required Korean UI copy', () => {
    expect(ENROLLMENT_CATALOG_LOADING_MESSAGE).toBe('과목을 불러오는 중입니다.');
    expect(ENROLLMENT_CATALOG_EMPTY_MESSAGE).toBe('등록된 활성 과목이 없습니다.');
    expect(ENROLLMENT_CATALOG_ERROR_MESSAGE).toBe(
      '과목을 불러오지 못했습니다. 다시 시도해 주세요.',
    );
    expect(ENROLLMENT_PRODUCT_EMPTY_MESSAGE).toBe('이 과목에 등록된 활성 상품이 없습니다.');
  });
});

describe('loadOwnerEnrollmentCatalog', () => {
  it('returns empty when no active courses exist', async () => {
    const { loadOwnerEnrollmentCatalog } = await import('@/lib/data/owner-enrollment');
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            order: async () => ({ data: [], error: null }),
          }),
        }),
      }),
    };

    const result = await loadOwnerEnrollmentCatalog(supabase as never);
    expect(result.status).toBe('empty');
  });

  it('returns error when a query fails', async () => {
    const { loadOwnerEnrollmentCatalog } = await import('@/lib/data/owner-enrollment');
    const supabase = {
      from: (table: string) => ({
        select: () => ({
          eq: () => ({
            order: async () =>
              table === 'courses'
                ? { data: null, error: { message: 'permission denied' } }
                : { data: [], error: null },
          }),
        }),
      }),
    };

    const result = await loadOwnerEnrollmentCatalog(supabase as never);
    expect(result.status).toBe('error');
  });

  it('returns ready catalog when active courses exist', async () => {
    const { loadOwnerEnrollmentCatalog } = await import('@/lib/data/owner-enrollment');
    const course = { id: 'c1', course_code: 'V', name: '보컬' };
    const supabase = {
      from: (table: string) => ({
        select: () => ({
          eq: () => ({
            order: async () => {
              if (table === 'courses') {
                return { data: [course], error: null };
              }
              return { data: [], error: null };
            },
          }),
        }),
      }),
    };

    const result = await loadOwnerEnrollmentCatalog(supabase as never);
    expect(result.status).toBe('ready');
    if (result.status === 'ready') {
      expect(result.catalog.courses).toEqual([course]);
    }
  });
});

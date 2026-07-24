import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  createOwnerCourseProduct,
  fetchOwnerActiveCourses,
  fetchOwnerCourseProductList,
  setOwnerCourseProductActive,
  updateOwnerCourseProduct,
} from '@/lib/data/owner-course-products';
import { loadOwnerEnrollmentCatalog } from '@/lib/data/owner-enrollment';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const integrationEnabled = Boolean(supabaseUrl && supabaseAnonKey);

function createAuthClient(storageKey: string) {
  return createClient(supabaseUrl!, supabaseAnonKey!, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      storageKey,
    },
  });
}

describe.skipIf(!integrationEnabled)('Owner course product integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-owner-course-products');
    const { error } = await ownerClient.auth.signInWithPassword({
      email: OWNER_AUTH_EMAIL,
      password: getOwnerTestPassword(),
    });
    if (error) {
      throw new Error(
        `Owner login failed (${error.message}). Run npm run db:seed:alpha after db reset.`,
      );
    }
  });

  it('loads active courses for product creation', async () => {
    const courses = await fetchOwnerActiveCourses(ownerClient);
    expect(courses.length).toBeGreaterThan(0);
    expect(courses.every((course) => course.course_code.length > 0)).toBe(true);
  });

  it('creates, updates, deactivates, and excludes inactive products from enrollment catalog', async () => {
    const suffix = Date.now().toString().slice(-6);
    const productCode = `V-INT${suffix}`;
    const courses = await fetchOwnerActiveCourses(ownerClient);
    const vocalCourse =
      courses.find((course) => course.course_code === 'V') ??
      courses.find((course) => course.course_code === 'VOC-A1');
    expect(vocalCourse).toBeTruthy();

    const created = await createOwnerCourseProduct(ownerClient, {
      courseId: vocalCourse!.id,
      productCode,
      productName: `Integration Vocal ${suffix}`,
      defaultLessonCount: 4,
      weeklyFrequency: 1,
      defaultTuitionKrw: 200000,
      courseMeta: {
        course_code: vocalCourse!.course_code,
        course_name: vocalCourse!.name,
      },
    });

    expect(created.product_code).toBe(productCode);
    expect(created.is_active).toBe(true);

    const catalogAfterCreate = await loadOwnerEnrollmentCatalog(ownerClient);
    expect(catalogAfterCreate.status).toBe('ready');
    if (catalogAfterCreate.status === 'ready') {
      expect(
        catalogAfterCreate.catalog.products.some((product) => product.id === created.id),
      ).toBe(true);
    }

    const updated = await updateOwnerCourseProduct(ownerClient, {
      courseProductId: created.id,
      expectedUpdatedAt: created.updated_at,
      productName: `Integration Vocal Updated ${suffix}`,
      defaultLessonCount: 4,
      weeklyFrequency: 1,
      defaultTuitionKrw: 210000,
      courseMeta: {
        course_code: vocalCourse!.course_code,
        course_name: vocalCourse!.name,
      },
    });

    expect(updated.product_name).toContain('Updated');

    const deactivated = await setOwnerCourseProductActive(ownerClient, {
      courseProductId: updated.id,
      isActive: false,
      reason: 'integration deactivate',
      expectedUpdatedAt: updated.updated_at,
      courseMeta: {
        course_code: vocalCourse!.course_code,
        course_name: vocalCourse!.name,
      },
    });

    expect(deactivated.is_active).toBe(false);

    const catalogAfterDeactivate = await loadOwnerEnrollmentCatalog(ownerClient);
    expect(catalogAfterDeactivate.status).toBe('ready');
    if (catalogAfterDeactivate.status === 'ready') {
      expect(
        catalogAfterDeactivate.catalog.products.some((product) => product.id === created.id),
      ).toBe(false);
    }

    const list = await fetchOwnerCourseProductList(ownerClient);
    expect(list.some((product) => product.id === created.id && !product.is_active)).toBe(true);
  });

  it('rejects duplicate product code submissions', async () => {
    const courses = await fetchOwnerActiveCourses(ownerClient);
    const course = courses[0];
    expect(course).toBeTruthy();

    const suffix = Date.now().toString().slice(-6);
    const productCode = `DUP${suffix}`;

    await createOwnerCourseProduct(ownerClient, {
      courseId: course.id,
      productCode,
      productName: `Duplicate Test ${suffix}`,
      defaultLessonCount: 4,
      weeklyFrequency: 1,
      defaultTuitionKrw: 100000,
      courseMeta: {
        course_code: course.course_code,
        course_name: course.name,
      },
    });

    await expect(
      createOwnerCourseProduct(ownerClient, {
        courseId: course.id,
        productCode,
        productName: `Duplicate Test Again ${suffix}`,
        defaultLessonCount: 8,
        weeklyFrequency: 2,
        defaultTuitionKrw: 200000,
        courseMeta: {
          course_code: course.course_code,
          course_name: course.name,
        },
      }),
    ).rejects.toThrow(/REVE_PRODUCT_CODE_EXISTS/);
  });

  it('blocks non-owner course product RPC access', async () => {
    const teacherClient = createAuthClient('reve-test-teacher-course-products');
    const { error: loginError } = await teacherClient.auth.signInWithPassword({
      email: 'teacher-alpha@test.local',
      password: 'TeacherAlpha123!',
    });
    expect(loginError).toBeNull();

    const courses = await fetchOwnerActiveCourses(ownerClient);
    const course = courses[0];

    const { error } = await teacherClient.rpc('reve_owner_create_course_product', {
      p_course_id: course.id,
      p_product_code: 'TEACH-001',
      p_product_name: 'Teacher Attempt',
      p_default_lesson_count: 4,
      p_weekly_frequency: 1,
      p_default_tuition_krw: 100000,
      p_expiration_policy: null,
    });

    expect(error).toBeTruthy();
    expect(error?.message).toMatch(/REVE_UNAUTHORIZED|permission denied/i);
  });
});

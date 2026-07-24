import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  createOwnerCourseProduct,
  setOwnerCourseProductActive,
} from '@/lib/data/owner-course-products';
import { createOwnerInitialEnrollment, loadOwnerEnrollmentCatalog } from '@/lib/data/owner-enrollment';
import { createOwnerStudent } from '@/lib/data/owner-students';
import { fetchStudentDetail } from '@/lib/data/owner-queries';
import { buildScheduleSlotsPayload } from '@/lib/domain/initial-enrollment';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const alphaTeacherBId = '22222222-2222-2222-2222-222222222102';
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

describe.skipIf(!integrationEnabled)('Phase 2B-2B3-R1 canonical enrollment verification', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-phase-2b2b3r1');
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

  it('creates S0001, enrolls on canonical Vocal product, and preserves history after deactivation', async () => {
    const suffix = Date.now().toString().slice(-6);
    const productCode = `V-R1-${suffix}`;

    const student = await createOwnerStudent(ownerClient, {
      name: `R1 Canonical Student ${suffix}`,
      phone: '010-2000-3000',
    });
    expect(student.student_code).toMatch(/^S[0-9]{4,}$/);

    const { data: vocalCourse, error: courseError } = await ownerClient
      .from('courses')
      .select('id, course_code, name')
      .eq('course_code', 'V')
      .eq('is_active', true)
      .single();
    expect(courseError).toBeNull();
    expect(vocalCourse?.course_code).toBe('V');

    const product = await createOwnerCourseProduct(ownerClient, {
      courseId: vocalCourse!.id,
      productCode,
      productName: `R1 Vocal 4 Lessons ${suffix}`,
      defaultLessonCount: 4,
      weeklyFrequency: 1,
      defaultTuitionKrw: 200000,
      courseMeta: {
        course_code: vocalCourse!.course_code,
        course_name: vocalCourse!.name,
      },
    });

    const catalogBefore = await loadOwnerEnrollmentCatalog(ownerClient);
    expect(catalogBefore.status).toBe('ready');
    if (catalogBefore.status === 'ready') {
      expect(
        catalogBefore.catalog.products.some(
          (row) => row.id === product.id && row.course_id === vocalCourse!.id,
        ),
      ).toBe(true);
    }

    const slotMinute = 10 + (Number(suffix) % 40);
    const scheduleSlots = buildScheduleSlotsPayload([
      {
        teacherId: alphaTeacherBId,
        weekday: 6,
        localTime: `12:${String(slotMinute).padStart(2, '0')}`,
        durationMinutes: 60,
        slotOrder: 1,
      },
    ]);

    const enrollment = await createOwnerInitialEnrollment(ownerClient, {
      studentId: student.id,
      courseProductId: product.id,
      scheduleStartDate: '2026-10-01',
      scheduleSlots,
      paidAmountKrw: 200000,
      paymentMethod: 'cash',
      paidAt: new Date('2026-10-01T09:00:00+09:00').toISOString(),
      idempotencyKey: `r1-canonical-${student.id}-${suffix}`,
    });

    expect(enrollment.pass_public_code).toBe(`V-${student.student_code}-001`);
    if (student.student_code === 'S0001') {
      expect(enrollment.pass_public_code).toBe('V-S0001-001');
    }

    const detail = await fetchStudentDetail(ownerClient, student.id);
    expect(detail.student.student_code).toBe(student.student_code);
    expect(detail.current_pass?.pass_code).toBe(enrollment.pass_public_code);

    const { count: passCount } = await ownerClient
      .from('passes')
      .select('id', { count: 'exact', head: true })
      .eq('student_id', student.id)
      .eq('course_id', vocalCourse!.id);
    expect(passCount).toBe(1);

    const { data: latestProduct, error: latestProductError } = await ownerClient
      .from('course_products')
      .select('updated_at')
      .eq('id', product.id)
      .single();
    expect(latestProductError).toBeNull();

    await setOwnerCourseProductActive(ownerClient, {
      courseProductId: product.id,
      isActive: false,
      reason: 'R1 runtime verification deactivate',
      expectedUpdatedAt: latestProduct!.updated_at,
      courseMeta: {
        course_code: vocalCourse!.course_code,
        course_name: vocalCourse!.name,
      },
    });

    const catalogAfter = await loadOwnerEnrollmentCatalog(ownerClient);
    if (catalogAfter.status === 'ready') {
      expect(catalogAfter.catalog.products.some((row) => row.id === product.id)).toBe(false);
    }

    const detailAfter = await fetchStudentDetail(ownerClient, student.id);
    expect(detailAfter.current_pass?.pass_code).toBe(enrollment.pass_public_code);
  });
});

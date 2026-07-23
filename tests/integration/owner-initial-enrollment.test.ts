import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  createOwnerInitialEnrollment,
  fetchOwnerEnrollmentCatalog,
} from '@/lib/data/owner-enrollment';
import { createOwnerStudent } from '@/lib/data/owner-students';
import { fetchStudentDetail } from '@/lib/data/owner-queries';
import { buildScheduleSlotsPayload } from '@/lib/domain/initial-enrollment';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';

const alphaTeacherId = '22222222-2222-2222-2222-222222222101';
const alphaTeacherBId = '22222222-2222-2222-2222-222222222102';
const vocalCourseId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee101';
const pianoCourseId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee102';
const vocalProduct4Id = 'ffffffff-ffff-ffff-ffff-fffffffff101';
const pianoProduct8Id = 'ffffffff-ffff-ffff-ffff-fffffffff102';
const scheduleStartDate = '2026-09-01';

/** Fixed slots reserved for integration enrollments; avoid alpha seed teacher/weekday/time pairs. */
const enrollmentScheduleFixtures = {
  voc4Weekly: vocalWeeklySlot(alphaTeacherId, 2, '13:00'),
  pia8TwiceWeekly: buildScheduleSlotsPayload([
    {
      teacherId: alphaTeacherId,
      weekday: 2,
      localTime: '14:00',
      durationMinutes: 60,
      slotOrder: 1,
    },
    {
      teacherId: alphaTeacherBId,
      weekday: 4,
      localTime: '15:00',
      durationMinutes: 60,
      slotOrder: 2,
    },
  ]),
  dupcourseWeekly: vocalWeeklySlot(alphaTeacherBId, 1, '16:00'),
  idemWeekly: vocalWeeklySlot(alphaTeacherBId, 3, '17:00'),
};

function studentStartDate(studentId: string): string {
  const day = (Number(studentId.replace(/\D/g, '').slice(-6)) || 1) % 20 + 1;
  return `2026-09-${String(day).padStart(2, '0')}`;
}

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

function vocalWeeklySlot(teacherId: string, weekday = 1, localTime = '11:00') {
  return buildScheduleSlotsPayload([
    {
      teacherId,
      weekday,
      localTime,
      durationMinutes: 60,
      slotOrder: 1,
    },
  ]);
}

function pianoTwiceWeeklySlots(teacherA: string, teacherB: string) {
  return buildScheduleSlotsPayload([
    {
      teacherId: teacherA,
      weekday: 2,
      localTime: '10:00',
      durationMinutes: 60,
      slotOrder: 1,
    },
    {
      teacherId: teacherB,
      weekday: 4,
      localTime: '15:00',
      durationMinutes: 60,
      slotOrder: 2,
    },
  ]);
}

async function createEnrollmentStudent(ownerClient: SupabaseClient, label: string) {
  const suffix = Date.now().toString().slice(-6);
  return createOwnerStudent(ownerClient, {
    name: `${label} Student ${suffix}`,
    phone: '010-1000-2000',
  });
}

describe.skipIf(!integrationEnabled)('Owner initial enrollment integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-owner-enrollment');
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

  it('loads the enrollment catalog with active teachers, courses, and products', async () => {
    const catalog = await fetchOwnerEnrollmentCatalog(ownerClient);
    expect(catalog.teachers.some((row) => row.id === alphaTeacherId)).toBe(true);
    expect(catalog.courses.some((row) => row.id === vocalCourseId)).toBe(true);
    expect(catalog.products.some((row) => row.id === vocalProduct4Id)).toBe(true);
    expect(catalog.products.some((row) => row.id === pianoProduct8Id)).toBe(true);
  });

  it('creates a four-lesson weekly initial enrollment with lessons, schedule, and audit rows', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'VOC4');
    const idempotencyKey = `int-voc4-${student.id}`;
    const startDate = studentStartDate(student.id);
    const scheduleSlots = enrollmentScheduleFixtures.voc4Weekly;

    const result = await createOwnerInitialEnrollment(ownerClient, {
      studentId: student.id,
      courseProductId: vocalProduct4Id,
      scheduleStartDate: startDate,
      scheduleSlots,
      paidAmountKrw: 200000,
      paymentMethod: 'cash',
      paidAt: new Date(`${startDate}T09:00:00+09:00`).toISOString(),
      idempotencyKey,
      ownerReason: 'integration_voc4',
    });

    expect(result.lesson_rows_created).toBe(4);
    expect(result.registered_lesson_count).toBe(4);
    expect(result.schedule_slots_created).toBe(1);
    expect(result.idempotent_replay).toBe(false);

    const detail = await fetchStudentDetail(ownerClient, student.id);
    expect(detail.current_pass?.registered_lesson_count).toBe(4);
    expect(detail.current_pass?.used_lesson_count).toBe(0);
    expect(detail.current_pass?.remaining_lesson_count).toBe(4);
    expect(detail.schedule_slots).toHaveLength(1);
    expect(detail.lessons).toHaveLength(4);
    expect(detail.lessons.map((lesson) => lesson.sequence_number).sort()).toEqual([1, 2, 3, 4]);

    const { data: auditRows, error: auditError } = await ownerClient
      .from('audit_logs')
      .select('action')
      .eq('resource_table', 'passes')
      .eq('resource_id', result.pass_id);

    expect(auditError).toBeNull();
    expect(auditRows?.length).toBeGreaterThan(0);
  });

  it('creates an eight-lesson twice-weekly initial enrollment with two schedule slots', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'PIA8');
    const idempotencyKey = `int-pia8-${student.id}`;
    const startDate = studentStartDate(student.id);
    const scheduleSlots = enrollmentScheduleFixtures.pia8TwiceWeekly;

    const result = await createOwnerInitialEnrollment(ownerClient, {
      studentId: student.id,
      courseProductId: pianoProduct8Id,
      scheduleStartDate: startDate,
      scheduleSlots,
      paidAmountKrw: 400000,
      paymentMethod: 'bank_transfer',
      paidAt: new Date(`${startDate}T09:00:00+09:00`).toISOString(),
      idempotencyKey,
      ownerReason: 'integration_pia8',
    });

    expect(result.lesson_rows_created).toBe(8);
    expect(result.registered_lesson_count).toBe(8);
    expect(result.schedule_slots_created).toBe(2);

    const detail = await fetchStudentDetail(ownerClient, student.id);
    expect(detail.current_pass?.used_lesson_count).toBe(0);
    expect(detail.current_pass?.remaining_lesson_count).toBe(8);
    expect(detail.schedule_slots).toHaveLength(2);
    expect(new Set(detail.schedule_slots.map((slot) => slot.weekday)).size).toBe(2);
    expect(detail.lessons).toHaveLength(8);
    expect(detail.lessons.map((lesson) => lesson.sequence_number).sort()).toEqual([
      1, 2, 3, 4, 5, 6, 7, 8,
    ]);
  });

  it('rejects weekly products submitted with an invalid slot count', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'VOCBAD');
    await expect(
      createOwnerInitialEnrollment(ownerClient, {
        studentId: student.id,
        courseProductId: vocalProduct4Id,
        scheduleStartDate,
        scheduleSlots: pianoTwiceWeeklySlots(alphaTeacherId, alphaTeacherBId),
        paidAmountKrw: 200000,
        paymentMethod: 'cash',
        paidAt: new Date(`${scheduleStartDate}T09:00:00+09:00`).toISOString(),
        idempotencyKey: `int-vocbad-${student.id}`,
      }),
    ).rejects.toThrow(/REVE_INVALID_SCHEDULE/);

    const { count } = await ownerClient
      .from('passes')
      .select('id', { count: 'exact', head: true })
      .eq('student_id', student.id);
    expect(count).toBe(0);
  });

  it('rejects twice-weekly products submitted with an invalid slot count', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'PIABAD');
    await expect(
      createOwnerInitialEnrollment(ownerClient, {
        studentId: student.id,
        courseProductId: pianoProduct8Id,
        scheduleStartDate,
        scheduleSlots: vocalWeeklySlot(alphaTeacherId),
        paidAmountKrw: 400000,
        paymentMethod: 'cash',
        paidAt: new Date(`${scheduleStartDate}T09:00:00+09:00`).toISOString(),
        idempotencyKey: `int-piabad-${student.id}`,
      }),
    ).rejects.toThrow(/REVE_INVALID_SCHEDULE/);

    const { count } = await ownerClient
      .from('passes')
      .select('id', { count: 'exact', head: true })
      .eq('student_id', student.id);
    expect(count).toBe(0);
  });

  it('rejects duplicate initial enrollment for the same course', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'DUPCOURSE');
    const firstKey = `int-dupcourse-1-${student.id}`;
    const dupStartDate = studentStartDate(student.id);
    const scheduleSlots = enrollmentScheduleFixtures.dupcourseWeekly;

    await createOwnerInitialEnrollment(ownerClient, {
      studentId: student.id,
      courseProductId: vocalProduct4Id,
      scheduleStartDate: dupStartDate,
      scheduleSlots,
      paidAmountKrw: 200000,
      paymentMethod: 'cash',
      paidAt: new Date(`${dupStartDate}T09:00:00+09:00`).toISOString(),
      idempotencyKey: firstKey,
    });

    await expect(
      createOwnerInitialEnrollment(ownerClient, {
        studentId: student.id,
        courseProductId: vocalProduct4Id,
        scheduleStartDate: dupStartDate,
        scheduleSlots,
        paidAmountKrw: 200000,
        paymentMethod: 'cash',
        paidAt: new Date(`${dupStartDate}T09:00:00+09:00`).toISOString(),
        idempotencyKey: `int-dupcourse-2-${student.id}`,
      }),
    ).rejects.toThrow(/REVE_NOT_INITIAL_ENROLLMENT/);
  });

  it('replays idempotent enrollment requests without creating duplicate passes', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'IDEM');
    const idempotencyKey = `int-idem-${student.id}`;
    const idemStartDate = studentStartDate(student.id);
    const scheduleSlots = enrollmentScheduleFixtures.idemWeekly;

    const first = await createOwnerInitialEnrollment(ownerClient, {
      studentId: student.id,
      courseProductId: vocalProduct4Id,
      scheduleStartDate: idemStartDate,
      scheduleSlots,
      paidAmountKrw: 200000,
      paymentMethod: 'cash',
      paidAt: new Date(`${idemStartDate}T09:00:00+09:00`).toISOString(),
      idempotencyKey,
    });

    const second = await createOwnerInitialEnrollment(ownerClient, {
      studentId: student.id,
      courseProductId: vocalProduct4Id,
      scheduleStartDate: idemStartDate,
      scheduleSlots,
      paidAmountKrw: 200000,
      paymentMethod: 'cash',
      paidAt: new Date(`${idemStartDate}T09:00:00+09:00`).toISOString(),
      idempotencyKey,
    });

    expect(second.idempotent_replay).toBe(true);
    expect(second.pass_id).toBe(first.pass_id);

    const { count } = await ownerClient
      .from('passes')
      .select('id', { count: 'exact', head: true })
      .eq('student_id', student.id)
      .eq('course_id', vocalCourseId);
    expect(count).toBe(1);
  });

  it('rejects non-owner initial enrollment mutations', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'NOAUTH');
    const teacherClient = createAuthClient('reve-test-teacher-enrollment');
    const { error: signInError } = await teacherClient.auth.signInWithPassword({
      email: teacherEmail,
      password: teacherPassword,
    });
    expect(signInError).toBeNull();

    await expect(
      createOwnerInitialEnrollment(teacherClient, {
        studentId: student.id,
        courseProductId: vocalProduct4Id,
        scheduleStartDate,
        scheduleSlots: vocalWeeklySlot(alphaTeacherId),
        paidAmountKrw: 200000,
        paymentMethod: 'cash',
        paidAt: new Date(`${scheduleStartDate}T09:00:00+09:00`).toISOString(),
        idempotencyKey: `int-noauth-${student.id}`,
      }),
    ).rejects.toThrow(/REVE_UNAUTHORIZED|42501/);
  });
});

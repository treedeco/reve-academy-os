import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import { createOwnerInitialEnrollment } from '@/lib/data/owner-enrollment';
import { createOwnerStudent } from '@/lib/data/owner-students';
import { createOwnerTeacher } from '@/lib/data/owner-teachers';
import { fetchStudentDetail } from '@/lib/data/owner-queries';
import {
  permanentlyDeleteStudent,
  permanentlyDeleteTeacher,
  previewDeleteStudent,
  previewDeleteTeacher,
  previewRemoveFixedPassSchedule,
  removeFixedPassSchedule,
} from '@/lib/data/owner-deletion';
import { buildScheduleSlotsPayload } from '@/lib/domain/initial-enrollment';
import {
  buildScheduleRemovalConfirmationPhrase,
  buildStudentDeleteConfirmationPhrase,
  buildTeacherDeleteConfirmationPhrase,
} from '@/lib/domain/owner-deletion';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';

const alphaTeacherId = '22222222-2222-2222-2222-222222222101';
const alphaTeacherBId = '22222222-2222-2222-2222-222222222102';
const vocalProduct4Id = 'ffffffff-ffff-ffff-ffff-fffffffff101';

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

/** Fixed slots reserved for deletion integration enrollments; avoid alpha seed and other integration fixtures. */
function weeklySlot(teacherId: string, weekday: number, localTime: string) {
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

async function createEnrollmentStudent(ownerClient: SupabaseClient, label: string) {
  const suffix = `${Date.now()}${Math.floor(Math.random() * 1000)}`.slice(-9);
  return createOwnerStudent(ownerClient, {
    name: `${label} Student ${suffix}`,
    phone: '010-4000-5000',
  });
}

async function enrollStudentWithSchedule(
  ownerClient: SupabaseClient,
  studentId: string,
  scheduleSlots: ReturnType<typeof weeklySlot>,
  startDate: string,
) {
  return createOwnerInitialEnrollment(ownerClient, {
    studentId,
    courseProductId: vocalProduct4Id,
    scheduleStartDate: startDate,
    scheduleSlots,
    paidAmountKrw: 200000,
    paymentMethod: 'cash',
    paidAt: new Date(`${startDate}T09:00:00+09:00`).toISOString(),
    idempotencyKey: `int-del-${studentId}`,
  });
}

describe.skipIf(!integrationEnabled)('Owner deletion integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-owner-deletion');
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

  it('previews and executes fixed pass-schedule removal, leaving history intact', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'SCHEDDEL');
    const startDate = '2026-09-07';
    await enrollStudentWithSchedule(
      ownerClient,
      student.id,
      weeklySlot(alphaTeacherId, 4, '10:30'),
      startDate,
    );

    const detail = await fetchStudentDetail(ownerClient, student.id);
    expect(detail.current_pass).not.toBeNull();
    expect(detail.schedule_slots).toHaveLength(1);
    const passId = detail.current_pass!.pass_id;

    const preview = await previewRemoveFixedPassSchedule(ownerClient, {
      passId,
      effectiveFrom: startDate,
    });
    expect(preview.active_slot_count).toBe(1);
    expect(preview.blockers).toEqual([]);

    const result = await removeFixedPassSchedule(ownerClient, {
      passId,
      expectedPassUpdatedAt: preview.pass_updated_at,
      effectiveFrom: startDate,
      reason: 'integration test schedule removal',
      confirmationCode: buildScheduleRemovalConfirmationPhrase(preview.pass_code),
      preflightFingerprint: preview.preflight_fingerprint,
    });

    expect(result.no_change).toBe(false);
    expect(result.removed_schedule_slot_count).toBe(1);

    const detailAfter = await fetchStudentDetail(ownerClient, student.id);
    expect(detailAfter.schedule_slots).toHaveLength(0);
    expect(detailAfter.current_pass).not.toBeNull();

    // Idempotent replay: nothing left to remove.
    const secondPreview = await previewRemoveFixedPassSchedule(ownerClient, {
      passId,
      effectiveFrom: startDate,
    });
    expect(secondPreview.active_slot_count).toBe(0);

    const secondResult = await removeFixedPassSchedule(ownerClient, {
      passId,
      expectedPassUpdatedAt: secondPreview.pass_updated_at,
      effectiveFrom: startDate,
      reason: 'integration test idempotent replay',
      confirmationCode: buildScheduleRemovalConfirmationPhrase(secondPreview.pass_code),
      preflightFingerprint: secondPreview.preflight_fingerprint,
    });
    expect(secondResult.no_change).toBe(true);
    expect(secondResult.removed_schedule_slot_count).toBe(0);
  });

  it('permanently deletes a dedicated fixture student and its dependent rows', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'STUDENTDEL');
    const startDate = '2026-09-08';
    await enrollStudentWithSchedule(
      ownerClient,
      student.id,
      weeklySlot(alphaTeacherBId, 4, '11:30'),
      startDate,
    );

    const preview = await previewDeleteStudent(ownerClient, student.id);
    expect(preview.pass_count).toBeGreaterThan(0);
    expect(preview.lesson_count).toBeGreaterThan(0);

    const result = await permanentlyDeleteStudent(ownerClient, {
      studentId: student.id,
      expectedUpdatedAt: preview.updated_at,
      confirmationCode: buildStudentDeleteConfirmationPhrase(preview.student_code),
      reason: 'integration test permanent deletion',
      preflightFingerprint: preview.preflight_fingerprint,
    });

    expect(result.already_deleted).toBe(false);
    expect(result.deleted_pass_count).toBeGreaterThan(0);
    expect(result.deleted_lesson_count).toBeGreaterThan(0);

    const { count: studentCount } = await ownerClient
      .from('students')
      .select('id', { count: 'exact', head: true })
      .eq('id', student.id);
    expect(studentCount).toBe(0);

    const { count: passCount } = await ownerClient
      .from('passes')
      .select('id', { count: 'exact', head: true })
      .eq('student_id', student.id);
    expect(passCount).toBe(0);

    const replay = await permanentlyDeleteStudent(ownerClient, {
      studentId: student.id,
      expectedUpdatedAt: preview.updated_at,
      confirmationCode: buildStudentDeleteConfirmationPhrase(preview.student_code),
      reason: 'integration test idempotent replay',
      preflightFingerprint: preview.preflight_fingerprint,
    });
    expect(replay.already_deleted).toBe(true);
    expect(replay.deleted_pass_count).toBe(0);
  });

  it('rejects a confirmation-phrase mismatch without deleting the student', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'CONFIRMBAD');
    const preview = await previewDeleteStudent(ownerClient, student.id);

    await expect(
      permanentlyDeleteStudent(ownerClient, {
        studentId: student.id,
        expectedUpdatedAt: preview.updated_at,
        confirmationCode: 'not the right phrase',
        reason: 'integration test confirmation mismatch',
        preflightFingerprint: preview.preflight_fingerprint,
      }),
    ).rejects.toThrow(/REVE_CONFIRMATION_MISMATCH/);

    const { count } = await ownerClient
      .from('students')
      .select('id', { count: 'exact', head: true })
      .eq('id', student.id);
    expect(count).toBe(1);
  });

  it('permanently deletes a dedicated fixture teacher with reassignment to another active teacher', async () => {
    const suffix = `${Date.now()}`.slice(-8);
    const teacher = await createOwnerTeacher(ownerClient, {
      teacherCode: `T-DELINT${suffix}`,
      name: `Deletion Reassign Teacher ${suffix}`,
    });

    const student = await createEnrollmentStudent(ownerClient, 'TEACHDEL');
    const startDate = '2026-09-09';
    await enrollStudentWithSchedule(
      ownerClient,
      student.id,
      weeklySlot(teacher.id, 5, '09:30'),
      startDate,
    );

    const preview = await previewDeleteTeacher(ownerClient, teacher.id);
    expect(preview.total_lesson_count).toBeGreaterThan(0);
    expect(preview.active_schedule_slot_count).toBe(1);

    const result = await permanentlyDeleteTeacher(ownerClient, {
      teacherId: teacher.id,
      expectedUpdatedAt: preview.updated_at,
      linkHandlingMode: 'reassign',
      replacementTeacherId: alphaTeacherId,
      confirmationCode: buildTeacherDeleteConfirmationPhrase(preview.teacher_code, teacher.name),
      reason: 'integration test teacher deletion with reassignment',
      preflightFingerprint: preview.preflight_fingerprint,
    });

    expect(result.already_deleted).toBe(false);
    expect(result.link_handling_mode).toBe('reassign');
    expect(result.reassigned_active_slot_count).toBe(1);

    const { count: teacherCount } = await ownerClient
      .from('teachers')
      .select('id', { count: 'exact', head: true })
      .eq('id', teacher.id);
    expect(teacherCount).toBe(0);

    // Student, pass, and schedule slot survive — reassigned to the replacement teacher.
    const detail = await fetchStudentDetail(ownerClient, student.id);
    expect(detail.current_pass).not.toBeNull();
    expect(detail.schedule_slots).toHaveLength(1);
    expect(detail.schedule_slots[0]?.teacher_id).toBe(alphaTeacherId);

    const replay = await permanentlyDeleteTeacher(ownerClient, {
      teacherId: teacher.id,
      expectedUpdatedAt: preview.updated_at,
      linkHandlingMode: 'reassign',
      replacementTeacherId: alphaTeacherId,
      confirmationCode: buildTeacherDeleteConfirmationPhrase(preview.teacher_code, teacher.name),
      reason: 'integration test idempotent replay',
      preflightFingerprint: preview.preflight_fingerprint,
    });
    expect(replay.already_deleted).toBe(true);
  });

  it('rejects non-owner deletion mutations', async () => {
    const student = await createEnrollmentStudent(ownerClient, 'NOAUTHDEL');
    const teacherClient = createAuthClient('reve-test-teacher-deletion');
    const { error: signInError } = await teacherClient.auth.signInWithPassword({
      email: teacherEmail,
      password: teacherPassword,
    });
    expect(signInError).toBeNull();

    await expect(previewDeleteStudent(teacherClient, student.id)).rejects.toThrow(
      /REVE_UNAUTHORIZED|42501/,
    );

    await expect(
      permanentlyDeleteStudent(teacherClient, {
        studentId: student.id,
        expectedUpdatedAt: new Date().toISOString(),
        confirmationCode: 'bogus',
        reason: 'unauthorized attempt',
        preflightFingerprint: 'bogus',
      }),
    ).rejects.toThrow(/REVE_UNAUTHORIZED|42501/);

    const { count } = await ownerClient
      .from('students')
      .select('id', { count: 'exact', head: true })
      .eq('id', student.id);
    expect(count).toBe(1);
  });
});

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  createOwnerStudent,
  fetchOwnerStudentMasterList,
  fetchOwnerStudentMasterRow,
  setOwnerStudentActive,
  updateOwnerStudent,
} from '@/lib/data/owner-students';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';
const linkedStudentId = '44444444-4444-4444-4444-444444444101';

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

describe.skipIf(!integrationEnabled)('Owner student master data integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-owner-students');
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

  it('fetches the owner student master list in one query', async () => {
    const students = await fetchOwnerStudentMasterList(ownerClient);
    expect(students.length).toBeGreaterThanOrEqual(1);
    expect(students.some((row) => row.student_code === 'S1A1')).toBe(true);
  });

  it('creates, updates, deactivates, and reactivates a student through RPC wrappers', async () => {
    const suffix = Date.now().toString().slice(-6);

    const created = await createOwnerStudent(ownerClient, {
      name: `Integration Student ${suffix}`,
      phone: '010-5555-6666',
      email: `student-${suffix}@test.local`,
    });

    expect(created.student_code).toMatch(/^S[0-9]{4,}$/);
    expect(created.operational_status).toBe('active');

    const row = await fetchOwnerStudentMasterRow(ownerClient, created.id);
    expect(row.name).toBe(`Integration Student ${suffix}`);

    const updated = await updateOwnerStudent(ownerClient, {
      studentId: created.id,
      expectedUpdatedAt: created.updated_at,
      name: `Integration Student Updated ${suffix}`,
      phone: '010-7777-8888',
      email: `student-updated-${suffix}@test.local`,
    });

    expect(updated.name).toContain('Updated');

    const deactivated = await setOwnerStudentActive(ownerClient, {
      studentId: updated.id,
      operationalStatus: 'inactive',
      reason: 'integration deactivate',
      expectedUpdatedAt: updated.updated_at,
    });

    expect(deactivated.operational_status).toBe('inactive');

    const reactivated = await setOwnerStudentActive(ownerClient, {
      studentId: deactivated.id,
      operationalStatus: 'active',
      reason: 'integration reactivate',
      expectedUpdatedAt: deactivated.updated_at,
    });

    expect(reactivated.operational_status).toBe('active');

    const { data: auditRows, error: auditError } = await ownerClient
      .from('audit_logs')
      .select('action, resource_table, resource_id')
      .eq('resource_table', 'students')
      .eq('resource_id', created.id)
      .order('created_at', { ascending: true });

    expect(auditError).toBeNull();
    expect(auditRows?.map((row) => row.action)).toEqual(
      expect.arrayContaining(['student.created', 'student.updated', 'student.status_changed']),
    );
  });

  it('rejects required-field violations on create', async () => {
    await expect(
      createOwnerStudent(ownerClient, {
        name: '',
      }),
    ).rejects.toThrow(/REVE_INVALID_NAME/);
  });

  it('blocks deactivation when a linked active profile exists', async () => {
    const linked = await fetchOwnerStudentMasterRow(ownerClient, linkedStudentId);
    expect(linked.operational_status).toBe('active');

    await expect(
      setOwnerStudentActive(ownerClient, {
        studentId: linked.id,
        operationalStatus: 'inactive',
        reason: 'integration blocked deactivate',
        expectedUpdatedAt: linked.updated_at,
      }),
    ).rejects.toThrow(/REVE_PROFILE_LINK_CONFLICT/);
  });

  it('rejects non-owner student master data mutations', async () => {
    const teacherClient = createAuthClient('reve-test-teacher-students');
    const { error: signInError } = await teacherClient.auth.signInWithPassword({
      email: teacherEmail,
      password: teacherPassword,
    });
    expect(signInError).toBeNull();

    await expect(
      createOwnerStudent(teacherClient, {
        name: 'Teacher Client Student',
      }),
    ).rejects.toThrow(/REVE_UNAUTHORIZED|42501/);
  });

  it('rejects direct student table inserts for authenticated clients', async () => {
    const { error } = await ownerClient.from('students').insert({
      student_code: 'S-DIRECT',
      name: 'Direct Student',
    });

    expect(error).toBeTruthy();
  });

  it('assigns a unique generated student code on each create', async () => {
    const suffix = Date.now().toString().slice(-6);

    const created = await createOwnerStudent(ownerClient, {
      name: `Duplicate Guard ${suffix}`,
    });

    const { count, error } = await ownerClient
      .from('students')
      .select('id', { count: 'exact', head: true })
      .eq('student_code', created.student_code);

    expect(error).toBeNull();
    expect(count).toBe(1);
    expect(created.student_code).toMatch(/^S[0-9]{4,}$/);
  });
});

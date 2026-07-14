import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  createOwnerTeacher,
  fetchOwnerTeacherList,
  setOwnerTeacherActive,
  updateOwnerTeacher,
} from '@/lib/data/owner-teachers';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';
const assignedTeacherId = '22222222-2222-2222-2222-222222222101';

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

describe.skipIf(!integrationEnabled)('Owner teacher master data integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-owner-teachers');
    const { error } = await ownerClient.auth.signInWithPassword({
      email: ownerEmail,
      password: ownerPassword,
    });
    if (error) {
      throw new Error(
        `Owner login failed (${error.message}). Run npm run db:seed:alpha after db reset.`,
      );
    }
  });

  it('fetches the owner teacher list in one query', async () => {
    const teachers = await fetchOwnerTeacherList(ownerClient);
    expect(teachers.length).toBeGreaterThanOrEqual(2);
    expect(teachers.some((row) => row.teacher_code === 'T-A1')).toBe(true);
  });

  it('creates, updates, deactivates, and reactivates a teacher through RPC wrappers', async () => {
    const suffix = Date.now().toString().slice(-6);
    const teacherCode = `T-INT${suffix}`;

    const created = await createOwnerTeacher(ownerClient, {
      teacherCode,
      name: `Integration Teacher ${suffix}`,
      phone: '010-5555-6666',
      email: `teacher-${suffix}@test.local`,
    });

    expect(created.teacher_code).toBe(teacherCode);
    expect(created.is_active).toBe(true);

    const updated = await updateOwnerTeacher(ownerClient, {
      teacherId: created.id,
      expectedUpdatedAt: created.updated_at,
      name: `Integration Teacher Updated ${suffix}`,
      phone: '010-7777-8888',
      email: `teacher-updated-${suffix}@test.local`,
    });

    expect(updated.name).toContain('Updated');

    const deactivated = await setOwnerTeacherActive(ownerClient, {
      teacherId: updated.id,
      isActive: false,
      reason: 'integration deactivate',
      expectedUpdatedAt: updated.updated_at,
    });

    expect(deactivated.is_active).toBe(false);

    const reactivated = await setOwnerTeacherActive(ownerClient, {
      teacherId: deactivated.id,
      isActive: true,
      reason: 'integration reactivate',
      expectedUpdatedAt: deactivated.updated_at,
    });

    expect(reactivated.is_active).toBe(true);

    const { data: auditRows, error: auditError } = await ownerClient
      .from('audit_logs')
      .select('action, resource_table, resource_id')
      .eq('resource_table', 'teachers')
      .eq('resource_id', created.id)
      .order('created_at', { ascending: true });

    expect(auditError).toBeNull();
    expect(auditRows?.map((row) => row.action)).toEqual(
      expect.arrayContaining(['teacher.created', 'teacher.updated', 'teacher.status_changed']),
    );
  });

  it('blocks deactivation when active assignments exist', async () => {
    const teachers = await fetchOwnerTeacherList(ownerClient);
    const assigned = teachers.find((row) => row.id === assignedTeacherId);
    expect(assigned).toBeDefined();

    await expect(
      setOwnerTeacherActive(ownerClient, {
        teacherId: assigned!.id,
        isActive: false,
        reason: 'integration blocked deactivate',
        expectedUpdatedAt: assigned!.updated_at,
      }),
    ).rejects.toThrow(/REVE_ACTIVE_ASSIGNMENTS_EXIST/);
  });

  it('rejects non-owner teacher master data mutations', async () => {
    const teacherClient = createAuthClient('reve-test-teacher-teachers');
    const { error: signInError } = await teacherClient.auth.signInWithPassword({
      email: teacherEmail,
      password: teacherPassword,
    });
    expect(signInError).toBeNull();

    await expect(
      createOwnerTeacher(teacherClient, {
        teacherCode: 'T-TEACH',
        name: 'Teacher Client',
      }),
    ).rejects.toThrow(/REVE_UNAUTHORIZED|42501/);
  });

  it('rejects direct teacher table inserts for authenticated clients', async () => {
    const { error } = await ownerClient.from('teachers').insert({
      teacher_code: 'T-DIRECT',
      name: 'Direct Teacher',
    });

    expect(error).toBeTruthy();
  });
});

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  fetchPassUsage,
  fetchStudentDetail,
  fetchTodayLessons,
  fetchWeeklySchedule,
  transitionLessonStatus,
} from '@/lib/data/owner-queries';
import { mapDatabaseError } from '@/lib/domain/format';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';
const alphaPassId = '66666666-6666-6666-6666-666666666101';
const alphaStudentId = '44444444-4444-4444-4444-444444444101';

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

describe.skipIf(!integrationEnabled)('Owner data integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-owner');
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

  it('loads today lessons for authenticated owner', async () => {
    const lessons = await fetchTodayLessons(ownerClient);
    expect(Array.isArray(lessons)).toBe(true);
  });

  it('returns derived pass usage counts from authoritative RPC', async () => {
    const usage = await fetchPassUsage(ownerClient, alphaPassId);
    expect(usage.registered_lesson_count).toBe(4);
    expect(usage.used_lesson_count + usage.remaining_lesson_count).toBe(4);
  });

  it('loads student detail with pass summary', async () => {
    const detail = await fetchStudentDetail(ownerClient, alphaStudentId);
    expect(detail.student.name).toBe('Alpha Student');
    expect(detail.current_pass?.pass_code).toBe('V-S1A1-001');
  });

  it('loads weekly schedule entries for authenticated owner', async () => {
    const entries = await fetchWeeklySchedule(ownerClient);
    expect(entries.length).toBeGreaterThanOrEqual(3);
    expect(entries.some((entry) => entry.student_name === 'Alpha Student' && entry.weekday === 1)).toBe(true);
    expect(entries.some((entry) => entry.student_name === 'Beta Student' && entry.weekday === 3)).toBe(true);
    expect(entries.every((entry) => entry.pass_status === 'active')).toBe(true);
  });

  it('maps RPC transition errors to readable messages', async () => {
    const alphaLessonId = '99999999-9999-9999-9999-999999999101';
    const { data: lesson, error } = await ownerClient
      .from('lessons')
      .select('id, updated_at')
      .eq('id', alphaLessonId)
      .maybeSingle();

    expect(error).toBeNull();
    expect(lesson).toBeDefined();

    try {
      await transitionLessonStatus(ownerClient, {
        lessonId: lesson!.id,
        newStatus: 'completed',
        expectedUpdatedAt: '1970-01-01T00:00:00.000Z',
      });
      expect.unreachable('expected stale transition to fail');
    } catch (error) {
      expect(mapDatabaseError(error as { message?: string })).toMatch(/다른 사용자|새로고침/);
    }
  });

  it('rejects unauthorized pass usage reads for teacher', async () => {
    const teacherClient = createAuthClient('reve-test-teacher');
    const { error: signInError } = await teacherClient.auth.signInWithPassword({
      email: teacherEmail,
      password: teacherPassword,
    });
    expect(signInError).toBeNull();

    await expect(fetchPassUsage(teacherClient, alphaPassId)).rejects.toThrow(/REVE_UNAUTHORIZED|42501/);
  });
});

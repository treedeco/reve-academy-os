import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { saveLessonNote } from '@/lib/data/lesson-notes';
import { fetchTodayLessons, transitionLessonStatus } from '@/lib/data/owner-queries';
import {
  fetchTeacherAssignedStudents,
  fetchTeacherTodayLessons,
} from '@/lib/data/teacher-queries';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';
const teacherBetaEmail = 'teacher-beta@test.local';
const alphaTodayLessonId = '99999999-9999-9999-9999-999999999101';
const betaTodayLessonId = '99999999-9999-9999-9999-999999999201';

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

async function signIn(client: SupabaseClient, email: string, password: string) {
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) {
    throw new Error(`Login failed for ${email}: ${error.message}`);
  }
}

describe.skipIf(!integrationEnabled)('Immediate owner/teacher operations', () => {
  let ownerClient: SupabaseClient;
  let teacherClient: SupabaseClient;
  let teacherBetaClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-immediate-owner');
    teacherClient = createAuthClient('reve-test-immediate-teacher');
    teacherBetaClient = createAuthClient('reve-test-immediate-teacher-beta');

    await signIn(ownerClient, OWNER_AUTH_EMAIL, getOwnerTestPassword());
    await signIn(teacherClient, teacherEmail, teacherPassword);
    await signIn(teacherBetaClient, teacherBetaEmail, 'TeacherBeta123!');
  });

  it('owner can view today lessons', async () => {
    const lessons = await fetchTodayLessons(ownerClient);
    expect(lessons.length).toBeGreaterThan(0);
  });

  it('owner can create and update lesson content', async () => {
    const lessons = await fetchTodayLessons(ownerClient);
    const lesson = lessons.find((row) => row.id === alphaTodayLessonId);
    expect(lesson).toBeTruthy();

    const {
      data: { user },
    } = await ownerClient.auth.getUser();
    expect(user).toBeTruthy();

    const created = await saveLessonNote(ownerClient, {
      lessonId: lesson!.id,
      authorProfileId: user!.id,
      body: `Owner immediate note ${Date.now()}`,
      noteId: lesson!.memo_note_id,
    });
    expect(created.body.length).toBeGreaterThan(0);

    const reloaded = await fetchTodayLessons(ownerClient);
    expect(reloaded.find((row) => row.id === lesson!.id)?.memo_summary).toBe(created.body);
  });

  it('owner can change lesson status via trusted RPC', async () => {
    const lessons = await fetchTodayLessons(ownerClient);
    const lesson = lessons.find((row) => row.id === alphaTodayLessonId);
    expect(lesson).toBeTruthy();

    if (lesson!.status !== 'scheduled') {
      return;
    }

    const result = await transitionLessonStatus(ownerClient, {
      lessonId: lesson!.id,
      newStatus: 'completed',
      expectedUpdatedAt: lesson!.updated_at,
    });
    expect(result.new_status).toBe('completed');
  });

  it('teacher can authenticate and view own assigned lessons', async () => {
    const lessons = await fetchTeacherTodayLessons(teacherClient);
    expect(lessons.some((row) => row.id === alphaTodayLessonId)).toBe(true);
    expect(lessons.some((row) => row.id === betaTodayLessonId)).toBe(false);
  });

  it('teacher can view assigned student summaries without financial fields', async () => {
    const students = await fetchTeacherAssignedStudents(teacherClient);
    expect(students.length).toBeGreaterThan(0);
    expect(students[0]).not.toHaveProperty('phone');
    expect(students[0]).not.toHaveProperty('email');
  });

  it('teacher can change permitted lesson status when scheduled', async () => {
    const lessons = await fetchTeacherTodayLessons(teacherClient);
    const lesson = lessons.find((row) => row.id === alphaTodayLessonId);
    expect(lesson).toBeTruthy();

    if (lesson!.status !== 'scheduled') {
      return;
    }

    const result = await transitionLessonStatus(teacherClient, {
      lessonId: lesson!.id,
      newStatus: 'completed',
      expectedUpdatedAt: lesson!.updated_at,
    });
    expect(result.new_status).toBe('completed');
  });

  it('teacher can create lesson content and persist after reload', async () => {
    const lessons = await fetchTeacherTodayLessons(teacherClient);
    const lesson = lessons.find((row) => row.id === alphaTodayLessonId);
    expect(lesson).toBeTruthy();

    const {
      data: { user },
    } = await teacherClient.auth.getUser();
    expect(user).toBeTruthy();

    const body = `Teacher immediate note ${Date.now()}`;
    const saved = await saveLessonNote(teacherClient, {
      lessonId: lesson!.id,
      authorProfileId: user!.id,
      body,
      noteId: lesson!.memo_note_id,
    });
    expect(saved.body).toBe(body);

    const reloaded = await fetchTeacherTodayLessons(teacherClient);
    expect(reloaded.find((row) => row.id === lesson!.id)?.memo_summary).toBe(body);
  });

  it('teacher cannot access another teacher lesson via query', async () => {
    const { data, error } = await teacherBetaClient
      .from('lessons')
      .select('id')
      .eq('id', alphaTodayLessonId)
      .maybeSingle();

    expect(error).toBeNull();
    expect(data).toBeNull();
  });

  it('teacher cannot invoke owner-only payment RPC', async () => {
    const { error } = await teacherClient.rpc('reve_owner_get_pass_usage', {
      p_pass_id: '66666666-6666-6666-6666-666666666101',
    });
    expect(error).toBeTruthy();
  });

  it('unauthenticated user cannot mutate lesson status', async () => {
    const anonClient = createAuthClient('reve-test-immediate-anon');
    const { error } = await anonClient.rpc('reve_transition_lesson_status', {
      p_lesson_id: alphaTodayLessonId,
      p_new_status: 'completed',
      p_expected_updated_at: new Date().toISOString(),
    });
    expect(error).toBeTruthy();
  });
});

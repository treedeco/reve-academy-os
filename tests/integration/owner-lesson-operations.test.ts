import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { execSync } from 'node:child_process';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  correctLessonStatus,
  directRescheduleLesson,
  fetchPassUsage,
  fetchWeeklyTimetableLessons,
  transitionLessonStatus,
} from '@/lib/data/owner-queries';
import { mapDatabaseError } from '@/lib/domain/format';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';

const alphaPassId = '66666666-6666-6666-6666-666666666101';
const alphaTodayLessonId = '99999999-9999-9999-9999-999999999101';
const betaLesson1Id = '99999999-9999-9999-9999-999999999201';

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

describe.skipIf(!integrationEnabled)('Owner lesson operations integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-lesson-ops');
    const { error } = await ownerClient.auth.signInWithPassword({
      email: ownerEmail,
      password: ownerPassword,
    });
    if (error) {
      throw new Error(`Owner login failed (${error.message}). Run npm run db:seed:alpha after db reset.`);
    }
  });

  afterAll(() => {
    const repoRoot = path.resolve(__dirname, '../..');
    execSync('powershell -ExecutionPolicy Bypass -File scripts/seed-owner-alpha.ps1', {
      cwd: repoRoot,
      stdio: 'inherit',
    });
  });

  it('corrects a completed lesson back to scheduled and restores pass counts', async () => {
    const { data: beforeLesson } = await ownerClient
      .from('lessons')
      .select('updated_at')
      .eq('id', alphaTodayLessonId)
      .single();

    const completed = await transitionLessonStatus(ownerClient, {
      lessonId: alphaTodayLessonId,
      newStatus: 'completed',
      expectedUpdatedAt: beforeLesson!.updated_at,
    });
    expect(completed.used_lesson_count).toBeGreaterThan(0);

    const corrected = await correctLessonStatus(ownerClient, {
      lessonId: alphaTodayLessonId,
      newStatus: 'scheduled',
      expectedUpdatedAt: completed.lesson_updated_at,
      reason: 'Integration correction to scheduled',
    });
    expect(corrected.new_status).toBe('scheduled');

    const usage = await fetchPassUsage(ownerClient, alphaPassId);
    expect(usage?.used_lesson_count).toBe(0);
    expect(usage?.remaining_lesson_count).toBe(4);
  });

  it('requires correction reason', async () => {
    const { data: lesson } = await ownerClient
      .from('lessons')
      .select('updated_at, status')
      .eq('id', alphaTodayLessonId)
      .single();

    if (lesson?.status !== 'completed') {
      await transitionLessonStatus(ownerClient, {
        lessonId: alphaTodayLessonId,
        newStatus: 'completed',
        expectedUpdatedAt: lesson!.updated_at,
      });
    }

    const { data: completedLesson } = await ownerClient
      .from('lessons')
      .select('updated_at')
      .eq('id', alphaTodayLessonId)
      .single();

    await expect(
      correctLessonStatus(ownerClient, {
        lessonId: alphaTodayLessonId,
        newStatus: 'scheduled',
        expectedUpdatedAt: completedLesson!.updated_at,
        reason: '   ',
      }),
    ).rejects.toThrow(/REVE_REASON_REQUIRED|사유/);
  });

  it('directly reschedules a lesson without cascade', async () => {
    const { data: lesson } = await ownerClient
      .from('lessons')
      .select('updated_at, pass_id, passes(updated_at)')
      .eq('id', betaLesson1Id)
      .single();

    const passJoin = Array.isArray(lesson?.passes) ? lesson?.passes[0] : lesson?.passes;

    const result = await directRescheduleLesson(ownerClient, {
      lessonId: betaLesson1Id,
      newScheduledAt: '2026-08-20T05:00:00.000Z',
      expectedLessonUpdatedAt: lesson!.updated_at,
      reason: 'Integration direct reschedule',
      cascade: false,
      expectedPassUpdatedAt: passJoin?.updated_at ?? null,
    });

    expect(result.new_scheduled_at).toContain('2026-08-20');
    expect(result.cascaded_lesson_count).toBe(0);
  });

  it('rejects lesson start at 22:00 local time', async () => {
    const { data: lesson } = await ownerClient
      .from('lessons')
      .select('updated_at')
      .eq('id', betaLesson1Id)
      .single();

    await expect(
      directRescheduleLesson(ownerClient, {
        lessonId: betaLesson1Id,
        newScheduledAt: '2026-08-20T13:00:00.000Z',
        expectedLessonUpdatedAt: lesson!.updated_at,
        reason: 'Integration invalid hours',
        cascade: false,
      }),
    ).rejects.toSatisfy((error: Error) => {
      const message = mapDatabaseError(error);
      return message.includes('22:00');
    });
  });

  it('loads weekly timetable lessons with progress fields', async () => {
    const lessons = await fetchWeeklyTimetableLessons(ownerClient);
    expect(Array.isArray(lessons)).toBe(true);
    if (lessons.length > 0) {
      const first = lessons[0]!;
      expect(first.lesson_progress).toMatch(/^\d+-\d+$/);
      expect(first.registered_lesson_count).toBeGreaterThan(0);
      expect(first.sequence_number).toBeGreaterThan(0);
    }
  });
});

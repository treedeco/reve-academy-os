import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  correctLessonStatus,
  directRescheduleLesson,
  fetchPassUsage,
  fetchStudentDetail,
  fetchWeeklyTimetableLessons,
  transitionLessonStatus,
} from '@/lib/data/owner-queries';
import {
  changeFixedPassSchedule,
  changeSingleLessonSchedule,
  countFutureEligibleLessons,
} from '@/lib/data/owner-schedule-edit';
import { scheduleSlotsFromPassSlots } from '@/lib/domain/owner-schedule-edit';
import { mapDatabaseError } from '@/lib/domain/format';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';
import { applyLocalSqlFixture } from '@/tests/helpers/apply-local-sql-fixture';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

const alphaPassId = '66666666-6666-6666-6666-666666666101';
const alphaTodayLessonId = '99999999-9999-9999-9999-999999999101';
const deltaLesson3Id = '99999999-9999-9999-9999-999999999213';
const deltaLesson4Id = '99999999-9999-9999-9999-999999999214';
const deltaStudentId = '44444444-4444-4444-4444-444444444104';
const deltaPassId = '66666666-6666-6666-6666-666666666103';

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
    applyLocalSqlFixture('fixture-reset-owner-lesson-operations.sql');
    ownerClient = createAuthClient('reve-test-lesson-ops');
    const { error } = await ownerClient.auth.signInWithPassword({
      email: OWNER_AUTH_EMAIL,
      password: getOwnerTestPassword(),
    });
    if (error) {
      throw new Error(`Owner login failed (${error.message}). Run npm run db:seed:alpha after db reset.`);
    }
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
      .eq('id', deltaLesson3Id)
      .single();

    const passJoin = Array.isArray(lesson?.passes) ? lesson?.passes[0] : lesson?.passes;

    const result = await directRescheduleLesson(ownerClient, {
      lessonId: deltaLesson3Id,
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
      .eq('id', deltaLesson4Id)
      .single();

    await expect(
      directRescheduleLesson(ownerClient, {
        lessonId: deltaLesson4Id,
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

  it('accepts lesson start at 10:00 Seoul local time', async () => {
    const { data: lesson } = await ownerClient
      .from('lessons')
      .select('updated_at')
      .eq('id', deltaLesson4Id)
      .single();

    const result = await directRescheduleLesson(ownerClient, {
      lessonId: deltaLesson4Id,
      newScheduledAt: '2026-08-20T01:00:00.000Z',
      expectedLessonUpdatedAt: lesson!.updated_at,
      reason: 'Integration 10:00 slot',
      cascade: false,
    });

    expect(result.new_scheduled_at).toContain('2026-08-20T01:00:00');
  });

  it('changes one lesson without altering pass counts', async () => {
    const usageBefore = await fetchPassUsage(ownerClient, deltaPassId);
    const { data: lesson } = await ownerClient
      .from('lessons')
      .select('updated_at')
      .eq('id', deltaLesson3Id)
      .single();

    const result = await changeSingleLessonSchedule(ownerClient, {
      lessonId: deltaLesson3Id,
      newScheduledAt: '2026-08-21T05:00:00.000Z',
      expectedLessonUpdatedAt: lesson!.updated_at,
      reason: 'Integration single reschedule',
    });

    expect(result.new_scheduled_at).toContain('2026-08-21T05:00:00');

    const usageAfter = await fetchPassUsage(ownerClient, deltaPassId);
    expect(usageAfter?.remaining_lesson_count).toBe(usageBefore?.remaining_lesson_count);
    expect(usageAfter?.registered_lesson_count).toBe(usageBefore?.registered_lesson_count);
  });

  it('changes fixed schedule and moves future eligible lessons', async () => {
    const detailBefore = await fetchStudentDetail(ownerClient, deltaStudentId);
    const { data: passRow } = await ownerClient
      .from('passes')
      .select('updated_at')
      .eq('id', deltaPassId)
      .single();
    expect(passRow?.updated_at).toBeTruthy();

    const currentSlot = detailBefore.schedule_slots[0];
    expect(currentSlot).toBeDefined();
    const currentWeekday = currentSlot!.weekday;
    const currentTime = currentSlot!.local_start_time.slice(0, 5);
    const targetWeekday = currentWeekday === 4 ? 2 : 4;
    const targetTime = currentTime === '14:00' ? '15:00' : '14:00';

    const slots = scheduleSlotsFromPassSlots(detailBefore.schedule_slots).map((slot) => ({
      ...slot,
      weekday: targetWeekday,
      localTime: targetTime,
    }));

    const futureCount = await countFutureEligibleLessons(ownerClient, deltaPassId, '2026-07-01');
    expect(futureCount).toBeGreaterThan(0);

    const result = await changeFixedPassSchedule(ownerClient, {
      passId: deltaPassId,
      expectedPassUpdatedAt: passRow!.updated_at,
      effectiveFrom: '2026-07-01',
      slots,
      reason: 'Integration fixed schedule change',
    });

    expect(result.no_change).toBe(false);
    expect(result.future_eligible_lesson_count).toBeGreaterThan(0);

    const detailAfter = await fetchStudentDetail(ownerClient, deltaStudentId);
    expect(detailAfter.schedule_slots[0]?.weekday).toBe(targetWeekday);
    expect(detailAfter.schedule_slots[0]?.local_start_time.slice(0, 5)).toBe(targetTime);
  });
});

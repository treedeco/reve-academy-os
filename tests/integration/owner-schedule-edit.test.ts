import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  changeFixedPassSchedule,
  changeSingleLessonSchedule,
  countFutureEligibleLessons,
} from '@/lib/data/owner-schedule-edit';
import { fetchPassUsage, fetchStudentDetail, fetchWeeklyTimetableLessons } from '@/lib/data/owner-queries';
import { scheduleSlotsFromPassSlots } from '@/lib/domain/owner-schedule-edit';
import { OWNER_AUTH_EMAIL } from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';
import { applyLocalSqlFixture } from '@/tests/helpers/apply-local-sql-fixture';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

const deltaStudentId = '44444444-4444-4444-4444-444444444104';
const deltaPassId = '66666666-6666-6666-6666-666666666104';
const deltaLesson3Id = '99999999-9999-9999-9999-999999999213';

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

describe.skipIf(!integrationEnabled)('Owner direct schedule editing integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    applyLocalSqlFixture('fixture-reset-owner-lesson-operations.sql');
    ownerClient = createAuthClient('reve-test-schedule-edit');
    const { error } = await ownerClient.auth.signInWithPassword({
      email: OWNER_AUTH_EMAIL,
      password: getOwnerTestPassword(),
    });
    if (error) {
      throw new Error(`Owner login failed (${error.message}). Run npm run db:seed:alpha after db reset.`);
    }
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

    expect(result.new_scheduled_at).toBe('2026-08-21T05:00:00.000Z');

    const usageAfter = await fetchPassUsage(ownerClient, deltaPassId);
    expect(usageAfter?.remaining_lesson_count).toBe(usageBefore?.remaining_lesson_count);
    expect(usageAfter?.registered_lesson_count).toBe(usageBefore?.registered_lesson_count);
  });

  it('changes fixed schedule and moves future eligible lessons', async () => {
    const detailBefore = await fetchStudentDetail(ownerClient, deltaStudentId);
    const passUpdatedAt = detailBefore.lessons[0]?.pass_updated_at;
    expect(passUpdatedAt).toBeTruthy();

    const slots = scheduleSlotsFromPassSlots(detailBefore.schedule_slots).map((slot) => ({
      ...slot,
      weekday: 4,
      localTime: '14:00',
    }));

    const futureCount = await countFutureEligibleLessons(ownerClient, deltaPassId, '2026-07-01');
    expect(futureCount).toBeGreaterThan(0);

    const result = await changeFixedPassSchedule(ownerClient, {
      passId: deltaPassId,
      expectedPassUpdatedAt: passUpdatedAt!,
      effectiveFrom: '2026-07-01',
      slots,
      reason: 'Integration fixed schedule change',
    });

    expect(result.no_change).toBe(false);
    expect(result.future_eligible_lesson_count).toBeGreaterThan(0);

    const detailAfter = await fetchStudentDetail(ownerClient, deltaStudentId);
    expect(detailAfter.schedule_slots[0]?.weekday).toBe(4);
    expect(detailAfter.schedule_slots[0]?.local_start_time.slice(0, 5)).toBe('14:00');

    const usage = await fetchPassUsage(ownerClient, deltaPassId);
    expect(usage?.remaining_lesson_count).toBeGreaterThan(0);
  });

  it('updates weekly timetable after schedule change', async () => {
    const lessons = await fetchWeeklyTimetableLessons(ownerClient);
    expect(Array.isArray(lessons)).toBe(true);
  });
});

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { changeSingleLessonSchedule } from '@/lib/data/owner-schedule-edit';

describe('direct reschedule cascade UX defaults', () => {
  it('defaults changeSingleLessonSchedule to cascade=true with pass token', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: [
        {
          lesson_id: 'l1',
          cascaded_lesson_count: 2,
          no_change: false,
          new_scheduled_at: '2026-09-28T02:00:00.000Z',
        },
      ],
      error: null,
    });

    await changeSingleLessonSchedule({ rpc } as never, {
      lessonId: 'l1',
      newScheduledAt: '2026-09-28T02:00:00.000Z',
      expectedLessonUpdatedAt: '2026-09-01T00:00:00.000Z',
      reason: 'unit cascade default',
      expectedPassUpdatedAt: '2026-09-01T00:00:00.000Z',
    });

    expect(rpc).toHaveBeenCalledWith('reve_owner_direct_reschedule_lesson', {
      p_lesson_id: 'l1',
      p_new_scheduled_at: '2026-09-28T02:00:00.000Z',
      p_expected_lesson_updated_at: '2026-09-01T00:00:00.000Z',
      p_reason: 'unit cascade default',
      p_cascade: true,
      p_expected_pass_updated_at: '2026-09-01T00:00:00.000Z',
    });
  });

  it('allows explicit cascade=false opt-out', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: [{ lesson_id: 'l1', cascaded_lesson_count: 0, no_change: false }],
      error: null,
    });

    await changeSingleLessonSchedule({ rpc } as never, {
      lessonId: 'l1',
      newScheduledAt: '2026-09-28T02:00:00.000Z',
      expectedLessonUpdatedAt: '2026-09-01T00:00:00.000Z',
      reason: 'unit no cascade',
      cascade: false,
    });

    expect(rpc).toHaveBeenCalledWith(
      'reve_owner_direct_reschedule_lesson',
      expect.objectContaining({ p_cascade: false, p_expected_pass_updated_at: null }),
    );
  });

  it('defaults LessonRescheduleDialog cascade checkbox to true', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'components/owner/lesson-reschedule-dialog.tsx'),
      'utf8',
    );
    expect(source).toContain('useState(true)');
    expect(source).toContain('이후 미진행 수업 자동 이동');
  });

  it('ships migration that excludes cascade set from collision checks', () => {
    const source = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260904120000_phase_2b_direct_reschedule_cascade_collision_fix.sql',
      ),
      'utf8',
    );
    expect(source).toContain('student_has_operational_lesson_collision_excluding');
    expect(source).toContain('teacher_has_operational_lesson_collision_excluding');
    expect(source).toContain('lesson_is_cascade_eligible');
  });
});

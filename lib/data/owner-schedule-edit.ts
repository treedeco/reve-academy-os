import type { SupabaseClient } from '@supabase/supabase-js';
import { directRescheduleLesson } from '@/lib/data/owner-queries';
import { buildScheduleSlotsPayloadFromInputs } from '@/lib/domain/owner-schedule-edit';
import type {
  DirectRescheduleResult,
  EnrollmentScheduleSlotInput,
  FixedPassScheduleChangeResult,
} from '@/lib/domain/types';

export async function countFutureEligibleLessons(
  supabase: SupabaseClient,
  passId: string,
  effectiveDateKey: string,
): Promise<number> {
  const effectiveStart = `${effectiveDateKey}T00:00:00+09:00`;
  const { count, error } = await supabase
    .from('lessons')
    .select('id', { count: 'exact', head: true })
    .eq('pass_id', passId)
    .gte('scheduled_at', effectiveStart)
    .in('status', ['scheduled', 'postponed'])
    .is('actual_start_at', null)
    .is('actual_end_at', null);

  if (error) {
    throw new Error(error.message);
  }

  return count ?? 0;
}

export async function changeFixedPassSchedule(
  supabase: SupabaseClient,
  input: {
    passId: string;
    expectedPassUpdatedAt: string;
    effectiveFrom: string;
    slots: EnrollmentScheduleSlotInput[];
    reason: string;
  },
): Promise<FixedPassScheduleChangeResult> {
  const { data, error } = await supabase.rpc('reve_owner_change_fixed_pass_schedule', {
    p_pass_id: input.passId,
    p_expected_pass_updated_at: input.expectedPassUpdatedAt,
    p_effective_from: input.effectiveFrom,
    p_schedule_slots: buildScheduleSlotsPayloadFromInputs(input.slots),
    p_reason: input.reason,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Fixed schedule change returned no data');
  }

  return row as FixedPassScheduleChangeResult;
}

export async function changeSingleLessonSchedule(
  supabase: SupabaseClient,
  input: {
    lessonId: string;
    newScheduledAt: string;
    expectedLessonUpdatedAt: string;
    reason: string;
  },
): Promise<DirectRescheduleResult> {
  return directRescheduleLesson(supabase, {
    lessonId: input.lessonId,
    newScheduledAt: input.newScheduledAt,
    expectedLessonUpdatedAt: input.expectedLessonUpdatedAt,
    reason: input.reason,
    cascade: false,
    expectedPassUpdatedAt: null,
  });
}

export async function fetchLessonScheduleEditContext(
  supabase: SupabaseClient,
  lessonId: string,
): Promise<{
  id: string;
  updated_at: string;
  scheduled_at: string;
  status: string;
  pass_id: string;
  pass_updated_at: string;
  weekly_frequency: number;
  remaining_lesson_count: number;
  schedule_slot_id: string | null;
  assigned_teacher_id: string;
} | null> {
  const { data: lesson, error } = await supabase
    .from('lessons')
    .select(
      `
      id,
      updated_at,
      scheduled_at,
      status,
      pass_id,
      schedule_slot_id,
      assigned_teacher_id,
      passes!inner (
        updated_at,
        weekly_frequency_snapshot,
        registered_lesson_count_snapshot
      )
    `,
    )
    .eq('id', lessonId)
    .maybeSingle();

  if (error || !lesson) {
    return null;
  }

  const pass = Array.isArray(lesson.passes) ? lesson.passes[0] : lesson.passes;
  if (!pass) {
    return null;
  }

  const { count: usedCount } = await supabase
    .from('lessons')
    .select('id', { count: 'exact', head: true })
    .eq('pass_id', lesson.pass_id)
    .in('status', ['completed', 'same_day_cancelled', 'makeup_completed']);

  const registered = pass.registered_lesson_count_snapshot as number;
  const used = usedCount ?? 0;

  return {
    id: lesson.id,
    updated_at: lesson.updated_at,
    scheduled_at: lesson.scheduled_at,
    status: lesson.status,
    pass_id: lesson.pass_id,
    pass_updated_at: pass.updated_at as string,
    weekly_frequency: pass.weekly_frequency_snapshot as number,
    remaining_lesson_count: Math.max(registered - used, 0),
    schedule_slot_id: lesson.schedule_slot_id,
    assigned_teacher_id: lesson.assigned_teacher_id,
  };
}

export async function fetchPassScheduleSlotsWithTeachers(
  supabase: SupabaseClient,
  passId: string,
): Promise<
  Array<{
    id: string;
    weekday: number;
    local_start_time: string;
    duration_minutes: number;
    slot_order: number;
    teacher_id: string;
    teacher_name: string;
  }>
> {
  const { data, error } = await supabase
    .from('schedule_slots')
    .select('id, weekday, local_start_time, duration_minutes, slot_order, teacher_id, teachers(name)')
    .eq('pass_id', passId)
    .eq('is_active', true)
    .order('slot_order', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return (data ?? []).map((row) => {
    const teacher = Array.isArray(row.teachers) ? row.teachers[0] : row.teachers;
    return {
      id: row.id,
      weekday: row.weekday,
      local_start_time: row.local_start_time,
      duration_minutes: row.duration_minutes,
      slot_order: row.slot_order,
      teacher_id: row.teacher_id,
      teacher_name: teacher?.name ?? '',
    };
  });
}

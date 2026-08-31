import type { SupabaseClient } from '@supabase/supabase-js';
import type { TodayLessonRow } from '@/lib/domain/types';
import { fetchTodayLessons } from '@/lib/data/owner-queries';

export interface TeacherAssignedStudentSummary {
  student_id: string;
  student_code: string;
  student_name: string;
  course_id: string;
  course_code: string;
  course_name: string;
  pass_id: string;
  pass_code: string;
  pass_status: string;
  registered_lesson_count: number;
  used_lesson_count: number;
  remaining_lesson_count: number;
  next_assigned_lesson_at: string | null;
  schedule_weekday: number | null;
  schedule_local_start_time: string | null;
}

export async function fetchTeacherTodayLessons(
  supabase: SupabaseClient,
): Promise<TodayLessonRow[]> {
  return fetchTodayLessons(supabase);
}

export async function fetchTeacherAssignedStudents(
  supabase: SupabaseClient,
): Promise<TeacherAssignedStudentSummary[]> {
  const { data, error } = await supabase.rpc('reve_get_my_assigned_student_summaries');

  if (error) {
    throw new Error(error.message);
  }

  return (data ?? []) as TeacherAssignedStudentSummary[];
}

import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  DashboardSummary,
  LessonTransitionResult,
  PassUsageSummary,
  StudentDetailData,
  StudentListRow,
  TodayLessonRow,
} from '@/lib/domain/types';
import { getSeoulDayBounds } from '@/lib/domain/format';

export async function fetchTodayLessons(supabase: SupabaseClient): Promise<TodayLessonRow[]> {
  const { startIso, endIso } = getSeoulDayBounds();

  const { data, error } = await supabase
    .from('lessons')
    .select(
      `
      id,
      scheduled_at,
      status,
      updated_at,
      sequence_number,
      student_id,
      pass_id,
      course_id,
      assigned_teacher_id
    `,
    )
    .gte('scheduled_at', startIso)
    .lte('scheduled_at', endIso)
    .order('scheduled_at', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  const rows = data ?? [];
  if (rows.length === 0) {
    return [];
  }

  const studentIds = [...new Set(rows.map((row) => row.student_id))];
  const courseIds = [...new Set(rows.map((row) => row.course_id))];
  const teacherIds = [...new Set(rows.map((row) => row.assigned_teacher_id))];
  const lessonIds = rows.map((row) => row.id);

  const [studentsResult, coursesResult, teachersResult, notesResult] = await Promise.all([
    supabase.from('students').select('id, name').in('id', studentIds),
    supabase.from('courses').select('id, name').in('id', courseIds),
    supabase.from('teachers').select('id, name').in('id', teacherIds),
    supabase
      .from('lesson_notes')
      .select('lesson_id, body, created_at')
      .in('lesson_id', lessonIds)
      .order('created_at', { ascending: false }),
  ]);

  if (studentsResult.error) {
    throw new Error(studentsResult.error.message);
  }
  if (coursesResult.error) {
    throw new Error(coursesResult.error.message);
  }
  if (teachersResult.error) {
    throw new Error(teachersResult.error.message);
  }

  const studentsById = new Map((studentsResult.data ?? []).map((row) => [row.id, row.name]));
  const coursesById = new Map((coursesResult.data ?? []).map((row) => [row.id, row.name]));
  const teachersById = new Map((teachersResult.data ?? []).map((row) => [row.id, row.name]));
  const notesByLesson = new Map<string, string>();

  for (const note of notesResult.data ?? []) {
    if (!notesByLesson.has(note.lesson_id)) {
      notesByLesson.set(note.lesson_id, note.body);
    }
  }

  return rows.map((row) => ({
    id: row.id,
    scheduled_at: row.scheduled_at,
    status: row.status,
    updated_at: row.updated_at,
    sequence_number: row.sequence_number,
    student_id: row.student_id,
    student_name: studentsById.get(row.student_id) ?? '',
    course_id: row.course_id,
    course_name: coursesById.get(row.course_id) ?? '',
    teacher_id: row.assigned_teacher_id,
    teacher_name: teachersById.get(row.assigned_teacher_id) ?? '',
    pass_id: row.pass_id,
    memo_summary: notesByLesson.get(row.id) ?? null,
  }));
}

export async function fetchDashboardSummary(supabase: SupabaseClient): Promise<DashboardSummary> {
  const lessons = await fetchTodayLessons(supabase);

  const scheduledStatuses = new Set(['scheduled', 'postponed']);
  const completedStatuses = new Set(['completed', 'same_day_cancelled', 'makeup_completed']);
  const cancelledStatuses = new Set([
    'advance_cancelled',
    'teacher_cancelled',
    'academy_closed',
    'postponed',
  ]);

  return {
    total_today: lessons.length,
    scheduled_count: lessons.filter((lesson) => scheduledStatuses.has(lesson.status)).length,
    completed_count: lessons.filter((lesson) => completedStatuses.has(lesson.status)).length,
    cancelled_or_postponed_count: lessons.filter((lesson) => cancelledStatuses.has(lesson.status))
      .length,
    students_with_lesson_today: new Set(lessons.map((lesson) => lesson.student_id)).size,
  };
}

export async function fetchPassUsage(
  supabase: SupabaseClient,
  passId: string,
): Promise<PassUsageSummary> {
  const { data, error } = await supabase.rpc('reve_owner_get_pass_usage', {
    p_pass_id: passId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Pass usage not found');
  }

  return row as PassUsageSummary;
}

export async function fetchStudentList(
  supabase: SupabaseClient,
  search: string,
): Promise<StudentListRow[]> {
  let query = supabase
    .from('students')
    .select('id, name, student_code, operational_status')
    .order('name', { ascending: true })
    .limit(50);

  const trimmed = search.trim();
  if (trimmed) {
    query = query.ilike('name', `%${trimmed}%`);
  }

  const { data: students, error } = await query;
  if (error) {
    throw new Error(error.message);
  }

  const rows: StudentListRow[] = [];

  for (const student of students ?? []) {
    const { data: passes } = await supabase
      .from('passes')
      .select('id, course_id, status, sequence_number, courses(name)')
      .eq('student_id', student.id)
      .in('status', ['active', 'reserved'])
      .order('sequence_number', { ascending: false })
      .limit(1);

    const currentPass = passes?.[0];
    let usage: PassUsageSummary | null = null;

    if (currentPass) {
      usage = await fetchPassUsage(supabase, currentPass.id);
    }

    const course = Array.isArray(currentPass?.courses)
      ? currentPass?.courses[0]
      : currentPass?.courses;

    let teacherName: string | null = null;
    if (currentPass) {
      const { data: slots } = await supabase
        .from('schedule_slots')
        .select('teachers(name)')
        .eq('pass_id', currentPass.id)
        .eq('is_active', true)
        .order('slot_order', { ascending: true })
        .limit(1);

      const teacher = Array.isArray(slots?.[0]?.teachers)
        ? slots?.[0]?.teachers[0]
        : slots?.[0]?.teachers;
      teacherName = teacher?.name ?? null;
    }

    rows.push({
      id: student.id,
      name: student.name,
      student_code: student.student_code,
      operational_status: student.operational_status,
      course_id: currentPass?.course_id ?? null,
      course_name: course?.name ?? null,
      teacher_name: teacherName,
      next_lesson_at: usage?.next_lesson_at ?? null,
      remaining_lesson_count: usage?.remaining_lesson_count ?? null,
      pass_id: currentPass?.id ?? null,
    });
  }

  return rows;
}

export async function fetchStudentDetail(
  supabase: SupabaseClient,
  studentId: string,
): Promise<StudentDetailData> {
  const { data: student, error: studentError } = await supabase
    .from('students')
    .select('id, name, student_code, operational_status')
    .eq('id', studentId)
    .maybeSingle();

  if (studentError || !student) {
    throw new Error('학생 정보를 찾을 수 없습니다.');
  }

  const { data: passes } = await supabase
    .from('passes')
    .select('id, pass_code, status, sequence_number')
    .eq('student_id', studentId)
    .order('sequence_number', { ascending: false });

  const currentPassRow = (passes ?? []).find((pass) => ['active', 'reserved'].includes(pass.status));
  const currentPass = currentPassRow ? await fetchPassUsage(supabase, currentPassRow.id) : null;

  const { data: slots } = currentPassRow
    ? await supabase
        .from('schedule_slots')
        .select('id, weekday, local_start_time, duration_minutes, teachers(name)')
        .eq('pass_id', currentPassRow.id)
        .eq('is_active', true)
        .order('slot_order', { ascending: true })
    : { data: [] };

  const passIds = (passes ?? []).map((pass) => pass.id);
  const { data: lessons } = passIds.length
    ? await supabase
        .from('lessons')
        .select('id, sequence_number, scheduled_at, status, updated_at, pass_id')
        .in('pass_id', passIds)
        .order('scheduled_at', { ascending: false })
        .limit(30)
    : { data: [] };

  const lessonIds = (lessons ?? []).map((lesson) => lesson.id);
  const { data: lessonNotes } = lessonIds.length
    ? await supabase
        .from('lesson_notes')
        .select('id, lesson_id, body, visibility, created_at')
        .in('lesson_id', lessonIds)
        .order('created_at', { ascending: false })
        .limit(10)
    : { data: [] };

  type TeacherJoin = { name: string } | { name: string }[] | null;

  function readTeacherName(teacher: TeacherJoin): string {
    if (!teacher) {
      return '';
    }
    if (Array.isArray(teacher)) {
      return teacher[0]?.name ?? '';
    }
    return teacher.name;
  }

  const teacherName = slots?.[0] ? readTeacherName(slots[0].teachers as TeacherJoin) : null;

  return {
    student,
    teacher_name: teacherName ?? null,
    current_pass: currentPass,
    schedule_slots: (slots ?? []).map((slot) => ({
      id: slot.id,
      weekday: slot.weekday,
      local_start_time: slot.local_start_time,
      duration_minutes: slot.duration_minutes,
      teacher_name: readTeacherName(slot.teachers as TeacherJoin),
    })),
    lessons: (lessons ?? []).map((lesson) => ({
      id: lesson.id,
      sequence_number: lesson.sequence_number,
      scheduled_at: lesson.scheduled_at,
      status: lesson.status,
      updated_at: lesson.updated_at,
    })),
    lesson_notes: lessonNotes ?? [],
    previous_passes: (passes ?? [])
      .filter((pass) => pass.id !== currentPassRow?.id)
      .map((pass) => ({
        id: pass.id,
        pass_code: pass.pass_code,
        status: pass.status,
        sequence_number: pass.sequence_number,
      })),
  };
}

export async function transitionLessonStatus(
  supabase: SupabaseClient,
  input: {
    lessonId: string;
    newStatus: string;
    expectedUpdatedAt: string;
    reason?: string;
  },
): Promise<LessonTransitionResult> {
  const { data, error } = await supabase.rpc('reve_transition_lesson_status', {
    p_lesson_id: input.lessonId,
    p_new_status: input.newStatus,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_reason: input.reason ?? null,
    p_actual_started_at: input.newStatus === 'completed' ? new Date().toISOString() : null,
    p_actual_ended_at: input.newStatus === 'completed' ? new Date().toISOString() : null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Lesson transition returned no data');
  }

  return row as LessonTransitionResult;
}

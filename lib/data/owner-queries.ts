import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  DashboardSummary,
  LessonTransitionResult,
  OwnerRefundablePaymentRow,
  OwnerScheduleChangeRequestRow,
  OwnerSmsNotificationRow,
  PassUsageSummary,
  PassStatus,
  PaymentRefundResult,
  ScheduleChangeApplyResult,
  ScheduleChangeReviewResult,
  SmsConfirmResult,
  StudentDetailData,
  StudentListRow,
  TodayLessonRow,
  LessonStatus,
} from '@/lib/domain/types';
import { getSeoulDayBounds } from '@/lib/domain/format';
import { ELIGIBLE_SMS_STATUSES } from '@/lib/domain/sms';
import { isRefundablePassStatus } from '@/lib/domain/refund';
import { isActionableScheduleChangeRequest } from '@/lib/domain/schedule-change';
import {
  buildActiveStudentCourseKeys,
  pickNextLessonForSlot,
  shouldIncludePassSlot,
  type WeeklyScheduleEntry,
} from '@/lib/domain/weekly-schedule';

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

type ScheduleSlotPassJoin = {
  id: string;
  pass_code: string;
  status: PassStatus;
  student_id: string;
  course_id: string;
  weekly_frequency_snapshot: number;
  registered_lesson_count_snapshot: number;
  students: { id: string; name: string } | { id: string; name: string }[] | null;
  courses: { id: string; name: string } | { id: string; name: string }[] | null;
};

type ScheduleSlotTeacherJoin = { id: string; name: string } | { id: string; name: string }[] | null;

type ScheduleSlotRow = {
  id: string;
  weekday: number;
  local_start_time: string;
  duration_minutes: number;
  slot_order: number;
  pass_id: string;
  teacher_id: string;
  passes: ScheduleSlotPassJoin | ScheduleSlotPassJoin[] | null;
  teachers: ScheduleSlotTeacherJoin;
};

function readJoinedRow<T>(value: T | T[] | null): T | null {
  if (!value) {
    return null;
  }
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

/**
 * Owner weekly fixed schedule read.
 * Query count: 2 (active schedule_slots+joins, batched upcoming lessons). Zero per-row requests.
 */
export async function fetchWeeklySchedule(supabase: SupabaseClient): Promise<WeeklyScheduleEntry[]> {
  const { data: slots, error } = await supabase
    .from('schedule_slots')
    .select(
      `
      id,
      weekday,
      local_start_time,
      duration_minutes,
      slot_order,
      pass_id,
      teacher_id,
      passes!inner (
        id,
        pass_code,
        status,
        student_id,
        course_id,
        weekly_frequency_snapshot,
        registered_lesson_count_snapshot,
        students ( id, name ),
        courses ( id, name )
      ),
      teachers ( id, name )
    `,
    )
    .eq('is_active', true);

  if (error) {
    throw new Error(error.message);
  }

  const slotRows = (slots ?? []) as ScheduleSlotRow[];
  if (slotRows.length === 0) {
    return [];
  }

  const passRows = slotRows
    .map((slot) => {
      const pass = readJoinedRow(slot.passes);
      if (!pass) {
        return null;
      }
      return {
        student_id: pass.student_id,
        course_id: pass.course_id,
        pass_status: pass.status,
      };
    })
    .filter((row): row is NonNullable<typeof row> => row !== null);

  const activeStudentCourseKeys = buildActiveStudentCourseKeys(passRows);

  const filteredSlots = slotRows.filter((slot) => {
    const pass = readJoinedRow(slot.passes);
    if (!pass) {
      return false;
    }
    return shouldIncludePassSlot(
      pass.status,
      pass.student_id,
      pass.course_id,
      activeStudentCourseKeys,
    );
  });

  if (filteredSlots.length === 0) {
    return [];
  }

  const passIds = [...new Set(filteredSlots.map((slot) => slot.pass_id))];
  const referenceIso = new Date().toISOString();

  const { data: lessons, error: lessonsError } = await supabase
    .from('lessons')
    .select('id, pass_id, schedule_slot_id, scheduled_at, status')
    .in('pass_id', passIds)
    .gte('scheduled_at', referenceIso)
    .order('scheduled_at', { ascending: true });

  if (lessonsError) {
    throw new Error(lessonsError.message);
  }

  const lessonRows = lessons ?? [];

  return filteredSlots.map((slot) => {
    const pass = readJoinedRow(slot.passes);
    const student = pass ? readJoinedRow(pass.students) : null;
    const course = pass ? readJoinedRow(pass.courses) : null;
    const teacher = readJoinedRow(slot.teachers);
    const nextLesson = pickNextLessonForSlot(lessonRows, slot.id, referenceIso);

    return {
      slot_id: slot.id,
      pass_id: slot.pass_id,
      pass_code: pass?.pass_code ?? '',
      pass_status: pass?.status ?? 'active',
      weekday: slot.weekday,
      local_start_time: slot.local_start_time,
      duration_minutes: slot.duration_minutes,
      slot_order: slot.slot_order,
      student_id: pass?.student_id ?? '',
      student_name: student?.name ?? '',
      teacher_id: slot.teacher_id,
      teacher_name: teacher?.name ?? '',
      course_id: pass?.course_id ?? '',
      course_name: course?.name ?? '',
      weekly_frequency: pass?.weekly_frequency_snapshot ?? 0,
      registered_lesson_count: pass?.registered_lesson_count_snapshot ?? 0,
      next_lesson_id: nextLesson?.id ?? null,
      next_lesson_scheduled_at: nextLesson?.scheduled_at ?? null,
      next_lesson_status: nextLesson?.status ?? null,
    };
  });
}

type SmsPassJoin = {
  id: string;
  pass_code: string;
  status: PassStatus;
  product_name_snapshot: string | null;
  courses: { name: string } | { name: string }[] | null;
};

type SmsStudentJoin = { name: string } | { name: string }[] | null;

type SmsNotificationRow = {
  id: string;
  status: string;
  message_body_snapshot: string | null;
  target_date: string | null;
  notification_type: string;
  student_id: string;
  pass_id: string;
  students: SmsStudentJoin;
  passes: SmsPassJoin | SmsPassJoin[] | null;
};

/**
 * Owner eligible SMS notifications for manual send confirmation.
 * Query count: 1 (sms_notifications + student/pass/course joins). Zero per-row requests.
 */
export async function fetchOwnerSmsNotifications(
  supabase: SupabaseClient,
): Promise<OwnerSmsNotificationRow[]> {
  const { data, error } = await supabase
    .from('sms_notifications')
    .select(
      `
      id,
      status,
      message_body_snapshot,
      target_date,
      notification_type,
      student_id,
      pass_id,
      students ( name ),
      passes (
        id,
        pass_code,
        status,
        product_name_snapshot,
        courses ( name )
      )
    `,
    )
    .in('status', [...ELIGIBLE_SMS_STATUSES])
    .order('target_date', { ascending: true, nullsFirst: false })
    .order('created_at', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as SmsNotificationRow[]).map((row) => {
    const student = readJoinedRow(row.students);
    const pass = readJoinedRow(row.passes);
    const course = pass ? readJoinedRow(pass.courses) : null;

    return {
      id: row.id,
      status: row.status,
      message_body_snapshot: row.message_body_snapshot,
      target_date: row.target_date,
      notification_type: row.notification_type,
      student_id: row.student_id,
      student_name: student?.name ?? '',
      pass_id: row.pass_id,
      pass_code: pass?.pass_code ?? '',
      pass_status: pass?.status ?? 'active',
      product_name: pass?.product_name_snapshot ?? null,
      course_name: course?.name ?? null,
    };
  });
}

export async function confirmOwnerSmsSent(
  supabase: SupabaseClient,
  smsNotificationId: string,
): Promise<SmsConfirmResult> {
  const { data, error } = await supabase.rpc('reve_owner_confirm_sms_sent', {
    p_sms_notification_id: smsNotificationId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('SMS confirmation returned no data');
  }

  return row as SmsConfirmResult;
}

type RefundPassJoin = {
  id: string;
  pass_code: string;
  status: PassStatus;
  product_name_snapshot: string | null;
};

type RefundStudentJoin = { name: string } | { name: string }[] | null;
type RefundCourseJoin = { name: string } | { name: string }[] | null;
type RefundRowJoin = { id: string } | { id: string }[] | null;

type RefundablePaymentRow = {
  id: string;
  paid_amount_krw: number;
  paid_at: string | null;
  status: string;
  student_id: string;
  course_id: string;
  renewed_pass_id: string | null;
  students: RefundStudentJoin;
  courses: RefundCourseJoin;
  passes: RefundPassJoin | RefundPassJoin[] | null;
  payment_refunds: RefundRowJoin;
};

/**
 * Owner refundable completed payments (full refund MVP).
 * Query count: 1 (payments + joins + refund anti-filter in mapper). Zero per-row requests.
 */
export async function fetchOwnerRefundablePayments(
  supabase: SupabaseClient,
): Promise<OwnerRefundablePaymentRow[]> {
  const { data, error } = await supabase
    .from('payments')
    .select(
      `
      id,
      paid_amount_krw,
      paid_at,
      status,
      student_id,
      course_id,
      renewed_pass_id,
      students ( name ),
      courses ( name ),
      passes!payments_renewed_pass_id_fkey!inner (
        id,
        pass_code,
        status,
        product_name_snapshot
      ),
      payment_refunds ( id )
    `,
    )
    .eq('status', 'completed')
    .not('renewed_pass_id', 'is', null)
    .in('passes.status', ['active', 'reserved'])
    .order('paid_at', { ascending: true, nullsFirst: false });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as RefundablePaymentRow[])
    .filter((row) => {
      const refund = readJoinedRow(row.payment_refunds);
      return !refund;
    })
    .filter((row) => {
      const pass = readJoinedRow(row.passes);
      return pass ? isRefundablePassStatus(pass.status) : false;
    })
    .map((row) => {
      const student = readJoinedRow(row.students);
      const course = readJoinedRow(row.courses);
      const pass = readJoinedRow(row.passes);

      return {
        id: row.id,
        paid_amount_krw: row.paid_amount_krw,
        paid_at: row.paid_at,
        payment_status: row.status,
        student_id: row.student_id,
        student_name: student?.name ?? '',
        course_id: row.course_id,
        course_name: course?.name ?? '',
        pass_id: pass?.id ?? row.renewed_pass_id ?? '',
        pass_code: pass?.pass_code ?? '',
        pass_status: pass?.status ?? 'active',
        product_name: pass?.product_name_snapshot ?? null,
      };
    });
}

export async function processOwnerPaymentRefund(
  supabase: SupabaseClient,
  input: {
    paymentId: string;
    refundedAmountKrw: number;
    reason: string;
  },
): Promise<PaymentRefundResult> {
  const { data, error } = await supabase.rpc('reve_process_payment_refund', {
    p_payment_id: input.paymentId,
    p_refunded_amount_krw: input.refundedAmountKrw,
    p_reason: input.reason,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Payment refund returned no data');
  }

  return row as PaymentRefundResult;
}

type ScheduleLessonPassJoin = {
  pass_code: string;
  product_name_snapshot: string | null;
  status: PassStatus;
  courses: ScheduleLessonCourseJoin | ScheduleLessonCourseJoin[] | null;
};

type ScheduleLessonCourseJoin = { name: string };
type ScheduleStudentJoin = { name: string };
type ScheduleLessonJoin = {
  id: string;
  sequence_number: number;
  scheduled_at: string;
  status: LessonStatus;
  updated_at: string;
  pass_id: string;
  course_id: string;
  passes: ScheduleLessonPassJoin | ScheduleLessonPassJoin[] | null;
};

type ScheduleChangeRequestRow = {
  id: string;
  status: string;
  updated_at: string;
  requested_reason: string;
  proposed_scheduled_at: string | null;
  approved_scheduled_at: string | null;
  request_source_role: string;
  applied_at: string | null;
  student_id: string;
  students: ScheduleStudentJoin | ScheduleStudentJoin[] | null;
  lessons: ScheduleLessonJoin | ScheduleLessonJoin[] | null;
};

/**
 * Owner actionable schedule change requests (submitted + approved pending apply).
 * Query count: 1 (schedule_change_requests + joins). Zero per-row requests.
 */
export async function fetchOwnerScheduleChangeRequests(
  supabase: SupabaseClient,
): Promise<OwnerScheduleChangeRequestRow[]> {
  const { data, error } = await supabase
    .from('schedule_change_requests')
    .select(
      `
      id,
      status,
      updated_at,
      requested_reason,
      proposed_scheduled_at,
      approved_scheduled_at,
      request_source_role,
      applied_at,
      student_id,
      students ( name ),
      lessons!schedule_change_requests_target_lesson_id_fkey (
        id,
        sequence_number,
        scheduled_at,
        status,
        updated_at,
        pass_id,
        course_id,
        passes!lessons_pass_student_course_fkey (
          pass_code,
          product_name_snapshot,
          status,
          courses ( name )
        )
      )
    `,
    )
    .in('status', ['submitted', 'approved'])
    .order('created_at', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as ScheduleChangeRequestRow[])
    .filter((row) => isActionableScheduleChangeRequest(row))
    .map((row) => {
      const student = readJoinedRow(row.students);
      const lesson = readJoinedRow(row.lessons);
      const pass = lesson ? readJoinedRow(lesson.passes) : null;
      const course = pass ? readJoinedRow(pass.courses) : null;

      if (!lesson) {
        throw new Error('Schedule change request is missing lesson context');
      }

      return {
        id: row.id,
        status: row.status,
        updated_at: row.updated_at,
        requested_reason: row.requested_reason,
        proposed_scheduled_at: row.proposed_scheduled_at,
        approved_scheduled_at: row.approved_scheduled_at,
        request_source_role: row.request_source_role,
        applied_at: row.applied_at,
        student_id: row.student_id,
        student_name: student?.name ?? '',
        lesson_id: lesson.id,
        lesson_sequence_number: lesson.sequence_number,
        lesson_scheduled_at: lesson.scheduled_at,
        lesson_status: lesson.status,
        lesson_updated_at: lesson.updated_at,
        pass_id: lesson.pass_id,
        pass_code: pass?.pass_code ?? '',
        pass_status: pass?.status ?? 'active',
        course_id: lesson.course_id,
        course_name: course?.name ?? '',
        product_name: pass?.product_name_snapshot ?? null,
      };
    });
}

export async function reviewOwnerScheduleChangeRequest(
  supabase: SupabaseClient,
  input: {
    requestId: string;
    decision: 'approve' | 'reject';
    expectedRequestUpdatedAt: string;
    decisionReason: string;
    approvedScheduledAt?: string | null;
  },
): Promise<ScheduleChangeReviewResult> {
  const { data, error } = await supabase.rpc('reve_owner_review_schedule_change_request', {
    p_request_id: input.requestId,
    p_decision: input.decision,
    p_expected_request_updated_at: input.expectedRequestUpdatedAt,
    p_decision_reason: input.decisionReason,
    p_approved_scheduled_at: input.approvedScheduledAt ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Schedule change review returned no data');
  }

  return row as ScheduleChangeReviewResult;
}

export async function applyOwnerScheduleChangeRequest(
  supabase: SupabaseClient,
  input: {
    requestId: string;
    expectedRequestUpdatedAt: string;
    expectedLessonUpdatedAt: string;
  },
): Promise<ScheduleChangeApplyResult> {
  const { data, error } = await supabase.rpc('reve_owner_apply_schedule_change_request', {
    p_request_id: input.requestId,
    p_expected_request_updated_at: input.expectedRequestUpdatedAt,
    p_expected_lesson_updated_at: input.expectedLessonUpdatedAt,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Schedule change apply returned no data');
  }

  return row as ScheduleChangeApplyResult;
}

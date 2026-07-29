import type { SupabaseClient } from '@supabase/supabase-js';
import type { TeacherLinkHandlingMode } from '@/lib/domain/owner-deletion';

function readRpcRow<T>(data: unknown): T {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('RPC returned no data');
  }
  return row as T;
}

export type ScheduleRemovalPreview = {
  student_name: string;
  student_code: string;
  pass_code: string;
  pass_status: string;
  pass_updated_at: string;
  active_slot_count: number;
  current_weekday_times: string;
  future_timetable_lesson_count: number;
  manually_moved_future_lesson_count: number;
  preserved_past_lesson_count: number;
  preserved_completed_lesson_count: number;
  preflight_fingerprint: string;
  blockers: string[];
  warnings: string[];
};

export type ScheduleRemovalResult = {
  pass_id: string;
  removed_schedule_slot_count: number;
  removed_or_cancelled_future_lesson_count: number;
  preserved_past_lesson_count: number;
  preserved_completed_lesson_count: number;
  effective_from: string;
  pass_updated_at: string;
  no_change: boolean;
};

export type StudentDeletionPreview = {
  student_id: string;
  student_code: string;
  student_name: string;
  operational_status: string;
  updated_at: string;
  linked_profile_id: string | null;
  auth_user_exists: boolean;
  lesson_count: number;
  pass_count: number;
  payment_count: number;
  payment_refund_count: number;
  sms_notification_count: number;
  schedule_slot_count: number;
  lesson_note_count: number;
  schedule_change_request_count: number;
  lesson_schedule_change_count: number;
  preflight_fingerprint: string;
  blockers: string[];
  warnings: string[];
};

export type StudentDeletionResult = {
  student_id: string;
  already_deleted: boolean;
  deleted_lesson_count: number;
  deleted_pass_count: number;
  deleted_payment_count: number;
  deleted_payment_refund_count: number;
  deleted_sms_notification_count: number;
  deleted_schedule_slot_count: number;
  deleted_lesson_note_count: number;
  deleted_schedule_change_request_count: number;
  deleted_lesson_schedule_change_count: number;
  profile_deleted: boolean;
  auth_user_id: string | null;
  correlation_id: string;
};

export type TeacherDeletionPreview = {
  teacher_id: string;
  teacher_code: string;
  teacher_name: string;
  is_active: boolean;
  updated_at: string;
  linked_profile_id: string | null;
  auth_user_exists: boolean;
  total_lesson_count: number;
  future_eligible_lesson_count: number;
  past_deductible_lesson_count: number;
  active_schedule_slot_count: number;
  total_schedule_slot_count: number;
  preflight_fingerprint: string;
  blockers: string[];
  warnings: string[];
};

export type TeacherDeletionResult = {
  teacher_id: string;
  already_deleted: boolean;
  link_handling_mode: TeacherLinkHandlingMode;
  future_reassigned_lesson_count: number;
  future_cancelled_lesson_count: number;
  reassigned_active_slot_count: number;
  snapshotted_lesson_count: number;
  deleted_schedule_slot_count: number;
  profile_deleted: boolean;
  auth_user_id: string | null;
  correlation_id: string;
};

export async function previewRemoveFixedPassSchedule(
  supabase: SupabaseClient,
  input: { passId: string; effectiveFrom: string },
): Promise<ScheduleRemovalPreview> {
  const { data, error } = await supabase.rpc('reve_owner_preview_remove_fixed_pass_schedule', {
    p_pass_id: input.passId,
    p_effective_from: input.effectiveFrom,
  });

  if (error) {
    throw new Error(error.message);
  }

  return readRpcRow<ScheduleRemovalPreview>(data);
}

export async function removeFixedPassSchedule(
  supabase: SupabaseClient,
  input: {
    passId: string;
    expectedPassUpdatedAt: string;
    effectiveFrom: string;
    reason: string;
    confirmationCode: string;
    preflightFingerprint: string;
  },
): Promise<ScheduleRemovalResult> {
  const { data, error } = await supabase.rpc('reve_owner_remove_fixed_pass_schedule', {
    p_pass_id: input.passId,
    p_expected_pass_updated_at: input.expectedPassUpdatedAt,
    p_effective_from: input.effectiveFrom,
    p_reason: input.reason,
    p_confirmation_code: input.confirmationCode,
    p_preflight_fingerprint: input.preflightFingerprint,
  });

  if (error) {
    throw new Error(error.message);
  }

  return readRpcRow<ScheduleRemovalResult>(data);
}

export async function previewDeleteStudent(
  supabase: SupabaseClient,
  studentId: string,
): Promise<StudentDeletionPreview> {
  const { data, error } = await supabase.rpc('reve_owner_preview_delete_student', {
    p_student_id: studentId,
  });

  if (error) {
    throw new Error(error.message);
  }

  return readRpcRow<StudentDeletionPreview>(data);
}

export async function permanentlyDeleteStudent(
  supabase: SupabaseClient,
  input: {
    studentId: string;
    expectedUpdatedAt: string;
    confirmationCode: string;
    reason: string;
    preflightFingerprint: string;
  },
): Promise<StudentDeletionResult> {
  const { data, error } = await supabase.rpc('reve_owner_permanently_delete_student', {
    p_student_id: input.studentId,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_confirmation_code: input.confirmationCode,
    p_reason: input.reason,
    p_preflight_fingerprint: input.preflightFingerprint,
  });

  if (error) {
    throw new Error(error.message);
  }

  return readRpcRow<StudentDeletionResult>(data);
}

export async function previewDeleteTeacher(
  supabase: SupabaseClient,
  teacherId: string,
): Promise<TeacherDeletionPreview> {
  const { data, error } = await supabase.rpc('reve_owner_preview_delete_teacher', {
    p_teacher_id: teacherId,
  });

  if (error) {
    throw new Error(error.message);
  }

  return readRpcRow<TeacherDeletionPreview>(data);
}

export async function permanentlyDeleteTeacher(
  supabase: SupabaseClient,
  input: {
    teacherId: string;
    expectedUpdatedAt: string;
    linkHandlingMode: TeacherLinkHandlingMode;
    replacementTeacherId: string | null;
    confirmationCode: string;
    reason: string;
    preflightFingerprint: string;
  },
): Promise<TeacherDeletionResult> {
  const { data, error } = await supabase.rpc('reve_owner_permanently_delete_teacher', {
    p_teacher_id: input.teacherId,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_link_handling_mode: input.linkHandlingMode,
    p_replacement_teacher_id: input.replacementTeacherId,
    p_confirmation_code: input.confirmationCode,
    p_reason: input.reason,
    p_preflight_fingerprint: input.preflightFingerprint,
  });

  if (error) {
    throw new Error(error.message);
  }

  return readRpcRow<TeacherDeletionResult>(data);
}

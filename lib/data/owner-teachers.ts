import type { SupabaseClient } from '@supabase/supabase-js';
import type { OwnerTeacherMutationResult, OwnerTeacherRow } from '@/lib/domain/types';

type TeacherQueryRow = {
  id: string;
  teacher_code: string;
  name: string;
  phone: string | null;
  email: string | null;
  is_active: boolean;
  updated_at: string;
};

type TeacherRpcRow = {
  teacher_id: string;
  teacher_code: string;
  teacher_name: string;
  is_active: boolean;
  linked_profile_id: string | null;
  created_at: string;
  updated_at: string;
};

function mapTeacherQueryRow(row: TeacherQueryRow): OwnerTeacherRow {
  return {
    id: row.id,
    teacher_code: row.teacher_code,
    name: row.name,
    phone: row.phone,
    email: row.email,
    is_active: row.is_active,
    updated_at: row.updated_at,
  };
}

function mapTeacherRpcRow(row: TeacherRpcRow): OwnerTeacherMutationResult {
  return {
    id: row.teacher_id,
    teacher_code: row.teacher_code,
    name: row.teacher_name,
    phone: null,
    email: null,
    is_active: row.is_active,
    updated_at: row.updated_at,
  };
}

function readRpcRow(data: unknown): TeacherRpcRow {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Teacher RPC returned no data');
  }
  return row as TeacherRpcRow;
}

/**
 * Owner teacher list read.
 * Query count: 1 (teachers). Zero per-row requests.
 */
export async function fetchOwnerTeacherList(supabase: SupabaseClient): Promise<OwnerTeacherRow[]> {
  const { data, error } = await supabase
    .from('teachers')
    .select('id, teacher_code, name, phone, email, is_active, updated_at')
    .order('name', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return (data ?? []).map((row) => mapTeacherQueryRow(row as TeacherQueryRow));
}

export async function createOwnerTeacher(
  supabase: SupabaseClient,
  input: {
    teacherCode: string;
    name: string;
    phone?: string | null;
    email?: string | null;
  },
): Promise<OwnerTeacherMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_create_teacher', {
    p_teacher_code: input.teacherCode,
    p_name: input.name,
    p_phone: input.phone ?? null,
    p_email: input.email ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const mapped = mapTeacherRpcRow(readRpcRow(data));
  return {
    ...mapped,
    phone: input.phone?.trim() || null,
    email: input.email?.trim() || null,
  };
}

export async function updateOwnerTeacher(
  supabase: SupabaseClient,
  input: {
    teacherId: string;
    expectedUpdatedAt: string;
    name: string;
    phone?: string | null;
    email?: string | null;
  },
): Promise<OwnerTeacherMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_update_teacher', {
    p_teacher_id: input.teacherId,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_name: input.name,
    p_phone: input.phone ?? null,
    p_email: input.email ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const mapped = mapTeacherRpcRow(readRpcRow(data));
  return {
    ...mapped,
    phone: input.phone?.trim() || null,
    email: input.email?.trim() || null,
  };
}

export async function setOwnerTeacherActive(
  supabase: SupabaseClient,
  input: {
    teacherId: string;
    isActive: boolean;
    reason: string;
    expectedUpdatedAt: string;
  },
): Promise<OwnerTeacherMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_set_teacher_active', {
    p_teacher_id: input.teacherId,
    p_is_active: input.isActive,
    p_reason: input.reason,
    p_expected_updated_at: input.expectedUpdatedAt,
  });

  if (error) {
    throw new Error(error.message);
  }

  return mapTeacherRpcRow(readRpcRow(data));
}

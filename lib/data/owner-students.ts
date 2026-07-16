import type { SupabaseClient } from '@supabase/supabase-js';
import type { OwnerStudentMutationResult, OwnerStudentRow } from '@/lib/domain/types';

type StudentQueryRow = {
  id: string;
  student_code: string;
  name: string;
  phone: string | null;
  email: string | null;
  operational_status: string;
  updated_at: string;
};

type StudentRpcRow = {
  student_id: string;
  student_code: string;
  student_name: string;
  operational_status: string;
  linked_profile_id: string | null;
  created_at: string;
  updated_at: string;
};

function mapStudentQueryRow(row: StudentQueryRow): OwnerStudentRow {
  return {
    id: row.id,
    student_code: row.student_code,
    name: row.name,
    phone: row.phone,
    email: row.email,
    operational_status: row.operational_status,
    updated_at: row.updated_at,
  };
}

function mapStudentRpcRow(row: StudentRpcRow): OwnerStudentMutationResult {
  return {
    id: row.student_id,
    student_code: row.student_code,
    name: row.student_name,
    phone: null,
    email: null,
    operational_status: row.operational_status,
    updated_at: row.updated_at,
  };
}

function readRpcRow(data: unknown): StudentRpcRow {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Student RPC returned no data');
  }
  return row as StudentRpcRow;
}

/**
 * Owner student master list read.
 * Query count: 1 (students). Zero per-row requests.
 */
export async function fetchOwnerStudentMasterList(
  supabase: SupabaseClient,
): Promise<OwnerStudentRow[]> {
  const { data, error } = await supabase
    .from('students')
    .select('id, student_code, name, phone, email, operational_status, updated_at')
    .order('name', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return (data ?? []).map((row) => mapStudentQueryRow(row as StudentQueryRow));
}

export async function fetchOwnerStudentMasterRow(
  supabase: SupabaseClient,
  studentId: string,
): Promise<OwnerStudentRow> {
  const { data, error } = await supabase
    .from('students')
    .select('id, student_code, name, phone, email, operational_status, updated_at')
    .eq('id', studentId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }
  if (!data) {
    throw new Error('Student not found');
  }

  return mapStudentQueryRow(data as StudentQueryRow);
}

export async function createOwnerStudent(
  supabase: SupabaseClient,
  input: {
    studentCode: string;
    name: string;
    phone?: string | null;
    email?: string | null;
  },
): Promise<OwnerStudentMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_create_student', {
    p_student_code: input.studentCode,
    p_name: input.name,
    p_phone: input.phone ?? null,
    p_email: input.email ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const mapped = mapStudentRpcRow(readRpcRow(data));
  return {
    ...mapped,
    phone: input.phone?.trim() || null,
    email: input.email?.trim() || null,
  };
}

export async function updateOwnerStudent(
  supabase: SupabaseClient,
  input: {
    studentId: string;
    expectedUpdatedAt: string;
    name: string;
    phone?: string | null;
    email?: string | null;
  },
): Promise<OwnerStudentMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_update_student', {
    p_student_id: input.studentId,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_name: input.name,
    p_phone: input.phone ?? null,
    p_email: input.email ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const mapped = mapStudentRpcRow(readRpcRow(data));
  return {
    ...mapped,
    phone: input.phone?.trim() || null,
    email: input.email?.trim() || null,
  };
}

export async function setOwnerStudentActive(
  supabase: SupabaseClient,
  input: {
    studentId: string;
    operationalStatus: 'active' | 'inactive' | 'archived';
    reason: string;
    expectedUpdatedAt: string;
  },
): Promise<OwnerStudentMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_set_student_active', {
    p_student_id: input.studentId,
    p_operational_status: input.operationalStatus,
    p_reason: input.reason,
    p_expected_updated_at: input.expectedUpdatedAt,
  });

  if (error) {
    throw new Error(error.message);
  }

  return mapStudentRpcRow(readRpcRow(data));
}

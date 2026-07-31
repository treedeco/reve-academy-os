/**
 * Create an authenticated Owner Supabase client for production operator scripts.
 * Never logs credentials or tokens.
 */
import { createClient } from '@supabase/supabase-js';
import {
  PRODUCTION_SUPABASE_URL,
  assertProductionAppUrl,
  assertProductionSupabaseUrl,
} from './reve-production-operator-guard.mjs';

export const OWNER_AUTH_EMAIL = 'reve@owner.local';

export async function createProductionOwnerSession({
  supabaseUrl = process.env.PRODUCTION_SUPABASE_URL ?? PRODUCTION_SUPABASE_URL,
  anonKey = process.env.PRODUCTION_SUPABASE_ANON_KEY ?? '',
  ownerPassword = process.env.PRODUCTION_OWNER_PASSWORD ?? '',
} = {}) {
  assertProductionSupabaseUrl(supabaseUrl);
  assertProductionAppUrl(process.env.PRODUCTION_URL);

  if (!anonKey) {
    throw new Error('PRODUCTION_SUPABASE_ANON_KEY is required.');
  }
  if (!ownerPassword) {
    throw new Error('PRODUCTION_OWNER_PASSWORD is required in the current process environment.');
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await authClient.auth.signInWithPassword({
    email: OWNER_AUTH_EMAIL,
    password: ownerPassword,
  });

  if (error || !data.session) {
    throw new Error(`Owner login failed: ${error?.message ?? 'no_session'}`);
  }

  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: profile, error: profileError } = await client
    .from('profiles')
    .select('id, role, account_state')
    .eq('id', data.user.id)
    .maybeSingle();

  if (profileError || !profile || profile.role !== 'owner' || profile.account_state !== 'active') {
    throw new Error('Owner profile validation failed.');
  }

  return { client, userId: data.user.id };
}

function readRpcRow(data) {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('RPC returned no data');
  }
  return row;
}

export async function previewDeleteStudent(client, studentId) {
  const { data, error } = await client.rpc('reve_owner_preview_delete_student', {
    p_student_id: studentId,
  });
  if (error) {
    throw new Error(error.message);
  }
  return readRpcRow(data);
}

export async function permanentlyDeleteStudent(client, input) {
  const { data, error } = await client.rpc('reve_owner_permanently_delete_student', {
    p_student_id: input.studentId,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_confirmation_code: input.confirmationCode,
    p_reason: input.reason,
    p_preflight_fingerprint: input.preflightFingerprint,
  });
  if (error) {
    throw new Error(error.message);
  }
  return readRpcRow(data);
}

export async function previewDeleteTeacher(client, teacherId) {
  const { data, error } = await client.rpc('reve_owner_preview_delete_teacher', {
    p_teacher_id: teacherId,
  });
  if (error) {
    throw new Error(error.message);
  }
  return readRpcRow(data);
}

export async function permanentlyDeleteTeacher(client, input) {
  const { data, error } = await client.rpc('reve_owner_permanently_delete_teacher', {
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
  return readRpcRow(data);
}

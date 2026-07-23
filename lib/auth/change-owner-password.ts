import type { SupabaseClient } from '@supabase/supabase-js';
import {
  buildPasswordChangeCompletedMetadata,
} from '@/lib/auth/owner-password-metadata';
import {
  mapOwnerPasswordAuthError,
  validateOwnerPasswordChangeInput,
} from '@/lib/domain/owner-password';

export type ChangeOwnerPasswordInput = {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
};

export type ChangeOwnerPasswordResult =
  | { status: 'success' }
  | { status: 'validation_error'; message: string }
  | { status: 'not_authenticated'; message: string }
  | { status: 'incorrect_current_password'; message: string }
  | { status: 'update_failed'; message: string }
  | { status: 'audit_failed'; message: string }
  | { status: 'sign_out_failed'; message: string };

export async function recordOwnerPasswordChangeAudit(
  supabase: SupabaseClient,
): Promise<{ ok: true; idempotentReplay: boolean } | { ok: false; message: string }> {
  const { data, error } = await supabase.rpc('reve_owner_record_password_change_completed');

  if (error) {
    return {
      ok: false,
      message: '완료 기록 저장에 실패했습니다.',
    };
  }

  const row = Array.isArray(data) ? data[0] : data;
  return {
    ok: true,
    idempotentReplay: Boolean(row?.idempotent_replay),
  };
}

export async function changeOwnerPassword(
  supabase: SupabaseClient,
  input: ChangeOwnerPasswordInput,
): Promise<ChangeOwnerPasswordResult> {
  const validation = validateOwnerPasswordChangeInput(input);
  if (!validation.ok) {
    return { status: 'validation_error', message: validation.message };
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user?.email) {
    return {
      status: 'not_authenticated',
      message: '세션이 만료되었습니다. 다시 로그인해 주세요.',
    };
  }

  const { error: verifyError } = await supabase.auth.signInWithPassword({
    email: user.email,
    password: input.currentPassword,
  });

  if (verifyError) {
    const message = mapOwnerPasswordAuthError(verifyError);
    if (message === '현재 비밀번호가 올바르지 않습니다.') {
      return { status: 'incorrect_current_password', message };
    }
    return { status: 'update_failed', message };
  }

  const { error: updateError } = await supabase.auth.updateUser({
    password: input.newPassword,
    data: buildPasswordChangeCompletedMetadata(user.user_metadata),
  });

  if (updateError) {
    return {
      status: 'update_failed',
      message: mapOwnerPasswordAuthError(updateError),
    };
  }

  const auditResult = await recordOwnerPasswordChangeAudit(supabase);
  if (!auditResult.ok) {
    return { status: 'audit_failed', message: auditResult.message };
  }

  const { error: signOutError } = await supabase.auth.signOut({ scope: 'global' });
  if (signOutError) {
    return {
      status: 'sign_out_failed',
      message: '비밀번호는 변경되었지만 로그아웃에 실패했습니다. 모든 기기에서 수동으로 로그아웃해 주세요.',
    };
  }

  return { status: 'success' };
}

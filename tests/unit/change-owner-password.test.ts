import { describe, expect, it, vi } from 'vitest';
import {
  changeOwnerPassword,
  recordOwnerPasswordChangeAudit,
} from '@/lib/auth/change-owner-password';

function createSupabaseMock(overrides: Record<string, unknown> = {}) {
  const rpc = vi.fn(async () => ({ data: [{ idempotent_replay: false }], error: null }));
  const signOut = vi.fn(async () => ({ error: null }));
  const updateUser = vi.fn(async () => ({ data: { user: { id: 'user-1' } }, error: null }));
  const signInWithPassword = vi.fn(async () => ({ data: { session: {} }, error: null }));
  const getUser = vi.fn(async () => ({
    data: { user: { id: 'user-1', email: 'owner@test.local', user_metadata: { must_change_password: true } } },
    error: null,
  }));

  return {
    auth: { getUser, signInWithPassword, updateUser, signOut },
    rpc,
    ...overrides,
    _mocks: { getUser, signInWithPassword, updateUser, signOut, rpc },
  };
}

describe('changeOwnerPassword', () => {
  it('does not call updateUser when current password verification fails', async () => {
    const supabase = createSupabaseMock();
    supabase._mocks.signInWithPassword.mockResolvedValueOnce({
      data: { session: null },
      error: { message: 'Invalid login credentials' },
    } as never);

    const result = await changeOwnerPassword(supabase as never, {
      currentPassword: 'WrongPassword123!',
      newPassword: 'NewPassword123!',
      confirmPassword: 'NewPassword123!',
    });

    expect(result).toEqual({
      status: 'incorrect_current_password',
      message: '현재 비밀번호가 올바르지 않습니다.',
    });
    expect(supabase._mocks.updateUser).not.toHaveBeenCalled();
    expect(supabase._mocks.rpc).not.toHaveBeenCalled();
    expect(supabase._mocks.signOut).not.toHaveBeenCalled();
  });

  it('does not clear marker or sign out when password update fails', async () => {
    const supabase = createSupabaseMock();
    supabase._mocks.updateUser.mockResolvedValueOnce({
      data: { user: null },
      error: { message: 'Password is too weak' },
    } as never);

    const result = await changeOwnerPassword(supabase as never, {
      currentPassword: 'CurrentPass123!',
      newPassword: 'NewPassword123!',
      confirmPassword: 'NewPassword123!',
    });

    expect(result.status).toBe('update_failed');
    expect(supabase._mocks.rpc).not.toHaveBeenCalled();
    expect(supabase._mocks.signOut).not.toHaveBeenCalled();
  });

  it('does not report complete success when audit recording fails', async () => {
    const supabase = createSupabaseMock();
    supabase._mocks.rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'permission denied' },
    } as never);

    const result = await changeOwnerPassword(supabase as never, {
      currentPassword: 'CurrentPass123!',
      newPassword: 'NewPassword123!',
      confirmPassword: 'NewPassword123!',
    });

    expect(result).toEqual({
      status: 'audit_failed',
      message: '완료 기록 저장에 실패했습니다.',
    });
    expect(supabase._mocks.signOut).not.toHaveBeenCalled();
  });

  it('calls operations in the correct order on success', async () => {
    const order: string[] = [];
    const supabase = createSupabaseMock();
    supabase._mocks.getUser.mockImplementation(async () => {
      order.push('getUser');
      return {
        data: { user: { id: 'user-1', email: 'owner@test.local', user_metadata: { must_change_password: true } } },
        error: null,
      };
    });
    supabase._mocks.signInWithPassword.mockImplementation(async () => {
      order.push('signInWithPassword');
      return { data: { session: {} }, error: null };
    });
    supabase._mocks.updateUser.mockImplementation(async () => {
      order.push('updateUser');
      return { data: { user: { id: 'user-1' } }, error: null };
    });
    supabase._mocks.rpc.mockImplementation(async () => {
      order.push('rpc');
      return { data: [{ idempotent_replay: false }], error: null };
    });
    supabase._mocks.signOut.mockImplementation(async () => {
      order.push('signOut');
      return { error: null };
    });

    const result = await changeOwnerPassword(supabase as never, {
      currentPassword: 'CurrentPass123!',
      newPassword: 'NewPassword123!',
      confirmPassword: 'NewPassword123!',
    });

    expect(result).toEqual({ status: 'success' });
    expect(order).toEqual([
      'getUser',
      'signInWithPassword',
      'updateUser',
      'rpc',
      'signOut',
    ]);
    expect(supabase._mocks.updateUser).toHaveBeenCalledWith({
      password: 'NewPassword123!',
      data: { must_change_password: false },
    });
    expect(supabase._mocks.signOut).toHaveBeenCalledWith({ scope: 'global' });
  });
});

describe('recordOwnerPasswordChangeAudit', () => {
  it('does not include password material in RPC payload', async () => {
    const rpc = vi.fn(async () => ({ data: [{ idempotent_replay: false }], error: null }));
    await recordOwnerPasswordChangeAudit({ rpc } as never);
    expect(rpc).toHaveBeenCalledWith('reve_owner_record_password_change_completed');
    expect(JSON.stringify(rpc.mock.calls)).not.toContain('Password');
  });
});

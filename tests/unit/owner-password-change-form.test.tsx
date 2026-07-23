import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { OwnerPasswordChangeForm } from '@/components/owner/owner-password-change-form';

const { changeOwnerPassword, recordOwnerPasswordChangeAudit, push, refresh } = vi.hoisted(() => ({
  changeOwnerPassword: vi.fn(),
  recordOwnerPasswordChangeAudit: vi.fn(),
  push: vi.fn(),
  refresh: vi.fn(),
}));

vi.mock('@/lib/auth/change-owner-password', () => ({
  changeOwnerPassword,
  recordOwnerPasswordChangeAudit,
}));

vi.mock('@/lib/supabase/client', () => ({
  createClient: () => ({}),
}));

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push, refresh }),
}));

describe('OwnerPasswordChangeForm', () => {
  afterEach(() => {
    cleanup();
    changeOwnerPassword.mockReset();
    recordOwnerPasswordChangeAudit.mockReset();
    push.mockReset();
    refresh.mockReset();
  });

  it('blocks repeated submission while a request is running', async () => {
    let resolveChange: ((value: unknown) => void) | undefined;
    changeOwnerPassword.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveChange = resolve;
        }),
    );

    render(<OwnerPasswordChangeForm />);
    await userEvent.type(screen.getByLabelText('현재 비밀번호'), 'CurrentPass123!');
    await userEvent.type(screen.getByLabelText('새 비밀번호'), 'NewPassword123!');
    await userEvent.type(screen.getByLabelText('새 비밀번호 확인'), 'NewPassword123!');

    await userEvent.click(screen.getByRole('button', { name: '비밀번호 변경' }));
    expect(screen.getByRole('button', { name: '변경 중…' })).toBeDisabled();

    resolveChange?.({ status: 'success' });
    await waitFor(() => {
      expect(push).toHaveBeenCalledWith('/login?passwordChanged=1');
    });
  });

  it('redirects to login with success query after password change', async () => {
    changeOwnerPassword.mockResolvedValueOnce({ status: 'success' });

    render(<OwnerPasswordChangeForm />);
    await userEvent.type(screen.getByLabelText('현재 비밀번호'), 'CurrentPass123!');
    await userEvent.type(screen.getByLabelText('새 비밀번호'), 'NewPassword123!');
    await userEvent.type(screen.getByLabelText('새 비밀번호 확인'), 'NewPassword123!');
    await userEvent.click(screen.getByRole('button', { name: '비밀번호 변경' }));

    await waitFor(() => {
      expect(push).toHaveBeenCalledWith('/login?passwordChanged=1');
      expect(refresh).toHaveBeenCalled();
    });
  });

  it('shows audit retry state without claiming complete success', async () => {
    changeOwnerPassword.mockResolvedValueOnce({ status: 'audit_failed', message: 'fail' });

    render(<OwnerPasswordChangeForm />);
    await userEvent.type(screen.getByLabelText('현재 비밀번호'), 'CurrentPass123!');
    await userEvent.type(screen.getByLabelText('새 비밀번호'), 'NewPassword123!');
    await userEvent.type(screen.getByLabelText('새 비밀번호 확인'), 'NewPassword123!');
    await userEvent.click(screen.getByRole('button', { name: '비밀번호 변경' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('완료 기록 저장에 실패');
    expect(screen.getByRole('button', { name: '완료 처리 다시 시도' })).toBeInTheDocument();
    expect(push).not.toHaveBeenCalled();
  });
});

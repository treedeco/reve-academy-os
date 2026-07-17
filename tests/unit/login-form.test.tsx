import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import LoginForm from '@/app/login/login-form';
import { OWNER_AUTH_EMAIL, OWNER_LOGIN_USERNAME } from '@/lib/auth/owner-login';

const signInWithPassword = vi.fn();
const signOut = vi.fn();
const maybeSingle = vi.fn();

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock('@/lib/supabase/client', () => ({
  createClient: () => ({
    auth: {
      signInWithPassword,
      signOut,
    },
    from: () => ({
      select: () => ({
        maybeSingle,
      }),
    }),
  }),
}));

describe('LoginForm', () => {
  afterEach(() => {
    cleanup();
    signInWithPassword.mockReset();
    signOut.mockReset();
    maybeSingle.mockReset();
  });

  it('shows validation error when fields are empty', async () => {
    render(<LoginForm />);
    await userEvent.click(screen.getByRole('button', { name: '로그인' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('사용자 이름과 비밀번호');
  });

  it('rejects incorrect username without calling Supabase', async () => {
    render(<LoginForm />);
    await userEvent.type(screen.getByLabelText('사용자 이름'), 'wrong-user');
    await userEvent.type(screen.getByLabelText('비밀번호'), 'any-password');
    await userEvent.click(screen.getByRole('button', { name: '로그인' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('사용자 이름 또는 비밀번호');
    expect(signInWithPassword).not.toHaveBeenCalled();
  });

  it('rejects legacy owner identifier without calling Supabase', async () => {
    render(<LoginForm />);
    await userEvent.type(screen.getByLabelText('사용자 이름'), 'owner-alpha@test.local');
    await userEvent.type(screen.getByLabelText('비밀번호'), 'legacy-password');
    await userEvent.click(screen.getByRole('button', { name: '로그인' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('사용자 이름 또는 비밀번호');
    expect(signInWithPassword).not.toHaveBeenCalled();
  });

  it('shows authentication error for incorrect password', async () => {
    signInWithPassword.mockResolvedValueOnce({
      error: { message: 'Invalid login credentials' },
    });

    render(<LoginForm />);
    await userEvent.type(screen.getByLabelText('사용자 이름'), OWNER_LOGIN_USERNAME);
    await userEvent.type(screen.getByLabelText('비밀번호'), 'wrong-password');
    await userEvent.click(screen.getByRole('button', { name: '로그인' }));

    expect(signInWithPassword).toHaveBeenCalledWith({
      email: OWNER_AUTH_EMAIL,
      password: 'wrong-password',
    });
    expect(await screen.findByRole('alert')).toHaveTextContent('사용자 이름 또는 비밀번호');
  });

  it('signs in with reve username mapped to owner auth email', async () => {
    signInWithPassword.mockResolvedValueOnce({ error: null });
    maybeSingle.mockResolvedValueOnce({
      data: { role: 'owner', account_state: 'active' },
      error: null,
    });

    render(<LoginForm />);
    await userEvent.type(screen.getByLabelText('사용자 이름'), OWNER_LOGIN_USERNAME);
    await userEvent.type(screen.getByLabelText('비밀번호'), 'configured-password');
    await userEvent.click(screen.getByRole('button', { name: '로그인' }));

    expect(signInWithPassword).toHaveBeenCalledWith({
      email: OWNER_AUTH_EMAIL,
      password: 'configured-password',
    });
  });
});

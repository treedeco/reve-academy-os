import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import LoginForm from '@/app/login/login-form';

const signInWithPassword = vi.fn();
const maybeSingle = vi.fn();

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock('@/lib/supabase/client', () => ({
  createClient: () => ({
    auth: {
      signInWithPassword,
      signOut: vi.fn(),
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
    maybeSingle.mockReset();
  });

  it('shows validation error when fields are empty', async () => {
    render(<LoginForm />);
    await userEvent.click(screen.getByRole('button', { name: '로그인' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('이메일과 비밀번호');
  });

  it('shows authentication error from sign-in failure', async () => {
    signInWithPassword.mockResolvedValueOnce({
      error: { message: 'Invalid login credentials' },
    });

    render(<LoginForm />);
    await userEvent.type(screen.getByLabelText('이메일'), 'bad@test.local');
    await userEvent.type(screen.getByLabelText('비밀번호'), 'wrong');
    await userEvent.click(screen.getByRole('button', { name: '로그인' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('이메일 또는 비밀번호');
  });
});

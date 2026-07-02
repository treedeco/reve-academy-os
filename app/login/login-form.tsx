'use client';

import { useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { mapDatabaseError } from '@/lib/domain/format';

export default function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(searchParams.get('error'));
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError(null);

    if (!email.trim() || !password) {
      setError('이메일과 비밀번호를 입력해 주세요.');
      setPending(false);
      return;
    }

    try {
      const supabase = createClient();
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (signInError) {
        throw signInError;
      }

      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser();

      if (userError || !user) {
        throw new Error('REVE_INVALID_PROFILE');
      }

      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('role, account_state')
        .eq('id', user.id)
        .maybeSingle();

      if (profileError || profile?.role !== 'owner' || profile.account_state !== 'active') {
        await supabase.auth.signOut();
        throw new Error('REVE_INVALID_PROFILE');
      }

      const next = searchParams.get('next') || '/dashboard';
      router.push(next);
      router.refresh();
    } catch (caught) {
      setError(mapDatabaseError(caught as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50 px-4">
      <div className="w-full max-w-md rounded-xl border border-slate-200 bg-white p-8 shadow-sm">
        <h1 className="text-2xl font-semibold">REVE ACADEMY OS</h1>
        <p className="mt-2 text-sm text-slate-600">Owner Alpha 로그인</p>

        <form className="mt-8 space-y-4" onSubmit={handleSubmit}>
          <div>
            <label className="block text-sm font-medium text-slate-700" htmlFor="email">
              이메일
            </label>
            <input
              id="email"
              type="email"
              autoComplete="username"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              disabled={pending}
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700" htmlFor="password">
              비밀번호
            </label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              disabled={pending}
            />
          </div>

          {error ? (
            <p className="text-sm text-red-600" role="alert">
              {error}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={pending}
            className="w-full rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
          >
            {pending ? '로그인 중…' : '로그인'}
          </button>
        </form>
      </div>
    </div>
  );
}

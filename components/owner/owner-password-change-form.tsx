'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { changeOwnerPassword, recordOwnerPasswordChangeAudit } from '@/lib/auth/change-owner-password';
import { createClient } from '@/lib/supabase/client';
import {
  OWNER_PASSWORD_AUDIT_RETRY_MESSAGE,
  OWNER_PASSWORD_CHANGED_LOGIN_MESSAGE,
} from '@/lib/domain/owner-password';

type FormStatus =
  | 'idle'
  | 'submitting'
  | 'audit_retry'
  | 'success';

export function OwnerPasswordChangeForm() {
  const router = useRouter();
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [status, setStatus] = useState<FormStatus>('idle');

  useEffect(() => {
    return () => {
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
    };
  }, []);

  function clearSecrets() {
    setCurrentPassword('');
    setNewPassword('');
    setConfirmPassword('');
  }

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (status === 'submitting') {
      return;
    }

    setStatus('submitting');
    setError(null);
    setInfo(null);

    const supabase = createClient();
    const result = await changeOwnerPassword(supabase, {
      currentPassword,
      newPassword,
      confirmPassword,
    });

    if (result.status === 'success') {
      clearSecrets();
      setStatus('success');
      router.push(`/login?passwordChanged=1`);
      router.refresh();
      return;
    }

    if (result.status === 'audit_failed') {
      clearSecrets();
      setStatus('audit_retry');
      setError(OWNER_PASSWORD_AUDIT_RETRY_MESSAGE);
      return;
    }

    if (result.status === 'sign_out_failed') {
      clearSecrets();
      setStatus('idle');
      setError(result.message);
      return;
    }

    setStatus('idle');
    setError(result.message);
  }

  async function handleAuditRetry() {
    if (status === 'submitting') {
      return;
    }

    setStatus('submitting');
    setError(null);
    setInfo(null);

    const supabase = createClient();
    const auditResult = await recordOwnerPasswordChangeAudit(supabase);
    if (!auditResult.ok) {
      setStatus('audit_retry');
      setError(OWNER_PASSWORD_AUDIT_RETRY_MESSAGE);
      return;
    }

    const { error: signOutError } = await supabase.auth.signOut({ scope: 'global' });
    clearSecrets();

    if (signOutError) {
      setStatus('idle');
      setError(
        '완료 기록은 저장되었지만 로그아웃에 실패했습니다. 모든 기기에서 수동으로 로그아웃해 주세요.',
      );
      return;
    }

    setStatus('success');
    router.push(`/login?passwordChanged=1`);
    router.refresh();
  }

  const isBusy = status === 'submitting';

  return (
    <div className="mx-auto w-full max-w-lg rounded-xl border border-slate-200 bg-white p-6 shadow-sm lg:p-8">
      <h1 className="text-2xl font-semibold">비밀번호 변경</h1>
      <p className="mt-2 text-sm text-slate-600">
        현재 비밀번호를 확인한 뒤 새 비밀번호로 변경합니다. 변경 후 모든 세션에서 로그아웃됩니다.
      </p>

      {info ? (
        <p className="mt-4 rounded-md bg-blue-50 px-3 py-2 text-sm text-blue-800" role="status">
          {info}
        </p>
      ) : null}

      {error ? (
        <p className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700" role="alert">
          {error}
        </p>
      ) : null}

      {status === 'audit_retry' ? (
        <div className="mt-6 space-y-3">
          <button
            type="button"
            disabled={isBusy}
            onClick={handleAuditRetry}
            className="w-full rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
          >
            {isBusy ? '처리 중…' : '완료 처리 다시 시도'}
          </button>
          <p className="text-xs text-slate-500">{OWNER_PASSWORD_CHANGED_LOGIN_MESSAGE}</p>
        </div>
      ) : (
        <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
          <div>
            <label className="block text-sm font-medium text-slate-700" htmlFor="current-password">
              현재 비밀번호
            </label>
            <input
              id="current-password"
              type="password"
              autoComplete="current-password"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={currentPassword}
              onChange={(event) => setCurrentPassword(event.target.value)}
              disabled={isBusy}
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700" htmlFor="new-password">
              새 비밀번호
            </label>
            <input
              id="new-password"
              type="password"
              autoComplete="new-password"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={newPassword}
              onChange={(event) => setNewPassword(event.target.value)}
              disabled={isBusy}
            />
            <p className="mt-1 text-xs text-slate-500">
              12자 이상, 영문 소문자·대문자·숫자·특수문자 중 3종류 이상
            </p>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700" htmlFor="confirm-password">
              새 비밀번호 확인
            </label>
            <input
              id="confirm-password"
              type="password"
              autoComplete="new-password"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={confirmPassword}
              onChange={(event) => setConfirmPassword(event.target.value)}
              disabled={isBusy}
            />
          </div>

          <button
            type="submit"
            disabled={isBusy}
            className="w-full rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
          >
            {isBusy ? '변경 중…' : '비밀번호 변경'}
          </button>
        </form>
      )}
    </div>
  );
}

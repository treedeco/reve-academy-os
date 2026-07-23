'use client';

import { useEffect } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';

export function OwnerPasswordChangePrompt({
  mustChangePassword,
}: {
  mustChangePassword: boolean;
}) {
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    if (mustChangePassword && !pathname.startsWith('/account/password')) {
      router.replace('/account/password');
    }
  }, [mustChangePassword, pathname, router]);

  if (!mustChangePassword) {
    return null;
  }

  if (pathname.startsWith('/account/password')) {
    return (
      <div className="mb-4 rounded-md border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
        초기 비밀번호를 변경해야 합니다. 아래 양식에서 새 비밀번호를 설정해 주세요.
      </div>
    );
  }

  return null;
}

export function OwnerAccountNavLink({ pathname }: { pathname: string }) {
  const isActive = pathname.startsWith('/account/password');

  return (
    <Link
      href="/account/password"
      className={`block rounded-md px-3 py-2 text-sm ${
        isActive
          ? 'bg-brand-50 font-medium text-brand-700'
          : 'text-slate-700 hover:bg-slate-100'
      }`}
    >
      비밀번호 변경
    </Link>
  );
}

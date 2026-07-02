'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

const NAV_ITEMS = [
  { href: '/dashboard', label: '대시보드' },
  { href: '/lessons/today', label: '오늘의 수업' },
  { href: '/students', label: '학생' },
];

export function OwnerShell({
  children,
  ownerName,
}: {
  children: React.ReactNode;
  ownerName: string;
}) {
  const pathname = usePathname();
  const router = useRouter();

  async function handleLogout() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push('/login');
    router.refresh();
  }

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white lg:hidden">
        <div className="flex items-center justify-between px-4 py-3">
          <div>
            <p className="text-sm font-semibold">REVE ACADEMY OS</p>
            <p className="text-xs text-slate-500">{ownerName}</p>
          </div>
          <button
            type="button"
            onClick={handleLogout}
            className="rounded-md border border-slate-300 px-3 py-1 text-sm"
          >
            로그아웃
          </button>
        </div>
        <nav className="flex gap-2 overflow-x-auto px-4 pb-3">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`whitespace-nowrap rounded-full px-3 py-1 text-sm ${
                pathname.startsWith(item.href)
                  ? 'bg-brand-600 text-white'
                  : 'bg-slate-100 text-slate-700'
              }`}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </header>

      <div className="mx-auto flex max-w-7xl">
        <aside className="hidden min-h-screen w-64 border-r border-slate-200 bg-white p-6 lg:block">
          <p className="text-lg font-semibold">REVE ACADEMY OS</p>
          <p className="mt-1 text-sm text-slate-500">Owner Alpha</p>
          <p className="mt-4 text-sm font-medium">{ownerName}</p>
          <nav className="mt-8 space-y-2">
            {NAV_ITEMS.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className={`block rounded-md px-3 py-2 text-sm ${
                  pathname.startsWith(item.href)
                    ? 'bg-brand-50 font-medium text-brand-700'
                    : 'text-slate-700 hover:bg-slate-100'
                }`}
              >
                {item.label}
              </Link>
            ))}
          </nav>
          <button
            type="button"
            onClick={handleLogout}
            className="mt-8 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          >
            로그아웃
          </button>
        </aside>

        <main className="min-h-screen flex-1 p-4 lg:p-8">{children}</main>
      </div>
    </div>
  );
}

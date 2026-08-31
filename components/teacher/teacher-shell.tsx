'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

const NAV_ITEMS = [
  { href: '/teacher/lessons/today', label: '오늘의 수업' },
  { href: '/teacher/students', label: '담당 학생' },
];

export function TeacherShell({
  children,
  teacherName,
}: {
  children: React.ReactNode;
  teacherName: string;
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
      <header className="border-b border-slate-200 bg-white">
        <div className="flex items-center justify-between px-4 py-3">
          <div>
            <p className="text-sm font-semibold">REVE ACADEMY OS</p>
            <p className="text-xs text-slate-500">{teacherName}</p>
          </div>
          <button
            type="button"
            onClick={() => void handleLogout()}
            className="min-h-11 rounded-md border border-slate-300 px-4 py-2 text-sm"
          >
            로그아웃
          </button>
        </div>
        <nav className="flex gap-2 overflow-x-auto px-4 pb-3">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`min-h-11 whitespace-nowrap rounded-full px-4 py-2 text-sm ${
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
      <main className="mx-auto max-w-3xl px-4 py-4">{children}</main>
    </div>
  );
}

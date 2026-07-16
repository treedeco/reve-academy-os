import Link from 'next/link';
import { StudentsCreatePanel } from '@/components/owner/students-create-panel';
import { ErrorState } from '@/components/ui/state-blocks';
import { formatDateTimeSeoul } from '@/lib/domain/format';
import { fetchStudentList } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function StudentsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q = '' } = await searchParams;
  const supabase = await createClient();

  try {
    const students = await fetchStudentList(supabase, q);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">학생</h1>
          <p className="mt-1 text-sm text-slate-600">현재 pass 기준 운영 정보</p>
        </div>

        <StudentsCreatePanel />

        <form className="flex flex-col gap-3 sm:flex-row" action="/students" method="get">
          <input
            type="search"
            name="q"
            defaultValue={q}
            placeholder="학생 이름 검색"
            className="w-full max-w-md rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
          <button
            type="submit"
            className="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white"
          >
            검색
          </button>
        </form>

        <div className="hidden overflow-x-auto rounded-lg border border-slate-200 bg-white lg:block">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 bg-slate-50 text-left text-slate-500">
                <th className="px-4 py-3">학생</th>
                <th className="px-4 py-3">상태</th>
                <th className="px-4 py-3">과목</th>
                <th className="px-4 py-3">강사</th>
                <th className="px-4 py-3">다음 수업</th>
                <th className="px-4 py-3">잔여</th>
              </tr>
            </thead>
            <tbody>
              {students.map((student) => (
                <tr key={student.id} className="border-b border-slate-100">
                  <td className="px-4 py-3">
                    <Link href={`/students/${student.id}`} className="font-medium text-brand-700">
                      {student.name}
                    </Link>
                  </td>
                  <td className="px-4 py-3">{student.operational_status}</td>
                  <td className="px-4 py-3">{student.course_name ?? '-'}</td>
                  <td className="px-4 py-3">{student.teacher_name ?? '-'}</td>
                  <td className="px-4 py-3">
                    {student.next_lesson_at
                      ? formatDateTimeSeoul(student.next_lesson_at)
                      : '-'}
                  </td>
                  <td className="px-4 py-3">{student.remaining_lesson_count ?? '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="space-y-3 lg:hidden">
          {students.map((student) => (
            <Link
              key={student.id}
              href={`/students/${student.id}`}
              className="block rounded-lg border border-slate-200 bg-white p-4"
            >
              <p className="font-medium">{student.name}</p>
              <p className="mt-1 text-sm text-slate-600">
                {student.course_name ?? '과목 없음'} · {student.teacher_name ?? '강사 없음'}
              </p>
              <p className="mt-2 text-sm">
                잔여 {student.remaining_lesson_count ?? '-'} · 다음{' '}
                {student.next_lesson_at ? formatDateTimeSeoul(student.next_lesson_at) : '-'}
              </p>
            </Link>
          ))}
        </div>
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

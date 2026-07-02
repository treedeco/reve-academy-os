import Link from 'next/link';
import { StudentPassSummary } from '@/components/owner/student-pass-summary';
import { ErrorState } from '@/components/ui/state-blocks';
import { formatDateTimeSeoul, formatLessonStatus } from '@/lib/domain/format';
import { WEEKDAY_LABELS, type LessonStatus } from '@/lib/domain/types';
import { fetchStudentDetail } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function StudentDetailPage({
  params,
}: {
  params: Promise<{ studentId: string }>;
}) {
  const { studentId } = await params;
  const supabase = await createClient();

  try {
    const detail = await fetchStudentDetail(supabase, studentId);

    return (
      <div className="space-y-6">
        <div>
          <Link href="/students" className="text-sm text-brand-700">
            ← 학생 목록
          </Link>
          <h1 className="mt-3 text-2xl font-semibold">{detail.student.name}</h1>
          <p className="mt-1 text-sm text-slate-600">
            {detail.student.student_code} · {detail.student.operational_status}
          </p>
          {detail.teacher_name ? (
            <p className="mt-1 text-sm text-slate-600">담당 강사: {detail.teacher_name}</p>
          ) : null}
        </div>

        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-lg font-semibold">현재 회차권</h2>
          {detail.current_pass ? (
            <StudentPassSummary pass={detail.current_pass} />
          ) : (
            <p className="mt-3 text-sm text-slate-600">현재 active/reserved pass가 없습니다.</p>
          )}
        </section>

        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-lg font-semibold">고정 일정</h2>
          {detail.schedule_slots.length === 0 ? (
            <p className="mt-3 text-sm text-slate-600">등록된 고정 일정이 없습니다.</p>
          ) : (
            <ul className="mt-3 space-y-2">
              {detail.schedule_slots.map((slot) => (
                <li key={slot.id} className="text-sm">
                  {WEEKDAY_LABELS[slot.weekday]} {slot.local_start_time.slice(0, 5)} ·{' '}
                  {slot.duration_minutes}분 · {slot.teacher_name}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-lg font-semibold">수업 이력</h2>
          <div className="mt-3 overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-slate-500">
                  <th className="px-2 py-2">회차</th>
                  <th className="px-2 py-2">일시</th>
                  <th className="px-2 py-2">상태</th>
                </tr>
              </thead>
              <tbody>
                {detail.lessons.map((lesson) => (
                  <tr key={lesson.id} className="border-b border-slate-100">
                    <td className="px-2 py-2">{lesson.sequence_number}</td>
                    <td className="px-2 py-2">{formatDateTimeSeoul(lesson.scheduled_at)}</td>
                    <td className="px-2 py-2">
                      {formatLessonStatus(lesson.status as LessonStatus)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {detail.lesson_notes.length > 0 ? (
          <section className="rounded-lg border border-slate-200 bg-white p-4">
            <h2 className="text-lg font-semibold">최근 수업 메모</h2>
            <ul className="mt-3 space-y-3">
              {detail.lesson_notes.map((note) => (
                <li key={note.id} className="rounded-md bg-slate-50 p-3 text-sm">
                  {note.body}
                </li>
              ))}
            </ul>
          </section>
        ) : null}

        {detail.previous_passes.length > 0 ? (
          <section className="rounded-lg border border-slate-200 bg-white p-4">
            <h2 className="text-lg font-semibold">이전 회차권</h2>
            <ul className="mt-3 space-y-2 text-sm">
              {detail.previous_passes.map((pass) => (
                <li key={pass.id}>
                  {pass.pass_code} · {pass.status} · seq {pass.sequence_number}
                </li>
              ))}
            </ul>
          </section>
        ) : null}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

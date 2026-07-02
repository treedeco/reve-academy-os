import { ErrorState } from '@/components/ui/state-blocks';
import { fetchDashboardSummary } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function DashboardPage() {
  const supabase = await createClient();

  try {
    const summary = await fetchDashboardSummary(supabase);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">대시보드</h1>
          <p className="mt-1 text-sm text-slate-600">오늘 운영 현황 요약</p>
        </div>

        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
          {[
            { label: '오늘 수업', value: summary.total_today },
            { label: '예정/연기', value: summary.scheduled_count },
            { label: '완료/차감', value: summary.completed_count },
            { label: '취소/휴무', value: summary.cancelled_or_postponed_count },
            { label: '오늘 수업 학생', value: summary.students_with_lesson_today },
          ].map((card) => (
            <div key={card.label} className="rounded-lg border border-slate-200 bg-white p-4">
              <p className="text-sm text-slate-500">{card.label}</p>
              <p className="mt-2 text-3xl font-semibold">{card.value}</p>
            </div>
          ))}
        </div>
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

import { WeeklyScheduleView } from '@/components/owner/weekly-schedule-view';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchWeeklySchedule } from '@/lib/data/owner-queries';
import { groupWeeklyScheduleEntries } from '@/lib/domain/weekly-schedule';
import { createClient } from '@/lib/supabase/server';

function buildWeekContextLabel(): string {
  const formatter = new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  });
  return `고정 주간 시간표 · 기준일 ${formatter.format(new Date())} (Asia/Seoul)`;
}

export default async function WeeklySchedulePage() {
  const supabase = await createClient();

  try {
    const entries = await fetchWeeklySchedule(supabase);
    const groups = groupWeeklyScheduleEntries(entries);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">주간 시간표</h1>
          <p className="mt-1 text-sm text-slate-600">
            학원 고정 주간 일정입니다. 개별 수업 연기·변경은 고정 시간표 위치를 바꾸지 않습니다.
          </p>
        </div>

        {groups.length === 0 ? (
          <EmptyState
            title="표시할 주간 일정이 없습니다"
            description="활성 수강권의 고정 시간표가 등록되면 이 화면에 표시됩니다."
          />
        ) : (
          <WeeklyScheduleView groups={groups} weekContextLabel={buildWeekContextLabel()} />
        )}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

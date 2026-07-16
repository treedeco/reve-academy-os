import { WeeklyTimetableView } from '@/components/owner/weekly-timetable-view';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchWeeklyTimetableLessons } from '@/lib/data/owner-queries';
import { groupTimetableLessonsByWeekday } from '@/lib/domain/weekly-timetable';
import { createClient } from '@/lib/supabase/server';

function buildWeekContextLabel(): string {
  const formatter = new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  });
  return `이번 주 수업 시간표 · 기준 ${formatter.format(new Date())} (Asia/Seoul)`;
}

export default async function WeeklySchedulePage() {
  const supabase = await createClient();

  try {
    const lessons = await fetchWeeklyTimetableLessons(supabase);
    const columns = groupTimetableLessonsByWeekday(lessons);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">주간 시간표</h1>
          <p className="mt-1 text-sm text-slate-600">
            이번 주 실제 수업 일정입니다. 개별 수업 이동은 고정 주간 패턴을 바꾸지 않습니다.
          </p>
        </div>

        {columns.every((column) => column.lessons.length === 0) ? (
          <EmptyState
            title="표시할 이번 주 수업이 없습니다"
            description="활성 수강권의 이번 주 예정 수업이 등록되면 시간표에 표시됩니다."
          />
        ) : (
          <WeeklyTimetableView columns={columns} weekContextLabel={buildWeekContextLabel()} />
        )}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

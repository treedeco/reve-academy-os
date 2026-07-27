import { WeeklyTimetableClient } from '@/components/owner/weekly-timetable-client';
import { ErrorState } from '@/components/ui/state-blocks';
import { fetchWeeklyTimetableLessons } from '@/lib/data/owner-queries';
import {
  buildWeekContextLabel,
  buildWeeklyTimetableColumns,
  getSeoulWeekBounds,
  isSameSeoulWeek,
  parseWeekReference,
} from '@/lib/domain/weekly-timetable';
import { createClient } from '@/lib/supabase/server';

export default async function WeeklySchedulePage({
  searchParams,
}: {
  searchParams: Promise<{ week?: string }>;
}) {
  const { week } = await searchParams;
  const supabase = await createClient();

  try {
    const weekReference = parseWeekReference(week);
    const weekBounds = getSeoulWeekBounds(weekReference);
    const lessons = await fetchWeeklyTimetableLessons(supabase, { weekReference });
    const columns = buildWeeklyTimetableColumns(lessons, weekReference);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">주간 시간표</h1>
          <p className="mt-1 text-sm text-slate-600">
            선택한 주의 실제 수업 일정입니다. 개별 수업 이동은 고정 주간 패턴을 바꾸지 않습니다.
          </p>
        </div>

        <WeeklyTimetableClient
          initialColumns={columns}
          weekReferenceDateKey={weekBounds.mondayDateKey}
          weekContextLabel={buildWeekContextLabel(weekReference)}
          isCurrentWeek={isSameSeoulWeek(weekReference, new Date())}
        />
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

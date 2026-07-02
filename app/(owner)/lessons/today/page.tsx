import { TodayLessonsPanel } from '@/components/owner/today-lessons-panel';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchTodayLessons } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function TodayLessonsPage() {
  const supabase = await createClient();

  try {
    const lessons = await fetchTodayLessons(supabase);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">오늘의 수업</h1>
          <p className="mt-1 text-sm text-slate-600">상태 변경은 trusted RPC를 통해서만 저장됩니다.</p>
        </div>

        {lessons.length === 0 ? (
          <EmptyState
            title="오늘 예정된 수업이 없습니다"
            description="새 수업이 등록되면 이 화면에 표시됩니다."
          />
        ) : (
          <TodayLessonsPanel initialLessons={lessons} />
        )}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

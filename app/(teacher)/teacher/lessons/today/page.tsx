import { TeacherTodayLessonsPanel } from '@/components/teacher/teacher-today-lessons-panel';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { getAuthenticatedTeacher } from '@/lib/auth/teacher-session';
import { fetchTeacherTodayLessons } from '@/lib/data/teacher-queries';
import { createClient } from '@/lib/supabase/server';

export default async function TeacherTodayLessonsPage() {
  const supabase = await createClient();
  const { profile, error } = await getAuthenticatedTeacher(supabase);

  if (!profile) {
    return <ErrorState message={error ?? '강사 권한이 없습니다.'} />;
  }

  try {
    const lessons = await fetchTeacherTodayLessons(supabase);

    return (
      <div className="space-y-4">
        <div>
          <h1 className="text-2xl font-semibold">오늘의 수업</h1>
          <p className="mt-1 text-sm text-slate-600">담당 수업의 출석과 수업 내용을 기록합니다.</p>
        </div>

        {lessons.length === 0 ? (
          <EmptyState
            title="오늘 예정된 수업이 없습니다"
            description="배정된 수업이 있으면 이 화면에 표시됩니다."
          />
        ) : (
          <TeacherTodayLessonsPanel initialLessons={lessons} authorProfileId={profile.id} />
        )}
      </div>
    );
  } catch (caught) {
    return <ErrorState message={(caught as Error).message} />;
  }
}

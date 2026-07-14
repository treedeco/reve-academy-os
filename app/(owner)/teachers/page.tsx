import { TeachersPanel } from '@/components/owner/teachers-panel';
import { ErrorState } from '@/components/ui/state-blocks';
import { fetchOwnerTeacherList } from '@/lib/data/owner-teachers';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerTeachersPage() {
  const supabase = await createClient();

  try {
    const teachers = await fetchOwnerTeacherList(supabase);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">강사</h1>
          <p className="mt-1 text-sm text-slate-600">
            강사 마스터 정보를 등록하고 수정합니다. 배정 해제는 고정 일정 또는 수업 배정을 변경한 뒤
            비활성화할 수 있습니다.
          </p>
        </div>

        <TeachersPanel initialTeachers={teachers} />
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

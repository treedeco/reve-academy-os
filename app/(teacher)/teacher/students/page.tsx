import { TeacherStudentsPanel } from '@/components/teacher/teacher-students-panel';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchTeacherAssignedStudents } from '@/lib/data/teacher-queries';
import { createClient } from '@/lib/supabase/server';

export default async function TeacherStudentsPage() {
  const supabase = await createClient();

  try {
    const students = await fetchTeacherAssignedStudents(supabase);

    return (
      <div className="space-y-4">
        <div>
          <h1 className="text-2xl font-semibold">담당 학생</h1>
          <p className="mt-1 text-sm text-slate-600">배정된 학생과 회차권 요약입니다.</p>
        </div>

        {students.length === 0 ? (
          <EmptyState
            title="담당 학생이 없습니다"
            description="배정된 수업이 있으면 학생 정보가 표시됩니다."
          />
        ) : (
          <TeacherStudentsPanel students={students} />
        )}
      </div>
    );
  } catch (caught) {
    return <ErrorState message={(caught as Error).message} />;
  }
}

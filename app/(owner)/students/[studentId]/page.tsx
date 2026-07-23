import { StudentDetailClient } from '@/components/owner/student-detail-client';
import { ErrorState } from '@/components/ui/state-blocks';
import { fetchStudentDetail, fetchStudentOperationalHistory } from '@/lib/data/owner-queries';
import { fetchOwnerStudentMasterRow } from '@/lib/data/owner-students';
import { createClient } from '@/lib/supabase/server';

export default async function StudentDetailPage({
  params,
}: {
  params: Promise<{ studentId: string }>;
}) {
  const { studentId } = await params;

  try {
    const supabaseClient = await createClient();
    const [detail, master, operationalHistory] = await Promise.all([
      fetchStudentDetail(supabaseClient, studentId),
      fetchOwnerStudentMasterRow(supabaseClient, studentId),
      fetchStudentOperationalHistory(supabaseClient, studentId),
    ]);

    return (
      <StudentDetailClient
        initialDetail={detail}
        initialMaster={master}
        operationalHistory={operationalHistory}
      />
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

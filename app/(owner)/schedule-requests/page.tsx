import { ScheduleChangeRequestsPanel } from '@/components/owner/schedule-change-requests-panel';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchOwnerScheduleChangeRequests } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerScheduleRequestsPage() {
  const supabase = await createClient();

  try {
    const requests = await fetchOwnerScheduleChangeRequests(supabase);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">일정 변경 요청</h1>
          <p className="mt-1 text-sm text-slate-600">
            제출된 일정 변경 요청을 검토하고, 승인된 요청을 수업 일정에 적용합니다. 고정 주간
            시간표는 변경되지 않습니다.
          </p>
        </div>

        {requests.length === 0 ? (
          <EmptyState
            title="처리할 일정 변경 요청이 없습니다"
            description="검토 대기 또는 승인 후 적용 대기 중인 요청만 표시됩니다."
          />
        ) : (
          <ScheduleChangeRequestsPanel initialRequests={requests} />
        )}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

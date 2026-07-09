import { ScheduleChangeRequestsPanel } from '@/components/owner/schedule-change-requests-panel';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchOwnerScheduleChangeQueue } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerScheduleRequestsPage() {
  const supabase = await createClient();

  try {
    const queue = await fetchOwnerScheduleChangeQueue(supabase);
    const hasWork =
      queue.reviewRequests.length > 0 || queue.cascadePendingRequests.length > 0;

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">일정 변경 요청</h1>
          <p className="mt-1 text-sm text-slate-600">
            제출된 일정 변경 요청을 검토하고, 승인된 요청을 수업 일정에 적용한 뒤 필요하면 이후
            수업을 연쇄 재배치합니다. 고정 주간 시간표는 변경되지 않습니다.
          </p>
        </div>

        {!hasWork ? (
          <EmptyState
            title="처리할 일정 변경 요청이 없습니다"
            description="검토/적용 대기 또는 연쇄 재배치 대기 중인 요청만 표시됩니다."
          />
        ) : (
          <ScheduleChangeRequestsPanel
            initialReviewRequests={queue.reviewRequests}
            initialCascadePendingRequests={queue.cascadePendingRequests}
          />
        )}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

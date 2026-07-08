import { RefundablePaymentsPanel } from '@/components/owner/refundable-payments-panel';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchOwnerRefundablePayments } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerRefundsPage() {
  const supabase = await createClient();

  try {
    const payments = await fetchOwnerRefundablePayments(supabase);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">환불 처리</h1>
          <p className="mt-1 text-sm text-slate-600">
            완료된 결제에 대해 전액 환불을 처리합니다. 환불 후 수강권은 취소되며, 이 작업은 되돌릴 수
            없습니다.
          </p>
        </div>

        {payments.length === 0 ? (
          <EmptyState
            title="환불 가능한 결제가 없습니다"
            description="완료된 결제 중 환불 가능한 active/reserved 수강권 연결 결제만 표시됩니다."
          />
        ) : (
          <RefundablePaymentsPanel initialPayments={payments} />
        )}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

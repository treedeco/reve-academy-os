import { SmsNotificationsPanel } from '@/components/owner/sms-notifications-panel';
import { EmptyState, ErrorState } from '@/components/ui/state-blocks';
import { fetchOwnerSmsNotifications } from '@/lib/data/owner-queries';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerSmsPage() {
  const supabase = await createClient();

  try {
    const notifications = await fetchOwnerSmsNotifications(supabase);

    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">SMS 발송 확인</h1>
          <p className="mt-1 text-sm text-slate-600">
            외부 SMS 앱으로 메시지를 보낸 뒤, 아래에서 발송 확인을 기록합니다. 이 화면은 SMS를
            자동 발송하지 않습니다.
          </p>
        </div>

        {notifications.length === 0 ? (
          <EmptyState
            title="발송 확인이 필요한 SMS가 없습니다"
            description="발송 예정·발송 대상·미발송(소진) 상태의 알림만 표시됩니다."
          />
        ) : (
          <SmsNotificationsPanel initialNotifications={notifications} />
        )}
      </div>
    );
  } catch (error) {
    return <ErrorState message={(error as Error).message} />;
  }
}

'use client';

import { useMemo, useState } from 'react';
import { confirmOwnerSmsSent } from '@/lib/data/owner-queries';
import { formatDateSeoul, mapDatabaseError } from '@/lib/domain/format';
import { formatSmsStatus } from '@/lib/domain/sms';
import type { OwnerSmsNotificationRow } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

export function SmsNotificationsPanel({
  initialNotifications,
}: {
  initialNotifications: OwnerSmsNotificationRow[];
}) {
  const [notifications, setNotifications] = useState(initialNotifications);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [errorById, setErrorById] = useState<Record<string, string>>({});
  const [successById, setSuccessById] = useState<Record<string, string>>({});

  const notificationMap = useMemo(
    () => new Map(notifications.map((row) => [row.id, row])),
    [notifications],
  );

  async function handleCopy(notificationId: string, message: string | null) {
    if (!message) {
      setErrorById((prev) => ({
        ...prev,
        [notificationId]: '복사할 메시지가 없습니다.',
      }));
      return;
    }

    try {
      await navigator.clipboard.writeText(message);
      setCopiedId(notificationId);
      setErrorById((prev) => ({ ...prev, [notificationId]: '' }));
      window.setTimeout(() => {
        setCopiedId((current) => (current === notificationId ? null : current));
      }, 2000);
    } catch {
      setErrorById((prev) => ({
        ...prev,
        [notificationId]: '클립보드 복사에 실패했습니다. 메시지를 직접 선택해 복사해 주세요.',
      }));
    }
  }

  async function handleConfirm(notificationId: string) {
    const current = notificationMap.get(notificationId);
    if (!current || pendingId === notificationId) {
      return;
    }

    setPendingId(notificationId);
    setErrorById((prev) => ({ ...prev, [notificationId]: '' }));
    setSuccessById((prev) => ({ ...prev, [notificationId]: '' }));

    try {
      const supabase = createClient();
      const result = await confirmOwnerSmsSent(supabase, notificationId);

      setSuccessById((prev) => ({
        ...prev,
        [notificationId]: result.no_change
          ? '이미 발송 확인된 항목입니다.'
          : '발송 확인이 저장되었습니다.',
      }));

      setNotifications((prev) => prev.filter((row) => row.id !== notificationId));
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [notificationId]: mapDatabaseError(error as { message?: string }),
      }));
    } finally {
      setPendingId(null);
    }
  }

  if (notifications.length === 0) {
    return (
      <div
        data-testid="sms-notifications-empty"
        className="rounded-lg border border-dashed border-slate-300 bg-white p-8 text-center"
      >
        <p className="font-medium text-slate-900">발송 확인이 필요한 SMS가 없습니다</p>
        <p className="mt-2 text-sm text-slate-600">
          발송 예정·발송 대상·미발송(소진) 상태의 알림만 이 화면에 표시됩니다.
        </p>
      </div>
    );
  }

  return (
    <div data-testid="sms-notifications-panel" className="space-y-4">
      {notifications.map((notification) => {
        const message = notification.message_body_snapshot ?? '';
        const isPending = pendingId === notification.id;
        const isCopied = copiedId === notification.id;
        const passContext = [notification.course_name, notification.product_name]
          .filter(Boolean)
          .join(' · ');

        return (
          <article
            key={notification.id}
            data-testid={`sms-item-${notification.id}`}
            className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm lg:p-5"
          >
            <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div className="min-w-0 flex-1 space-y-2">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-base font-semibold text-slate-900">
                    {notification.student_name}
                  </h2>
                  <span className="rounded-full bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700">
                    {formatSmsStatus(notification.status)}
                  </span>
                </div>

                {passContext ? (
                  <p className="text-sm text-slate-600">{passContext}</p>
                ) : null}

                <dl className="grid gap-1 text-sm text-slate-600 sm:grid-cols-2">
                  {notification.target_date ? (
                    <div>
                      <dt className="inline text-slate-500">대상일 </dt>
                      <dd className="inline">{formatDateSeoul(notification.target_date)}</dd>
                    </div>
                  ) : null}
                  <div>
                    <dt className="inline text-slate-500">수강권 </dt>
                    <dd className="inline">{notification.pass_code}</dd>
                  </div>
                </dl>

                <div className="rounded-md border border-slate-200 bg-slate-50 p-3">
                  <p className="text-xs font-medium text-slate-500">발송 메시지</p>
                  <p
                    data-testid={`sms-message-${notification.id}`}
                    className="mt-1 whitespace-pre-wrap break-words text-sm text-slate-900"
                  >
                    {message || '(메시지 없음)'}
                  </p>
                </div>
              </div>

              <div className="flex shrink-0 flex-col gap-2 sm:flex-row lg:flex-col lg:min-w-[9rem]">
                <button
                  type="button"
                  data-testid={`sms-copy-${notification.id}`}
                  disabled={!message || isPending}
                  onClick={() => handleCopy(notification.id, notification.message_body_snapshot)}
                  className="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {isCopied ? '복사됨' : '메시지 복사'}
                </button>
                <button
                  type="button"
                  data-testid={`sms-confirm-${notification.id}`}
                  disabled={isPending}
                  onClick={() => handleConfirm(notification.id)}
                  className="rounded-md bg-brand-600 px-3 py-2 text-sm font-medium text-white hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {isPending ? '확인 중…' : '발송 확인'}
                </button>
              </div>
            </div>

            {errorById[notification.id] ? (
              <p className="mt-3 text-sm text-red-600" role="alert">
                {errorById[notification.id]}
              </p>
            ) : null}

            {successById[notification.id] ? (
              <p className="mt-3 text-sm text-emerald-700" role="status">
                {successById[notification.id]}
              </p>
            ) : null}
          </article>
        );
      })}
    </div>
  );
}

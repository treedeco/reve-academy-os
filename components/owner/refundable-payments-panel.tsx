'use client';

import { useMemo, useState } from 'react';
import { processOwnerPaymentRefund } from '@/lib/data/owner-queries';
import { formatDateTimeSeoul } from '@/lib/domain/format';
import {
  formatKrwAmount,
  formatPassStatusLabel,
  mapRefundError,
  REFUND_ELIGIBILITY_LABEL,
} from '@/lib/domain/refund';
import type { OwnerRefundablePaymentRow } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

export function RefundablePaymentsPanel({
  initialPayments,
}: {
  initialPayments: OwnerRefundablePaymentRow[];
}) {
  const [payments, setPayments] = useState(initialPayments);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [reasonById, setReasonById] = useState<Record<string, string>>({});
  const [errorById, setErrorById] = useState<Record<string, string>>({});
  const [successById, setSuccessById] = useState<Record<string, string>>({});

  const paymentMap = useMemo(() => new Map(payments.map((row) => [row.id, row])), [payments]);

  async function handleRefund(paymentId: string) {
    const current = paymentMap.get(paymentId);
    if (!current || pendingId === paymentId) {
      return;
    }

    const reason = reasonById[paymentId]?.trim();
    if (!reason) {
      setErrorById((prev) => ({
        ...prev,
        [paymentId]: '환불 사유를 입력해 주세요.',
      }));
      return;
    }

    const confirmed = window.confirm(
      `${current.student_name} 학생 결제 ${formatKrwAmount(current.paid_amount_krw)} 전액 환불을 진행할까요?\n\n수강권 ${current.pass_code} (${formatPassStatusLabel(current.pass_status)})이 취소됩니다.`,
    );
    if (!confirmed) {
      return;
    }

    setPendingId(paymentId);
    setErrorById((prev) => ({ ...prev, [paymentId]: '' }));
    setSuccessById((prev) => ({ ...prev, [paymentId]: '' }));

    try {
      const supabase = createClient();
      await processOwnerPaymentRefund(supabase, {
        paymentId,
        refundedAmountKrw: current.paid_amount_krw,
        reason,
      });

      setSuccessById((prev) => ({
        ...prev,
        [paymentId]: '환불 처리가 완료되었습니다.',
      }));
      setPayments((prev) => prev.filter((row) => row.id !== paymentId));
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [paymentId]: mapRefundError(error as { message?: string }),
      }));
    } finally {
      setPendingId(null);
    }
  }

  if (payments.length === 0) {
    return (
      <div
        data-testid="refundable-payments-empty"
        className="rounded-lg border border-dashed border-slate-300 bg-white p-8 text-center"
      >
        <p className="font-medium text-slate-900">환불 가능한 결제가 없습니다</p>
        <p className="mt-2 text-sm text-slate-600">
          완료된 결제 중 active/reserved 수강권에 연결되고, 아직 환불되지 않은 항목만 표시됩니다.
        </p>
      </div>
    );
  }

  return (
    <div data-testid="refundable-payments-panel" className="space-y-4">
      {payments.map((payment) => {
        const isPending = pendingId === payment.id;
        const reason = reasonById[payment.id] ?? '';
        const canConfirm = reason.trim().length > 0 && !isPending;

        return (
          <article
            key={payment.id}
            data-testid={`refund-item-${payment.id}`}
            className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm lg:p-5"
          >
            <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div className="min-w-0 flex-1 space-y-2">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-base font-semibold text-slate-900">{payment.student_name}</h2>
                  <span className="rounded-full bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700">
                    {REFUND_ELIGIBILITY_LABEL}
                  </span>
                </div>

                <p className="text-sm text-slate-600">
                  {[payment.course_name, payment.product_name].filter(Boolean).join(' · ')}
                </p>

                <dl className="grid gap-1 text-sm text-slate-600 sm:grid-cols-2">
                  <div>
                    <dt className="inline text-slate-500">결제 금액 </dt>
                    <dd className="inline font-medium text-slate-900">
                      {formatKrwAmount(payment.paid_amount_krw)}
                    </dd>
                  </div>
                  <div>
                    <dt className="inline text-slate-500">결제일 </dt>
                    <dd className="inline">
                      {payment.paid_at ? formatDateTimeSeoul(payment.paid_at) : '-'}
                    </dd>
                  </div>
                  <div>
                    <dt className="inline text-slate-500">수강권 </dt>
                    <dd className="inline">{payment.pass_code}</dd>
                  </div>
                  <div>
                    <dt className="inline text-slate-500">수강권 상태 </dt>
                    <dd className="inline">{formatPassStatusLabel(payment.pass_status)}</dd>
                  </div>
                </dl>
              </div>

              <div className="w-full shrink-0 space-y-2 lg:max-w-sm">
                <label className="block text-sm font-medium text-slate-700" htmlFor={`refund-reason-${payment.id}`}>
                  환불 사유
                </label>
                <textarea
                  id={`refund-reason-${payment.id}`}
                  data-testid={`refund-reason-${payment.id}`}
                  rows={3}
                  value={reason}
                  disabled={isPending}
                  onChange={(event) =>
                    setReasonById((prev) => ({ ...prev, [payment.id]: event.target.value }))
                  }
                  placeholder="환불 사유를 입력해 주세요."
                  className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-50"
                />
                <button
                  type="button"
                  data-testid={`refund-confirm-${payment.id}`}
                  disabled={!canConfirm}
                  onClick={() => handleRefund(payment.id)}
                  className="w-full rounded-md bg-brand-600 px-3 py-2 text-sm font-medium text-white hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {isPending ? '환불 처리 중…' : `전액 환불 (${formatKrwAmount(payment.paid_amount_krw)})`}
                </button>
              </div>
            </div>

            {errorById[payment.id] ? (
              <p className="mt-3 text-sm text-red-600" role="alert">
                {errorById[payment.id]}
              </p>
            ) : null}

            {successById[payment.id] ? (
              <p className="mt-3 text-sm text-emerald-700" role="status">
                {successById[payment.id]}
              </p>
            ) : null}
          </article>
        );
      })}
    </div>
  );
}

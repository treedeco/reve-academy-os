import {
  formatDateTimeSeoul,
  formatPaymentStatusLabel,
} from '@/lib/domain/format';
import { formatKrwAmount } from '@/lib/domain/refund';
import {
  formatCascadeStatusLabel,
  formatScheduleRequestStatusLabel,
} from '@/lib/domain/student-history';
import type { StudentOperationalHistory } from '@/lib/domain/types';

function formatOptionalDateTime(iso: string | null): string {
  return iso ? formatDateTimeSeoul(iso) : '-';
}

export function StudentOperationalHistoryPanel({ history }: { history: StudentOperationalHistory }) {
  return (
    <div className="space-y-6" data-testid="student-operational-history">
      <section
        className="rounded-lg border border-slate-200 bg-white p-4"
        data-testid="payment-history-section"
      >
        <h2 className="text-lg font-semibold">결제 이력</h2>
        {history.payments.length === 0 ? (
          <p className="mt-3 text-sm text-slate-600" data-testid="payment-history-empty">
            결제 이력이 없습니다.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-slate-500">
                  <th className="px-2 py-2">일시</th>
                  <th className="px-2 py-2">상태</th>
                  <th className="px-2 py-2">금액</th>
                  <th className="px-2 py-2">Pass</th>
                  <th className="px-2 py-2">과정</th>
                </tr>
              </thead>
              <tbody>
                {history.payments.map((payment) => (
                  <tr key={payment.id} className="border-b border-slate-100" data-testid="payment-history-row">
                    <td className="px-2 py-2">
                      {formatOptionalDateTime(payment.paid_at ?? payment.created_at)}
                    </td>
                    <td className="px-2 py-2">{formatPaymentStatusLabel(payment.status)}</td>
                    <td className="px-2 py-2">{formatKrwAmount(payment.paid_amount_krw)}</td>
                    <td className="px-2 py-2">{payment.pass_code ?? '-'}</td>
                    <td className="px-2 py-2">{payment.course_name ?? '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section
        className="rounded-lg border border-slate-200 bg-white p-4"
        data-testid="refund-history-section"
      >
        <h2 className="text-lg font-semibold">환불 이력</h2>
        {history.refunds.length === 0 ? (
          <p className="mt-3 text-sm text-slate-600" data-testid="refund-history-empty">
            환불 이력이 없습니다.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-slate-500">
                  <th className="px-2 py-2">환불 일시</th>
                  <th className="px-2 py-2">금액</th>
                  <th className="px-2 py-2">Pass</th>
                  <th className="px-2 py-2">과정</th>
                  <th className="px-2 py-2">사유</th>
                </tr>
              </thead>
              <tbody>
                {history.refunds.map((refund) => (
                  <tr key={refund.id} className="border-b border-slate-100" data-testid="refund-history-row">
                    <td className="px-2 py-2">{formatDateTimeSeoul(refund.refunded_at)}</td>
                    <td className="px-2 py-2">{formatKrwAmount(refund.refunded_amount_krw)}</td>
                    <td className="px-2 py-2">{refund.pass_code ?? '-'}</td>
                    <td className="px-2 py-2">{refund.course_name ?? '-'}</td>
                    <td className="px-2 py-2">{refund.reason}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section
        className="rounded-lg border border-slate-200 bg-white p-4"
        data-testid="schedule-request-history-section"
      >
        <h2 className="text-lg font-semibold">일정 변경 요청 이력</h2>
        {history.schedule_requests.length === 0 ? (
          <p className="mt-3 text-sm text-slate-600" data-testid="schedule-request-history-empty">
            일정 변경 요청 이력이 없습니다.
          </p>
        ) : (
          <div className="mt-3 space-y-3">
            {history.schedule_requests.map((request) => (
              <article
                key={request.id}
                className="rounded-md border border-slate-100 bg-slate-50 p-3 text-sm"
                data-testid="schedule-request-history-row"
              >
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <span className="font-medium">
                    {request.lesson_sequence_number}회차 ·{' '}
                    {formatScheduleRequestStatusLabel(request.status)}
                  </span>
                  <span className="text-slate-500">
                    연쇄:{' '}
                    {formatCascadeStatusLabel({
                      status: request.status,
                      applied_at: request.applied_at,
                      cascade_completed_at: request.cascade_completed_at,
                    })}
                  </span>
                </div>
                <dl className="mt-2 grid gap-2 sm:grid-cols-2">
                  <div>
                    <dt className="text-slate-500">현재 일정</dt>
                    <dd>{formatOptionalDateTime(request.lesson_scheduled_at)}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">요청 일정</dt>
                    <dd>{formatOptionalDateTime(request.proposed_scheduled_at)}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">승인 일정</dt>
                    <dd>{formatOptionalDateTime(request.approved_scheduled_at)}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">적용 일시</dt>
                    <dd>{formatOptionalDateTime(request.applied_at)}</dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">Pass / 과정</dt>
                    <dd>
                      {request.pass_code || '-'} · {request.course_name || '-'}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-slate-500">요청 일시</dt>
                    <dd>{formatDateTimeSeoul(request.created_at)}</dd>
                  </div>
                </dl>
                <p className="mt-2 text-slate-700">{request.requested_reason}</p>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

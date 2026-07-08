'use client';

import { useMemo, useState } from 'react';
import {
  applyOwnerScheduleChangeRequest,
  reviewOwnerScheduleChangeRequest,
} from '@/lib/data/owner-queries';
import { formatDateTimeSeoul } from '@/lib/domain/format';
import {
  canApplyScheduleRequest,
  canApproveScheduleRequest,
  defaultApprovedTimeLocal,
  formatLessonStatusLabel,
  formatPassStatusLabel,
  formatScheduleRequestSourceRoleLabel,
  formatScheduleRequestStatusLabel,
  mapScheduleChangeError,
  parseSeoulDateTimeLocal,
  toDateTimeLocalSeoul,
} from '@/lib/domain/schedule-change';
import type { OwnerScheduleChangeRequestRow } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

export function ScheduleChangeRequestsPanel({
  initialRequests,
}: {
  initialRequests: OwnerScheduleChangeRequestRow[];
}) {
  const [requests, setRequests] = useState(initialRequests);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [pendingAction, setPendingAction] = useState<'approve' | 'reject' | 'apply' | null>(null);
  const [approvedTimeById, setApprovedTimeById] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      initialRequests.map((row) => [
        row.id,
        defaultApprovedTimeLocal({
          proposed_scheduled_at: row.proposed_scheduled_at,
          lesson_scheduled_at: row.lesson_scheduled_at,
        }),
      ]),
    ),
  );
  const [approvalNoteById, setApprovalNoteById] = useState<Record<string, string>>({});
  const [rejectionReasonById, setRejectionReasonById] = useState<Record<string, string>>({});
  const [errorById, setErrorById] = useState<Record<string, string>>({});
  const [successById, setSuccessById] = useState<Record<string, string>>({});

  const requestMap = useMemo(() => new Map(requests.map((row) => [row.id, row])), [requests]);

  async function handleApprove(requestId: string) {
    const current = requestMap.get(requestId);
    if (!current || pendingId === requestId || !canApproveScheduleRequest(current.status)) {
      return;
    }

    const decisionReason = approvalNoteById[requestId]?.trim();
    if (!decisionReason) {
      setErrorById((prev) => ({ ...prev, [requestId]: '승인 사유를 입력해 주세요.' }));
      return;
    }

    const approvedIso = parseSeoulDateTimeLocal(approvedTimeById[requestId] ?? '');
    if (!approvedIso) {
      setErrorById((prev) => ({ ...prev, [requestId]: '승인 일시를 입력해 주세요.' }));
      return;
    }

    setPendingId(requestId);
    setPendingAction('approve');
    setErrorById((prev) => ({ ...prev, [requestId]: '' }));
    setSuccessById((prev) => ({ ...prev, [requestId]: '' }));

    try {
      const supabase = createClient();
      const result = await reviewOwnerScheduleChangeRequest(supabase, {
        requestId,
        decision: 'approve',
        expectedRequestUpdatedAt: current.updated_at,
        decisionReason,
        approvedScheduledAt: approvedIso,
      });

      setSuccessById((prev) => ({
        ...prev,
        [requestId]: '요청을 승인했습니다. 적용 버튼으로 수업 일정을 변경할 수 있습니다.',
      }));
      setRequests((prev) =>
        prev.map((row) =>
          row.id === requestId
            ? {
                ...row,
                status: result.new_request_status,
                updated_at: result.request_updated_at,
                approved_scheduled_at: result.approved_scheduled_at,
              }
            : row,
        ),
      );
      if (result.approved_scheduled_at) {
        setApprovedTimeById((prev) => ({
          ...prev,
          [requestId]: toDateTimeLocalSeoul(result.approved_scheduled_at),
        }));
      }
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [requestId]: mapScheduleChangeError(error as { message?: string }),
      }));
    } finally {
      setPendingId(null);
      setPendingAction(null);
    }
  }

  async function handleReject(requestId: string) {
    const current = requestMap.get(requestId);
    if (!current || pendingId === requestId || !canApproveScheduleRequest(current.status)) {
      return;
    }

    const decisionReason = rejectionReasonById[requestId]?.trim();
    if (!decisionReason) {
      setErrorById((prev) => ({ ...prev, [requestId]: '거절 사유를 입력해 주세요.' }));
      return;
    }

    const confirmed = window.confirm(`${current.student_name} 학생의 일정 변경 요청을 거절할까요?`);
    if (!confirmed) {
      return;
    }

    setPendingId(requestId);
    setPendingAction('reject');
    setErrorById((prev) => ({ ...prev, [requestId]: '' }));
    setSuccessById((prev) => ({ ...prev, [requestId]: '' }));

    try {
      const supabase = createClient();
      await reviewOwnerScheduleChangeRequest(supabase, {
        requestId,
        decision: 'reject',
        expectedRequestUpdatedAt: current.updated_at,
        decisionReason,
      });

      setRequests((prev) => prev.filter((row) => row.id !== requestId));
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [requestId]: mapScheduleChangeError(error as { message?: string }),
      }));
    } finally {
      setPendingId(null);
      setPendingAction(null);
    }
  }

  async function handleApply(requestId: string) {
    const current = requestMap.get(requestId);
    if (!current || pendingId === requestId || !canApplyScheduleRequest(current.status, current.applied_at)) {
      return;
    }

    if (!current.approved_scheduled_at) {
      setErrorById((prev) => ({ ...prev, [requestId]: '승인 일시가 없습니다.' }));
      return;
    }

    const confirmed = window.confirm(
      `${current.student_name} 학생 ${current.lesson_sequence_number}회차 수업을\n${formatDateTimeSeoul(current.approved_scheduled_at)}(으)로 변경할까요?`,
    );
    if (!confirmed) {
      return;
    }

    setPendingId(requestId);
    setPendingAction('apply');
    setErrorById((prev) => ({ ...prev, [requestId]: '' }));
    setSuccessById((prev) => ({ ...prev, [requestId]: '' }));

    try {
      const supabase = createClient();
      await applyOwnerScheduleChangeRequest(supabase, {
        requestId,
        expectedRequestUpdatedAt: current.updated_at,
        expectedLessonUpdatedAt: current.lesson_updated_at,
      });

      setSuccessById((prev) => ({
        ...prev,
        [requestId]: '일정 변경을 적용했습니다.',
      }));
      setRequests((prev) => prev.filter((row) => row.id !== requestId));
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [requestId]: mapScheduleChangeError(error as { message?: string }),
      }));
    } finally {
      setPendingId(null);
      setPendingAction(null);
    }
  }

  if (requests.length === 0) {
    return (
      <div
        data-testid="schedule-change-requests-empty"
        className="rounded-lg border border-dashed border-slate-300 bg-white p-8 text-center"
      >
        <p className="font-medium text-slate-900">처리할 일정 변경 요청이 없습니다</p>
        <p className="mt-2 text-sm text-slate-600">
          검토 대기 또는 승인 후 적용 대기 중인 요청만 표시됩니다.
        </p>
      </div>
    );
  }

  return (
    <div data-testid="schedule-change-requests-panel" className="space-y-4">
      {requests.map((request) => {
        const isPending = pendingId === request.id;
        const isSubmitted = canApproveScheduleRequest(request.status);
        const isApproved = canApplyScheduleRequest(request.status, request.applied_at);
        const approvalNote = approvalNoteById[request.id] ?? '';
        const rejectionReason = rejectionReasonById[request.id] ?? '';
        const approvedTime = approvedTimeById[request.id] ?? '';

        return (
          <article
            key={request.id}
            data-testid={`schedule-request-item-${request.id}`}
            className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm lg:p-5"
          >
            <div className="flex flex-col gap-4">
              <div className="min-w-0 flex-1 space-y-2">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-base font-semibold text-slate-900">{request.student_name}</h2>
                  <span className="rounded-full bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700">
                    {formatScheduleRequestStatusLabel(request.status)}
                  </span>
                  <span className="text-xs text-slate-500">
                    요청: {formatScheduleRequestSourceRoleLabel(request.request_source_role)}
                  </span>
                </div>

                <p className="text-sm text-slate-600">
                  {[request.course_name, request.product_name].filter(Boolean).join(' · ')} ·{' '}
                  {request.pass_code} ({formatPassStatusLabel(request.pass_status)})
                </p>

                <dl className="grid gap-1 text-sm text-slate-600 sm:grid-cols-2">
                  <div>
                    <dt className="inline text-slate-500">회차 </dt>
                    <dd className="inline font-medium">{request.lesson_sequence_number}</dd>
                  </div>
                  <div>
                    <dt className="inline text-slate-500">수업 상태 </dt>
                    <dd className="inline">{formatLessonStatusLabel(request.lesson_status)}</dd>
                  </div>
                  <div>
                    <dt className="inline text-slate-500">현재 일시 </dt>
                    <dd className="inline">{formatDateTimeSeoul(request.lesson_scheduled_at)}</dd>
                  </div>
                  <div>
                    <dt className="inline text-slate-500">희망 일시 </dt>
                    <dd className="inline">
                      {request.proposed_scheduled_at
                        ? formatDateTimeSeoul(request.proposed_scheduled_at)
                        : '-'}
                    </dd>
                  </div>
                  {request.approved_scheduled_at ? (
                    <div className="sm:col-span-2">
                      <dt className="inline text-slate-500">승인 일시 </dt>
                      <dd className="inline font-medium text-slate-900">
                        {formatDateTimeSeoul(request.approved_scheduled_at)}
                      </dd>
                    </div>
                  ) : null}
                  <div className="sm:col-span-2">
                    <dt className="inline text-slate-500">요청 사유 </dt>
                    <dd className="inline">{request.requested_reason}</dd>
                  </div>
                </dl>
              </div>

              {isSubmitted ? (
                <div className="grid gap-4 lg:grid-cols-2">
                  <div className="space-y-2 rounded-md border border-slate-200 p-3">
                    <p className="text-sm font-medium text-slate-900">승인</p>
                    <label className="block text-sm text-slate-700" htmlFor={`approved-time-${request.id}`}>
                      승인 일시
                    </label>
                    <input
                      id={`approved-time-${request.id}`}
                      type="datetime-local"
                      data-testid={`approved-time-${request.id}`}
                      value={approvedTime}
                      disabled={isPending}
                      onChange={(event) =>
                        setApprovedTimeById((prev) => ({
                          ...prev,
                          [request.id]: event.target.value,
                        }))
                      }
                      className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-50"
                    />
                    <label className="block text-sm text-slate-700" htmlFor={`approval-note-${request.id}`}>
                      승인 사유
                    </label>
                    <textarea
                      id={`approval-note-${request.id}`}
                      data-testid={`approval-note-${request.id}`}
                      rows={2}
                      value={approvalNote}
                      disabled={isPending}
                      onChange={(event) =>
                        setApprovalNoteById((prev) => ({ ...prev, [request.id]: event.target.value }))
                      }
                      placeholder="승인 사유를 입력해 주세요."
                      className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-50"
                    />
                    <button
                      type="button"
                      data-testid={`approve-${request.id}`}
                      disabled={isPending || !approvalNote.trim() || !approvedTime.trim()}
                      onClick={() => void handleApprove(request.id)}
                      className="w-full rounded-md bg-brand-600 px-3 py-2 text-sm font-medium text-white hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      {isPending && pendingAction === 'approve' ? '승인 처리 중…' : '승인'}
                    </button>
                  </div>

                  <div className="space-y-2 rounded-md border border-slate-200 p-3">
                    <p className="text-sm font-medium text-slate-900">거절</p>
                    <label className="block text-sm text-slate-700" htmlFor={`rejection-reason-${request.id}`}>
                      거절 사유
                    </label>
                    <textarea
                      id={`rejection-reason-${request.id}`}
                      data-testid={`rejection-reason-${request.id}`}
                      rows={4}
                      value={rejectionReason}
                      disabled={isPending}
                      onChange={(event) =>
                        setRejectionReasonById((prev) => ({ ...prev, [request.id]: event.target.value }))
                      }
                      placeholder="거절 사유를 입력해 주세요."
                      className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-50"
                    />
                    <button
                      type="button"
                      data-testid={`reject-${request.id}`}
                      disabled={isPending || !rejectionReason.trim()}
                      onClick={() => void handleReject(request.id)}
                      className="w-full rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-700 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      {isPending && pendingAction === 'reject' ? '거절 처리 중…' : '거절'}
                    </button>
                  </div>
                </div>
              ) : null}

              {isApproved ? (
                <div className="space-y-2 rounded-md border border-emerald-200 bg-emerald-50/40 p-3">
                  <p className="text-sm font-medium text-slate-900">승인된 일정 적용</p>
                  <p className="text-sm text-slate-600">
                    승인 일시:{' '}
                    <span className="font-medium text-slate-900">
                      {request.approved_scheduled_at
                        ? formatDateTimeSeoul(request.approved_scheduled_at)
                        : '-'}
                    </span>
                  </p>
                  <button
                    type="button"
                    data-testid={`apply-${request.id}`}
                    disabled={isPending}
                    onClick={() => void handleApply(request.id)}
                    className="w-full rounded-md bg-emerald-700 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-800 disabled:cursor-not-allowed disabled:opacity-50 lg:max-w-sm"
                  >
                    {isPending && pendingAction === 'apply' ? '적용 중…' : '일정 변경 적용'}
                  </button>
                </div>
              ) : null}
            </div>

            {errorById[request.id] ? (
              <p className="mt-3 text-sm text-red-600" role="alert">
                {errorById[request.id]}
              </p>
            ) : null}

            {successById[request.id] ? (
              <p className="mt-3 text-sm text-emerald-700" role="status">
                {successById[request.id]}
              </p>
            ) : null}
          </article>
        );
      })}
    </div>
  );
}

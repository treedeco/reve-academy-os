'use client';

import { useEffect, useState } from 'react';
import { correctLessonStatus } from '@/lib/data/owner-queries';
import { mapDatabaseError, formatLessonStatus } from '@/lib/domain/format';
import {
  CORRECTION_TARGET_STATUSES,
  formatLessonProgress,
  isDeductibleLessonStatus,
} from '@/lib/domain/lesson-correction';
import type { LessonStatus, LessonTransitionResult, PassUsageSummary } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

type CorrectionLesson = {
  id: string;
  status: LessonStatus;
  sequence_number: number;
  updated_at: string;
  registered_lesson_count: number;
};

export function LessonStatusCorrectionDialog({
  open,
  onClose,
  lesson,
  studentName,
  courseName,
  passUsage,
  onSuccess,
}: {
  open: boolean;
  onClose: () => void;
  lesson: CorrectionLesson;
  studentName: string;
  courseName: string;
  passUsage: Pick<PassUsageSummary, 'used_lesson_count' | 'remaining_lesson_count'> | null;
  onSuccess: (result: LessonTransitionResult) => void;
}) {
  const [proposedStatus, setProposedStatus] = useState<LessonStatus>(CORRECTION_TARGET_STATUSES[0]);
  const [reason, setReason] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (open) {
      setProposedStatus(CORRECTION_TARGET_STATUSES[0]);
      setReason('');
      setError('');
      setPending(false);
    }
  }, [open, lesson.id, lesson.status]);

  if (!open) {
    return null;
  }

  const deductionBefore = isDeductibleLessonStatus(lesson.status);
  const deductionAfter = isDeductibleLessonStatus(proposedStatus);
  const usedBefore = passUsage?.used_lesson_count;
  const remainingBefore = passUsage?.remaining_lesson_count;

  async function handleConfirm() {
    const trimmedReason = reason.trim();
    if (!trimmedReason) {
      setError('정정 사유를 입력해 주세요.');
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      const result = await correctLessonStatus(supabase, {
        lessonId: lesson.id,
        newStatus: proposedStatus,
        expectedUpdatedAt: lesson.updated_at,
        reason: trimmedReason,
      });
      onSuccess(result);
      onClose();
    } catch (caught) {
      setError(mapDatabaseError(caught as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      data-testid="lesson-status-correction-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="lesson-correction-title"
    >
      <div className="w-full max-w-lg rounded-lg border border-slate-200 bg-white p-5 shadow-lg">
        <h2 id="lesson-correction-title" className="text-lg font-semibold">
          상태 정정
        </h2>

        <dl className="mt-4 space-y-2 text-sm">
          <div>
            <dt className="inline text-slate-500">학생 </dt>
            <dd className="inline font-medium">{studentName}</dd>
          </div>
          <div>
            <dt className="inline text-slate-500">과목 </dt>
            <dd className="inline">{courseName}</dd>
          </div>
          <div>
            <dt className="inline text-slate-500">회차 </dt>
            <dd className="inline">
              {formatLessonProgress(lesson.registered_lesson_count, lesson.sequence_number)}
            </dd>
          </div>
          <div>
            <dt className="inline text-slate-500">현재 상태 </dt>
            <dd className="inline">{formatLessonStatus(lesson.status)}</dd>
          </div>
          <div>
            <dt className="inline text-slate-500">정정 상태 </dt>
            <dd className="inline">
              <select
                id="correction-target-status"
                className="ml-1 rounded-md border border-slate-300 px-2 py-1 text-sm"
                value={proposedStatus}
                disabled={pending}
                onChange={(event) => setProposedStatus(event.target.value as LessonStatus)}
                data-testid="correction-target-status"
              >
                {CORRECTION_TARGET_STATUSES.map((status) => (
                  <option key={status} value={status}>
                    {formatLessonStatus(status)}
                  </option>
                ))}
              </select>
            </dd>
          </div>
          <div>
            <dt className="inline text-slate-500">차감 </dt>
            <dd className="inline">
              {deductionBefore ? '차감됨' : '미차감'} → {deductionAfter ? '차감됨' : '미차감'}
            </dd>
          </div>
          {usedBefore !== undefined && remainingBefore !== undefined ? (
            <div>
              <dt className="inline text-slate-500">회차권 사용/잔여 </dt>
              <dd className="inline">
                {usedBefore}/{remainingBefore} →{' '}
                {deductionBefore && !deductionAfter
                  ? `${usedBefore - 1}/${remainingBefore + 1}`
                  : !deductionBefore && deductionAfter
                    ? `${usedBefore + 1}/${remainingBefore - 1}`
                    : `${usedBefore}/${remainingBefore}`}
              </dd>
            </div>
          ) : null}
        </dl>

        <label className="mt-4 block text-sm font-medium text-slate-700" htmlFor="correction-reason">
          정정 사유 (필수)
        </label>
        <input
          id="correction-reason"
          type="text"
          className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          value={reason}
          disabled={pending}
          onChange={(event) => setReason(event.target.value)}
          data-testid="correction-reason"
        />

        {pending ? <p className="mt-3 text-sm text-slate-500">저장 중…</p> : null}
        {error ? (
          <p className="mt-3 text-sm text-red-600" role="alert" data-testid="correction-error">
            {error}
          </p>
        ) : null}

        <div className="mt-5 flex justify-end gap-2">
          <button
            type="button"
            className="rounded-md border border-slate-300 px-4 py-2 text-sm"
            disabled={pending}
            onClick={onClose}
            data-testid="correction-cancel"
          >
            취소
          </button>
          <button
            type="button"
            className="rounded-md bg-brand-700 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
            disabled={pending}
            onClick={() => void handleConfirm()}
            data-testid="correction-confirm"
          >
            정정 확인
          </button>
        </div>
      </div>
    </div>
  );
}

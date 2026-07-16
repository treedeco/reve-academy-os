'use client';

import { useState } from 'react';
import { LessonRescheduleDialog } from '@/components/owner/lesson-reschedule-dialog';
import { LessonStatusCorrectionDialog } from '@/components/owner/lesson-status-correction-dialog';
import { transitionLessonStatus } from '@/lib/data/owner-queries';
import { mapDatabaseError, formatLessonStatus } from '@/lib/domain/format';
import {
  canOrdinaryTransition,
  isDeductibleLessonStatus,
  isScheduleChangeableLessonStatus,
} from '@/lib/domain/lesson-correction';
import {
  ORDINARY_TRANSITION_TARGETS,
  STATUS_REQUIRES_REASON,
  type DirectRescheduleResult,
  type LessonStatus,
  type LessonTransitionResult,
  type OwnerLessonOperationsRow,
  type PassUsageSummary,
} from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

export function LessonOperationsPanel({
  lesson,
  passUsage,
  onLessonUpdated,
  onPassUsageUpdated,
}: {
  lesson: OwnerLessonOperationsRow;
  passUsage: PassUsageSummary | null;
  onLessonUpdated: (lessonId: string, patch: Partial<OwnerLessonOperationsRow>) => void;
  onPassUsageUpdated?: (usage: PassUsageSummary) => void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');
  const [reason, setReason] = useState('');
  const [correctionOpen, setCorrectionOpen] = useState(false);
  const [rescheduleOpen, setRescheduleOpen] = useState(false);

  const ordinaryOptions = ORDINARY_TRANSITION_TARGETS[lesson.status] ?? [];
  const showOrdinarySelect = canOrdinaryTransition(lesson.status) && ordinaryOptions.length > 0;
  const showCorrection = isDeductibleLessonStatus(lesson.status);
  const showReschedule = isScheduleChangeableLessonStatus(lesson.status);

  const passUsageForLesson =
    passUsage && passUsage.pass_id === lesson.pass_id
      ? {
          used_lesson_count: passUsage.used_lesson_count,
          remaining_lesson_count: passUsage.remaining_lesson_count,
        }
      : null;

  async function handleStatusChange(nextStatus: LessonStatus) {
    if (pending || nextStatus === lesson.status) {
      return;
    }

    const trimmedReason = reason.trim();
    if (STATUS_REQUIRES_REASON.has(nextStatus) && !trimmedReason) {
      setError('변경 사유를 입력해 주세요.');
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      const result = await transitionLessonStatus(supabase, {
        lessonId: lesson.id,
        newStatus: nextStatus,
        expectedUpdatedAt: lesson.updated_at,
        reason: trimmedReason || undefined,
      });

      onLessonUpdated(lesson.id, {
        status: result.new_status as LessonStatus,
        updated_at: result.lesson_updated_at,
      });

      if (onPassUsageUpdated && passUsage && passUsage.pass_id === result.pass_id) {
        onPassUsageUpdated({
          ...passUsage,
          pass_status: result.pass_status as PassUsageSummary['pass_status'],
          registered_lesson_count: result.registered_lesson_count,
          used_lesson_count: result.used_lesson_count,
          remaining_lesson_count: result.remaining_lesson_count,
          next_lesson_at: result.next_lesson_at,
        });
      }
    } catch (caught) {
      setError(mapDatabaseError(caught as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  function handleCorrectionSuccess(result: LessonTransitionResult) {
    onLessonUpdated(lesson.id, {
      status: result.new_status as LessonStatus,
      updated_at: result.lesson_updated_at,
    });

    if (onPassUsageUpdated && passUsage && passUsage.pass_id === result.pass_id) {
      onPassUsageUpdated({
        ...passUsage,
        pass_status: result.pass_status as PassUsageSummary['pass_status'],
        registered_lesson_count: result.registered_lesson_count,
        used_lesson_count: result.used_lesson_count,
        remaining_lesson_count: result.remaining_lesson_count,
        next_lesson_at: result.next_lesson_at,
      });
    }
  }

  function handleRescheduleSuccess(result: DirectRescheduleResult) {
    onLessonUpdated(lesson.id, {
      status: result.new_lesson_status as LessonStatus,
      scheduled_at: result.new_scheduled_at,
      updated_at: result.lesson_updated_at,
      pass_updated_at: result.pass_updated_at,
    });
  }

  if (!showOrdinarySelect && !showCorrection && !showReschedule) {
    return <span className="text-sm text-slate-500">—</span>;
  }

  return (
    <div className="space-y-2" data-testid={`lesson-operations-${lesson.id}`}>
      {showOrdinarySelect ? (
        <>
          <select
            className="w-full min-w-[8rem] rounded-md border border-slate-300 px-2 py-1 text-sm"
            disabled={pending}
            value={lesson.status}
            aria-label="상태 변경"
            data-testid={`lesson-status-select-${lesson.id}`}
            onChange={(event) => void handleStatusChange(event.target.value as LessonStatus)}
          >
            <option value={lesson.status}>{formatLessonStatus(lesson.status)}</option>
            {ordinaryOptions.map((status) => (
              <option key={status} value={status}>
                {formatLessonStatus(status)}
              </option>
            ))}
          </select>

          {ordinaryOptions.some((status) => STATUS_REQUIRES_REASON.has(status)) ? (
            <input
              type="text"
              placeholder="변경 사유 (필요 시)"
              className="w-full rounded-md border border-slate-300 px-2 py-1 text-sm"
              value={reason}
              disabled={pending}
              onChange={(event) => setReason(event.target.value)}
              data-testid={`lesson-status-reason-${lesson.id}`}
            />
          ) : null}
        </>
      ) : null}

      {showCorrection ? (
        <button
          type="button"
          className="w-full rounded-md border border-slate-300 px-2 py-1 text-sm hover:bg-slate-50 disabled:opacity-50"
          disabled={pending}
          onClick={() => setCorrectionOpen(true)}
          data-testid={`lesson-correction-open-${lesson.id}`}
        >
          상태 정정
        </button>
      ) : null}

      {showReschedule ? (
        <button
          type="button"
          className="w-full rounded-md border border-slate-300 px-2 py-1 text-sm hover:bg-slate-50 disabled:opacity-50"
          disabled={pending}
          onClick={() => setRescheduleOpen(true)}
          data-testid={`lesson-reschedule-open-${lesson.id}`}
        >
          일시 변경
        </button>
      ) : null}

      {pending ? <p className="text-xs text-slate-500">저장 중…</p> : null}
      {error ? (
        <p className="text-xs text-red-600" role="alert">
          {error}
        </p>
      ) : null}

      <LessonStatusCorrectionDialog
        open={correctionOpen}
        onClose={() => setCorrectionOpen(false)}
        lesson={lesson}
        studentName={lesson.student_name}
        courseName={lesson.course_name}
        passUsage={passUsageForLesson}
        onSuccess={handleCorrectionSuccess}
      />

      <LessonRescheduleDialog
        open={rescheduleOpen}
        onClose={() => setRescheduleOpen(false)}
        lesson={lesson}
        studentName={lesson.student_name}
        courseName={lesson.course_name}
        onSuccess={handleRescheduleSuccess}
      />
    </div>
  );
}

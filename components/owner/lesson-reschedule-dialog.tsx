'use client';

import { useEffect, useState } from 'react';
import { directRescheduleLesson } from '@/lib/data/owner-queries';
import {
  parseLocalTimeToMinutes,
  validateAcademyLessonWindow,
} from '@/lib/domain/academy-hours';
import { formatDateTimeSeoul, mapDatabaseError } from '@/lib/domain/format';
import { formatLessonProgress } from '@/lib/domain/lesson-correction';
import { parseSeoulDateTimeLocal, toDateTimeLocalSeoul } from '@/lib/domain/schedule-change';
import type { DirectRescheduleResult, LessonStatus } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

type RescheduleLesson = {
  id: string;
  status: LessonStatus;
  sequence_number: number;
  scheduled_at: string;
  updated_at: string;
  registered_lesson_count: number;
  duration_minutes: number;
  pass_id: string;
  pass_updated_at: string;
};

export function LessonRescheduleDialog({
  open,
  onClose,
  lesson,
  studentName,
  courseName,
  onSuccess,
}: {
  open: boolean;
  onClose: () => void;
  lesson: RescheduleLesson;
  studentName: string;
  courseName: string;
  onSuccess: (result: DirectRescheduleResult) => void;
}) {
  const [dateValue, setDateValue] = useState('');
  const [timeValue, setTimeValue] = useState('');
  const [cascade, setCascade] = useState(false);
  const [reason, setReason] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (open) {
      const local = toDateTimeLocalSeoul(lesson.scheduled_at);
      const [date, time] = local.split('T');
      setDateValue(date ?? '');
      setTimeValue(time ?? '');
      setCascade(false);
      setReason('');
      setError('');
      setPending(false);
    }
  }, [open, lesson.id, lesson.scheduled_at]);

  if (!open) {
    return null;
  }

  async function handleConfirm() {
    const trimmedReason = reason.trim();
    if (!trimmedReason) {
      setError('변경 사유를 입력해 주세요.');
      return;
    }

    if (!dateValue || !timeValue) {
      setError('날짜와 시간을 입력해 주세요.');
      return;
    }

    const startMinutes = parseLocalTimeToMinutes(timeValue);
    const hoursError = validateAcademyLessonWindow(startMinutes, lesson.duration_minutes);
    if (hoursError) {
      setError(hoursError);
      return;
    }

    const newScheduledAt = parseSeoulDateTimeLocal(`${dateValue}T${timeValue}`);
    if (!newScheduledAt) {
      setError('올바른 날짜와 시간을 입력해 주세요.');
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      const result = await directRescheduleLesson(supabase, {
        lessonId: lesson.id,
        newScheduledAt,
        expectedLessonUpdatedAt: lesson.updated_at,
        reason: trimmedReason,
        cascade,
        expectedPassUpdatedAt: cascade ? lesson.pass_updated_at : null,
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
      data-testid="lesson-reschedule-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="lesson-reschedule-title"
    >
      <div className="w-full max-w-lg rounded-lg border border-slate-200 bg-white p-5 shadow-lg">
        <h2 id="lesson-reschedule-title" className="text-lg font-semibold">
          일시 변경
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
            <dt className="inline text-slate-500">현재 일시 </dt>
            <dd className="inline">{formatDateTimeSeoul(lesson.scheduled_at)}</dd>
          </div>
        </dl>

        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <div>
            <label className="block text-sm font-medium text-slate-700" htmlFor="reschedule-date">
              날짜
            </label>
            <input
              id="reschedule-date"
              type="date"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
              value={dateValue}
              disabled={pending}
              onChange={(event) => setDateValue(event.target.value)}
              data-testid="reschedule-date"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700" htmlFor="reschedule-time">
              시간
            </label>
            <input
              id="reschedule-time"
              type="time"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
              value={timeValue}
              disabled={pending}
              onChange={(event) => setTimeValue(event.target.value)}
              data-testid="reschedule-time"
            />
          </div>
        </div>

        <label className="mt-4 flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={cascade}
            disabled={pending}
            onChange={(event) => setCascade(event.target.checked)}
            data-testid="reschedule-cascade"
          />
          이후 수업 연쇄 재배치
        </label>

        <label className="mt-4 block text-sm font-medium text-slate-700" htmlFor="reschedule-reason">
          변경 사유 (필수)
        </label>
        <input
          id="reschedule-reason"
          type="text"
          className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          value={reason}
          disabled={pending}
          onChange={(event) => setReason(event.target.value)}
          data-testid="reschedule-reason"
        />

        {pending ? <p className="mt-3 text-sm text-slate-500">저장 중…</p> : null}
        {error ? (
          <p className="mt-3 text-sm text-red-600" role="alert" data-testid="reschedule-error">
            {error}
          </p>
        ) : null}

        <div className="mt-5 flex justify-end gap-2">
          <button
            type="button"
            className="rounded-md border border-slate-300 px-4 py-2 text-sm"
            disabled={pending}
            onClick={onClose}
            data-testid="reschedule-cancel"
          >
            취소
          </button>
          <button
            type="button"
            className="rounded-md bg-brand-700 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
            disabled={pending}
            onClick={() => void handleConfirm()}
            data-testid="reschedule-confirm"
          >
            변경 확인
          </button>
        </div>
      </div>
    </div>
  );
}

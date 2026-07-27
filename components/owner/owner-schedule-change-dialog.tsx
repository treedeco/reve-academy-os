'use client';

import { useEffect, useMemo, useState } from 'react';
import { ScheduleTimeSelect } from '@/components/owner/schedule-time-select';
import {
  changeFixedPassSchedule,
  changeSingleLessonSchedule,
  countFutureEligibleLessons,
} from '@/lib/data/owner-schedule-edit';
import { loadOwnerEnrollmentCatalog } from '@/lib/data/owner-enrollment';
import {
  formatFixedWeeklyScheduleLabel,
  formatFixedWeeklySchedulesLabel,
  formatSeoulDateTimeShortWithWeekday,
  formatSeoulDateTimeWithWeekday,
  formatSeoulWeekdayLabel,
  mapOwnerScheduleEditError,
  OWNER_SCHEDULE_CHANGE_MODE_LABELS,
  scheduleSlotsFromPassSlots,
  validateRecurringScheduleChange,
  validateSingleScheduleChange,
  type OwnerScheduleChangeMode,
} from '@/lib/domain/owner-schedule-edit';
import { parseSeoulDateTimeLocal, toDateTimeLocalSeoul } from '@/lib/domain/schedule-change';
import { isScheduleChangeableLessonStatus } from '@/lib/domain/lesson-correction';
import type {
  DirectRescheduleResult,
  EnrollmentScheduleSlotInput,
  FixedPassScheduleChangeResult,
  LessonStatus,
} from '@/lib/domain/types';
import { WEEKDAY_LABELS } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

type ScheduleLessonContext = {
  id: string;
  scheduled_at: string;
  updated_at: string;
  status: LessonStatus;
  duration_minutes: number;
  pass_id: string;
  pass_updated_at: string;
  sequence_number: number;
  registered_lesson_count: number;
};

type ScheduleSlotContext = {
  id: string;
  weekday: number;
  local_start_time: string;
  duration_minutes: number;
  teacher_id: string;
  teacher_name: string;
};

type DialogStep = 'mode' | 'form' | 'confirm';

function formatTodayDateInput(): string {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(new Date());
}

export function OwnerScheduleChangeDialog({
  open,
  onClose,
  studentName,
  courseName,
  teacherName,
  remainingLessonCount,
  lesson,
  scheduleSlots,
  weeklyFrequency,
  onSuccess,
  initialMode = null,
}: {
  open: boolean;
  onClose: () => void;
  studentName: string;
  courseName: string;
  teacherName: string;
  remainingLessonCount: number | null;
  lesson: ScheduleLessonContext;
  scheduleSlots: ScheduleSlotContext[];
  weeklyFrequency: number;
  onSuccess: (result: {
    mode: OwnerScheduleChangeMode;
    single?: DirectRescheduleResult;
    recurring?: FixedPassScheduleChangeResult;
  }) => void;
  initialMode?: OwnerScheduleChangeMode | null;
}) {
  const [step, setStep] = useState<DialogStep>(initialMode ? 'form' : 'mode');
  const [mode, setMode] = useState<OwnerScheduleChangeMode | null>(initialMode);
  const [dateValue, setDateValue] = useState('');
  const [timeValue, setTimeValue] = useState('');
  const [effectiveDate, setEffectiveDate] = useState(formatTodayDateInput());
  const [slotInputs, setSlotInputs] = useState<EnrollmentScheduleSlotInput[]>([]);
  const [teachers, setTeachers] = useState<Array<{ id: string; name: string }>>([]);
  const [futureLessonCount, setFutureLessonCount] = useState<number | null>(null);
  const [reason, setReason] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');

  const fixedScheduleLabel = useMemo(
    () => formatFixedWeeklySchedulesLabel(scheduleSlots),
    [scheduleSlots],
  );

  const canChangeLesson = isScheduleChangeableLessonStatus(lesson.status);

  useEffect(() => {
    if (!open) {
      return;
    }

    const local = toDateTimeLocalSeoul(lesson.scheduled_at);
    const [date, time] = local.split('T');
    setStep(initialMode ? 'form' : 'mode');
    setMode(initialMode);
    setDateValue(date ?? '');
    setTimeValue(time ?? '');
    setEffectiveDate(formatTodayDateInput());
    setSlotInputs(scheduleSlotsFromPassSlots(scheduleSlots));
    setReason('');
    setError('');
    setPending(false);
    setFutureLessonCount(null);

    void (async () => {
      const supabase = createClient();
      const catalog = await loadOwnerEnrollmentCatalog(supabase);
      if (catalog.status === 'ready') {
        setTeachers(catalog.catalog.teachers.map((row) => ({ id: row.id, name: row.name })));
      }
    })();
  }, [open, lesson.id, lesson.scheduled_at, initialMode, scheduleSlots]);

  useEffect(() => {
    if (!open || mode !== 'recurring' || !lesson.pass_id || !effectiveDate) {
      return;
    }

    void (async () => {
      try {
        const supabase = createClient();
        const count = await countFutureEligibleLessons(supabase, lesson.pass_id, effectiveDate);
        setFutureLessonCount(count);
      } catch {
        setFutureLessonCount(null);
      }
    })();
  }, [open, mode, lesson.pass_id, effectiveDate]);

  if (!open) {
    return null;
  }

  const newSingleScheduledAt =
    dateValue && timeValue ? parseSeoulDateTimeLocal(`${dateValue}T${timeValue}`) : null;

  const newFixedScheduleLabel =
    slotInputs.length > 0
      ? slotInputs
          .map((slot) =>
            formatFixedWeeklyScheduleLabel({ weekday: slot.weekday, localTime: slot.localTime }),
          )
          .join(' · ')
      : fixedScheduleLabel;

  function handleSelectMode(nextMode: OwnerScheduleChangeMode) {
    if (nextMode === 'single' && !canChangeLesson) {
      setError('일정을 변경할 수 없는 수업입니다.');
      return;
    }
    setMode(nextMode);
    setStep('form');
    setError('');
  }

  function handleProceedToConfirm() {
    if (!mode) {
      setError('변경 방식을 선택해 주세요.');
      return;
    }

    if (mode === 'single') {
      const validationError = validateSingleScheduleChange({
        dateKey: dateValue,
        timeValue,
        durationMinutes: lesson.duration_minutes,
        reason,
      });
      if (validationError) {
        setError(validationError);
        return;
      }
    } else {
      const validationError = validateRecurringScheduleChange({
        effectiveDateKey: effectiveDate,
        slots: slotInputs,
        reason,
        weeklyFrequency,
      });
      if (validationError) {
        setError(validationError);
        return;
      }
    }

    setError('');
    setStep('confirm');
  }

  async function handleSave() {
    if (!mode) {
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();

      if (mode === 'single') {
        const validationError = validateSingleScheduleChange({
          dateKey: dateValue,
          timeValue,
          durationMinutes: lesson.duration_minutes,
          reason,
        });
        if (validationError) {
          setError(validationError);
          return;
        }

        const newScheduledAt = parseSeoulDateTimeLocal(`${dateValue}T${timeValue}`);
        if (!newScheduledAt) {
          setError('올바른 날짜와 시간을 선택해 주세요.');
          return;
        }

        const result = await changeSingleLessonSchedule(supabase, {
          lessonId: lesson.id,
          newScheduledAt,
          expectedLessonUpdatedAt: lesson.updated_at,
          reason: reason.trim(),
        });
        onSuccess({ mode: 'single', single: result });
        onClose();
        return;
      }

      const result = await changeFixedPassSchedule(supabase, {
        passId: lesson.pass_id,
        expectedPassUpdatedAt: lesson.pass_updated_at,
        effectiveFrom: effectiveDate,
        slots: slotInputs,
        reason: reason.trim(),
      });
      onSuccess({ mode: 'recurring', recurring: result });
      onClose();
    } catch (caught) {
      setError(mapOwnerScheduleEditError(caught as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      data-testid="owner-schedule-change-dialog"
      role="dialog"
      aria-modal="true"
    >
      <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-lg border border-slate-200 bg-white p-5 shadow-lg">
        <h2 className="text-lg font-semibold">수업 일정 변경</h2>

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
            <dt className="inline text-slate-500">강사 </dt>
            <dd className="inline">{teacherName}</dd>
          </div>
          <div>
            <dt className="inline text-slate-500">현재 수업 </dt>
            <dd className="inline">{formatSeoulDateTimeWithWeekday(lesson.scheduled_at)}</dd>
          </div>
          <div>
            <dt className="inline text-slate-500">고정 일정 </dt>
            <dd className="inline">{fixedScheduleLabel}</dd>
          </div>
          {remainingLessonCount !== null ? (
            <div>
              <dt className="inline text-slate-500">잔여 회차 </dt>
              <dd className="inline">{remainingLessonCount}</dd>
            </div>
          ) : null}
        </dl>

        {step === 'mode' ? (
          <div className="mt-5 space-y-3">
            <p className="text-sm font-medium text-slate-700">변경 방식을 선택해 주세요.</p>
            <button
              type="button"
              className="w-full rounded-md border border-slate-300 px-4 py-3 text-left text-sm hover:bg-slate-50 disabled:opacity-50"
              disabled={!canChangeLesson}
              onClick={() => handleSelectMode('single')}
              data-testid="schedule-change-mode-single"
            >
              {OWNER_SCHEDULE_CHANGE_MODE_LABELS.single}
            </button>
            <button
              type="button"
              className="w-full rounded-md border border-slate-300 px-4 py-3 text-left text-sm hover:bg-slate-50"
              onClick={() => handleSelectMode('recurring')}
              data-testid="schedule-change-mode-recurring"
            >
              {OWNER_SCHEDULE_CHANGE_MODE_LABELS.recurring}
            </button>
          </div>
        ) : null}

        {step === 'form' && mode === 'single' ? (
          <div className="mt-5 space-y-4">
            <p className="text-sm font-medium text-brand-700">{OWNER_SCHEDULE_CHANGE_MODE_LABELS.single}</p>
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <label className="block text-sm font-medium text-slate-700" htmlFor="schedule-change-date">
                  수업 날짜
                </label>
                <input
                  id="schedule-change-date"
                  type="date"
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                  value={dateValue}
                  disabled={pending}
                  onChange={(event) => setDateValue(event.target.value)}
                  data-testid="schedule-change-date"
                />
                {dateValue ? (
                  <p className="mt-1 text-xs text-slate-500">{formatSeoulWeekdayLabel(dateValue)}요일</p>
                ) : null}
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-700" htmlFor="schedule-change-time">
                  시작 시간
                </label>
                <ScheduleTimeSelect
                  id="schedule-change-time"
                  value={timeValue}
                  disabled={pending}
                  onChange={setTimeValue}
                  testId="schedule-change-time"
                />
              </div>
            </div>
          </div>
        ) : null}

        {step === 'form' && mode === 'recurring' ? (
          <div className="mt-5 space-y-4">
            <p className="text-sm font-medium text-brand-700">
              {OWNER_SCHEDULE_CHANGE_MODE_LABELS.recurring}
            </p>
            <div>
              <label className="block text-sm font-medium text-slate-700" htmlFor="schedule-effective-date">
                적용 시작일
              </label>
              <input
                id="schedule-effective-date"
                type="date"
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                value={effectiveDate}
                disabled={pending}
                onChange={(event) => setEffectiveDate(event.target.value)}
                data-testid="schedule-effective-date"
              />
              {effectiveDate ? (
                <p className="mt-1 text-xs text-slate-500">{formatSeoulWeekdayLabel(effectiveDate)}요일</p>
              ) : null}
            </div>
            {slotInputs.map((slot, index) => (
              <div key={slot.slotOrder} className="rounded-md border border-slate-200 p-3">
                <p className="text-sm font-medium">고정 일정 {slot.slotOrder}</p>
                <div className="mt-3 grid gap-3 sm:grid-cols-2">
                  <div>
                    <label className="block text-sm text-slate-600" htmlFor={`slot-weekday-${index}`}>
                      요일
                    </label>
                    <select
                      id={`slot-weekday-${index}`}
                      className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                      value={slot.weekday}
                      disabled={pending}
                      onChange={(event) => {
                        const weekday = Number.parseInt(event.target.value, 10);
                        setSlotInputs((prev) =>
                          prev.map((row, rowIndex) =>
                            rowIndex === index ? { ...row, weekday } : row,
                          ),
                        );
                      }}
                      data-testid={`schedule-slot-weekday-${index}`}
                    >
                      {WEEKDAY_LABELS.map((label, weekday) => (
                        <option key={label} value={weekday}>
                          {label}요일
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm text-slate-600" htmlFor={`slot-time-${index}`}>
                      시작 시간
                    </label>
                    <ScheduleTimeSelect
                      id={`slot-time-${index}`}
                      value={slot.localTime}
                      disabled={pending}
                      onChange={(localTime) => {
                        setSlotInputs((prev) =>
                          prev.map((row, rowIndex) =>
                            rowIndex === index ? { ...row, localTime } : row,
                          ),
                        );
                      }}
                      testId={`schedule-slot-time-${index}`}
                    />
                  </div>
                  <div className="sm:col-span-2">
                    <label className="block text-sm text-slate-600" htmlFor={`slot-teacher-${index}`}>
                      강사
                    </label>
                    <select
                      id={`slot-teacher-${index}`}
                      className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                      value={slot.teacherId}
                      disabled={pending}
                      onChange={(event) => {
                        const teacherId = event.target.value;
                        setSlotInputs((prev) =>
                          prev.map((row, rowIndex) =>
                            rowIndex === index ? { ...row, teacherId } : row,
                          ),
                        );
                      }}
                      data-testid={`schedule-slot-teacher-${index}`}
                    >
                      <option value="">강사 선택</option>
                      {teachers.map((teacher) => (
                        <option key={teacher.id} value={teacher.id}>
                          {teacher.name}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>
            ))}
            {futureLessonCount !== null ? (
              <p className="text-sm text-slate-600" data-testid="schedule-future-lesson-count">
                변경 대상: 미진행 수업 {futureLessonCount}건
              </p>
            ) : null}
          </div>
        ) : null}

        {step === 'confirm' ? (
          <div className="mt-5 rounded-md bg-slate-50 p-4 text-sm" data-testid="schedule-change-summary">
            {mode === 'single' && newSingleScheduledAt ? (
              <>
                <p>
                  기존: {formatSeoulDateTimeShortWithWeekday(lesson.scheduled_at)}
                </p>
                <p>변경: {formatSeoulDateTimeShortWithWeekday(newSingleScheduledAt)}</p>
                <p>적용 범위: 이번 수업만</p>
              </>
            ) : null}
            {mode === 'recurring' ? (
              <>
                <p>기존 고정 일정: {fixedScheduleLabel}</p>
                <p>새 고정 일정: {newFixedScheduleLabel}</p>
                <p>적용 시작일: {effectiveDate}</p>
                <p>변경 대상: 미진행 수업 {futureLessonCount ?? 0}건</p>
              </>
            ) : null}
          </div>
        ) : null}

        {(step === 'form' || step === 'confirm') && mode ? (
          <div className="mt-4">
            <label className="block text-sm font-medium text-slate-700" htmlFor="schedule-change-reason">
              변경 사유 (필수)
            </label>
            <input
              id="schedule-change-reason"
              type="text"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
              value={reason}
              disabled={pending}
              onChange={(event) => setReason(event.target.value)}
              data-testid="schedule-change-reason"
            />
          </div>
        ) : null}

        {pending ? <p className="mt-3 text-sm text-slate-500">저장 중…</p> : null}
        {error ? (
          <p className="mt-3 text-sm text-red-600" role="alert" data-testid="schedule-change-error">
            {error}
          </p>
        ) : null}

        <div className="mt-5 flex justify-end gap-2">
          <button
            type="button"
            className="rounded-md border border-slate-300 px-4 py-2 text-sm"
            disabled={pending}
            onClick={() => {
              if (step === 'confirm') {
                setStep('form');
                return;
              }
              onClose();
            }}
            data-testid="schedule-change-cancel"
          >
            {step === 'confirm' ? '뒤로' : '취소'}
          </button>
          {step === 'form' ? (
            <button
              type="button"
              className="rounded-md bg-brand-700 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
              disabled={pending}
              onClick={() => handleProceedToConfirm()}
              data-testid="schedule-change-next"
            >
              확인 요약
            </button>
          ) : null}
          {step === 'confirm' ? (
            <button
              type="button"
              className="rounded-md bg-brand-700 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
              disabled={pending}
              onClick={() => void handleSave()}
              data-testid="schedule-change-save"
            >
              저장
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

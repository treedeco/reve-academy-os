'use client';

import Link from 'next/link';
import { formatLessonStatus } from '@/lib/domain/format';
import type { WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import { formatMinutesAsLocalTime } from '@/lib/domain/academy-hours';

export function WeeklyTimetableLessonCard({
  lesson,
  compact = false,
  selected = false,
  hasTimeOverlap = false,
  onSelect,
  onScheduleChange,
}: {
  lesson: WeeklyTimetableLesson;
  compact?: boolean;
  selected?: boolean;
  hasTimeOverlap?: boolean;
  onSelect?: (lesson: WeeklyTimetableLesson) => void;
  onScheduleChange?: (lesson: WeeklyTimetableLesson) => void;
}) {
  const startLabel = formatMinutesAsLocalTime(lesson.local_start_minutes);
  const title = `${startLabel} ${lesson.student_name} ${lesson.lesson_progress} ${formatLessonStatus(lesson.lesson_status)}`;
  const isVeryShort = compact && lesson.duration_minutes <= 30;

  return (
    <article
      className={`h-full min-h-0 overflow-hidden rounded-md border bg-white shadow-sm ${
        compact ? 'flex flex-col gap-0.5 px-2 py-1.5' : 'space-y-1 p-3'
      } ${
        hasTimeOverlap
          ? 'border-amber-400 ring-1 ring-amber-300'
          : selected
            ? 'border-brand-600 ring-1 ring-brand-600'
            : 'border-slate-300'
      }`}
      data-testid={`weekly-timetable-lesson-${lesson.lesson_id}`}
      data-time-overlap={hasTimeOverlap ? 'true' : 'false'}
      title={title}
    >
      {hasTimeOverlap ? (
        <p
          className="shrink-0 text-[10px] font-semibold leading-snug text-amber-800"
          data-testid={`weekly-timetable-overlap-badge-${lesson.lesson_id}`}
        >
          시간 겹침
        </p>
      ) : null}
      <p className="shrink-0 text-[11px] font-semibold tabular-nums leading-snug text-slate-700">
        {startLabel}
      </p>
      <p
        className={`min-w-0 truncate font-semibold leading-snug text-slate-900 ${
          compact ? 'text-sm' : 'text-base'
        }`}
      >
        {lesson.student_name}
      </p>
      {!compact ? (
        <>
          <p className="break-words text-xs leading-snug text-slate-500">{lesson.teacher_name}</p>
          <p className="break-words text-xs leading-snug text-slate-500">{lesson.course_name}</p>
        </>
      ) : null}
      {!isVeryShort ? (
        <p
          className="mt-0.5 shrink-0 text-[11px] font-medium leading-snug text-brand-700"
          data-testid="lesson-progress-label"
        >
          {lesson.lesson_progress}
        </p>
      ) : null}
      {!compact ? (
        <p className="text-xs leading-snug text-slate-500">{formatLessonStatus(lesson.lesson_status)}</p>
      ) : null}
      {!isVeryShort ? (
        <div
          className={`mt-auto flex min-h-0 flex-wrap gap-x-2 gap-y-0.5 overflow-hidden ${
            compact ? 'pt-0.5' : 'pt-1'
          }`}
        >
          {onSelect ? (
            <button
              type="button"
              className="shrink-0 text-[11px] leading-snug text-brand-700 underline"
              onClick={() => onSelect(lesson)}
              data-testid={`weekly-lesson-detail-open-${lesson.lesson_id}`}
            >
              상세
            </button>
          ) : (
            <Link
              href={`/students/${lesson.student_id}`}
              prefetch={false}
              className="shrink-0 text-[11px] leading-snug text-brand-700 underline"
            >
              상세
            </Link>
          )}
          {onScheduleChange ? (
            <button
              type="button"
              className="shrink-0 text-[11px] leading-snug text-brand-700 underline"
              onClick={() => onScheduleChange(lesson)}
              data-testid={`weekly-lesson-schedule-open-${lesson.lesson_id}`}
            >
              일정 변경
            </button>
          ) : null}
        </div>
      ) : null}
    </article>
  );
}

'use client';

import Link from 'next/link';
import { formatLessonStatus } from '@/lib/domain/format';
import type { WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import { formatMinutesAsLocalTime } from '@/lib/domain/academy-hours';

export function WeeklyTimetableLessonCard({
  lesson,
  compact = false,
  selected = false,
  onSelect,
  onScheduleChange,
}: {
  lesson: WeeklyTimetableLesson;
  compact?: boolean;
  selected?: boolean;
  onSelect?: (lesson: WeeklyTimetableLesson) => void;
  onScheduleChange?: (lesson: WeeklyTimetableLesson) => void;
}) {
  const startLabel = formatMinutesAsLocalTime(lesson.local_start_minutes);
  const title = `${startLabel} ${lesson.student_name} ${lesson.lesson_progress} ${formatLessonStatus(lesson.lesson_status)}`;
  const isVeryShort = compact && lesson.duration_minutes <= 30;

  return (
    <article
      className={`h-full min-h-0 overflow-hidden rounded-md border bg-white text-xs shadow-sm ${
        compact ? 'flex flex-col p-1' : 'p-2'
      } ${selected ? 'border-brand-600 ring-1 ring-brand-600' : 'border-slate-200'}`}
      data-testid={`weekly-timetable-lesson-${lesson.lesson_id}`}
      title={title}
    >
      <p className="shrink-0 font-semibold tabular-nums leading-tight">{startLabel}</p>
      <p className="mt-0.5 min-w-0 truncate font-medium leading-tight">{lesson.student_name}</p>
      {!compact ? (
        <>
          <p className="break-words text-slate-600">{lesson.teacher_name}</p>
          <p className="break-words text-slate-600">{lesson.course_name}</p>
        </>
      ) : null}
      {!isVeryShort ? (
        <p className="mt-0.5 shrink-0 font-medium leading-tight text-brand-700" data-testid="lesson-progress-label">
          {lesson.lesson_progress}
        </p>
      ) : null}
      {!compact ? <p className="text-slate-500">{formatLessonStatus(lesson.lesson_status)}</p> : null}
      {!isVeryShort ? (
        <div className={`mt-auto flex min-h-0 flex-wrap gap-x-2 gap-y-0 overflow-hidden ${compact ? 'pt-0.5' : 'mt-2'}`}>
          {onSelect ? (
            <button
              type="button"
              className="shrink-0 text-brand-700 underline"
              onClick={() => onSelect(lesson)}
              data-testid={`weekly-lesson-detail-open-${lesson.lesson_id}`}
            >
              상세
            </button>
          ) : (
            <Link
              href={`/students/${lesson.student_id}`}
              prefetch={false}
              className="shrink-0 text-brand-700 underline"
            >
              상세
            </Link>
          )}
          {onScheduleChange ? (
            <button
              type="button"
              className="shrink-0 text-brand-700 underline"
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

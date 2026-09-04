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

  return (
    <article
      className={`rounded-md border bg-white p-2 text-xs shadow-sm ${
        selected ? 'border-brand-600 ring-1 ring-brand-600' : 'border-slate-200'
      }`}
      data-testid={`weekly-timetable-lesson-${lesson.lesson_id}`}
      title={`${startLabel} ${lesson.student_name} ${lesson.lesson_progress}`}
    >
      <p className="font-semibold tabular-nums">{startLabel}</p>
      <p className="mt-1 font-medium break-words">{lesson.student_name}</p>
      {!compact ? (
        <>
          <p className="text-slate-600 break-words">{lesson.teacher_name}</p>
          <p className="text-slate-600 break-words">{lesson.course_name}</p>
        </>
      ) : null}
      <p className="mt-1 font-medium text-brand-700" data-testid="lesson-progress-label">
        {lesson.lesson_progress}
      </p>
      <p className="text-slate-500">{formatLessonStatus(lesson.lesson_status)}</p>
      <div className="mt-2 flex flex-wrap gap-2">
        {onSelect ? (
          <button
            type="button"
            className="text-brand-700 underline"
            onClick={() => onSelect(lesson)}
            data-testid={`weekly-lesson-detail-open-${lesson.lesson_id}`}
          >
            상세
          </button>
        ) : (
          <Link
            href={`/students/${lesson.student_id}`}
            prefetch={false}
            className="text-brand-700 underline"
          >
            상세
          </Link>
        )}
        {onScheduleChange ? (
          <button
            type="button"
            className="text-brand-700 underline"
            onClick={() => onScheduleChange(lesson)}
            data-testid={`weekly-lesson-schedule-open-${lesson.lesson_id}`}
          >
            일정 변경
          </button>
        ) : null}
      </div>
    </article>
  );
}

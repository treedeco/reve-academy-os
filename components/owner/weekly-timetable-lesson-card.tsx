import Link from 'next/link';
import { formatLessonStatus } from '@/lib/domain/format';
import type { WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import { formatMinutesAsLocalTime } from '@/lib/domain/academy-hours';

export function WeeklyTimetableLessonCard({
  lesson,
  compact = false,
}: {
  lesson: WeeklyTimetableLesson;
  compact?: boolean;
}) {
  const startLabel = formatMinutesAsLocalTime(lesson.local_start_minutes);

  return (
    <article
      className="rounded-md border border-slate-200 bg-white p-2 text-xs shadow-sm"
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
      <Link
        href={`/students/${lesson.student_id}`}
        className="mt-1 inline-block text-brand-700 underline"
      >
        상세
      </Link>
    </article>
  );
}

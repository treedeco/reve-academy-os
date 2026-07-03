import {
  formatLocalTime,
  formatNextLessonLabel,
  formatPassStatusLabel,
  type WeeklyScheduleEntry,
} from '@/lib/domain/weekly-schedule';
import { formatLessonStatus } from '@/lib/domain/format';
import type { LessonStatus } from '@/lib/domain/types';

export function WeeklyScheduleEntryCard({ entry }: { entry: WeeklyScheduleEntry }) {
  const teacherName = entry.teacher_name || '담당교사 없음';
  const courseName = entry.course_name || '과목 없음';
  const nextLessonLabel = formatNextLessonLabel(
    entry.next_lesson_scheduled_at,
    entry.next_lesson_status,
  );

  return (
    <article
      className="rounded-lg border border-slate-200 bg-white p-3 shadow-sm"
      data-testid={`weekly-schedule-entry-${entry.slot_id}`}
    >
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-base font-semibold tabular-nums">{formatLocalTime(entry.local_start_time)}</p>
        <span className="shrink-0 rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-700">
          {formatPassStatusLabel(entry.pass_status)}
        </span>
      </div>

      <p className="mt-2 font-medium break-words">{entry.student_name || '학생 없음'}</p>
      <p className="text-sm text-slate-600 break-words">{teacherName}</p>
      <p className="text-sm text-slate-600 break-words">{courseName}</p>

      <dl className="mt-3 space-y-1 text-xs text-slate-600">
        <div className="flex justify-between gap-2">
          <dt>주간 빈도</dt>
          <dd>주 {entry.weekly_frequency}회 · {entry.registered_lesson_count}회 등록</dd>
        </div>
        <div>
          <dt className="sr-only">다음 수업</dt>
          <dd className="break-words">{nextLessonLabel}</dd>
          {entry.next_lesson_status ? (
            <dd className="mt-0.5 text-slate-500">
              상태: {formatLessonStatus(entry.next_lesson_status as LessonStatus)}
            </dd>
          ) : null}
        </div>
      </dl>
    </article>
  );
}

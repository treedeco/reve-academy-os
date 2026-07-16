import type { WeeklyTimetableDayColumn } from '@/lib/domain/weekly-timetable';
import { formatMinutesAsLocalTime } from '@/lib/domain/academy-hours';
import { WeeklyTimetableLessonCard } from '@/components/owner/weekly-timetable-lesson-card';

export function WeeklyTimetableMobileList({ columns }: { columns: WeeklyTimetableDayColumn[] }) {
  const nonEmpty = columns.filter((column) => column.lessons.length > 0);

  return (
    <div className="space-y-8 lg:hidden" data-testid="weekly-timetable-mobile">
      {nonEmpty.map((column) => (
        <section key={column.weekday} data-testid={`weekly-timetable-mobile-day-${column.weekday}`}>
          <h2 className="mb-3 text-lg font-semibold">{column.weekday_label}요일</h2>
          <div className="space-y-3">
            {column.lessons.map((lesson) => (
              <div key={lesson.lesson_id} className="flex gap-3">
                <p className="w-12 shrink-0 text-sm font-semibold tabular-nums">
                  {formatMinutesAsLocalTime(lesson.local_start_minutes)}
                </p>
                <div className="min-w-0 flex-1">
                  <WeeklyTimetableLessonCard lesson={lesson} />
                </div>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

import type { WeeklyTimetableDayColumn, WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import {
  buildTimetableRows,
  TIMETABLE_END_MINUTES,
  TIMETABLE_INTERVAL_MINUTES,
  TIMETABLE_START_MINUTES,
} from '@/lib/domain/weekly-timetable';
import { formatMinutesAsLocalTime } from '@/lib/domain/academy-hours';
import { WeeklyTimetableLessonCard } from '@/components/owner/weekly-timetable-lesson-card';

const ROW_HEIGHT_PX = 32;

function assignOverlapLanes(lessons: WeeklyTimetableLesson[]) {
  const lanes = new Map<string, { lane: number; laneCount: number }>();
  const sorted = [...lessons].sort(
    (a, b) =>
      a.local_start_minutes - b.local_start_minutes ||
      a.duration_minutes - b.duration_minutes,
  );

  for (let index = 0; index < sorted.length; index += 1) {
    const lesson = sorted[index];
    const start = lesson.local_start_minutes;
    const end = start + lesson.duration_minutes;
    const active = sorted.slice(0, index).filter((other) => {
      const otherEnd = other.local_start_minutes + other.duration_minutes;
      return other.local_start_minutes < end && start < otherEnd;
    });
    const used = new Set(active.map((other) => lanes.get(other.lesson_id)?.lane ?? 0));
    let lane = 0;
    while (used.has(lane)) {
      lane += 1;
    }
    const laneCount = Math.max(
      lane + 1,
      ...active.map((other) => lanes.get(other.lesson_id)?.laneCount ?? 1),
    );
    for (const other of active) {
      const existing = lanes.get(other.lesson_id);
      if (existing) {
        lanes.set(other.lesson_id, { ...existing, laneCount: Math.max(existing.laneCount, laneCount) });
      }
    }
    lanes.set(lesson.lesson_id, { lane, laneCount });
  }

  return lanes;
}

function DayColumn({ column }: { column: WeeklyTimetableDayColumn }) {
  const rows = buildTimetableRows();
  const totalHeight = rows.length * ROW_HEIGHT_PX;
  const lanes = assignOverlapLanes(column.lessons);

  return (
    <div
      className="relative min-w-0 flex-1 border-l border-slate-200"
      data-testid={`weekly-timetable-day-${column.weekday}`}
    >
      <div className="relative" style={{ height: totalHeight }}>
        {rows.map((row, index) => (
          <div
            key={row.start_minutes}
            className="absolute inset-x-0 border-t border-slate-100"
            style={{ top: index * ROW_HEIGHT_PX, height: ROW_HEIGHT_PX }}
            data-testid={`weekly-timetable-cell-${column.weekday}-${row.start_minutes}`}
          />
        ))}

        {column.lessons.map((lesson) => {
          const laneInfo = lanes.get(lesson.lesson_id) ?? { lane: 0, laneCount: 1 };
          const top =
            ((lesson.local_start_minutes - TIMETABLE_START_MINUTES) / TIMETABLE_INTERVAL_MINUTES) *
            ROW_HEIGHT_PX;
          const height = Math.max(
            ROW_HEIGHT_PX,
            (lesson.duration_minutes / TIMETABLE_INTERVAL_MINUTES) * ROW_HEIGHT_PX,
          );
          const widthPercent = 100 / laneInfo.laneCount;
          const leftPercent = widthPercent * laneInfo.lane;

          return (
            <div
              key={lesson.lesson_id}
              className="absolute px-0.5"
              style={{
                top,
                height,
                left: `${leftPercent}%`,
                width: `${widthPercent}%`,
              }}
              data-testid={`weekly-timetable-placement-${lesson.lesson_id}`}
            >
              <WeeklyTimetableLessonCard lesson={lesson} compact />
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function WeeklyTimetableGrid({ columns }: { columns: WeeklyTimetableDayColumn[] }) {
  const rows = buildTimetableRows();
  const totalHeight = rows.length * ROW_HEIGHT_PX;

  return (
    <div className="hidden lg:block" data-testid="weekly-timetable-grid">
      <div className="overflow-x-auto">
        <div className="flex min-w-[960px]">
          <div className="w-16 shrink-0" style={{ height: totalHeight }}>
            {rows.map((row, index) => (
              <div
                key={row.start_minutes}
                className="border-t border-slate-200 pr-1 text-right text-xs tabular-nums text-slate-600"
                style={{ height: ROW_HEIGHT_PX, lineHeight: `${ROW_HEIGHT_PX}px` }}
                data-testid={`weekly-timetable-row-${row.start_minutes}`}
              >
                {row.label}
              </div>
            ))}
          </div>

          {columns.map((column) => (
            <DayColumn key={column.weekday} column={column} />
          ))}
        </div>
      </div>
      <p className="mt-2 text-xs text-slate-500" data-testid="weekly-timetable-range-label">
        {formatMinutesAsLocalTime(TIMETABLE_START_MINUTES)}–
        {formatMinutesAsLocalTime(TIMETABLE_END_MINUTES)}
      </p>
    </div>
  );
}

export function weeklyTimetableHasFinalBoundaryRow(): boolean {
  const rows = buildTimetableRows();
  const lastRow = rows[rows.length - 1];
  return (
    lastRow?.end_minutes === TIMETABLE_END_MINUTES &&
    lastRow.start_minutes === TIMETABLE_END_MINUTES - TIMETABLE_INTERVAL_MINUTES
  );
}

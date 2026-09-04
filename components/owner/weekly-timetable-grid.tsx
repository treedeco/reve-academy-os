'use client';

import type { WeeklyTimetableDayColumn, WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import {
  buildTimetableRows,
  computeTimetableEventBox,
  TIMETABLE_END_MINUTES,
  TIMETABLE_INTERVAL_MINUTES,
  TIMETABLE_START_MINUTES,
  WEEKLY_TIMETABLE_ROW_HEIGHT_PX,
} from '@/lib/domain/weekly-timetable';
import { formatMinutesAsLocalTime } from '@/lib/domain/academy-hours';
import { WeeklyTimetableLessonCard } from '@/components/owner/weekly-timetable-lesson-card';

export { WEEKLY_TIMETABLE_ROW_HEIGHT_PX };

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

function DayColumn({
  column,
  onLessonSelect,
  onScheduleChange,
  selectedLessonId,
}: {
  column: WeeklyTimetableDayColumn;
  onLessonSelect?: (lesson: WeeklyTimetableLesson) => void;
  onScheduleChange?: (lesson: WeeklyTimetableLesson) => void;
  selectedLessonId?: string | null;
}) {
  const rows = buildTimetableRows();
  const totalHeight = rows.length * WEEKLY_TIMETABLE_ROW_HEIGHT_PX;
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
            style={{ top: index * WEEKLY_TIMETABLE_ROW_HEIGHT_PX, height: WEEKLY_TIMETABLE_ROW_HEIGHT_PX }}
            data-testid={`weekly-timetable-cell-${column.weekday}-${row.start_minutes}`}
          />
        ))}

        {column.lessons.map((lesson) => {
          const laneInfo = lanes.get(lesson.lesson_id) ?? { lane: 0, laneCount: 1 };
          const box = computeTimetableEventBox(
            lesson.local_start_minutes,
            lesson.duration_minutes,
            WEEKLY_TIMETABLE_ROW_HEIGHT_PX,
          );
          if (!box) {
            return null;
          }
          const widthPercent = 100 / laneInfo.laneCount;
          const leftPercent = widthPercent * laneInfo.lane;

          return (
            <div
              key={lesson.lesson_id}
              className="absolute overflow-hidden px-0.5"
              style={{
                top: box.top,
                height: box.height,
                left: `${leftPercent}%`,
                width: `${widthPercent}%`,
              }}
              data-testid={`weekly-timetable-placement-${lesson.lesson_id}`}
              data-row-span={Math.round(box.height / WEEKLY_TIMETABLE_ROW_HEIGHT_PX)}
            >
              <WeeklyTimetableLessonCard
                lesson={lesson}
                compact
                selected={selectedLessonId === lesson.lesson_id}
                onSelect={onLessonSelect}
                onScheduleChange={onScheduleChange}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function WeeklyTimetableGrid({
  columns,
  onLessonSelect,
  onScheduleChange,
  selectedLessonId,
}: {
  columns: WeeklyTimetableDayColumn[];
  onLessonSelect?: (lesson: WeeklyTimetableLesson) => void;
  onScheduleChange?: (lesson: WeeklyTimetableLesson) => void;
  selectedLessonId?: string | null;
}) {
  const rows = buildTimetableRows();
  const totalHeight = rows.length * WEEKLY_TIMETABLE_ROW_HEIGHT_PX;

  return (
    <div className="hidden lg:block" data-testid="weekly-timetable-grid">
      <div className="max-h-[70vh] overflow-y-auto overflow-x-auto" data-testid="weekly-timetable-scroll">
        <div className="min-w-[960px]">
          <div className="sticky top-0 z-20 flex border-b border-slate-200 bg-white shadow-sm">
            <div className="w-16 shrink-0" />
            {columns.map((column) => (
              <div
                key={column.weekday}
                className="min-w-0 flex-1 border-l border-slate-200 px-2 py-2 text-center text-sm font-semibold"
                data-testid={`weekly-timetable-header-${column.weekday}`}
              >
                {column.header_label}
              </div>
            ))}
          </div>

          <div className="flex">
            <div className="w-16 shrink-0" style={{ height: totalHeight }}>
              {rows.map((row) => (
                <div
                  key={row.start_minutes}
                  className="border-t border-slate-200 pr-1 text-right text-xs tabular-nums text-slate-600"
                  style={{
                    height: WEEKLY_TIMETABLE_ROW_HEIGHT_PX,
                    lineHeight: `${WEEKLY_TIMETABLE_ROW_HEIGHT_PX}px`,
                  }}
                  data-testid={`weekly-timetable-row-${row.start_minutes}`}
                >
                  {row.label}
                </div>
              ))}
            </div>

            {columns.map((column) => (
              <DayColumn
                key={column.weekday}
                column={column}
                onLessonSelect={onLessonSelect}
                onScheduleChange={onScheduleChange}
                selectedLessonId={selectedLessonId}
              />
            ))}
          </div>
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

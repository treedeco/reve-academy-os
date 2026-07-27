'use client';

import type { WeeklyTimetableDayColumn, WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import { WeeklyTimetableGrid } from '@/components/owner/weekly-timetable-grid';
import { WeeklyTimetableMobileList } from '@/components/owner/weekly-timetable-mobile-list';

export function WeeklyTimetableView({
  columns,
  weekContextLabel,
  onLessonSelect,
  onScheduleChange,
  selectedLessonId,
}: {
  columns: WeeklyTimetableDayColumn[];
  weekContextLabel: string;
  onLessonSelect?: (lesson: WeeklyTimetableLesson) => void;
  onScheduleChange?: (lesson: WeeklyTimetableLesson) => void;
  selectedLessonId?: string | null;
}) {
  return (
    <div className="space-y-6" data-testid="weekly-timetable-view">
      <p className="text-sm text-slate-600">{weekContextLabel}</p>
      <WeeklyTimetableGrid
        columns={columns}
        onLessonSelect={onLessonSelect}
        onScheduleChange={onScheduleChange}
        selectedLessonId={selectedLessonId}
      />
      <WeeklyTimetableMobileList
        columns={columns}
        onLessonSelect={onLessonSelect}
        onScheduleChange={onScheduleChange}
        selectedLessonId={selectedLessonId}
      />
    </div>
  );
}

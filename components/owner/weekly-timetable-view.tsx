import type { WeeklyTimetableDayColumn } from '@/lib/domain/weekly-timetable';
import { WeeklyTimetableGrid } from '@/components/owner/weekly-timetable-grid';
import { WeeklyTimetableMobileList } from '@/components/owner/weekly-timetable-mobile-list';

export function WeeklyTimetableView({
  columns,
  weekContextLabel,
}: {
  columns: WeeklyTimetableDayColumn[];
  weekContextLabel: string;
}) {
  return (
    <div className="space-y-6" data-testid="weekly-timetable-view">
      <p className="text-sm text-slate-600">{weekContextLabel}</p>
      <WeeklyTimetableGrid columns={columns} />
      <WeeklyTimetableMobileList columns={columns} />
    </div>
  );
}

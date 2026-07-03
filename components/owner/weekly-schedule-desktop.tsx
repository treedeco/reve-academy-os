import type { WeeklyScheduleDayGroup } from '@/lib/domain/weekly-schedule';
import { WeeklyScheduleEntryCard } from '@/components/owner/weekly-schedule-entry';

export function WeeklyScheduleDesktop({ groups }: { groups: WeeklyScheduleDayGroup[] }) {
  return (
    <div
      className="hidden gap-4 lg:grid"
      style={{ gridTemplateColumns: `repeat(${Math.min(groups.length, 7)}, minmax(0, 1fr))` }}
      data-testid="weekly-schedule-desktop"
    >
      {groups.map((group) => (
        <section key={group.weekday} data-testid={`weekly-schedule-desktop-day-${group.weekday}`}>
          <h2 className="sticky top-0 z-10 border-b border-slate-200 bg-slate-50 py-2 text-center text-sm font-semibold">
            {group.weekday_label}
          </h2>
          <div className="space-y-3 py-3">
            {group.entries.map((entry) => (
              <WeeklyScheduleEntryCard key={entry.slot_id} entry={entry} />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

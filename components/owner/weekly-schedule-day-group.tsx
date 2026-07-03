import type { WeeklyScheduleDayGroup } from '@/lib/domain/weekly-schedule';
import { WeeklyScheduleEntryCard } from '@/components/owner/weekly-schedule-entry';

export function WeeklyScheduleDayGroupSection({ group }: { group: WeeklyScheduleDayGroup }) {
  return (
    <section data-testid={`weekly-schedule-day-${group.weekday}`}>
      <h2 className="mb-3 text-lg font-semibold">{group.weekday_label}요일</h2>
      <div className="space-y-3">
        {group.entries.map((entry) => (
          <WeeklyScheduleEntryCard key={entry.slot_id} entry={entry} />
        ))}
      </div>
    </section>
  );
}

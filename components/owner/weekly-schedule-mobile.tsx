import type { WeeklyScheduleDayGroup } from '@/lib/domain/weekly-schedule';
import { WeeklyScheduleDayGroupSection } from '@/components/owner/weekly-schedule-day-group';

export function WeeklyScheduleMobile({ groups }: { groups: WeeklyScheduleDayGroup[] }) {
  return (
    <div className="space-y-8 lg:hidden" data-testid="weekly-schedule-mobile">
      {groups.map((group) => (
        <WeeklyScheduleDayGroupSection key={group.weekday} group={group} />
      ))}
    </div>
  );
}

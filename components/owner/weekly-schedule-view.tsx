import type { WeeklyScheduleDayGroup } from '@/lib/domain/weekly-schedule';
import { WeeklyScheduleDesktop } from '@/components/owner/weekly-schedule-desktop';
import { WeeklyScheduleMobile } from '@/components/owner/weekly-schedule-mobile';

export function WeeklyScheduleView({
  groups,
  weekContextLabel,
}: {
  groups: WeeklyScheduleDayGroup[];
  weekContextLabel: string;
}) {
  return (
    <div className="space-y-6" data-testid="weekly-schedule-view">
      <p className="text-sm text-slate-600">{weekContextLabel}</p>
      <WeeklyScheduleDesktop groups={groups} />
      <WeeklyScheduleMobile groups={groups} />
    </div>
  );
}

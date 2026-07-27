import { buildAcademyTimeOptions } from '@/lib/domain/owner-schedule-edit';

const TIME_OPTIONS = buildAcademyTimeOptions();

export function ScheduleTimeSelect({
  id,
  value,
  disabled,
  onChange,
  testId,
}: {
  id: string;
  value: string;
  disabled?: boolean;
  onChange: (value: string) => void;
  testId?: string;
}) {
  return (
    <select
      id={id}
      className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
      value={value}
      disabled={disabled}
      onChange={(event) => onChange(event.target.value)}
      data-testid={testId}
    >
      <option value="">시간 선택</option>
      {TIME_OPTIONS.map((time) => (
        <option key={time} value={time}>
          {time}
        </option>
      ))}
    </select>
  );
}

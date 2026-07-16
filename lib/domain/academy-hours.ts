/** Academy operating window in Asia/Seoul local time (minutes from midnight). */
export const ACADEMY_FIRST_START_MINUTES = 13 * 60;
export const ACADEMY_LAST_START_MINUTES = 21 * 60;
export const ACADEMY_LAST_END_MINUTES = 22 * 60;

export function parseLocalTimeToMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map((part) => Number.parseInt(part, 10));
  return hours * 60 + minutes;
}

export function formatMinutesAsLocalTime(totalMinutes: number): string {
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

export function validateAcademyLessonWindow(
  startMinutes: number,
  durationMinutes: number,
): string | null {
  if (startMinutes < ACADEMY_FIRST_START_MINUTES) {
    return '수업 시작은 13:00 이후여야 합니다.';
  }
  if (startMinutes >= ACADEMY_LAST_END_MINUTES) {
    return '수업 시작은 22:00 이전이어야 합니다.';
  }
  if (startMinutes + durationMinutes > ACADEMY_LAST_END_MINUTES) {
    return '수업 종료는 22:00을 넘을 수 없습니다.';
  }
  return null;
}

export function seoulLocalDateTimeToMinutes(iso: string): number {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Seoul',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const parts = formatter.formatToParts(new Date(iso));
  const hour = Number.parseInt(parts.find((part) => part.type === 'hour')?.value ?? '0', 10);
  const minute = Number.parseInt(parts.find((part) => part.type === 'minute')?.value ?? '0', 10);
  return hour * 60 + minute;
}

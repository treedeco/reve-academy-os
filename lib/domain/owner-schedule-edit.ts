import {
  ACADEMY_FIRST_START_MINUTES,
  ACADEMY_LAST_START_MINUTES,
  formatMinutesAsLocalTime,
  parseLocalTimeToMinutes,
  validateAcademyLessonWindow,
} from '@/lib/domain/academy-hours';
import { parseSeoulDateTimeLocal } from '@/lib/domain/schedule-change';
import { weekdayLabelMonFirst } from '@/lib/domain/weekly-schedule';
import type { EnrollmentScheduleSlotInput } from '@/lib/domain/types';
import { WEEKDAY_LABELS } from '@/lib/domain/types';

export type OwnerScheduleChangeMode = 'single' | 'recurring';

export const OWNER_SCHEDULE_CHANGE_MODE_LABELS: Record<OwnerScheduleChangeMode, string> = {
  single: '이번 수업만 변경',
  recurring: '고정 일정 변경',
};

export const TIMETABLE_TIME_STEP_MINUTES = 30;

export function buildAcademyTimeOptions(): string[] {
  const options: string[] = [];
  for (
    let minutes = ACADEMY_FIRST_START_MINUTES;
    minutes <= ACADEMY_LAST_START_MINUTES;
    minutes += TIMETABLE_TIME_STEP_MINUTES
  ) {
    options.push(formatMinutesAsLocalTime(minutes));
  }
  return options;
}

export function getSeoulWeekdayFromDateKey(dateKey: string): number {
  const parsed = new Date(`${dateKey}T12:00:00+09:00`);
  return parsed.getUTCDay();
}

export function formatSeoulWeekdayLabel(dateKey: string): string {
  return WEEKDAY_LABELS[getSeoulWeekdayFromDateKey(dateKey)];
}

export function formatSeoulDateTimeWithWeekday(iso: string): string {
  return new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
}

export function formatSeoulDateTimeShortWithWeekday(iso: string): string {
  return new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    month: 'numeric',
    day: 'numeric',
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
}

export function formatFixedWeeklyScheduleLabel(input: {
  weekday: number;
  localTime: string;
}): string {
  const time = input.localTime.slice(0, 5);
  return `매주 ${weekdayLabelMonFirst(input.weekday)}요일 ${time}`;
}

export function formatFixedWeeklySchedulesLabel(
  slots: ReadonlyArray<{ weekday: number; local_start_time: string }>,
): string {
  if (slots.length === 0) {
    return '-';
  }
  return slots
    .map((slot) =>
      formatFixedWeeklyScheduleLabel({
        weekday: slot.weekday,
        localTime: slot.local_start_time,
      }),
    )
    .join(' · ');
}

export function buildScheduleSlotsPayloadFromInputs(
  slots: EnrollmentScheduleSlotInput[],
): unknown[] {
  return slots.map((slot) => ({
    teacher_id: slot.teacherId,
    weekday: slot.weekday,
    local_time: slot.localTime,
    duration_minutes: slot.durationMinutes,
    slot_order: slot.slotOrder,
  }));
}

export function scheduleSlotsFromPassSlots(
  slots: ReadonlyArray<{
    id: string;
    weekday: number;
    local_start_time: string;
    duration_minutes: number;
    teacher_id: string;
  }>,
): EnrollmentScheduleSlotInput[] {
  return slots.map((slot, index) => ({
    teacherId: slot.teacher_id,
    weekday: slot.weekday,
    localTime: slot.local_start_time.slice(0, 5),
    durationMinutes: slot.duration_minutes,
    slotOrder: index + 1,
  }));
}

export function validateSingleScheduleChange(input: {
  dateKey: string;
  timeValue: string;
  durationMinutes: number;
  reason: string;
}): string | null {
  if (!input.reason.trim()) {
    return '변경 사유를 입력해 주세요.';
  }
  if (!input.dateKey || !input.timeValue) {
    return '날짜와 시간을 선택해 주세요.';
  }
  const startMinutes = parseLocalTimeToMinutes(input.timeValue);
  const hoursError = validateAcademyLessonWindow(startMinutes, input.durationMinutes);
  if (hoursError) {
    return hoursError;
  }
  const scheduledAt = parseSeoulDateTimeLocal(`${input.dateKey}T${input.timeValue}`);
  if (!scheduledAt) {
    return '올바른 날짜와 시간을 선택해 주세요.';
  }
  return null;
}

export function validateRecurringScheduleChange(input: {
  effectiveDateKey: string;
  slots: EnrollmentScheduleSlotInput[];
  reason: string;
  weeklyFrequency: number;
}): string | null {
  if (!input.reason.trim()) {
    return '변경 사유를 입력해 주세요.';
  }
  if (!input.effectiveDateKey) {
    return '적용 시작일을 선택해 주세요.';
  }
  if (input.slots.length !== input.weeklyFrequency) {
    return '고정 일정 개수가 상품 주당 횟수와 일치하지 않습니다.';
  }
  for (const slot of input.slots) {
    if (!slot.teacherId) {
      return '강사를 선택해 주세요.';
    }
    const startMinutes = parseLocalTimeToMinutes(slot.localTime);
    const hoursError = validateAcademyLessonWindow(startMinutes, slot.durationMinutes);
    if (hoursError) {
      return hoursError;
    }
  }
  return null;
}

export function mapOwnerScheduleEditError(error: { message?: string } | null): string {
  if (!error?.message) {
    return '일정 변경에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }
  if (error.message.includes('REVE_SCHEDULE_COLLISION')) {
    return '강사 또는 학생 일정이 겹칩니다. 다른 시간을 선택해 주세요.';
  }
  if (error.message.includes('REVE_STUDENT_SCHEDULE_COLLISION')) {
    return '학생의 다른 수업과 일정이 겹칩니다.';
  }
  if (error.message.includes('REVE_LESSON_NOT_CHANGEABLE')) {
    return '일정을 변경할 수 없는 수업입니다.';
  }
  if (error.message.includes('REVE_SCHEDULE_CHANGE_DENIED')) {
    return '일정을 변경할 수 없는 수업입니다.';
  }
  if (error.message.includes('REVE_PASS_SCHEDULE_IMMUTABLE')) {
    return '변경할 수 없는 수강권 상태입니다.';
  }
  if (error.message.includes('REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON')) {
    return '완료·취소된 수업 때문에 고정 일정을 적용할 수 없습니다.';
  }
  if (error.message.includes('REVE_EFFECTIVE_FROM_REQUIRED')) {
    return '적용 시작일을 선택해 주세요.';
  }
  return error.message;
}

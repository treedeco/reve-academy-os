import type { LessonStatus } from '@/lib/domain/types';

/** Matches `reve_private.is_correction_lesson_transition` deductible → non-deducted targets. */
export const CORRECTION_TARGET_STATUSES: LessonStatus[] = [
  'scheduled',
  'postponed',
  'advance_cancelled',
  'teacher_cancelled',
  'academy_closed',
];

export const DEDUCTIBLE_LESSON_STATUSES = new Set<LessonStatus>([
  'completed',
  'same_day_cancelled',
  'makeup_completed',
]);

export function isDeductibleLessonStatus(status: LessonStatus): boolean {
  return DEDUCTIBLE_LESSON_STATUSES.has(status);
}

export function canOrdinaryTransition(status: LessonStatus): boolean {
  return !isDeductibleLessonStatus(status);
}

export function formatLessonProgress(
  registeredLessonCount: number,
  sequenceNumber: number,
): string {
  return `${registeredLessonCount}-${sequenceNumber}`;
}

const SCHEDULE_CHANGEABLE_STATUSES = new Set<LessonStatus>([
  'scheduled',
  'postponed',
  'advance_cancelled',
  'teacher_cancelled',
  'academy_closed',
]);

export function isScheduleChangeableLessonStatus(status: LessonStatus): boolean {
  return SCHEDULE_CHANGEABLE_STATUSES.has(status);
}

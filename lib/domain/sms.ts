export type SmsNotificationStatus =
  | 'normal'
  | 'scheduled'
  | 'target'
  | 'exhausted_unsent'
  | 'sent';

export const ELIGIBLE_SMS_STATUSES = ['scheduled', 'target', 'exhausted_unsent'] as const;

export type EligibleSmsStatus = (typeof ELIGIBLE_SMS_STATUSES)[number];

export const SMS_STATUS_LABELS: Record<SmsNotificationStatus, string> = {
  normal: '정상',
  scheduled: '발송 예정',
  target: '발송 대상',
  exhausted_unsent: '미발송(소진)',
  sent: '발송 완료',
};

export function isEligibleSmsStatus(status: string): status is EligibleSmsStatus {
  return (ELIGIBLE_SMS_STATUSES as readonly string[]).includes(status);
}

export function formatSmsStatus(status: SmsNotificationStatus | string): string {
  return SMS_STATUS_LABELS[status as SmsNotificationStatus] ?? status;
}

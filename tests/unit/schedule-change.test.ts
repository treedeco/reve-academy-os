import { describe, expect, it } from 'vitest';
import { mapDatabaseError } from '@/lib/domain/format';
import {
  canApplyScheduleRequest,
  canApproveScheduleRequest,
  canCascadeScheduleRequest,
  formatScheduleRequestSourceRoleLabel,
  formatScheduleRequestStatusLabel,
  isActionableScheduleChangeRequest,
  isActionableScheduleRequestStatus,
  isCascadePendingScheduleChangeRequest,
  mapScheduleChangeError,
  parseSeoulDateTimeLocal,
} from '@/lib/domain/schedule-change';

describe('schedule change domain helpers', () => {
  it('filters actionable schedule request statuses', () => {
    expect(isActionableScheduleRequestStatus('submitted')).toBe(true);
    expect(isActionableScheduleRequestStatus('approved')).toBe(true);
    expect(isActionableScheduleRequestStatus('rejected')).toBe(false);
    expect(isActionableScheduleRequestStatus('applied')).toBe(false);
  });

  it('determines actionable queue membership', () => {
    expect(isActionableScheduleChangeRequest({ status: 'submitted', applied_at: null })).toBe(true);
    expect(isActionableScheduleChangeRequest({ status: 'approved', applied_at: null })).toBe(true);
    expect(isActionableScheduleChangeRequest({ status: 'approved', applied_at: '2026-07-01T00:00:00Z' })).toBe(
      false,
    );
    expect(isActionableScheduleChangeRequest({ status: 'rejected', applied_at: null })).toBe(false);
  });

  it('maps schedule request status and source labels', () => {
    expect(formatScheduleRequestStatusLabel('submitted')).toBe('검토 대기');
    expect(formatScheduleRequestStatusLabel('approved')).toBe('승인됨 (적용 전)');
    expect(formatScheduleRequestSourceRoleLabel('teacher')).toBe('강사');
  });

  it('controls approve, apply, and cascade affordances', () => {
    expect(canApproveScheduleRequest('submitted')).toBe(true);
    expect(canApproveScheduleRequest('approved')).toBe(false);
    expect(canApplyScheduleRequest('approved', null)).toBe(true);
    expect(canApplyScheduleRequest('submitted', null)).toBe(false);
    expect(
      canCascadeScheduleRequest({
        status: 'applied',
        applied_at: '2026-07-01T00:00:00Z',
        cascade_completed_at: null,
      }),
    ).toBe(true);
    expect(
      canCascadeScheduleRequest({
        status: 'applied',
        applied_at: '2026-07-01T00:00:00Z',
        cascade_completed_at: '2026-07-02T00:00:00Z',
      }),
    ).toBe(false);
  });

  it('determines cascade pending queue membership', () => {
    expect(
      isCascadePendingScheduleChangeRequest({
        status: 'applied',
        applied_at: '2026-07-01T00:00:00Z',
        cascade_completed_at: null,
      }),
    ).toBe(true);
    expect(
      isCascadePendingScheduleChangeRequest({
        status: 'applied',
        applied_at: '2026-07-01T00:00:00Z',
        cascade_completed_at: '2026-07-02T00:00:00Z',
      }),
    ).toBe(false);
    expect(
      isCascadePendingScheduleChangeRequest({
        status: 'approved',
        applied_at: null,
        cascade_completed_at: null,
      }),
    ).toBe(false);
  });

  it('parses Seoul datetime-local values', () => {
    expect(parseSeoulDateTimeLocal('2026-07-15T14:00')).toBe('2026-07-15T05:00:00.000Z');
    expect(parseSeoulDateTimeLocal('')).toBeNull();
    expect(parseSeoulDateTimeLocal('invalid')).toBeNull();
  });

  it('maps schedule change errors to safe Korean messages', () => {
    expect(mapScheduleChangeError({ message: 'REVE_SCHEDULE_COLLISION' })).toMatch(/겹칩니다/);
    expect(mapScheduleChangeError({ message: 'REVE_UNAUTHORIZED' })).toMatch(/권한/);
    expect(mapScheduleChangeError({ message: 'REVE_REQUEST_NOT_REVIEWABLE' })).toMatch(/검토할 수 없는/);
    expect(mapScheduleChangeError({ message: 'REVE_REQUEST_NOT_APPLICABLE' })).toMatch(/적용할 수 없는/);
    expect(mapScheduleChangeError({ message: 'REVE_APPROVED_TIME_REQUIRED' })).toMatch(/승인 일시/);
    expect(mapScheduleChangeError({ message: 'REVE_REASON_REQUIRED' })).toMatch(/사유/);
    expect(mapScheduleChangeError({ message: 'REVE_CASCADE_NOT_READY' })).toMatch(/연쇄 재배치/);
    expect(mapScheduleChangeError({ message: 'REVE_CASCADE_BLOCKED_BY_IMMUTABLE_LESSON' })).toMatch(/완료된 수업/);
    expect(mapScheduleChangeError({ message: 'REVE_CASCADE_ANCHOR_CHANGED' })).toMatch(/기준 수업/);
    expect(mapScheduleChangeError(null)).toMatch(/실패/);
    expect(mapScheduleChangeError({ message: 'unexpected database fault' })).toBe('unexpected database fault');
  });

  it('maps schedule change errors through shared database error helper', () => {
    expect(mapDatabaseError({ message: 'REVE_SCHEDULE_COLLISION' })).toMatch(/겹칩니다/);
    expect(mapDatabaseError({ message: 'REVE_REASON_REQUIRED' })).toMatch(/사유/);
  });
});

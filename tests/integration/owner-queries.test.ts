import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  applyOwnerScheduleChangeRequest,
  cascadeOwnerScheduleChangeRequest,
  confirmOwnerSmsSent,
  fetchOwnerRefundablePayments,
  fetchOwnerScheduleChangeQueue,
  fetchOwnerScheduleChangeRequests,
  fetchPassUsage,
  fetchOwnerSmsNotifications,
  fetchStudentDetail,
  fetchStudentOperationalHistory,
  fetchTodayLessons,
  fetchWeeklySchedule,
  processOwnerPaymentRefund,
  reviewOwnerScheduleChangeRequest,
  transitionLessonStatus,
} from '@/lib/data/owner-queries';
import { mapDatabaseError } from '@/lib/domain/format';
import { mapRefundError } from '@/lib/domain/refund';
import { mapScheduleChangeError } from '@/lib/domain/schedule-change';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';
const alphaPassId = '66666666-6666-6666-6666-666666666101';
const alphaStudentId = '44444444-4444-4444-4444-444444444101';
const betaStudentId = '44444444-4444-4444-4444-444444444102';
const gammaStudentId = '44444444-4444-4444-4444-444444444103';
const deltaStudentId = '44444444-4444-4444-4444-444444444104';
const zetaStudentId = '44444444-4444-4444-4444-444444444106';
const deltaSmsId = '88888888-8888-8888-8888-888888888103';
const betaPaymentId = '12121212-1212-1212-1212-121212121102';
const deltaPaymentId = '12121212-1212-1212-1212-121212121101';
const alreadyRefundedPaymentId = '12121212-1212-1212-1212-121212121104';
const submittedScheduleRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa301';
const approvedScheduleRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa302';
const rejectedScheduleRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa303';
const appliedScheduleRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa304';
const cascadePendingScheduleRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa305';

const integrationEnabled = Boolean(supabaseUrl && supabaseAnonKey);

function createAuthClient(storageKey: string) {
  return createClient(supabaseUrl!, supabaseAnonKey!, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      storageKey,
    },
  });
}

describe.skipIf(!integrationEnabled)('Owner data integration', () => {
  let ownerClient: SupabaseClient;

  beforeAll(async () => {
    ownerClient = createAuthClient('reve-test-owner');
    const { error } = await ownerClient.auth.signInWithPassword({
      email: ownerEmail,
      password: ownerPassword,
    });
    if (error) {
      throw new Error(
        `Owner login failed (${error.message}). Run npm run db:seed:alpha after db reset.`,
      );
    }
  });

  it('loads today lessons for authenticated owner', async () => {
    const lessons = await fetchTodayLessons(ownerClient);
    expect(Array.isArray(lessons)).toBe(true);
  });

  it('returns derived pass usage counts from authoritative RPC', async () => {
    const usage = await fetchPassUsage(ownerClient, alphaPassId);
    expect(usage.registered_lesson_count).toBe(4);
    expect(usage.used_lesson_count + usage.remaining_lesson_count).toBe(4);
  });

  it('loads student detail with pass summary', async () => {
    const detail = await fetchStudentDetail(ownerClient, alphaStudentId);
    expect(detail.student.name).toBe('Alpha Student');
    expect(detail.current_pass?.pass_code).toBe('V-S1A1-001');
  });

  it('loads student operational history in two bounded queries', async () => {
    const deltaHistory = await fetchStudentOperationalHistory(ownerClient, deltaStudentId);
    expect(deltaHistory.payments.length).toBeGreaterThanOrEqual(1);
    expect(deltaHistory.payments.some((row) => row.pass_code === 'V-S1D1-001')).toBe(true);
    expect(deltaHistory.schedule_requests.length).toBeGreaterThanOrEqual(3);
    expect(deltaHistory.refunds).toHaveLength(0);

    const betaHistory = await fetchStudentOperationalHistory(ownerClient, betaStudentId);
    expect(betaHistory.payments.length).toBeGreaterThanOrEqual(1);
    expect(betaHistory.schedule_requests.length).toBeGreaterThanOrEqual(2);
    expect(betaHistory.refunds).toHaveLength(0);

    const zetaHistory = await fetchStudentOperationalHistory(ownerClient, zetaStudentId);
    expect(zetaHistory.refunds.length).toBe(1);
    expect(zetaHistory.payments.some((row) => row.status === 'refunded')).toBe(true);

    const gammaHistory = await fetchStudentOperationalHistory(ownerClient, gammaStudentId);
    expect(gammaHistory.payments).toHaveLength(0);
    expect(gammaHistory.refunds).toHaveLength(0);
    expect(gammaHistory.schedule_requests).toHaveLength(0);
  });

  it('loads weekly schedule entries for authenticated owner', async () => {
    const entries = await fetchWeeklySchedule(ownerClient);
    expect(entries.length).toBeGreaterThanOrEqual(3);
    expect(entries.some((entry) => entry.student_name === 'Alpha Student' && entry.weekday === 1)).toBe(true);
    expect(entries.some((entry) => entry.student_name === 'Beta Student' && entry.weekday === 3)).toBe(true);
    expect(entries.every((entry) => entry.pass_status === 'active')).toBe(true);
  });

  it('loads refundable owner payments in one query', async () => {
    const payments = await fetchOwnerRefundablePayments(ownerClient);
    expect(payments.length).toBeGreaterThanOrEqual(3);
    expect(payments.some((row) => row.student_name === 'Delta Student')).toBe(true);
    expect(payments.some((row) => row.student_name === 'Beta Student')).toBe(true);
    expect(payments.some((row) => row.student_name === 'Epsilon Student' && row.pass_status === 'reserved')).toBe(true);
    expect(payments.some((row) => row.student_name === 'Alpha Student')).toBe(false);
    expect(payments.some((row) => row.student_name === 'Zeta Student')).toBe(false);
  });

  it('loads eligible owner SMS notifications in one query', async () => {
    const notifications = await fetchOwnerSmsNotifications(ownerClient);
    expect(notifications.length).toBeGreaterThanOrEqual(3);
    expect(notifications.every((row) => ['scheduled', 'target', 'exhausted_unsent'].includes(row.status))).toBe(true);
    expect(notifications.some((row) => row.student_name === 'Beta Student' && row.status === 'scheduled')).toBe(true);
    expect(notifications.some((row) => row.student_name === 'Delta Student' && row.status === 'target')).toBe(true);
    expect(notifications.some((row) => row.student_name === 'Gamma Student' && row.status === 'exhausted_unsent')).toBe(true);
    expect(notifications.some((row) => row.student_name === 'Alpha Student')).toBe(false);
  });

  it('confirms SMS sent via trusted RPC and handles idempotent retry', async () => {
    const result = await confirmOwnerSmsSent(ownerClient, deltaSmsId);
    expect(result.new_status).toBe('sent');
    expect(result.no_change).toBe(false);

    const retry = await confirmOwnerSmsSent(ownerClient, deltaSmsId);
    expect(retry.new_status).toBe('sent');
    expect(retry.no_change).toBe(true);

    const notifications = await fetchOwnerSmsNotifications(ownerClient);
    expect(notifications.some((row) => row.id === deltaSmsId)).toBe(false);
  });

  it('maps SMS confirmation errors to readable messages', async () => {
    const alphaNormalSmsId = '88888888-8888-8888-8888-888888888101';
    await expect(confirmOwnerSmsSent(ownerClient, alphaNormalSmsId)).rejects.toThrow(
      /REVE_SMS_NOT_CONFIRMABLE/,
    );
    try {
      await confirmOwnerSmsSent(ownerClient, alphaNormalSmsId);
      expect.unreachable('expected non-confirmable SMS to fail');
    } catch (error) {
      expect(mapDatabaseError(error as { message?: string })).toMatch(/발송 확인할 수 없는/);
    }
  });

  it('loads owner schedule change queue in one query', async () => {
    const queue = await fetchOwnerScheduleChangeQueue(ownerClient);
    expect(queue.reviewRequests.length).toBeGreaterThanOrEqual(2);
    expect(queue.reviewRequests.some((row) => row.id === submittedScheduleRequestId && row.status === 'submitted')).toBe(true);
    expect(queue.reviewRequests.some((row) => row.id === approvedScheduleRequestId && row.status === 'approved')).toBe(true);
    expect(queue.reviewRequests.some((row) => row.id === rejectedScheduleRequestId)).toBe(false);
    expect(queue.reviewRequests.some((row) => row.id === appliedScheduleRequestId)).toBe(false);
    expect(queue.cascadePendingRequests.some((row) => row.id === cascadePendingScheduleRequestId)).toBe(true);
    expect(queue.cascadePendingRequests.some((row) => row.id === appliedScheduleRequestId)).toBe(false);
    expect(queue.cascadePendingRequests.some((row) => row.student_name === 'Delta Student')).toBe(true);

    const reviewOnly = await fetchOwnerScheduleChangeRequests(ownerClient);
    expect(reviewOnly).toEqual(queue.reviewRequests);
  });

  it('maps schedule change errors to readable messages', async () => {
    const queue = await fetchOwnerScheduleChangeRequests(ownerClient);
    const submitted = queue.find((row) => row.id === submittedScheduleRequestId);
    expect(submitted).toBeDefined();

    try {
      await reviewOwnerScheduleChangeRequest(ownerClient, {
        requestId: rejectedScheduleRequestId,
        decision: 'approve',
        expectedRequestUpdatedAt: new Date().toISOString(),
        decisionReason: 'Should fail',
        approvedScheduledAt: new Date().toISOString(),
      });
      expect.unreachable('expected non-reviewable request to fail');
    } catch (error) {
      expect(mapScheduleChangeError(error as { message?: string })).toMatch(/검토할 수 없는/);
    }

    try {
      await reviewOwnerScheduleChangeRequest(ownerClient, {
        requestId: submittedScheduleRequestId,
        decision: 'approve',
        expectedRequestUpdatedAt: submitted!.updated_at,
        decisionReason: '   ',
        approvedScheduledAt: submitted!.proposed_scheduled_at,
      });
      expect.unreachable('expected missing reason to fail');
    } catch (error) {
      expect(mapScheduleChangeError(error as { message?: string })).toMatch(/사유/);
    }
  });

  it('reviews and applies schedule change requests via trusted RPCs', async () => {
    const queue = await fetchOwnerScheduleChangeRequests(ownerClient);
    const submitted = queue.find((row) => row.id === submittedScheduleRequestId);
    const approved = queue.find((row) => row.id === approvedScheduleRequestId);
    expect(submitted).toBeDefined();
    expect(approved).toBeDefined();

    const reviewResult = await reviewOwnerScheduleChangeRequest(ownerClient, {
      requestId: submittedScheduleRequestId,
      decision: 'approve',
      expectedRequestUpdatedAt: submitted!.updated_at,
      decisionReason: 'Integration test approval',
      approvedScheduledAt: submitted!.proposed_scheduled_at,
    });
    expect(reviewResult.new_request_status).toBe('approved');
    expect(reviewResult.approved_scheduled_at).toBeTruthy();

    const afterApprove = await fetchOwnerScheduleChangeRequests(ownerClient);
    const approvedSubmitted = afterApprove.find((row) => row.id === submittedScheduleRequestId);
    expect(approvedSubmitted?.status).toBe('approved');

    const applyResult = await applyOwnerScheduleChangeRequest(ownerClient, {
      requestId: approvedScheduleRequestId,
      expectedRequestUpdatedAt: approved!.updated_at,
      expectedLessonUpdatedAt: approved!.lesson_updated_at,
    });
    expect(applyResult.request_status).toBe('applied');
    expect(applyResult.new_scheduled_at).toBeTruthy();

    const afterApply = await fetchOwnerScheduleChangeQueue(ownerClient);
    expect(afterApply.reviewRequests.some((row) => row.id === approvedScheduleRequestId)).toBe(false);
    expect(afterApply.cascadePendingRequests.some((row) => row.id === approvedScheduleRequestId)).toBe(true);
  });

  it('cascades applied schedule change requests via trusted RPC', async () => {
    const queue = await fetchOwnerScheduleChangeQueue(ownerClient);
    const pending = queue.cascadePendingRequests.find((row) => row.id === cascadePendingScheduleRequestId);
    expect(pending).toBeDefined();

    const result = await cascadeOwnerScheduleChangeRequest(ownerClient, {
      requestId: cascadePendingScheduleRequestId,
      expectedRequestUpdatedAt: pending!.updated_at,
      expectedAnchorLessonUpdatedAt: pending!.lesson_updated_at,
      expectedPassUpdatedAt: pending!.pass_updated_at,
      reason: 'Integration test cascade',
    });
    expect(result.cascade_completed_at).toBeTruthy();
    expect(result.cascaded_lesson_count).toBeGreaterThanOrEqual(0);

    const afterCascade = await fetchOwnerScheduleChangeQueue(ownerClient);
    expect(afterCascade.cascadePendingRequests.some((row) => row.id === cascadePendingScheduleRequestId)).toBe(false);
  });

  it('processes payment refund via trusted RPC and rejects duplicate attempts', async () => {
    const eligible = await fetchOwnerRefundablePayments(ownerClient);
    const beta = eligible.find((row) => row.id === betaPaymentId);
    expect(beta).toBeDefined();

    const result = await processOwnerPaymentRefund(ownerClient, {
      paymentId: betaPaymentId,
      refundedAmountKrw: beta!.paid_amount_krw,
      reason: 'Integration test refund',
    });
    expect(result.payment_status).toBe('refunded');
    expect(result.pass_status).toBe('cancelled');
    expect(result.refunded_amount_krw).toBe(200000);

    const afterRefund = await fetchOwnerRefundablePayments(ownerClient);
    expect(afterRefund.some((row) => row.id === betaPaymentId)).toBe(false);

    await expect(
      processOwnerPaymentRefund(ownerClient, {
        paymentId: betaPaymentId,
        refundedAmountKrw: 200000,
        reason: 'Duplicate refund attempt',
      }),
    ).rejects.toThrow(/REVE_REFUND_ALREADY_EXISTS/);
  });

  it('maps payment refund errors to readable messages', async () => {
    try {
      await processOwnerPaymentRefund(ownerClient, {
        paymentId: alreadyRefundedPaymentId,
        refundedAmountKrw: 200000,
        reason: 'Should fail',
      });
      expect.unreachable('expected already refunded payment to fail');
    } catch (error) {
      expect(mapRefundError(error as { message?: string })).toMatch(/이미 환불/);
    }

    try {
      await processOwnerPaymentRefund(ownerClient, {
        paymentId: deltaPaymentId,
        refundedAmountKrw: 200000,
        reason: '   ',
      });
      expect.unreachable('expected missing reason to fail');
    } catch (error) {
      expect(mapRefundError(error as { message?: string })).toMatch(/사유/);
    }
  });

  it('maps RPC transition errors to readable messages', async () => {
    const alphaLessonId = '99999999-9999-9999-9999-999999999101';
    const { data: lesson, error } = await ownerClient
      .from('lessons')
      .select('id, updated_at')
      .eq('id', alphaLessonId)
      .maybeSingle();

    expect(error).toBeNull();
    expect(lesson).toBeDefined();

    try {
      await transitionLessonStatus(ownerClient, {
        lessonId: lesson!.id,
        newStatus: 'completed',
        expectedUpdatedAt: '1970-01-01T00:00:00.000Z',
      });
      expect.unreachable('expected stale transition to fail');
    } catch (error) {
      expect(mapDatabaseError(error as { message?: string })).toMatch(/다른 사용자|새로고침/);
    }
  });

  it('rejects unauthorized pass usage reads for teacher', async () => {
    const teacherClient = createAuthClient('reve-test-teacher');
    const { error: signInError } = await teacherClient.auth.signInWithPassword({
      email: teacherEmail,
      password: teacherPassword,
    });
    expect(signInError).toBeNull();

    await expect(fetchPassUsage(teacherClient, alphaPassId)).rejects.toThrow(/REVE_UNAUTHORIZED|42501/);
  });
});

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  confirmOwnerSmsSent,
  fetchOwnerRefundablePayments,
  fetchPassUsage,
  fetchOwnerSmsNotifications,
  fetchStudentDetail,
  fetchTodayLessons,
  fetchWeeklySchedule,
  processOwnerPaymentRefund,
  transitionLessonStatus,
} from '@/lib/data/owner-queries';
import { mapDatabaseError } from '@/lib/domain/format';
import { mapRefundError } from '@/lib/domain/refund';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';
const teacherEmail = 'teacher-alpha@test.local';
const teacherPassword = 'TeacherAlpha123!';
const alphaPassId = '66666666-6666-6666-6666-666666666101';
const alphaStudentId = '44444444-4444-4444-4444-444444444101';
const deltaSmsId = '88888888-8888-8888-8888-888888888103';
const betaPaymentId = '12121212-1212-1212-1212-121212121102';
const deltaPaymentId = '12121212-1212-1212-1212-121212121101';
const alreadyRefundedPaymentId = '12121212-1212-1212-1212-121212121104';

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

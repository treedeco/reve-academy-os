import type { SupabaseClient } from '@supabase/supabase-js';

export interface OwnerPassRenewalResult {
  payment_id: string;
  payment_status: string;
  payment_updated_at: string;
  new_pass_id: string;
  new_pass_public_code: string;
  new_pass_sequence: number;
  new_pass_status: string;
  registered_lesson_count: number;
  lesson_rows_created: number;
  schedule_slots_copied: number;
  activation_required: boolean;
  activated_at: string | null;
  first_lesson_at: string | null;
  idempotent_replay: boolean;
}

type RenewalRpcRow = {
  payment_id: string;
  payment_status: string;
  payment_updated_at: string;
  new_pass_id: string;
  new_pass_public_code: string;
  new_pass_sequence: number;
  new_pass_status: string;
  registered_lesson_count: number;
  lesson_rows_created: number;
  schedule_slots_copied: number;
  activation_required: boolean;
  activated_at: string | null;
  first_lesson_at: string | null;
  idempotent_replay: boolean;
};

function readRenewalRpcRow(data: unknown): RenewalRpcRow {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Pass renewal RPC returned no data');
  }
  return row as RenewalRpcRow;
}

export async function recordOwnerPaymentAndRenewPass(
  supabase: SupabaseClient,
  input: {
    studentId: string;
    courseProductId: string;
    paidAmountKrw: number;
    paymentMethod: string;
    paidAt: string;
    idempotencyKey: string;
  },
): Promise<OwnerPassRenewalResult> {
  const { data, error } = await supabase.rpc('reve_owner_record_payment_and_renew_pass', {
    p_student_id: input.studentId,
    p_course_product_id: input.courseProductId,
    p_paid_amount_krw: input.paidAmountKrw,
    p_payment_method: input.paymentMethod,
    p_paid_at: input.paidAt,
    p_idempotency_key: input.idempotencyKey,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = readRenewalRpcRow(data);
  return {
    payment_id: row.payment_id,
    payment_status: row.payment_status,
    payment_updated_at: row.payment_updated_at,
    new_pass_id: row.new_pass_id,
    new_pass_public_code: row.new_pass_public_code,
    new_pass_sequence: row.new_pass_sequence,
    new_pass_status: row.new_pass_status,
    registered_lesson_count: row.registered_lesson_count,
    lesson_rows_created: row.lesson_rows_created,
    schedule_slots_copied: row.schedule_slots_copied,
    activation_required: row.activation_required,
    activated_at: row.activated_at,
    first_lesson_at: row.first_lesson_at,
    idempotent_replay: row.idempotent_replay,
  };
}

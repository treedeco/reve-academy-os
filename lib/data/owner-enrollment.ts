import type { SupabaseClient } from '@supabase/supabase-js';
import type { OwnerEnrollmentCatalog, OwnerInitialEnrollmentResult } from '@/lib/domain/types';

export type EnrollmentCatalogLoadState =
  | { status: 'loading' }
  | { status: 'ready'; catalog: OwnerEnrollmentCatalog }
  | { status: 'empty' }
  | { status: 'error' };

export async function loadOwnerEnrollmentCatalog(
  supabase: SupabaseClient,
): Promise<Exclude<EnrollmentCatalogLoadState, { status: 'loading' }>> {
  const [teachersResult, coursesResult, productsResult] = await Promise.all([
    supabase
      .from('teachers')
      .select('id, teacher_code, name')
      .eq('is_active', true)
      .order('name', { ascending: true }),
    supabase
      .from('courses')
      .select('id, course_code, name')
      .eq('is_active', true)
      .order('name', { ascending: true }),
    supabase
      .from('course_products')
      .select(
        'id, course_id, product_code, product_name, default_lesson_count, weekly_frequency, default_tuition_krw',
      )
      .eq('is_active', true)
      .order('product_name', { ascending: true }),
  ]);

  if (teachersResult.error || coursesResult.error || productsResult.error) {
    return { status: 'error' };
  }

  const catalog: OwnerEnrollmentCatalog = {
    teachers: teachersResult.data ?? [],
    courses: coursesResult.data ?? [],
    products: productsResult.data ?? [],
  };

  if (catalog.courses.length === 0) {
    return { status: 'empty' };
  }

  return { status: 'ready', catalog };
}

/** @deprecated Use loadOwnerEnrollmentCatalog for UI state handling. */
export async function fetchOwnerEnrollmentCatalog(
  supabase: SupabaseClient,
): Promise<OwnerEnrollmentCatalog> {
  const result = await loadOwnerEnrollmentCatalog(supabase);
  if (result.status === 'error') {
    throw new Error('Failed to load enrollment catalog');
  }
  if (result.status === 'empty') {
    return { teachers: [], courses: [], products: [] };
  }
  return result.catalog;
}

type EnrollmentRpcRow = {
  payment_id: string;
  payment_status: string;
  payment_updated_at: string;
  pass_id: string;
  pass_public_code: string;
  pass_sequence_number: number;
  pass_status: string;
  registered_lesson_count: number;
  schedule_slots_created: number;
  lesson_rows_created: number;
  first_lesson_at: string | null;
  last_lesson_at: string | null;
  sms_notification_status: string | null;
  idempotent_replay: boolean;
};

function readEnrollmentRpcRow(data: unknown): EnrollmentRpcRow {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Initial enrollment RPC returned no data');
  }
  return row as EnrollmentRpcRow;
}

export async function createOwnerInitialEnrollment(
  supabase: SupabaseClient,
  input: {
    studentId: string;
    courseProductId: string;
    scheduleStartDate: string;
    scheduleSlots: unknown[];
    paidAmountKrw: number;
    paymentMethod: string;
    paidAt: string;
    idempotencyKey: string;
    ownerReason?: string | null;
  },
): Promise<OwnerInitialEnrollmentResult> {
  const { data, error } = await supabase.rpc('reve_owner_create_initial_enrollment', {
    p_student_id: input.studentId,
    p_course_product_id: input.courseProductId,
    p_schedule_start_date: input.scheduleStartDate,
    p_schedule_slots: input.scheduleSlots,
    p_paid_amount_krw: input.paidAmountKrw,
    p_payment_method: input.paymentMethod,
    p_paid_at: input.paidAt,
    p_idempotency_key: input.idempotencyKey,
    p_owner_reason: input.ownerReason ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const row = readEnrollmentRpcRow(data);
  return {
    payment_id: row.payment_id,
    payment_status: row.payment_status,
    pass_id: row.pass_id,
    pass_public_code: row.pass_public_code,
    pass_sequence_number: row.pass_sequence_number,
    pass_status: row.pass_status,
    registered_lesson_count: row.registered_lesson_count,
    schedule_slots_created: row.schedule_slots_created,
    lesson_rows_created: row.lesson_rows_created,
    first_lesson_at: row.first_lesson_at,
    last_lesson_at: row.last_lesson_at,
    sms_notification_status: row.sms_notification_status,
    idempotent_replay: row.idempotent_replay,
  };
}

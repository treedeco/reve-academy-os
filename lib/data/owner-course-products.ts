import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  OwnerCourseProductMutationResult,
  OwnerCourseProductRow,
  OwnerEnrollmentCourseOption,
} from '@/lib/domain/types';

type CourseProductQueryRow = {
  id: string;
  course_id: string;
  product_code: string;
  product_name: string;
  default_lesson_count: number;
  weekly_frequency: number;
  default_tuition_krw: number;
  expiration_policy: string | null;
  is_active: boolean;
  updated_at: string;
  courses: {
    course_code: string;
    name: string;
  } | {
    course_code: string;
    name: string;
  }[] | null;
};

type CourseProductRpcRow = {
  course_product_id: string;
  course_id: string;
  product_code: string;
  product_name: string;
  default_lesson_count: number;
  weekly_frequency: number;
  default_tuition_krw: number;
  expiration_policy: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

function readJoinedCourse(
  courses: CourseProductQueryRow['courses'],
): { course_code: string; name: string } | null {
  if (!courses) {
    return null;
  }
  return Array.isArray(courses) ? (courses[0] ?? null) : courses;
}

function mapCourseProductQueryRow(row: CourseProductQueryRow): OwnerCourseProductRow {
  const course = readJoinedCourse(row.courses);
  return {
    id: row.id,
    course_id: row.course_id,
    course_code: course?.course_code ?? '',
    course_name: course?.name ?? '',
    product_code: row.product_code,
    product_name: row.product_name,
    default_lesson_count: row.default_lesson_count,
    weekly_frequency: row.weekly_frequency,
    default_tuition_krw: row.default_tuition_krw,
    expiration_policy: row.expiration_policy,
    is_active: row.is_active,
    updated_at: row.updated_at,
  };
}

function readRpcRow(data: unknown): CourseProductRpcRow {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Course product RPC returned no data');
  }
  return row as CourseProductRpcRow;
}

function mapCourseProductRpcRow(
  row: CourseProductRpcRow,
  courseMeta?: Pick<OwnerCourseProductRow, 'course_code' | 'course_name'>,
): OwnerCourseProductMutationResult {
  return {
    id: row.course_product_id,
    course_id: row.course_id,
    course_code: courseMeta?.course_code ?? '',
    course_name: courseMeta?.course_name ?? '',
    product_code: row.product_code,
    product_name: row.product_name,
    default_lesson_count: row.default_lesson_count,
    weekly_frequency: row.weekly_frequency,
    default_tuition_krw: row.default_tuition_krw,
    expiration_policy: row.expiration_policy,
    is_active: row.is_active,
    updated_at: row.updated_at,
  };
}

/**
 * Owner course product list read.
 * Query count: 1 (course_products + course join). Zero per-row requests.
 */
export async function fetchOwnerCourseProductList(
  supabase: SupabaseClient,
): Promise<OwnerCourseProductRow[]> {
  const { data, error } = await supabase
    .from('course_products')
    .select(
      `
      id,
      course_id,
      product_code,
      product_name,
      default_lesson_count,
      weekly_frequency,
      default_tuition_krw,
      expiration_policy,
      is_active,
      updated_at,
      courses ( course_code, name )
    `,
    )
    .order('product_name', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return (data ?? []).map((row) => mapCourseProductQueryRow(row as CourseProductQueryRow));
}

export async function fetchOwnerActiveCourses(
  supabase: SupabaseClient,
): Promise<OwnerEnrollmentCourseOption[]> {
  const { data, error } = await supabase
    .from('courses')
    .select('id, course_code, name')
    .eq('is_active', true)
    .order('name', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return (data ?? []) as OwnerEnrollmentCourseOption[];
}

export async function createOwnerCourseProduct(
  supabase: SupabaseClient,
  input: {
    courseId: string;
    productCode: string;
    productName: string;
    defaultLessonCount: number;
    weeklyFrequency: number;
    defaultTuitionKrw: number;
    expirationPolicy?: string | null;
    courseMeta?: Pick<OwnerCourseProductRow, 'course_code' | 'course_name'>;
  },
): Promise<OwnerCourseProductMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_create_course_product', {
    p_course_id: input.courseId,
    p_product_code: input.productCode,
    p_product_name: input.productName,
    p_default_lesson_count: input.defaultLessonCount,
    p_weekly_frequency: input.weeklyFrequency,
    p_default_tuition_krw: input.defaultTuitionKrw,
    p_expiration_policy: input.expirationPolicy ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  return mapCourseProductRpcRow(readRpcRow(data), input.courseMeta);
}

export async function updateOwnerCourseProduct(
  supabase: SupabaseClient,
  input: {
    courseProductId: string;
    expectedUpdatedAt: string;
    productName: string;
    defaultLessonCount: number;
    weeklyFrequency: number;
    defaultTuitionKrw: number;
    expirationPolicy?: string | null;
    courseMeta?: Pick<OwnerCourseProductRow, 'course_code' | 'course_name'>;
  },
): Promise<OwnerCourseProductMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_update_course_product', {
    p_course_product_id: input.courseProductId,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_product_name: input.productName,
    p_default_lesson_count: input.defaultLessonCount,
    p_weekly_frequency: input.weeklyFrequency,
    p_default_tuition_krw: input.defaultTuitionKrw,
    p_expiration_policy: input.expirationPolicy ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }

  return mapCourseProductRpcRow(readRpcRow(data), input.courseMeta);
}

export async function setOwnerCourseProductActive(
  supabase: SupabaseClient,
  input: {
    courseProductId: string;
    isActive: boolean;
    reason: string;
    expectedUpdatedAt: string;
    courseMeta?: Pick<OwnerCourseProductRow, 'course_code' | 'course_name'>;
  },
): Promise<OwnerCourseProductMutationResult> {
  const { data, error } = await supabase.rpc('reve_owner_set_course_product_active', {
    p_course_product_id: input.courseProductId,
    p_is_active: input.isActive,
    p_reason: input.reason,
    p_expected_updated_at: input.expectedUpdatedAt,
  });

  if (error) {
    throw new Error(error.message);
  }

  return mapCourseProductRpcRow(readRpcRow(data), input.courseMeta);
}

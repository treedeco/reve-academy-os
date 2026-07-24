'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import {
  createOwnerCourseProduct,
  setOwnerCourseProductActive,
  updateOwnerCourseProduct,
} from '@/lib/data/owner-course-products';
import {
  formatCourseProductStatusLabel,
  formatTuitionKrw,
  mapCourseProductMasterDataError,
  validateCourseProductForm,
  type CourseProductFormInput,
} from '@/lib/domain/course-product-master-data';
import { formatDateTimeSeoul } from '@/lib/domain/format';
import type {
  OwnerCourseProductRow,
  OwnerEnrollmentCourseOption,
} from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

type CreateFormState = CourseProductFormInput & {
  courseId: string;
};

type StatusFormState = {
  reason: string;
};

const EMPTY_CREATE_FORM: CreateFormState = {
  courseId: '',
  productCode: '',
  productName: '',
  defaultLessonCount: '',
  weeklyFrequency: '1',
  defaultTuitionKrw: '',
  expirationPolicy: '',
};

function buildEditForm(product: OwnerCourseProductRow): CourseProductFormInput {
  return {
    productCode: product.product_code,
    productName: product.product_name,
    defaultLessonCount: String(product.default_lesson_count),
    weeklyFrequency: String(product.weekly_frequency),
    defaultTuitionKrw: String(product.default_tuition_krw),
    expirationPolicy: product.expiration_policy ?? '',
  };
}

function courseMetaFromList(
  courses: OwnerEnrollmentCourseOption[],
  courseId: string,
): Pick<OwnerCourseProductRow, 'course_code' | 'course_name'> | undefined {
  const course = courses.find((row) => row.id === courseId);
  if (!course) {
    return undefined;
  }
  return { course_code: course.course_code, course_name: course.name };
}

export function CourseProductsPanel({
  initialProducts,
  activeCourses,
}: {
  initialProducts: OwnerCourseProductRow[];
  activeCourses: OwnerEnrollmentCourseOption[];
}) {
  const [products, setProducts] = useState(initialProducts);
  const [courseFilter, setCourseFilter] = useState('all');
  const [createForm, setCreateForm] = useState<CreateFormState>(EMPTY_CREATE_FORM);
  const [editForms, setEditForms] = useState<Record<string, CourseProductFormInput>>({});
  const [statusForms, setStatusForms] = useState<Record<string, StatusFormState>>({});
  const [editingId, setEditingId] = useState<string | null>(null);
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [createError, setCreateError] = useState('');
  const [errorById, setErrorById] = useState<Record<string, string>>({});

  const productMap = useMemo(() => new Map(products.map((row) => [row.id, row])), [products]);

  const filteredProducts = useMemo(() => {
    const rows =
      courseFilter === 'all'
        ? products
        : products.filter((product) => product.course_id === courseFilter);
    return [...rows].sort((left, right) => {
      const courseCompare = left.course_name.localeCompare(right.course_name, 'ko');
      if (courseCompare !== 0) {
        return courseCompare;
      }
      return left.product_name.localeCompare(right.product_name, 'ko');
    });
  }, [courseFilter, products]);

  const groupedProducts = useMemo(() => {
    const groups = new Map<string, OwnerCourseProductRow[]>();
    for (const product of filteredProducts) {
      const key = `${product.course_code}|${product.course_name}`;
      const bucket = groups.get(key) ?? [];
      bucket.push(product);
      groups.set(key, bucket);
    }
    return [...groups.entries()];
  }, [filteredProducts]);

  function clearProductError(productId: string) {
    setErrorById((prev) => ({ ...prev, [productId]: '' }));
  }

  async function handleCreate() {
    if (pendingKey === 'create') {
      return;
    }

    if (!createForm.courseId) {
      setCreateError('과목을 선택해 주세요.');
      return;
    }

    const validationError = validateCourseProductForm(createForm, { requireCode: true });
    if (validationError) {
      setCreateError(validationError);
      return;
    }

    setPendingKey('create');
    setCreateError('');

    try {
      const supabase = createClient();
      const courseMeta = courseMetaFromList(activeCourses, createForm.courseId);
      const created = await createOwnerCourseProduct(supabase, {
        courseId: createForm.courseId,
        productCode: createForm.productCode.trim(),
        productName: createForm.productName.trim(),
        defaultLessonCount: Number(createForm.defaultLessonCount),
        weeklyFrequency: Number(createForm.weeklyFrequency),
        defaultTuitionKrw: Number(createForm.defaultTuitionKrw),
        expirationPolicy: createForm.expirationPolicy.trim() || null,
        courseMeta,
      });

      setProducts((prev) =>
        [...prev, created].sort((left, right) => {
          const courseCompare = left.course_name.localeCompare(right.course_name, 'ko');
          if (courseCompare !== 0) {
            return courseCompare;
          }
          return left.product_name.localeCompare(right.product_name, 'ko');
        }),
      );
      setCreateForm(EMPTY_CREATE_FORM);
    } catch (error) {
      setCreateError(mapCourseProductMasterDataError(error as { message?: string }));
    } finally {
      setPendingKey(null);
    }
  }

  async function handleUpdate(productId: string) {
    const current = productMap.get(productId);
    const form = editForms[productId];
    if (!current || !form || pendingKey === productId) {
      return;
    }

    const validationError = validateCourseProductForm(form, { requireCode: false });
    if (validationError) {
      setErrorById((prev) => ({ ...prev, [productId]: validationError }));
      return;
    }

    setPendingKey(productId);
    clearProductError(productId);

    try {
      const supabase = createClient();
      const updated = await updateOwnerCourseProduct(supabase, {
        courseProductId: productId,
        expectedUpdatedAt: current.updated_at,
        productName: form.productName.trim(),
        defaultLessonCount: Number(form.defaultLessonCount),
        weeklyFrequency: Number(form.weeklyFrequency),
        defaultTuitionKrw: Number(form.defaultTuitionKrw),
        expirationPolicy: form.expirationPolicy.trim() || null,
        courseMeta: {
          course_code: current.course_code,
          course_name: current.course_name,
        },
      });

      setProducts((prev) => prev.map((row) => (row.id === productId ? updated : row)));
      setEditingId(null);
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [productId]: mapCourseProductMasterDataError(error as { message?: string }),
      }));
    } finally {
      setPendingKey(null);
    }
  }

  async function handleStatusChange(productId: string, nextActive: boolean) {
    const current = productMap.get(productId);
    if (!current || pendingKey === productId) {
      return;
    }

    const reason = statusForms[productId]?.reason?.trim() ?? '';
    if (!reason) {
      setErrorById((prev) => ({
        ...prev,
        [productId]: '상태 변경 사유를 입력해 주세요.',
      }));
      return;
    }

    if (!nextActive) {
      const confirmed = window.confirm(`${current.product_name} 상품을 비활성화할까요?`);
      if (!confirmed) {
        return;
      }
    }

    setPendingKey(productId);
    clearProductError(productId);

    try {
      const supabase = createClient();
      const updated = await setOwnerCourseProductActive(supabase, {
        courseProductId: productId,
        isActive: nextActive,
        reason,
        expectedUpdatedAt: current.updated_at,
        courseMeta: {
          course_code: current.course_code,
          course_name: current.course_name,
        },
      });

      setProducts((prev) => prev.map((row) => (row.id === productId ? updated : row)));
      setStatusForms((prev) => ({ ...prev, [productId]: { reason: '' } }));
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [productId]: mapCourseProductMasterDataError(error as { message?: string }),
      }));
    } finally {
      setPendingKey(null);
    }
  }

  function startEditing(product: OwnerCourseProductRow) {
    setEditingId(product.id);
    setEditForms((prev) => ({ ...prev, [product.id]: buildEditForm(product) }));
    clearProductError(product.id);
  }

  function cancelEditing(productId: string) {
    setEditingId((current) => (current === productId ? null : current));
    clearProductError(productId);
  }

  return (
    <div className="space-y-6" data-testid="course-products-panel">
      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <label className="block text-sm">
          <span className="text-slate-600">과목 필터</span>
          <select
            value={courseFilter}
            onChange={(event) => setCourseFilter(event.target.value)}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 sm:max-w-xs"
            data-testid="course-products-filter"
          >
            <option value="all">전체 과목</option>
            {activeCourses.map((course) => (
              <option key={course.id} value={course.id}>
                {course.name} ({course.course_code})
              </option>
            ))}
          </select>
        </label>
      </section>

      <section
        className="rounded-lg border border-slate-200 bg-white p-4"
        data-testid="product-create-section"
      >
        <h2 className="text-lg font-semibold">상품 등록</h2>
        <p className="mt-1 text-sm text-slate-600">
          과목별 수강 상품의 회차, 주당 빈도, 수강료를 등록합니다.
        </p>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <label className="block text-sm">
            <span className="text-slate-600">과목</span>
            <select
              value={createForm.courseId}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, courseId: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="product-create-course"
              disabled={pendingKey === 'create'}
            >
              <option value="">과목 선택</option>
              {activeCourses.map((course) => (
                <option key={course.id} value={course.id}>
                  {course.name} ({course.course_code})
                </option>
              ))}
            </select>
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">상품 코드</span>
            <input
              type="text"
              value={createForm.productCode}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, productCode: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="product-create-code"
              disabled={pendingKey === 'create'}
              placeholder="예: V-4-001"
            />
          </label>
          <label className="block text-sm sm:col-span-2">
            <span className="text-slate-600">상품명</span>
            <input
              type="text"
              value={createForm.productName}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, productName: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="product-create-name"
              disabled={pendingKey === 'create'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">등록 회차</span>
            <input
              type="number"
              min={1}
              step={1}
              value={createForm.defaultLessonCount}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, defaultLessonCount: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="product-create-lesson-count"
              disabled={pendingKey === 'create'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">주당 수업 횟수</span>
            <input
              type="number"
              min={1}
              step={1}
              value={createForm.weeklyFrequency}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, weeklyFrequency: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="product-create-weekly-frequency"
              disabled={pendingKey === 'create'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">수강료 (원)</span>
            <input
              type="number"
              min={0}
              step={1}
              value={createForm.defaultTuitionKrw}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, defaultTuitionKrw: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="product-create-tuition"
              disabled={pendingKey === 'create'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">만료 정책 (선택)</span>
            <input
              type="text"
              value={createForm.expirationPolicy}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, expirationPolicy: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="product-create-expiration"
              disabled={pendingKey === 'create'}
            />
          </label>
        </div>
        {createError ? (
          <p className="mt-3 text-sm text-red-600" role="alert" data-testid="product-create-error">
            {createError}
          </p>
        ) : null}
        <button
          type="button"
          onClick={handleCreate}
          disabled={pendingKey === 'create'}
          className="mt-4 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
          data-testid="product-create-submit"
        >
          {pendingKey === 'create' ? '등록 중…' : '상품 등록'}
        </button>
      </section>

      {products.length === 0 ? (
        <div
          data-testid="course-products-empty"
          className="rounded-lg border border-dashed border-slate-300 bg-white p-8 text-center"
        >
          <p className="font-medium text-slate-900">등록된 수강 상품이 없습니다</p>
          <p className="mt-2 text-sm text-slate-600">
            위 양식으로 과목별 첫 상품을 등록해 주세요. 등록 후 초기 등록 화면에서 선택할 수
            있습니다.
          </p>
        </div>
      ) : filteredProducts.length === 0 ? (
        <div
          data-testid="course-products-filter-empty"
          className="rounded-lg border border-dashed border-slate-300 bg-white p-8 text-center"
        >
          <p className="font-medium text-slate-900">선택한 과목에 등록된 상품이 없습니다</p>
          <p className="mt-2 text-sm text-slate-600">다른 과목을 선택하거나 새 상품을 등록해 주세요.</p>
        </div>
      ) : (
        <div className="space-y-6" data-testid="course-products-list">
          {groupedProducts.map(([courseLabel, courseProducts]) => {
            const [courseCode, courseName] = courseLabel.split('|');
            return (
              <section key={courseLabel} data-testid={`course-products-group-${courseCode}`}>
                <h2 className="text-base font-semibold text-slate-900">
                  {courseName} ({courseCode})
                </h2>
                <div className="mt-3 space-y-4">
                  {courseProducts.map((product) => {
                    const isEditing = editingId === product.id;
                    const isPending = pendingKey === product.id;
                    const editForm = editForms[product.id] ?? buildEditForm(product);
                    const statusReason = statusForms[product.id]?.reason ?? '';
                    const rowError = errorById[product.id];

                    return (
                      <article
                        key={product.id}
                        data-testid={`product-item-${product.product_code}`}
                        className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
                      >
                        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                          <div className="min-w-0 flex-1 space-y-2">
                            <div className="flex flex-wrap items-center gap-2">
                              <h3 className="text-base font-semibold text-slate-900">
                                {product.product_name}
                              </h3>
                              <span
                                className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                                  product.is_active
                                    ? 'bg-emerald-50 text-emerald-700'
                                    : 'bg-slate-100 text-slate-600'
                                }`}
                                data-testid={`product-status-${product.product_code}`}
                              >
                                {formatCourseProductStatusLabel(product.is_active)}
                              </span>
                            </div>
                            <p className="text-sm text-slate-600">코드: {product.product_code}</p>
                            {!isEditing ? (
                              <dl className="grid gap-1 text-sm text-slate-600 sm:grid-cols-2">
                                <div>
                                  <dt className="inline text-slate-500">등록 회차 </dt>
                                  <dd className="inline">{product.default_lesson_count}회</dd>
                                </div>
                                <div>
                                  <dt className="inline text-slate-500">주당 수업 </dt>
                                  <dd className="inline">주 {product.weekly_frequency}회</dd>
                                </div>
                                <div>
                                  <dt className="inline text-slate-500">수강료 </dt>
                                  <dd className="inline">
                                    {formatTuitionKrw(product.default_tuition_krw)}
                                  </dd>
                                </div>
                                <div>
                                  <dt className="inline text-slate-500">만료 정책 </dt>
                                  <dd className="inline">{product.expiration_policy ?? '-'}</dd>
                                </div>
                                <div className="sm:col-span-2">
                                  <dt className="inline text-slate-500">수정 시각 </dt>
                                  <dd className="inline">
                                    {formatDateTimeSeoul(product.updated_at)}
                                  </dd>
                                </div>
                              </dl>
                            ) : (
                              <div className="grid gap-3 sm:grid-cols-2">
                                <label className="block text-sm sm:col-span-2">
                                  <span className="text-slate-600">상품명</span>
                                  <input
                                    type="text"
                                    value={editForm.productName}
                                    onChange={(event) =>
                                      setEditForms((prev) => ({
                                        ...prev,
                                        [product.id]: {
                                          ...editForm,
                                          productName: event.target.value,
                                        },
                                      }))
                                    }
                                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                                    data-testid={`product-edit-name-${product.product_code}`}
                                    disabled={isPending}
                                  />
                                </label>
                                <label className="block text-sm">
                                  <span className="text-slate-600">등록 회차</span>
                                  <input
                                    type="number"
                                    min={1}
                                    step={1}
                                    value={editForm.defaultLessonCount}
                                    onChange={(event) =>
                                      setEditForms((prev) => ({
                                        ...prev,
                                        [product.id]: {
                                          ...editForm,
                                          defaultLessonCount: event.target.value,
                                        },
                                      }))
                                    }
                                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                                    data-testid={`product-edit-lesson-count-${product.product_code}`}
                                    disabled={isPending}
                                  />
                                </label>
                                <label className="block text-sm">
                                  <span className="text-slate-600">주당 수업 횟수</span>
                                  <input
                                    type="number"
                                    min={1}
                                    step={1}
                                    value={editForm.weeklyFrequency}
                                    onChange={(event) =>
                                      setEditForms((prev) => ({
                                        ...prev,
                                        [product.id]: {
                                          ...editForm,
                                          weeklyFrequency: event.target.value,
                                        },
                                      }))
                                    }
                                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                                    data-testid={`product-edit-weekly-frequency-${product.product_code}`}
                                    disabled={isPending}
                                  />
                                </label>
                                <label className="block text-sm">
                                  <span className="text-slate-600">수강료 (원)</span>
                                  <input
                                    type="number"
                                    min={0}
                                    step={1}
                                    value={editForm.defaultTuitionKrw}
                                    onChange={(event) =>
                                      setEditForms((prev) => ({
                                        ...prev,
                                        [product.id]: {
                                          ...editForm,
                                          defaultTuitionKrw: event.target.value,
                                        },
                                      }))
                                    }
                                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                                    data-testid={`product-edit-tuition-${product.product_code}`}
                                    disabled={isPending}
                                  />
                                </label>
                                <label className="block text-sm">
                                  <span className="text-slate-600">만료 정책 (선택)</span>
                                  <input
                                    type="text"
                                    value={editForm.expirationPolicy}
                                    onChange={(event) =>
                                      setEditForms((prev) => ({
                                        ...prev,
                                        [product.id]: {
                                          ...editForm,
                                          expirationPolicy: event.target.value,
                                        },
                                      }))
                                    }
                                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                                    data-testid={`product-edit-expiration-${product.product_code}`}
                                    disabled={isPending}
                                  />
                                </label>
                              </div>
                            )}
                            {rowError ? (
                              <p
                                className="text-sm text-red-600"
                                role="alert"
                                data-testid={`product-error-${product.product_code}`}
                              >
                                {rowError}
                              </p>
                            ) : null}
                          </div>

                          <div className="flex shrink-0 flex-col gap-2 sm:flex-row lg:flex-col">
                            {isEditing ? (
                              <>
                                <button
                                  type="button"
                                  onClick={() => handleUpdate(product.id)}
                                  disabled={isPending}
                                  className="rounded-md bg-brand-600 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
                                  data-testid={`product-save-${product.product_code}`}
                                >
                                  {isPending ? '저장 중…' : '저장'}
                                </button>
                                <button
                                  type="button"
                                  onClick={() => cancelEditing(product.id)}
                                  disabled={isPending}
                                  className="rounded-md border border-slate-300 px-3 py-2 text-sm"
                                  data-testid={`product-cancel-${product.product_code}`}
                                >
                                  취소
                                </button>
                              </>
                            ) : (
                              <button
                                type="button"
                                onClick={() => startEditing(product)}
                                disabled={isPending}
                                className="rounded-md border border-slate-300 px-3 py-2 text-sm"
                                data-testid={`product-edit-${product.product_code}`}
                              >
                                수정
                              </button>
                            )}
                          </div>
                        </div>

                        <div className="mt-4 border-t border-slate-100 pt-4">
                          <label className="block text-sm">
                            <span className="text-slate-600">상태 변경 사유</span>
                            <input
                              type="text"
                              value={statusReason}
                              onChange={(event) =>
                                setStatusForms((prev) => ({
                                  ...prev,
                                  [product.id]: { reason: event.target.value },
                                }))
                              }
                              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                              data-testid={`product-status-reason-${product.product_code}`}
                              disabled={isPending}
                            />
                          </label>
                          <div className="mt-3 flex flex-wrap gap-2">
                            {product.is_active ? (
                              <button
                                type="button"
                                onClick={() => handleStatusChange(product.id, false)}
                                disabled={isPending}
                                className="rounded-md border border-amber-300 px-3 py-2 text-sm text-amber-800 disabled:opacity-50"
                                data-testid={`product-deactivate-${product.product_code}`}
                              >
                                비활성화
                              </button>
                            ) : (
                              <button
                                type="button"
                                onClick={() => handleStatusChange(product.id, true)}
                                disabled={isPending}
                                className="rounded-md border border-emerald-300 px-3 py-2 text-sm text-emerald-800 disabled:opacity-50"
                                data-testid={`product-reactivate-${product.product_code}`}
                              >
                                다시 활성화
                              </button>
                            )}
                          </div>
                        </div>
                      </article>
                    );
                  })}
                </div>
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function CourseProductsManageLink() {
  return (
    <Link
      href="/course-products"
      className="font-medium text-brand-700 underline"
      data-testid="course-products-manage-link"
    >
      수강 상품 관리
    </Link>
  );
}

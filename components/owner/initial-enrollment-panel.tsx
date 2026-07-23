'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  createOwnerInitialEnrollment,
  loadOwnerEnrollmentCatalog,
  type EnrollmentCatalogLoadState,
} from '@/lib/data/owner-enrollment';
import {
  ENROLLMENT_CATALOG_EMPTY_MESSAGE,
  ENROLLMENT_CATALOG_ERROR_MESSAGE,
  ENROLLMENT_CATALOG_LOADING_MESSAGE,
  ENROLLMENT_PRODUCT_EMPTY_MESSAGE,
} from '@/lib/domain/enrollment-catalog-messages';
import {
  ENROLLMENT_PAYMENT_METHODS,
  buildDefaultScheduleSlots,
  buildScheduleSlotsPayload,
  mapInitialEnrollmentError,
  validateInitialEnrollmentForm,
  type EnrollmentPaymentMethod,
} from '@/lib/domain/initial-enrollment';
import type {
  EnrollmentScheduleSlotInput,
  OwnerEnrollmentCatalog,
  OwnerInitialEnrollmentResult,
  OwnerStudentRow,
} from '@/lib/domain/types';
import { WEEKDAY_LABELS } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

function formatTodayDateInput(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function InitialEnrollmentPanel({
  student,
  onEnrollmentComplete,
}: {
  student: OwnerStudentRow;
  onEnrollmentComplete: (result: OwnerInitialEnrollmentResult) => Promise<void>;
}) {
  const idempotencyKeyRef = useRef(crypto.randomUUID());
  const [catalogState, setCatalogState] = useState<EnrollmentCatalogLoadState>({ status: 'loading' });
  const [courseId, setCourseId] = useState('');
  const [productId, setProductId] = useState('');
  const [scheduleStartDate, setScheduleStartDate] = useState(formatTodayDateInput());
  const [paymentMethod, setPaymentMethod] = useState<EnrollmentPaymentMethod>('cash');
  const [slots, setSlots] = useState<EnrollmentScheduleSlotInput[]>([]);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');
  const [successMessage, setSuccessMessage] = useState('');

  const loadCatalog = useCallback(async () => {
    setCatalogState({ status: 'loading' });
    const supabase = createClient();
    const result = await loadOwnerEnrollmentCatalog(supabase);
    setCatalogState(result);
  }, []);

  useEffect(() => {
    void loadCatalog();
  }, [loadCatalog]);

  const catalog: OwnerEnrollmentCatalog | null =
    catalogState.status === 'ready' ? catalogState.catalog : null;

  const selectedProduct = useMemo(
    () => catalog?.products.find((product) => product.id === productId) ?? null,
    [catalog?.products, productId],
  );

  const productsForCourse = useMemo(
    () => catalog?.products.filter((product) => product.course_id === courseId) ?? [],
    [catalog?.products, courseId],
  );

  const canSubmit =
    catalogState.status === 'ready' &&
    Boolean(selectedProduct) &&
    slots.length > 0 &&
    !pending;

  function handleCourseChange(nextCourseId: string) {
    setCourseId(nextCourseId);
    setProductId('');
    setSlots([]);
    setError('');
    setSuccessMessage('');
  }

  function handleProductChange(nextProductId: string) {
    const product = catalog?.products.find((row) => row.id === nextProductId) ?? null;
    setProductId(nextProductId);
    setError('');
    setSuccessMessage('');

    if (!product) {
      setSlots([]);
      return;
    }

    const defaultTeacherId = catalog?.teachers[0]?.id ?? '';
    setSlots(buildDefaultScheduleSlots(product, defaultTeacherId));
  }

  function updateSlot(index: number, patch: Partial<EnrollmentScheduleSlotInput>) {
    setSlots((prev) => prev.map((slot, slotIndex) => (slotIndex === index ? { ...slot, ...patch } : slot)));
  }

  async function handleSubmit() {
    if (!canSubmit || pending) {
      return;
    }

    const validationError = validateInitialEnrollmentForm({
      courseProductId: productId,
      scheduleStartDate,
      paymentMethod,
      product: selectedProduct,
      slots,
    });
    if (validationError) {
      setError(validationError);
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      const result = await createOwnerInitialEnrollment(supabase, {
        studentId: student.id,
        courseProductId: productId,
        scheduleStartDate,
        scheduleSlots: buildScheduleSlotsPayload(slots),
        paidAmountKrw: selectedProduct!.default_tuition_krw,
        paymentMethod,
        paidAt: new Date().toISOString(),
        idempotencyKey: idempotencyKeyRef.current,
        ownerReason: 'owner_initial_enrollment_ui',
      });

      await onEnrollmentComplete(result);
      setSuccessMessage(
        `${result.pass_public_code} 회차권이 생성되었습니다. (${result.lesson_rows_created}회 수업)`,
      );
      idempotencyKeyRef.current = crypto.randomUUID();
    } catch (submitError) {
      setError(mapInitialEnrollmentError(submitError as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  if (student.operational_status !== 'active') {
    return null;
  }

  return (
    <section
      className="rounded-lg border border-slate-200 bg-white p-4"
      data-testid="initial-enrollment-panel"
    >
      <h2 className="text-lg font-semibold">초기 등록</h2>
      <p className="mt-1 text-sm text-slate-600">
        강사, 과목, 상품, 고정 일정을 선택해 첫 회차권과 수업을 생성합니다.
      </p>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="block text-sm">
          <span className="text-slate-600">과목</span>
          <select
            value={courseId}
            onChange={(event) => handleCourseChange(event.target.value)}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="enrollment-course"
            disabled={pending || catalogState.status !== 'ready'}
          >
            <option value="">과목 선택</option>
            {catalog?.courses.map((course) => (
              <option key={course.id} value={course.id}>
                {course.name} ({course.course_code})
              </option>
            ))}
          </select>
          {catalogState.status === 'loading' ? (
            <p className="mt-1 text-xs text-slate-500" role="status" data-testid="enrollment-course-loading">
              {ENROLLMENT_CATALOG_LOADING_MESSAGE}
            </p>
          ) : null}
          {catalogState.status === 'empty' ? (
            <p className="mt-1 text-xs text-amber-700" role="status" data-testid="enrollment-course-empty">
              {ENROLLMENT_CATALOG_EMPTY_MESSAGE}
            </p>
          ) : null}
          {catalogState.status === 'error' ? (
            <div className="mt-1 space-y-2">
              <p className="text-xs text-red-600" role="alert" data-testid="enrollment-course-error">
                {ENROLLMENT_CATALOG_ERROR_MESSAGE}
              </p>
              <button
                type="button"
                onClick={() => void loadCatalog()}
                className="text-xs font-medium text-brand-700 underline"
                data-testid="enrollment-course-retry"
              >
                다시 시도
              </button>
            </div>
          ) : null}
        </label>

        <label className="block text-sm">
          <span className="text-slate-600">상품</span>
          <select
            value={productId}
            onChange={(event) => handleProductChange(event.target.value)}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="enrollment-product"
            disabled={pending || !courseId || catalogState.status !== 'ready'}
          >
            <option value="">상품 선택</option>
            {productsForCourse.map((product) => (
              <option key={product.id} value={product.id}>
                {product.product_name} · {product.default_lesson_count}회 · 주{' '}
                {product.weekly_frequency}회 · {product.default_tuition_krw.toLocaleString('ko-KR')}원
              </option>
            ))}
          </select>
          {courseId && catalogState.status === 'ready' && productsForCourse.length === 0 ? (
            <p className="mt-1 text-xs text-amber-700" role="status" data-testid="enrollment-product-empty">
              {ENROLLMENT_PRODUCT_EMPTY_MESSAGE}
            </p>
          ) : null}
        </label>

        <label className="block text-sm">
          <span className="text-slate-600">일정 시작일</span>
          <input
            type="date"
            value={scheduleStartDate}
            onChange={(event) => setScheduleStartDate(event.target.value)}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="enrollment-start-date"
            disabled={pending || catalogState.status !== 'ready'}
          />
        </label>

        <label className="block text-sm">
          <span className="text-slate-600">결제 수단</span>
          <select
            value={paymentMethod}
            onChange={(event) => setPaymentMethod(event.target.value as EnrollmentPaymentMethod)}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="enrollment-payment-method"
            disabled={pending || catalogState.status !== 'ready'}
          >
            {ENROLLMENT_PAYMENT_METHODS.map((method) => (
              <option key={method.value} value={method.value}>
                {method.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      {selectedProduct ? (
        <div className="mt-4 space-y-3" data-testid="enrollment-schedule-slots">
          <p className="text-sm font-medium text-slate-700">
            고정 일정 ({selectedProduct.weekly_frequency}개)
          </p>
          {slots.map((slot, index) => (
            <div
              key={`slot-${slot.slotOrder}`}
              className="grid gap-3 rounded-md border border-slate-100 bg-slate-50 p-3 sm:grid-cols-2 lg:grid-cols-4"
              data-testid={`enrollment-slot-${slot.slotOrder}`}
            >
              <label className="block text-sm">
                <span className="text-slate-600">강사</span>
                <select
                  value={slot.teacherId}
                  onChange={(event) => updateSlot(index, { teacherId: event.target.value })}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  data-testid={`enrollment-slot-teacher-${slot.slotOrder}`}
                  disabled={pending}
                >
                  <option value="">강사 선택</option>
                  {catalog?.teachers.map((teacher) => (
                    <option key={teacher.id} value={teacher.id}>
                      {teacher.name} ({teacher.teacher_code})
                    </option>
                  ))}
                </select>
              </label>
              <label className="block text-sm">
                <span className="text-slate-600">요일</span>
                <select
                  value={slot.weekday}
                  onChange={(event) =>
                    updateSlot(index, { weekday: Number.parseInt(event.target.value, 10) })
                  }
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  data-testid={`enrollment-slot-weekday-${slot.slotOrder}`}
                  disabled={pending}
                >
                  {WEEKDAY_LABELS.map((label, weekday) => (
                    <option key={label} value={weekday}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block text-sm">
                <span className="text-slate-600">시간</span>
                <input
                  type="time"
                  value={slot.localTime}
                  onChange={(event) => updateSlot(index, { localTime: event.target.value })}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  data-testid={`enrollment-slot-time-${slot.slotOrder}`}
                  disabled={pending}
                />
              </label>
              <label className="block text-sm">
                <span className="text-slate-600">시간(분)</span>
                <input
                  type="number"
                  min={1}
                  value={slot.durationMinutes}
                  onChange={(event) =>
                    updateSlot(index, {
                      durationMinutes: Number.parseInt(event.target.value, 10) || 0,
                    })
                  }
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  data-testid={`enrollment-slot-duration-${slot.slotOrder}`}
                  disabled={pending}
                />
              </label>
            </div>
          ))}
          <p className="text-sm text-slate-600" data-testid="enrollment-tuition">
            수강료: {selectedProduct.default_tuition_krw.toLocaleString('ko-KR')}원
          </p>
        </div>
      ) : null}

      {error ? (
        <p className="mt-3 text-sm text-red-600" role="alert" data-testid="enrollment-error">
          {error}
        </p>
      ) : null}
      {successMessage ? (
        <p className="mt-3 text-sm text-emerald-700" data-testid="enrollment-success">
          {successMessage}
        </p>
      ) : null}

      <button
        type="button"
        onClick={handleSubmit}
        disabled={!canSubmit}
        className="mt-4 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
        data-testid="enrollment-submit"
      >
        {pending ? '등록 중…' : '초기 등록 실행'}
      </button>
    </section>
  );
}

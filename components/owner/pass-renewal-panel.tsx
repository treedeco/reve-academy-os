'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  loadOwnerEnrollmentCatalog,
  type EnrollmentCatalogLoadState,
} from '@/lib/data/owner-enrollment';
import { recordOwnerPaymentAndRenewPass, type OwnerPassRenewalResult } from '@/lib/data/owner-pass-renewal';
import {
  ENROLLMENT_CATALOG_EMPTY_MESSAGE,
  ENROLLMENT_CATALOG_ERROR_MESSAGE,
  ENROLLMENT_CATALOG_LOADING_MESSAGE,
  ENROLLMENT_PRODUCT_EMPTY_MESSAGE,
} from '@/lib/domain/enrollment-catalog-messages';
import { formatPassStatusLabel } from '@/lib/domain/weekly-schedule';
import { formatFixedWeeklySchedulesLabel } from '@/lib/domain/owner-schedule-edit';
import {
  ENROLLMENT_PAYMENT_METHODS,
  mapPassRenewalError,
  paidAtFromDateInput,
  resolvePreferredProductId,
  validatePassRenewalForm,
  type EnrollmentPaymentMethod,
  type RenewablePassTarget,
} from '@/lib/domain/pass-renewal';
import { WEEKDAY_LABELS } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

function formatTodayDateInput(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function PassRenewalPanel({
  studentId,
  target,
  onRenewalComplete,
  onCancel,
}: {
  studentId: string;
  target: RenewablePassTarget;
  onRenewalComplete: (result: OwnerPassRenewalResult) => Promise<void>;
  onCancel: () => void;
}) {
  const idempotencyKeyRef = useRef(crypto.randomUUID());
  const [catalogState, setCatalogState] = useState<EnrollmentCatalogLoadState>({ status: 'loading' });
  const [productId, setProductId] = useState('');
  const [paymentDate, setPaymentDate] = useState(formatTodayDateInput());
  const [paymentMethod, setPaymentMethod] = useState<EnrollmentPaymentMethod>('cash');
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

  const catalog = catalogState.status === 'ready' ? catalogState.catalog : null;

  const productsForCourse = useMemo(
    () => catalog?.products.filter((product) => product.course_id === target.course_id) ?? [],
    [catalog?.products, target.course_id],
  );

  useEffect(() => {
    if (catalogState.status !== 'ready') {
      return;
    }
    setProductId(
      resolvePreferredProductId(productsForCourse, target.course_id, target.course_product_id),
    );
  }, [catalogState.status, productsForCourse, target.course_id, target.course_product_id]);

  const selectedProduct = useMemo(
    () => productsForCourse.find((product) => product.id === productId) ?? null,
    [productsForCourse, productId],
  );

  const scheduleLabel = useMemo(
    () =>
      formatFixedWeeklySchedulesLabel(
        target.schedule_slots.map((slot) => ({
          weekday: slot.weekday,
          local_start_time: slot.local_start_time,
        })),
      ),
    [target.schedule_slots],
  );

  const canSubmit =
    catalogState.status === 'ready' && Boolean(selectedProduct) && Boolean(paymentDate) && !pending;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError('');
    setSuccessMessage('');

    const validationError = validatePassRenewalForm({
      courseProductId: productId,
      paymentMethod,
      paidAmountKrw: selectedProduct?.default_tuition_krw ?? -1,
      product: selectedProduct,
    });
    if (validationError) {
      setError(validationError);
      return;
    }
    if (!selectedProduct) {
      return;
    }

    setPending(true);
    try {
      const supabase = createClient();
      const result = await recordOwnerPaymentAndRenewPass(supabase, {
        studentId,
        courseProductId: selectedProduct.id,
        paidAmountKrw: selectedProduct.default_tuition_krw,
        paymentMethod,
        paidAt: paidAtFromDateInput(paymentDate),
        idempotencyKey: idempotencyKeyRef.current,
      });

      if (result.idempotent_replay) {
        setSuccessMessage(
          `이미 처리된 결제입니다. ${result.new_pass_public_code} (${result.new_pass_status})`,
        );
      } else {
        setSuccessMessage(
          result.activation_required
            ? `선결제 완료: ${result.new_pass_public_code} (예약). 현재 회차 종료 후 활성화됩니다.`
            : `다음 회차 등록 완료: ${result.new_pass_public_code}`,
        );
      }

      await onRenewalComplete(result);
      idempotencyKeyRef.current = crypto.randomUUID();
    } catch (submitError) {
      setError(mapPassRenewalError(submitError as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  return (
    <section
      className="rounded-lg border border-brand-200 bg-brand-50/40 p-4"
      data-testid="pass-renewal-panel"
      data-renewal-mode={target.mode}
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="text-base font-semibold">다음 회차 등록</h3>
          <p className="mt-1 text-sm text-slate-600">
            {target.course_name} · {target.pass_code} · {formatPassStatusLabel(target.status)}
            {target.mode === 'prepaid_renewal' ? ' · 선결제(예약 회차)' : ''}
          </p>
        </div>
        <button
          type="button"
          className="text-sm text-slate-600 underline"
          onClick={onCancel}
          data-testid="pass-renewal-cancel"
        >
          닫기
        </button>
      </div>

      <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
        <div>
          <dt className="text-slate-500">과목</dt>
          <dd className="font-medium" data-testid="pass-renewal-course">
            {target.course_name}
          </dd>
        </div>
        <div>
          <dt className="text-slate-500">이전 Pass</dt>
          <dd className="font-medium" data-testid="pass-renewal-previous-pass">
            {target.pass_code}
          </dd>
        </div>
        <div>
          <dt className="text-slate-500">이전 강사</dt>
          <dd className="font-medium" data-testid="pass-renewal-teacher">
            {target.teacher_name ?? '-'}
          </dd>
        </div>
        <div>
          <dt className="text-slate-500">고정 일정 (복사)</dt>
          <dd className="font-medium" data-testid="pass-renewal-schedule">
            {scheduleLabel ||
              target.schedule_slots
                .map(
                  (slot) =>
                    `${WEEKDAY_LABELS[slot.weekday] ?? slot.weekday} ${slot.local_start_time.slice(0, 5)}`,
                )
                .join(', ') ||
              '-'}
          </dd>
        </div>
      </dl>
      <p className="mt-2 text-xs text-slate-500">
        강사·고정 일정은 이전 회차에서 새 회차로 복사됩니다. 등록 후 고정 일정 변경으로 수정할 수
        있습니다.
      </p>

      {catalogState.status === 'loading' ? (
        <p className="mt-4 text-sm text-slate-600" data-testid="pass-renewal-catalog-loading">
          {ENROLLMENT_CATALOG_LOADING_MESSAGE}
        </p>
      ) : null}
      {catalogState.status === 'error' ? (
        <p className="mt-4 text-sm text-red-700" data-testid="pass-renewal-catalog-error">
          {ENROLLMENT_CATALOG_ERROR_MESSAGE}
        </p>
      ) : null}
      {catalogState.status === 'empty' ? (
        <p className="mt-4 text-sm text-slate-600" data-testid="pass-renewal-catalog-empty">
          {ENROLLMENT_CATALOG_EMPTY_MESSAGE}
        </p>
      ) : null}

      {catalogState.status === 'ready' ? (
        <form className="mt-4 space-y-3" onSubmit={handleSubmit} data-testid="pass-renewal-form">
          <label className="block text-sm">
            <span className="text-slate-600">상품</span>
            <select
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={productId}
              onChange={(event) => setProductId(event.target.value)}
              data-testid="pass-renewal-product"
              required
            >
              <option value="">상품 선택</option>
              {productsForCourse.map((product) => (
                <option key={product.id} value={product.id}>
                  {product.product_name} · {product.default_lesson_count}회 · 주{' '}
                  {product.weekly_frequency}회 ·{' '}
                  {product.default_tuition_krw.toLocaleString('ko-KR')}원
                </option>
              ))}
            </select>
          </label>
          {productsForCourse.length === 0 ? (
            <p className="text-sm text-slate-600" data-testid="pass-renewal-product-empty">
              {ENROLLMENT_PRODUCT_EMPTY_MESSAGE}
            </p>
          ) : null}

          <label className="block text-sm">
            <span className="text-slate-600">결제 금액</span>
            <input
              className="mt-1 w-full rounded-md border border-slate-200 bg-slate-50 px-3 py-2"
              value={
                selectedProduct
                  ? `${selectedProduct.default_tuition_krw.toLocaleString('ko-KR')}원`
                  : '-'
              }
              readOnly
              data-testid="pass-renewal-amount"
            />
          </label>

          <label className="block text-sm">
            <span className="text-slate-600">결제일</span>
            <input
              type="date"
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={paymentDate}
              onChange={(event) => setPaymentDate(event.target.value)}
              data-testid="pass-renewal-payment-date"
              required
            />
          </label>

          <label className="block text-sm">
            <span className="text-slate-600">결제 수단</span>
            <select
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              value={paymentMethod}
              onChange={(event) =>
                setPaymentMethod(event.target.value as EnrollmentPaymentMethod)
              }
              data-testid="pass-renewal-payment-method"
              required
            >
              {ENROLLMENT_PAYMENT_METHODS.map((method) => (
                <option key={method.value} value={method.value}>
                  {method.label}
                </option>
              ))}
            </select>
          </label>

          {error ? (
            <p className="text-sm text-red-700" data-testid="pass-renewal-error" role="alert">
              {error}
            </p>
          ) : null}
          {successMessage ? (
            <p className="text-sm text-emerald-700" data-testid="pass-renewal-success">
              {successMessage}
            </p>
          ) : null}

          <button
            type="submit"
            className="rounded-md bg-brand-700 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
            disabled={!canSubmit}
            data-testid="pass-renewal-submit"
          >
            {pending ? '처리 중…' : '결제 기록 및 다음 회차 등록'}
          </button>
        </form>
      ) : null}
    </section>
  );
}

export function RenewablePassActions({
  targets,
  activeTargetId,
  onOpen,
}: {
  targets: RenewablePassTarget[];
  activeTargetId: string | null;
  onOpen: (target: RenewablePassTarget) => void;
}) {
  if (targets.length === 0) {
    return null;
  }

  return (
    <ul className="mt-3 space-y-2" data-testid="renewable-pass-actions">
      {targets.map((target) => (
        <li
          key={target.source_pass_id}
          className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-slate-200 bg-white px-3 py-2 text-sm"
          data-testid={`renewable-pass-${target.pass_code}`}
        >
          <div>
            <p className="font-medium">
              {target.course_name} · {target.pass_code}
            </p>
            <p className="text-slate-600">
              {formatPassStatusLabel(target.status)}
              {target.mode === 'prepaid_renewal' ? ' · 잔여 회차 있음(선결제 가능)' : ''}
            </p>
          </div>
          <button
            type="button"
            className="rounded-md border border-brand-700 px-3 py-1.5 text-brand-800 disabled:opacity-50"
            onClick={() => onOpen(target)}
            disabled={activeTargetId === target.source_pass_id}
            data-testid={`pass-renewal-open-${target.pass_code}`}
          >
            다음 회차 등록
          </button>
        </li>
      ))}
    </ul>
  );
}

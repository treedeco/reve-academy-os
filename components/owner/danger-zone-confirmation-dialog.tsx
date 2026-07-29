'use client';

import { useEffect, useId, useRef } from 'react';

export function DangerZoneConfirmationDialog({
  open,
  title,
  description,
  impactSummary,
  preservedItems,
  removedItems,
  blockers,
  warnings,
  confirmationLabel,
  confirmationPlaceholder,
  confirmationValue,
  onConfirmationChange,
  reasonLabel = '삭제 사유',
  reasonValue,
  onReasonChange,
  extraFields,
  submitLabel,
  pending,
  error,
  successMessage,
  onCancel,
  onSubmit,
  submitDisabled,
}: {
  open: boolean;
  title: string;
  description: string;
  impactSummary?: React.ReactNode;
  preservedItems?: string[];
  removedItems?: string[];
  blockers?: string[];
  warnings?: string[];
  confirmationLabel: string;
  confirmationPlaceholder: string;
  confirmationValue: string;
  onConfirmationChange: (value: string) => void;
  reasonLabel?: string;
  reasonValue: string;
  onReasonChange: (value: string) => void;
  extraFields?: React.ReactNode;
  submitLabel: string;
  pending: boolean;
  error?: string;
  successMessage?: string;
  onCancel: () => void;
  onSubmit: () => void;
  submitDisabled?: boolean;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const descriptionId = useId();
  const triggerRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) {
      return;
    }

    if (open && !dialog.open) {
      triggerRef.current = document.activeElement as HTMLElement | null;
      dialog.showModal();
    } else if (!open && dialog.open) {
      dialog.close();
      triggerRef.current?.focus();
    }
  }, [open]);

  if (!open) {
    return null;
  }

  const hasBlockers = Boolean(blockers?.length);
  const disabled = pending || submitDisabled || hasBlockers;

  return (
    <dialog
      ref={dialogRef}
      className="w-[min(100%,32rem)] max-h-[90vh] overflow-y-auto rounded-lg border border-slate-200 bg-white p-0 shadow-xl backdrop:bg-slate-900/40"
      aria-labelledby={titleId}
      aria-describedby={descriptionId}
      onCancel={(event) => {
        event.preventDefault();
        onCancel();
      }}
      data-testid="danger-zone-dialog"
    >
      <div className="border-b border-slate-200 px-4 py-3">
        <h2 id={titleId} className="text-lg font-semibold text-red-800">
          {title}
        </h2>
        <p id={descriptionId} className="mt-1 text-sm text-slate-600">
          {description}
        </p>
      </div>

      <div className="space-y-4 px-4 py-4">
        {impactSummary ? <div className="text-sm text-slate-700">{impactSummary}</div> : null}

        {removedItems && removedItems.length > 0 ? (
          <section>
            <h3 className="text-sm font-medium text-red-700">삭제되는 항목</h3>
            <ul className="mt-2 space-y-1 text-sm text-slate-700" data-testid="danger-removed-items">
              {removedItems.map((item) => (
                <li key={item}>· {item}</li>
              ))}
            </ul>
          </section>
        ) : null}

        {preservedItems && preservedItems.length > 0 ? (
          <section>
            <h3 className="text-sm font-medium text-emerald-700">보존되는 항목</h3>
            <ul className="mt-2 space-y-1 text-sm text-slate-700" data-testid="danger-preserved-items">
              {preservedItems.map((item) => (
                <li key={item}>· {item}</li>
              ))}
            </ul>
          </section>
        ) : null}

        {blockers && blockers.length > 0 ? (
          <section role="alert" data-testid="danger-blockers">
            <h3 className="text-sm font-medium text-red-700">삭제를 막는 항목</h3>
            <ul className="mt-2 space-y-1 text-sm text-red-700">
              {blockers.map((item) => (
                <li key={item}>· {item}</li>
              ))}
            </ul>
          </section>
        ) : null}

        {warnings && warnings.length > 0 ? (
          <section role="status" data-testid="danger-warnings">
            <h3 className="text-sm font-medium text-amber-700">주의</h3>
            <ul className="mt-2 space-y-1 text-sm text-amber-800">
              {warnings.map((item) => (
                <li key={item}>· {item}</li>
              ))}
            </ul>
          </section>
        ) : null}

        {extraFields}

        <label className="block text-sm">
          <span className="text-slate-600">{reasonLabel}</span>
          <textarea
            value={reasonValue}
            onChange={(event) => onReasonChange(event.target.value)}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            rows={3}
            disabled={pending}
            data-testid="danger-reason"
          />
        </label>

        <label className="block text-sm">
          <span className="text-slate-600">{confirmationLabel}</span>
          <input
            type="text"
            value={confirmationValue}
            onChange={(event) => onConfirmationChange(event.target.value)}
            placeholder={confirmationPlaceholder}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            autoComplete="off"
            disabled={pending}
            aria-describedby={`${titleId}-confirm-help`}
            data-testid="danger-confirmation"
          />
          <p id={`${titleId}-confirm-help`} className="mt-1 text-xs text-slate-500">
            정확히 「{confirmationPlaceholder}」 를 입력해야 삭제할 수 있습니다.
          </p>
        </label>

        {error ? (
          <p className="text-sm text-red-600" role="alert" data-testid="danger-error">
            {error}
          </p>
        ) : null}
        {successMessage ? (
          <p className="text-sm text-emerald-700" role="status" data-testid="danger-success">
            {successMessage}
          </p>
        ) : null}
      </div>

      <div className="flex flex-col-reverse gap-2 border-t border-slate-200 px-4 py-3 sm:flex-row sm:justify-end">
        <button
          type="button"
          onClick={onCancel}
          disabled={pending}
          className="rounded-md border border-slate-300 px-4 py-2 text-sm"
          data-testid="danger-cancel"
        >
          취소
        </button>
        <button
          type="button"
          onClick={onSubmit}
          disabled={disabled}
          className="rounded-md bg-red-700 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
          data-testid="danger-submit"
        >
          {pending ? '처리 중…' : submitLabel}
        </button>
      </div>
    </dialog>
  );
}

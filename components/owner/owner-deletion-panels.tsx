'use client';

import { useCallback, useMemo, useState } from 'react';
import { DangerZoneConfirmationDialog } from '@/components/owner/danger-zone-confirmation-dialog';
import {
  previewDeleteStudent,
  previewDeleteTeacher,
  previewRemoveFixedPassSchedule,
  removeFixedPassSchedule,
  permanentlyDeleteStudent,
  permanentlyDeleteTeacher,
  type ScheduleRemovalPreview,
  type StudentDeletionPreview,
  type TeacherDeletionPreview,
} from '@/lib/data/owner-deletion';
import {
  buildScheduleRemovalConfirmationPhrase,
  buildStudentDeleteConfirmationPhrase,
  buildTeacherDeleteConfirmationPhrase,
  formatCountLabel,
  mapOwnerDeletionError,
  TEACHER_LINK_HANDLING_OPTIONS,
  validateDeleteReason,
  validateEffectiveFromDate,
  validateReplacementTeacher,
  type TeacherLinkHandlingMode,
} from '@/lib/domain/owner-deletion';
import type { OwnerTeacherRow, PassUsageSummary } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

function formatTodayDateInput(): string {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(new Date());
}

export function RemoveFixedSchedulePanel({
  studentName,
  studentCode,
  currentPass,
  scheduleSlotsLabel,
  onScheduleRemoved,
}: {
  studentName: string;
  studentCode: string;
  currentPass: PassUsageSummary;
  scheduleSlotsLabel: string;
  onScheduleRemoved: () => Promise<void>;
}) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [preview, setPreview] = useState<ScheduleRemovalPreview | null>(null);
  const [effectiveFrom, setEffectiveFrom] = useState(formatTodayDateInput());
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [pending, setPending] = useState(false);
  const [previewPending, setPreviewPending] = useState(false);
  const [error, setError] = useState('');
  const [successMessage, setSuccessMessage] = useState('');

  const expectedConfirmation = useMemo(
    () => buildScheduleRemovalConfirmationPhrase(currentPass.pass_code),
    [currentPass.pass_code],
  );

  const loadPreview = useCallback(async () => {
    setPreviewPending(true);
    setError('');
    try {
      const supabase = createClient();
      const nextPreview = await previewRemoveFixedPassSchedule(supabase, {
        passId: currentPass.pass_id,
        effectiveFrom,
      });
      setPreview(nextPreview);
    } catch (previewError) {
      setError(mapOwnerDeletionError(previewError as { message?: string }));
    } finally {
      setPreviewPending(false);
    }
  }, [currentPass.pass_id, effectiveFrom]);

  async function openDialog() {
    setDialogOpen(true);
    setReason('');
    setConfirmed(false);
    setSuccessMessage('');
    setError('');
    await loadPreview();
  }

  async function handleSubmit() {
    if (!preview || pending) {
      return;
    }

    const reasonError = validateDeleteReason(reason);
    if (reasonError) {
      setError(reasonError);
      return;
    }

    const dateError = validateEffectiveFromDate(effectiveFrom);
    if (dateError) {
      setError(dateError);
      return;
    }

    if (!confirmed) {
      setError('정말 삭제하려면 확인란을 선택해 주세요.');
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      const result = await removeFixedPassSchedule(supabase, {
        passId: currentPass.pass_id,
        expectedPassUpdatedAt: preview.pass_updated_at,
        effectiveFrom,
        reason: reason.trim(),
        confirmationCode: expectedConfirmation,
        preflightFingerprint: preview.preflight_fingerprint,
      });

      setSuccessMessage(
        result.no_change
          ? '변경할 고정 일정이 없습니다.'
          : `고정 일정 ${result.removed_schedule_slot_count}건을 제거하고, 향후 수업 ${result.removed_or_cancelled_future_lesson_count}건을 처리했습니다.`,
      );
      await onScheduleRemoved();
    } catch (submitError) {
      setError(mapOwnerDeletionError(submitError as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  if (!['active', 'reserved'].includes(currentPass.pass_status)) {
    return null;
  }

  return (
    <>
      <div
        className="mt-4 rounded-md border border-amber-200 bg-amber-50 p-3"
        data-testid="remove-fixed-schedule-panel"
      >
        <h3 className="text-sm font-semibold text-amber-900">고정 일정 관리</h3>
        <p className="mt-1 text-sm text-amber-800">
          반복 고정 일정만 제거합니다. 과거·완료 수업과 결제 기록은 유지됩니다.
        </p>
        <button
          type="button"
          onClick={() => void openDialog()}
          className="mt-3 rounded-md border border-amber-600 bg-white px-3 py-2 text-sm font-medium text-amber-900"
          data-testid="remove-fixed-schedule-open"
        >
          고정 스케줄 삭제
        </button>
      </div>

      <DangerZoneConfirmationDialog
        open={dialogOpen}
        title="고정 스케줄 삭제"
        description="선택한 회차권의 반복 고정 일정을 제거합니다. 되돌릴 수 없습니다."
        impactSummary={
          preview ? (
            <dl className="grid gap-2 sm:grid-cols-2">
              <div>
                <dt className="text-slate-500">학생</dt>
                <dd>
                  {studentName} ({studentCode})
                </dd>
              </div>
              <div>
                <dt className="text-slate-500">수강권</dt>
                <dd>{preview.pass_code}</dd>
              </div>
              <div>
                <dt className="text-slate-500">현재 고정 일정</dt>
                <dd>{preview.current_weekday_times || scheduleSlotsLabel || '없음'}</dd>
              </div>
              <div>
                <dt className="text-slate-500">적용 시작일</dt>
                <dd>{effectiveFrom}</dd>
              </div>
              <div>
                <dt className="text-slate-500">영향 미래 수업</dt>
                <dd>{formatCountLabel(preview.future_timetable_lesson_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">수동 이동 미래 수업</dt>
                <dd>{formatCountLabel(preview.manually_moved_future_lesson_count, '건')}</dd>
              </div>
            </dl>
          ) : previewPending ? (
            <p role="status">영향 범위를 불러오는 중…</p>
          ) : null
        }
        preservedItems={
          preview
            ? [
                `과거·미차감 수업 ${formatCountLabel(preview.preserved_past_lesson_count, '건')}`,
                `완료(차감) 수업 ${formatCountLabel(preview.preserved_completed_lesson_count, '건')}`,
                '결제·환불·수강권 사용 이력',
              ]
            : undefined
        }
        removedItems={
          preview
            ? [
                `활성 고정 일정 ${formatCountLabel(preview.active_slot_count, '건')}`,
                `적용 시작일 이후 시간표 미래 수업 ${formatCountLabel(preview.future_timetable_lesson_count, '건')}`,
              ]
            : undefined
        }
        blockers={preview?.blockers}
        warnings={preview?.warnings}
        confirmed={confirmed}
        onConfirmedChange={setConfirmed}
        reasonValue={reason}
        onReasonChange={setReason}
        extraFields={
          <label className="block text-sm">
            <span className="text-slate-600">적용 시작일</span>
            <input
              type="date"
              value={effectiveFrom}
              onChange={(event) => {
                setEffectiveFrom(event.target.value);
                void loadPreview();
              }}
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              disabled={pending || previewPending}
              data-testid="remove-schedule-effective-from"
            />
          </label>
        }
        submitLabel="고정 스케줄 삭제"
        pending={pending || previewPending}
        error={error}
        successMessage={successMessage}
        onCancel={() => setDialogOpen(false)}
        onSubmit={() => void handleSubmit()}
        submitDisabled={
          !preview ||
          pending ||
          !confirmed ||
          !reason.trim() ||
          Boolean(preview.blockers?.length)
        }
      />
    </>
  );
}

export function StudentPermanentDeleteSection({
  studentId,
  studentCode,
  studentName,
}: {
  studentId: string;
  studentCode: string;
  studentName: string;
}) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [preview, setPreview] = useState<StudentDeletionPreview | null>(null);
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [pending, setPending] = useState(false);
  const [previewPending, setPreviewPending] = useState(false);
  const [error, setError] = useState('');

  const expectedConfirmation = buildStudentDeleteConfirmationPhrase(studentCode);

  async function openDialog() {
    setDialogOpen(true);
    setReason('');
    setConfirmed(false);
    setError('');
    setPreviewPending(true);
    try {
      const supabase = createClient();
      setPreview(await previewDeleteStudent(supabase, studentId));
    } catch (previewError) {
      setError(mapOwnerDeletionError(previewError as { message?: string }));
    } finally {
      setPreviewPending(false);
    }
  }

  async function handleSubmit() {
    if (!preview || pending) {
      return;
    }

    const reasonError = validateDeleteReason(reason);
    if (reasonError) {
      setError(reasonError);
      return;
    }

    if (!confirmed) {
      setError('정말 삭제하려면 확인란을 선택해 주세요.');
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      await permanentlyDeleteStudent(supabase, {
        studentId,
        expectedUpdatedAt: preview.updated_at,
        confirmationCode: expectedConfirmation,
        reason: reason.trim(),
        preflightFingerprint: preview.preflight_fingerprint,
      });
      window.location.href = '/students';
    } catch (submitError) {
      setError(mapOwnerDeletionError(submitError as { message?: string }));
      setPending(false);
    }
  }

  return (
    <section
      className="rounded-lg border border-red-200 bg-red-50 p-4"
      data-testid="student-permanent-delete-section"
    >
      <h2 className="text-lg font-semibold text-red-900">위험 작업</h2>
      <p className="mt-2 text-sm text-red-800">
        <strong>비활성화</strong>는 기록을 유지하고 운영 대상에서만 제외합니다.{' '}
        <strong>영구 삭제</strong>는 학생과 연결 데이터를 되돌릴 수 없게 제거합니다.
      </p>
      <button
        type="button"
        onClick={() => void openDialog()}
        className="mt-4 rounded-md bg-red-700 px-4 py-2 text-sm font-medium text-white"
        data-testid="student-permanent-delete-open"
      >
        학생 영구 삭제
      </button>

      <DangerZoneConfirmationDialog
        open={dialogOpen}
        title="학생 영구 삭제"
        description={`${studentName} (${studentCode}) 학생과 연결된 운영 데이터를 영구 삭제합니다.`}
        impactSummary={
          preview ? (
            <dl className="grid gap-2 sm:grid-cols-2">
              <div>
                <dt className="text-slate-500">회차권</dt>
                <dd>{formatCountLabel(preview.pass_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">수업</dt>
                <dd>{formatCountLabel(preview.lesson_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">결제</dt>
                <dd>{formatCountLabel(preview.payment_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">환불</dt>
                <dd>{formatCountLabel(preview.payment_refund_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">고정 일정</dt>
                <dd>{formatCountLabel(preview.schedule_slot_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">로그인 계정</dt>
                <dd>{preview.auth_user_exists ? '연결됨 (별도 회수 필요)' : '없음'}</dd>
              </div>
            </dl>
          ) : previewPending ? (
            <p role="status">연결 데이터를 분석하는 중…</p>
          ) : null
        }
        removedItems={
          preview
            ? [
                `회차권 ${formatCountLabel(preview.pass_count, '건')}`,
                `수업 ${formatCountLabel(preview.lesson_count, '건')}`,
                `결제 ${formatCountLabel(preview.payment_count, '건')}`,
                `SMS ${formatCountLabel(preview.sms_notification_count, '건')}`,
              ]
            : undefined
        }
        preservedItems={['감사 로그 tombstone (개인정보 제외)']}
        blockers={preview?.blockers}
        warnings={preview?.warnings}
        confirmed={confirmed}
        onConfirmedChange={setConfirmed}
        reasonValue={reason}
        onReasonChange={setReason}
        submitLabel="학생 영구 삭제"
        pending={pending || previewPending}
        error={error}
        onCancel={() => setDialogOpen(false)}
        onSubmit={() => void handleSubmit()}
        submitDisabled={
          !preview ||
          pending ||
          !confirmed ||
          !reason.trim() ||
          Boolean(preview.blockers?.length)
        }
      />
    </section>
  );
}

export function TeacherPermanentDeleteSection({
  teacher,
  activeTeachers,
  onDeleted,
}: {
  teacher: OwnerTeacherRow;
  activeTeachers: OwnerTeacherRow[];
  onDeleted: () => void;
}) {
  const [dialogOpen, setDialogOpen] = useState(false);
  const [preview, setPreview] = useState<TeacherDeletionPreview | null>(null);
  const [linkMode, setLinkMode] = useState<TeacherLinkHandlingMode>('reassign');
  const [replacementTeacherId, setReplacementTeacherId] = useState('');
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [pending, setPending] = useState(false);
  const [previewPending, setPreviewPending] = useState(false);
  const [error, setError] = useState('');

  const expectedConfirmation = buildTeacherDeleteConfirmationPhrase(
    teacher.teacher_code,
    teacher.name,
  );

  const replacementOptions = activeTeachers.filter(
    (row) => row.id !== teacher.id && row.is_active,
  );

  async function openDialog() {
    setDialogOpen(true);
    setReason('');
    setConfirmed(false);
    setError('');
    setLinkMode('reassign');
    setReplacementTeacherId(replacementOptions[0]?.id ?? '');
    setPreviewPending(true);
    try {
      const supabase = createClient();
      setPreview(await previewDeleteTeacher(supabase, teacher.id));
    } catch (previewError) {
      setError(mapOwnerDeletionError(previewError as { message?: string }));
    } finally {
      setPreviewPending(false);
    }
  }

  async function handleSubmit() {
    if (!preview || pending) {
      return;
    }

    const reasonError = validateDeleteReason(reason);
    if (reasonError) {
      setError(reasonError);
      return;
    }

    const replacementError = validateReplacementTeacher(linkMode, replacementTeacherId, teacher.id);
    if (replacementError) {
      setError(replacementError);
      return;
    }

    if (!confirmed) {
      setError('정말 삭제하려면 확인란을 선택해 주세요.');
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      await permanentlyDeleteTeacher(supabase, {
        teacherId: teacher.id,
        expectedUpdatedAt: preview.updated_at,
        linkHandlingMode: linkMode,
        replacementTeacherId: linkMode === 'reassign' ? replacementTeacherId : null,
        confirmationCode: expectedConfirmation,
        reason: reason.trim(),
        preflightFingerprint: preview.preflight_fingerprint,
      });
      setDialogOpen(false);
      onDeleted();
    } catch (submitError) {
      setError(mapOwnerDeletionError(submitError as { message?: string }));
      setPending(false);
    }
  }

  return (
    <section
      className="mt-4 rounded-lg border border-red-200 bg-red-50 p-3"
      data-testid={`teacher-permanent-delete-${teacher.id}`}
    >
      <h3 className="text-sm font-semibold text-red-900">위험 작업</h3>
      <p className="mt-1 text-sm text-red-800">
        강사 <strong>{teacher.name}</strong> ({teacher.teacher_code})를 영구 삭제합니다. 학생·결제
        데이터는 삭제되지 않습니다.
      </p>
      <button
        type="button"
        onClick={() => void openDialog()}
        className="mt-3 rounded-md bg-red-700 px-3 py-2 text-sm font-medium text-white"
        data-testid={`teacher-permanent-delete-open-${teacher.id}`}
      >
        강사 영구 삭제
      </button>

      <DangerZoneConfirmationDialog
        open={dialogOpen}
        title="강사 영구 삭제"
        description={`${teacher.name} (${teacher.teacher_code}) 강사를 영구 삭제합니다.`}
        impactSummary={
          preview ? (
            <dl className="grid gap-2 sm:grid-cols-2">
              <div>
                <dt className="text-slate-500">전체 수업</dt>
                <dd>{formatCountLabel(preview.total_lesson_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">미래 수업</dt>
                <dd>{formatCountLabel(preview.future_eligible_lesson_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">과거 차감 수업</dt>
                <dd>{formatCountLabel(preview.past_deductible_lesson_count, '건')}</dd>
              </div>
              <div>
                <dt className="text-slate-500">활성 고정 일정</dt>
                <dd>{formatCountLabel(preview.active_schedule_slot_count, '건')}</dd>
              </div>
            </dl>
          ) : previewPending ? (
            <p role="status">연결 데이터를 분석하는 중…</p>
          ) : null
        }
        preservedItems={['학생·회차권·결제', '과거·완료 수업 이력 (강사명 스냅샷)']}
        removedItems={['강사 마스터 row']}
        blockers={preview?.blockers}
        warnings={preview?.warnings}
        confirmed={confirmed}
        onConfirmedChange={setConfirmed}
        reasonValue={reason}
        onReasonChange={setReason}
        extraFields={
          <div className="space-y-3">
            <fieldset>
              <legend className="text-sm font-medium text-slate-700">연결 데이터 처리</legend>
              <div className="mt-2 space-y-2">
                {TEACHER_LINK_HANDLING_OPTIONS.map((option) => (
                  <label key={option.value} className="flex gap-2 text-sm">
                    <input
                      type="radio"
                      name={`teacher-link-${teacher.id}`}
                      value={option.value}
                      checked={linkMode === option.value}
                      onChange={() => setLinkMode(option.value)}
                      disabled={pending}
                    />
                    <span>
                      <span className="font-medium">{option.label}</span>
                      <span className="mt-0.5 block text-slate-600">{option.description}</span>
                    </span>
                  </label>
                ))}
              </div>
            </fieldset>
            {linkMode === 'reassign' ? (
              <label className="block text-sm">
                <span className="text-slate-600">재배정 강사</span>
                <select
                  value={replacementTeacherId}
                  onChange={(event) => setReplacementTeacherId(event.target.value)}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  disabled={pending || replacementOptions.length === 0}
                  data-testid="teacher-replacement-select"
                >
                  <option value="">강사 선택</option>
                  {replacementOptions.map((row) => (
                    <option key={row.id} value={row.id}>
                      {row.name} ({row.teacher_code})
                    </option>
                  ))}
                </select>
              </label>
            ) : null}
          </div>
        }
        submitLabel="강사 영구 삭제"
        pending={pending || previewPending}
        error={error}
        onCancel={() => setDialogOpen(false)}
        onSubmit={() => void handleSubmit()}
        submitDisabled={
          !preview ||
          pending ||
          !confirmed ||
          !reason.trim() ||
          Boolean(preview.blockers?.length) ||
          (linkMode === 'reassign' && !replacementTeacherId)
        }
      />
    </section>
  );
}

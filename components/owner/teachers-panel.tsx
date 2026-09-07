'use client';

import { useMemo, useState } from 'react';
import { TeacherPermanentDeleteSection } from '@/components/owner/owner-deletion-panels';
import {
  createOwnerTeacher,
  setOwnerTeacherActive,
  updateOwnerTeacher,
} from '@/lib/data/owner-teachers';
import { formatDateTimeSeoul } from '@/lib/domain/format';
import {
  formatTeacherStatusLabel,
  mapTeacherMasterDataError,
} from '@/lib/domain/teacher-master-data';
import type { OwnerTeacherRow } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

type TeacherFormState = {
  teacherCode: string;
  name: string;
  phone: string;
  email: string;
};

type StatusFormState = {
  reason: string;
};

const EMPTY_CREATE_FORM: TeacherFormState = {
  teacherCode: '',
  name: '',
  phone: '',
  email: '',
};

function buildEditForm(teacher: OwnerTeacherRow): TeacherFormState {
  return {
    teacherCode: teacher.teacher_code,
    name: teacher.name,
    phone: teacher.phone ?? '',
    email: teacher.email ?? '',
  };
}

function validateTeacherForm(form: TeacherFormState, requireCode: boolean): string | null {
  if (requireCode && !form.teacherCode.trim()) {
    return '강사 코드를 입력해 주세요.';
  }
  if (!form.name.trim()) {
    return '이름을 입력해 주세요.';
  }
  return null;
}

export function TeachersPanel({
  initialTeachers,
  initialShowInactive = false,
}: {
  initialTeachers: OwnerTeacherRow[];
  initialShowInactive?: boolean;
}) {
  const [teachers, setTeachers] = useState(initialTeachers);
  const [showInactive, setShowInactive] = useState(initialShowInactive);
  const [createForm, setCreateForm] = useState<TeacherFormState>(EMPTY_CREATE_FORM);
  const [editForms, setEditForms] = useState<Record<string, TeacherFormState>>({});
  const [statusForms, setStatusForms] = useState<Record<string, StatusFormState>>({});
  const [editingId, setEditingId] = useState<string | null>(null);
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [createError, setCreateError] = useState('');
  const [errorById, setErrorById] = useState<Record<string, string>>({});

  const teacherMap = useMemo(() => new Map(teachers.map((row) => [row.id, row])), [teachers]);
  const activeTeachers = useMemo(() => teachers.filter((row) => row.is_active), [teachers]);
  const inactiveTeachers = useMemo(() => teachers.filter((row) => !row.is_active), [teachers]);

  function clearTeacherError(teacherId: string) {
    setErrorById((prev) => ({ ...prev, [teacherId]: '' }));
  }

  async function handleCreate() {
    if (pendingKey === 'create') {
      return;
    }

    const validationError = validateTeacherForm(createForm, true);
    if (validationError) {
      setCreateError(validationError);
      return;
    }

    setPendingKey('create');
    setCreateError('');

    try {
      const supabase = createClient();
      const created = await createOwnerTeacher(supabase, {
        teacherCode: createForm.teacherCode.trim(),
        name: createForm.name.trim(),
        phone: createForm.phone.trim() || null,
        email: createForm.email.trim() || null,
      });

      setTeachers((prev) =>
        [...prev, created].sort((left, right) => left.name.localeCompare(right.name, 'ko')),
      );
      setCreateForm(EMPTY_CREATE_FORM);
    } catch (error) {
      setCreateError(mapTeacherMasterDataError(error as { message?: string }));
    } finally {
      setPendingKey(null);
    }
  }

  async function handleUpdate(teacherId: string) {
    const current = teacherMap.get(teacherId);
    const form = editForms[teacherId];
    if (!current || !form || pendingKey === teacherId) {
      return;
    }

    const validationError = validateTeacherForm(form, false);
    if (validationError) {
      setErrorById((prev) => ({ ...prev, [teacherId]: validationError }));
      return;
    }

    setPendingKey(teacherId);
    clearTeacherError(teacherId);

    try {
      const supabase = createClient();
      const updated = await updateOwnerTeacher(supabase, {
        teacherId,
        expectedUpdatedAt: current.updated_at,
        name: form.name.trim(),
        phone: form.phone.trim() || null,
        email: form.email.trim() || null,
      });

      setTeachers((prev) =>
        prev
          .map((row) => (row.id === teacherId ? updated : row))
          .sort((left, right) => left.name.localeCompare(right.name, 'ko')),
      );
      setEditingId(null);
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [teacherId]: mapTeacherMasterDataError(error as { message?: string }),
      }));
    } finally {
      setPendingKey(null);
    }
  }

  async function handleStatusChange(teacherId: string, nextActive: boolean) {
    const current = teacherMap.get(teacherId);
    if (!current || pendingKey === teacherId) {
      return;
    }

    const reason = statusForms[teacherId]?.reason?.trim() ?? '';
    if (!reason) {
      setErrorById((prev) => ({
        ...prev,
        [teacherId]: '상태 변경 사유를 입력해 주세요.',
      }));
      return;
    }

    if (!nextActive) {
      const confirmed = window.confirm(`${current.name} 강사를 비활성화할까요?`);
      if (!confirmed) {
        return;
      }
    }

    setPendingKey(teacherId);
    clearTeacherError(teacherId);

    try {
      const supabase = createClient();
      const updated = await setOwnerTeacherActive(supabase, {
        teacherId,
        isActive: nextActive,
        reason,
        expectedUpdatedAt: current.updated_at,
      });

      setTeachers((prev) =>
        prev.map((row) =>
          row.id === teacherId
            ? {
                ...row,
                is_active: updated.is_active,
                updated_at: updated.updated_at,
              }
            : row,
        ),
      );
      if (!nextActive) {
        setShowInactive(true);
      }
      setStatusForms((prev) => ({ ...prev, [teacherId]: { reason: '' } }));
    } catch (error) {
      setErrorById((prev) => ({
        ...prev,
        [teacherId]: mapTeacherMasterDataError(error as { message?: string }),
      }));
    } finally {
      setPendingKey(null);
    }
  }

  function startEditing(teacher: OwnerTeacherRow) {
    setEditingId(teacher.id);
    setEditForms((prev) => ({ ...prev, [teacher.id]: buildEditForm(teacher) }));
    clearTeacherError(teacher.id);
  }

  function cancelEditing(teacherId: string) {
    setEditingId((current) => (current === teacherId ? null : current));
    clearTeacherError(teacherId);
  }

  function renderTeacherCard(teacher: OwnerTeacherRow) {
    const isEditing = editingId === teacher.id;
    const isPending = pendingKey === teacher.id;
    const editForm = editForms[teacher.id] ?? buildEditForm(teacher);
    const statusReason = statusForms[teacher.id]?.reason ?? '';
    const rowError = errorById[teacher.id];

    return (
      <article
        key={teacher.id}
        data-testid={`teacher-item-${teacher.teacher_code}`}
        className={`rounded-lg border bg-white p-4 shadow-sm ${
          teacher.is_active ? 'border-slate-200' : 'border-slate-300 bg-slate-50/50'
        }`}
      >
        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div className="min-w-0 flex-1 space-y-2">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-base font-semibold text-slate-900">{teacher.name}</h3>
              <span
                className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                  teacher.is_active
                    ? 'bg-emerald-50 text-emerald-700'
                    : 'bg-slate-100 text-slate-600'
                }`}
                data-testid={`teacher-status-${teacher.teacher_code}`}
              >
                {formatTeacherStatusLabel(teacher.is_active)}
              </span>
            </div>
            <p className="text-sm text-slate-600">코드: {teacher.teacher_code}</p>
            {!isEditing ? (
              <dl className="grid gap-1 text-sm text-slate-600 sm:grid-cols-2">
                <div>
                  <dt className="inline text-slate-500">전화 </dt>
                  <dd className="inline">{teacher.phone ?? '-'}</dd>
                </div>
                <div>
                  <dt className="inline text-slate-500">이메일 </dt>
                  <dd className="inline break-all">{teacher.email ?? '-'}</dd>
                </div>
                <div className="sm:col-span-2">
                  <dt className="inline text-slate-500">수정 시각 </dt>
                  <dd className="inline">{formatDateTimeSeoul(teacher.updated_at)}</dd>
                </div>
              </dl>
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="block text-sm">
                  <span className="text-slate-600">이름</span>
                  <input
                    type="text"
                    value={editForm.name}
                    onChange={(event) =>
                      setEditForms((prev) => ({
                        ...prev,
                        [teacher.id]: { ...editForm, name: event.target.value },
                      }))
                    }
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                    data-testid={`teacher-edit-name-${teacher.teacher_code}`}
                    disabled={isPending}
                  />
                </label>
                <label className="block text-sm">
                  <span className="text-slate-600">전화번호</span>
                  <input
                    type="text"
                    value={editForm.phone}
                    onChange={(event) =>
                      setEditForms((prev) => ({
                        ...prev,
                        [teacher.id]: { ...editForm, phone: event.target.value },
                      }))
                    }
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                    data-testid={`teacher-edit-phone-${teacher.teacher_code}`}
                    disabled={isPending}
                  />
                </label>
                <label className="block text-sm sm:col-span-2">
                  <span className="text-slate-600">이메일</span>
                  <input
                    type="email"
                    value={editForm.email}
                    onChange={(event) =>
                      setEditForms((prev) => ({
                        ...prev,
                        [teacher.id]: { ...editForm, email: event.target.value },
                      }))
                    }
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                    data-testid={`teacher-edit-email-${teacher.teacher_code}`}
                    disabled={isPending}
                  />
                </label>
              </div>
            )}
          </div>

          <div className="flex w-full flex-col gap-2 lg:w-72">
            {isEditing ? (
              <>
                <button
                  type="button"
                  onClick={() => handleUpdate(teacher.id)}
                  disabled={isPending}
                  className="rounded-md bg-brand-600 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
                  data-testid={`teacher-save-${teacher.teacher_code}`}
                >
                  {isPending ? '저장 중…' : '저장'}
                </button>
                <button
                  type="button"
                  onClick={() => cancelEditing(teacher.id)}
                  disabled={isPending}
                  className="rounded-md border border-slate-300 px-3 py-2 text-sm"
                  data-testid={`teacher-cancel-edit-${teacher.teacher_code}`}
                >
                  취소
                </button>
              </>
            ) : (
              <button
                type="button"
                onClick={() => startEditing(teacher)}
                disabled={isPending}
                className="rounded-md border border-slate-300 px-3 py-2 text-sm"
                data-testid={`teacher-edit-${teacher.teacher_code}`}
              >
                정보 수정
              </button>
            )}

            <label className="block text-sm">
              <span className="text-slate-600">상태 변경 사유</span>
              <input
                type="text"
                value={statusReason}
                onChange={(event) =>
                  setStatusForms((prev) => ({
                    ...prev,
                    [teacher.id]: { reason: event.target.value },
                  }))
                }
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                data-testid={`teacher-status-reason-${teacher.teacher_code}`}
                disabled={isPending}
              />
            </label>

            {teacher.is_active ? (
              <button
                type="button"
                onClick={() => handleStatusChange(teacher.id, false)}
                disabled={isPending}
                className="rounded-md border border-red-300 px-3 py-2 text-sm text-red-700 disabled:opacity-50"
                data-testid={`teacher-deactivate-${teacher.teacher_code}`}
              >
                {isPending ? '처리 중…' : '비활성화'}
              </button>
            ) : (
              <button
                type="button"
                onClick={() => handleStatusChange(teacher.id, true)}
                disabled={isPending}
                className="rounded-md border border-emerald-300 px-3 py-2 text-sm text-emerald-700 disabled:opacity-50"
                data-testid={`teacher-reactivate-${teacher.teacher_code}`}
              >
                {isPending ? '처리 중…' : '재활성화'}
              </button>
            )}
          </div>
        </div>

        {rowError ? (
          <p
            className="mt-3 text-sm text-red-600"
            role="alert"
            data-testid={`teacher-error-${teacher.teacher_code}`}
          >
            {rowError}
          </p>
        ) : null}

        <TeacherPermanentDeleteSection
          teacher={teacher}
          activeTeachers={teachers}
          onDeleted={() => {
            setTeachers((prev) => prev.filter((row) => row.id !== teacher.id));
          }}
        />
      </article>
    );
  }

  return (
    <div className="space-y-6" data-testid="teachers-panel">
      <section
        className="rounded-lg border border-slate-200 bg-white p-4"
        data-testid="teacher-create-section"
      >
        <h2 className="text-lg font-semibold">강사 등록</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <label className="block text-sm">
            <span className="text-slate-600">강사 코드</span>
            <input
              type="text"
              value={createForm.teacherCode}
              onChange={(event) =>
                setCreateForm((prev) => ({ ...prev, teacherCode: event.target.value }))
              }
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="teacher-create-code"
              disabled={pendingKey === 'create'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">이름</span>
            <input
              type="text"
              value={createForm.name}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, name: event.target.value }))}
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="teacher-create-name"
              disabled={pendingKey === 'create'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">전화번호</span>
            <input
              type="text"
              value={createForm.phone}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, phone: event.target.value }))}
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="teacher-create-phone"
              disabled={pendingKey === 'create'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">이메일</span>
            <input
              type="email"
              value={createForm.email}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, email: event.target.value }))}
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="teacher-create-email"
              disabled={pendingKey === 'create'}
            />
          </label>
        </div>
        {createError ? (
          <p className="mt-3 text-sm text-red-600" role="alert" data-testid="teacher-create-error">
            {createError}
          </p>
        ) : null}
        <button
          type="button"
          onClick={handleCreate}
          disabled={pendingKey === 'create'}
          className="mt-4 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
          data-testid="teacher-create-submit"
        >
          {pendingKey === 'create' ? '등록 중…' : '강사 등록'}
        </button>
      </section>

      {teachers.length === 0 ? (
        <div
          data-testid="teachers-empty"
          className="rounded-lg border border-dashed border-slate-300 bg-white p-8 text-center"
        >
          <p className="font-medium text-slate-900">등록된 강사가 없습니다</p>
          <p className="mt-2 text-sm text-slate-600">위 양식으로 첫 강사를 등록해 주세요.</p>
        </div>
      ) : (
        <>
          <div className="flex flex-wrap items-center justify-between gap-4 pt-2">
            <div>
              <h2 className="text-lg font-semibold text-slate-900">
                강사 목록 ({activeTeachers.length}명)
              </h2>
              <p className="mt-0.5 text-sm text-slate-500">
                현재 활성 상태로 수업 및 고정 일정 배정이 가능한 강사입니다.
              </p>
            </div>
            <label
              className="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50 select-none"
              data-testid="show-inactive-teachers-toggle"
            >
              <input
                type="checkbox"
                checked={showInactive}
                onChange={(event) => setShowInactive(event.target.checked)}
                className="h-4 w-4 rounded border-slate-300 text-brand-600 focus:ring-brand-500"
                data-testid="show-inactive-teachers-checkbox"
              />
              <span>비활성 강사 보기</span>
              {inactiveTeachers.length > 0 ? (
                <span
                  className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-600"
                  data-testid="inactive-teachers-count-badge"
                >
                  {inactiveTeachers.length}
                </span>
              ) : null}
            </label>
          </div>

          {activeTeachers.length === 0 ? (
            <div
              data-testid="teachers-empty"
              className="rounded-lg border border-dashed border-slate-300 bg-white p-8 text-center"
            >
              <p className="font-medium text-slate-900">활성 상태인 강사가 없습니다</p>
              <p className="mt-2 text-sm text-slate-600">
                비활성 강사를 확인하려면 상단의 &quot;비활성 강사 보기&quot;를 선택해 주세요.
              </p>
            </div>
          ) : (
            <div className="space-y-4" data-testid="teachers-list">
              {activeTeachers.map((teacher) => renderTeacherCard(teacher))}
            </div>
          )}

          {showInactive ? (
            <section
              className="mt-8 space-y-4 rounded-xl border border-dashed border-slate-300 bg-slate-50/60 p-6"
              data-testid="inactive-teachers-section"
            >
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-200 pb-4">
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="text-base font-semibold text-slate-900">비활성 강사</h3>
                    <span
                      className="rounded-full bg-slate-200 px-2.5 py-0.5 text-xs font-semibold text-slate-700"
                      data-testid="inactive-teachers-section-count"
                    >
                      {inactiveTeachers.length}명
                    </span>
                  </div>
                  <p className="mt-1 text-xs text-slate-500">
                    수업 및 고정 일정 신규 배정에서 제외된 강사입니다. 필요 시 재활성화하거나 영구 삭제할 수 있습니다.
                  </p>
                </div>
              </div>

              {inactiveTeachers.length === 0 ? (
                <p className="py-4 text-center text-sm text-slate-500" data-testid="inactive-teachers-empty">
                  비활성 강사가 없습니다.
                </p>
              ) : (
                <div className="space-y-4" data-testid="inactive-teachers-list">
                  {inactiveTeachers.map((teacher) => renderTeacherCard(teacher))}
                </div>
              )}
            </section>
          ) : null}
        </>
      )}
    </div>
  );
}

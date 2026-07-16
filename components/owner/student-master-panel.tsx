'use client';

import { useState } from 'react';
import { setOwnerStudentActive, updateOwnerStudent } from '@/lib/data/owner-students';
import {
  formatStudentStatusLabel,
  mapStudentMasterDataError,
} from '@/lib/domain/student-master-data';
import type { OwnerStudentRow } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

type StudentFormState = {
  name: string;
  phone: string;
  email: string;
};

function buildEditForm(student: OwnerStudentRow): StudentFormState {
  return {
    name: student.name,
    phone: student.phone ?? '',
    email: student.email ?? '',
  };
}

function validateStudentForm(form: StudentFormState): string | null {
  if (!form.name.trim()) {
    return '이름을 입력해 주세요.';
  }
  return null;
}

export function StudentMasterPanel({
  student,
  onStudentChange,
}: {
  student: OwnerStudentRow;
  onStudentChange: (next: OwnerStudentRow) => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [editForm, setEditForm] = useState<StudentFormState>(() => buildEditForm(student));
  const [statusReason, setStatusReason] = useState('');
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [error, setError] = useState('');

  function resetEditForm(next: OwnerStudentRow) {
    setEditForm(buildEditForm(next));
  }

  async function handleUpdate() {
    if (pendingKey) {
      return;
    }

    const validationError = validateStudentForm(editForm);
    if (validationError) {
      setError(validationError);
      return;
    }

    setPendingKey('update');
    setError('');

    try {
      const supabase = createClient();
      const updated = await updateOwnerStudent(supabase, {
        studentId: student.id,
        expectedUpdatedAt: student.updated_at,
        name: editForm.name.trim(),
        phone: editForm.phone.trim() || null,
        email: editForm.email.trim() || null,
      });

      const nextStudent: OwnerStudentRow = {
        ...student,
        name: updated.name,
        phone: updated.phone,
        email: updated.email,
        updated_at: updated.updated_at,
      };
      onStudentChange(nextStudent);
      resetEditForm(nextStudent);
      setIsEditing(false);
    } catch (updateError) {
      setError(mapStudentMasterDataError(updateError as { message?: string }));
    } finally {
      setPendingKey(null);
    }
  }

  async function handleStatusChange(nextStatus: 'active' | 'inactive') {
    if (pendingKey) {
      return;
    }

    const reason = statusReason.trim();
    if (!reason) {
      setError('상태 변경 사유를 입력해 주세요.');
      return;
    }

    if (nextStatus === 'inactive') {
      const confirmed = window.confirm(`${student.name} 학생을 비활성화할까요?`);
      if (!confirmed) {
        return;
      }
    }

    setPendingKey('status');
    setError('');

    try {
      const supabase = createClient();
      const updated = await setOwnerStudentActive(supabase, {
        studentId: student.id,
        operationalStatus: nextStatus,
        reason,
        expectedUpdatedAt: student.updated_at,
      });

      const nextStudent: OwnerStudentRow = {
        ...student,
        operational_status: updated.operational_status,
        updated_at: updated.updated_at,
      };
      onStudentChange(nextStudent);
      setStatusReason('');
    } catch (statusError) {
      setError(mapStudentMasterDataError(statusError as { message?: string }));
    } finally {
      setPendingKey(null);
    }
  }

  const isActive = student.operational_status === 'active';

  return (
    <section
      className="rounded-lg border border-slate-200 bg-white p-4"
      data-testid="student-master-panel"
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">학생 정보</h2>
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${
            isActive ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-600'
          }`}
          data-testid="student-status-badge"
        >
          {formatStudentStatusLabel(student.operational_status)}
        </span>
      </div>

      {!isEditing ? (
        <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-slate-500">학생 코드</dt>
            <dd className="font-medium">{student.student_code}</dd>
          </div>
          <div>
            <dt className="text-slate-500">이름</dt>
            <dd className="font-medium" data-testid="student-display-name">
              {student.name}
            </dd>
          </div>
          <div>
            <dt className="text-slate-500">전화번호</dt>
            <dd>{student.phone ?? '-'}</dd>
          </div>
          <div>
            <dt className="text-slate-500">이메일</dt>
            <dd>{student.email ?? '-'}</dd>
          </div>
        </dl>
      ) : (
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <label className="block text-sm">
            <span className="text-slate-600">이름</span>
            <input
              type="text"
              value={editForm.name}
              onChange={(event) => setEditForm((prev) => ({ ...prev, name: event.target.value }))}
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="student-edit-name"
              disabled={pendingKey === 'update'}
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-600">전화번호</span>
            <input
              type="text"
              value={editForm.phone}
              onChange={(event) => setEditForm((prev) => ({ ...prev, phone: event.target.value }))}
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="student-edit-phone"
              disabled={pendingKey === 'update'}
            />
          </label>
          <label className="block text-sm sm:col-span-2">
            <span className="text-slate-600">이메일</span>
            <input
              type="email"
              value={editForm.email}
              onChange={(event) => setEditForm((prev) => ({ ...prev, email: event.target.value }))}
              className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              data-testid="student-edit-email"
              disabled={pendingKey === 'update'}
            />
          </label>
        </div>
      )}

      {error ? (
        <p className="mt-3 text-sm text-red-600" role="alert" data-testid="student-master-error">
          {error}
        </p>
      ) : null}

      <div className="mt-4 flex flex-wrap gap-2">
        {!isEditing ? (
          <button
            type="button"
            onClick={() => {
              setIsEditing(true);
              resetEditForm(student);
              setError('');
            }}
            className="rounded-md border border-slate-300 px-3 py-2 text-sm"
            data-testid="student-edit-open"
          >
            수정
          </button>
        ) : (
          <>
            <button
              type="button"
              onClick={handleUpdate}
              disabled={pendingKey === 'update'}
              className="rounded-md bg-brand-600 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
              data-testid="student-edit-save"
            >
              {pendingKey === 'update' ? '저장 중…' : '저장'}
            </button>
            <button
              type="button"
              onClick={() => {
                setIsEditing(false);
                resetEditForm(student);
                setError('');
              }}
              className="rounded-md border border-slate-300 px-3 py-2 text-sm"
              data-testid="student-edit-cancel"
            >
              취소
            </button>
          </>
        )}
      </div>

      <div className="mt-6 border-t border-slate-100 pt-4">
        <label className="block text-sm">
          <span className="text-slate-600">상태 변경 사유</span>
          <input
            type="text"
            value={statusReason}
            onChange={(event) => setStatusReason(event.target.value)}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="student-status-reason"
            disabled={Boolean(pendingKey)}
          />
        </label>
        <div className="mt-3 flex flex-wrap gap-2">
          {isActive ? (
            <button
              type="button"
              onClick={() => handleStatusChange('inactive')}
              disabled={Boolean(pendingKey)}
              className="rounded-md border border-slate-300 px-3 py-2 text-sm disabled:opacity-50"
              data-testid="student-deactivate"
            >
              비활성화
            </button>
          ) : (
            <button
              type="button"
              onClick={() => handleStatusChange('active')}
              disabled={Boolean(pendingKey)}
              className="rounded-md border border-slate-300 px-3 py-2 text-sm disabled:opacity-50"
              data-testid="student-reactivate"
            >
              활성화
            </button>
          )}
        </div>
      </div>
    </section>
  );
}

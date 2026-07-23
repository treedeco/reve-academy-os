'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { createOwnerStudent } from '@/lib/data/owner-students';
import { mapStudentMasterDataError } from '@/lib/domain/student-master-data';
import { createClient } from '@/lib/supabase/client';

type StudentFormState = {
  name: string;
  phone: string;
  email: string;
};

const EMPTY_FORM: StudentFormState = {
  name: '',
  phone: '',
  email: '',
};

function validateStudentForm(form: StudentFormState): string | null {
  if (!form.name.trim()) {
    return '이름을 입력해 주세요.';
  }
  return null;
}

export function StudentsCreatePanel() {
  const router = useRouter();
  const [form, setForm] = useState<StudentFormState>(EMPTY_FORM);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');

  async function handleCreate() {
    if (pending) {
      return;
    }

    const validationError = validateStudentForm(form);
    if (validationError) {
      setError(validationError);
      return;
    }

    setPending(true);
    setError('');

    try {
      const supabase = createClient();
      const created = await createOwnerStudent(supabase, {
        name: form.name.trim(),
        phone: form.phone.trim() || null,
        email: form.email.trim() || null,
      });

      setForm(EMPTY_FORM);
      router.push(`/students/${created.id}`);
    } catch (createError) {
      setError(mapStudentMasterDataError(createError as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  return (
    <section
      className="rounded-lg border border-slate-200 bg-white p-4"
      data-testid="student-create-section"
    >
      <h2 className="text-lg font-semibold">학생 등록</h2>
      <p className="mt-1 text-sm text-slate-600">
        학생 코드는 등록 시 시스템에서 자동으로 부여됩니다.
      </p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="block text-sm sm:col-span-2">
          <span className="text-slate-600">이름</span>
          <input
            type="text"
            value={form.name}
            onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="student-create-name"
            disabled={pending}
          />
        </label>
        <label className="block text-sm">
          <span className="text-slate-600">전화번호</span>
          <input
            type="text"
            value={form.phone}
            onChange={(event) => setForm((prev) => ({ ...prev, phone: event.target.value }))}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="student-create-phone"
            disabled={pending}
          />
        </label>
        <label className="block text-sm">
          <span className="text-slate-600">이메일</span>
          <input
            type="email"
            value={form.email}
            onChange={(event) => setForm((prev) => ({ ...prev, email: event.target.value }))}
            className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
            data-testid="student-create-email"
            disabled={pending}
          />
        </label>
      </div>
      {error ? (
        <p className="mt-3 text-sm text-red-600" role="alert" data-testid="student-create-error">
          {error}
        </p>
      ) : null}
      <button
        type="button"
        onClick={handleCreate}
        disabled={pending}
        className="mt-4 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
        data-testid="student-create-submit"
      >
        {pending ? '등록 중…' : '학생 등록'}
      </button>
    </section>
  );
}

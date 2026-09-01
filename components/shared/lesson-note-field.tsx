'use client';

import { useState } from 'react';
import { saveLessonNote } from '@/lib/data/lesson-notes';
import { mapDatabaseError } from '@/lib/domain/format';
import { createClient } from '@/lib/supabase/client';

export function LessonNoteField({
  lessonId,
  authorProfileId,
  initialBody,
  initialNoteId,
  compact = false,
}: {
  lessonId: string;
  authorProfileId: string;
  initialBody: string | null;
  initialNoteId: string | null;
  compact?: boolean;
}) {
  const [body, setBody] = useState(initialBody ?? '');
  const [noteId, setNoteId] = useState(initialNoteId);
  const [savedBody, setSavedBody] = useState(initialBody ?? '');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const isDirty = body.trim() !== savedBody.trim();

  async function handleSave() {
    if (pending || !isDirty) {
      return;
    }

    setPending(true);
    setError('');
    setSuccess('');

    try {
      const supabase = createClient();
      const saved = await saveLessonNote(supabase, {
        lessonId,
        authorProfileId,
        body,
        noteId,
      });
      setNoteId(saved.id);
      setBody(saved.body);
      setSavedBody(saved.body);
      setSuccess('저장됨');
    } catch (caught) {
      setError(mapDatabaseError(caught as { message?: string }));
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="space-y-2" data-testid={`lesson-note-${lessonId}`}>
      <label
        className="block text-sm font-medium text-slate-700"
        htmlFor={`lesson-note-input-${lessonId}`}
      >
        수업 내용
      </label>
      <textarea
        id={`lesson-note-input-${lessonId}`}
        rows={compact ? 3 : 4}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        value={body}
        onChange={(event) => {
          setBody(event.target.value);
          setSuccess('');
        }}
        disabled={pending}
        placeholder="수업 내용을 입력하세요"
      />
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          className="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
          onClick={() => void handleSave()}
          disabled={pending || !isDirty || !body.trim()}
          data-testid={`lesson-note-save-${lessonId}`}
        >
          {pending ? '저장 중…' : '저장'}
        </button>
        {success ? (
          <span className="text-sm text-green-700" role="status">
            {success}
          </span>
        ) : null}
        {error ? (
          <span className="text-sm text-red-600" role="alert">
            {error}
          </span>
        ) : null}
      </div>
    </div>
  );
}

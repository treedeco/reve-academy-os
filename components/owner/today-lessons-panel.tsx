'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import { mapDatabaseError, formatLessonStatus, formatTimeSeoul } from '@/lib/domain/format';
import {
  ORDINARY_TRANSITION_TARGETS,
  STATUS_REQUIRES_REASON,
  type LessonStatus,
  type TodayLessonRow,
} from '@/lib/domain/types';

export function TodayLessonsPanel({ initialLessons }: { initialLessons: TodayLessonRow[] }) {
  const [lessons, setLessons] = useState(initialLessons);
  const [pendingLessonId, setPendingLessonId] = useState<string | null>(null);
  const [errorByLesson, setErrorByLesson] = useState<Record<string, string>>({});
  const [reasonByLesson, setReasonByLesson] = useState<Record<string, string>>({});

  const lessonMap = useMemo(() => new Map(lessons.map((lesson) => [lesson.id, lesson])), [lessons]);

  async function handleStatusChange(lessonId: string, nextStatus: LessonStatus) {
    const current = lessonMap.get(lessonId);
    if (!current || pendingLessonId === lessonId) {
      return;
    }

    const reason = reasonByLesson[lessonId]?.trim();
    if (STATUS_REQUIRES_REASON.has(nextStatus) && !reason) {
      setErrorByLesson((prev) => ({
        ...prev,
        [lessonId]: '변경 사유를 입력해 주세요.',
      }));
      return;
    }

    const previous = current;
    setPendingLessonId(lessonId);
    setErrorByLesson((prev) => ({ ...prev, [lessonId]: '' }));
    setLessons((prev) =>
      prev.map((lesson) =>
        lesson.id === lessonId ? { ...lesson, status: nextStatus } : lesson,
      ),
    );

    try {
      const supabase = createClient();
      const { data, error } = await supabase.rpc('reve_transition_lesson_status', {
        p_lesson_id: lessonId,
        p_new_status: nextStatus,
        p_expected_updated_at: previous.updated_at,
        p_reason: reason ?? null,
        p_actual_started_at: nextStatus === 'completed' ? new Date().toISOString() : null,
        p_actual_ended_at: nextStatus === 'completed' ? new Date().toISOString() : null,
      });

      if (error) {
        throw error;
      }

      const row = Array.isArray(data) ? data[0] : data;
      if (!row) {
        throw new Error('Lesson transition returned no data');
      }

      setLessons((prev) =>
        prev.map((lesson) =>
          lesson.id === lessonId
            ? {
                ...lesson,
                status: row.new_status as LessonStatus,
                updated_at: row.lesson_updated_at,
              }
            : lesson,
        ),
      );
    } catch (error) {
      setLessons((prev) =>
        prev.map((lesson) => (lesson.id === lessonId ? previous : lesson)),
      );
      setErrorByLesson((prev) => ({
        ...prev,
        [lessonId]: mapDatabaseError(error as { message?: string }),
      }));
    } finally {
      setPendingLessonId(null);
    }
  }

  if (lessons.length === 0) {
    return null;
  }

  return (
    <div className="space-y-4">
      {lessons.map((lesson) => {
        const options = ORDINARY_TRANSITION_TARGETS[lesson.status] ?? [];
        const isPending = pendingLessonId === lesson.id;

        return (
          <article
            key={lesson.id}
            className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
            data-testid={`today-lesson-${lesson.id}`}
          >
            <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div>
                <p className="text-sm text-slate-500">{formatTimeSeoul(lesson.scheduled_at)}</p>
                <h2 className="text-lg font-semibold">{lesson.student_name}</h2>
                <p className="text-sm text-slate-600">
                  {lesson.course_name} · {lesson.teacher_name}
                </p>
                <p className="mt-2 text-sm">
                  현재 상태:{' '}
                  <span className="font-medium">{formatLessonStatus(lesson.status)}</span>
                </p>
                {lesson.memo_summary ? (
                  <p className="mt-2 text-sm text-slate-600">메모: {lesson.memo_summary}</p>
                ) : null}
                <Link
                  href={`/students/${lesson.student_id}`}
                  className="mt-3 inline-block text-sm font-medium text-brand-700"
                >
                  학생 상세 보기
                </Link>
              </div>

              <div className="w-full max-w-sm space-y-2">
                <label className="block text-sm font-medium text-slate-700" htmlFor={`status-${lesson.id}`}>
                  상태 변경
                </label>
                <select
                  id={`status-${lesson.id}`}
                  className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                  disabled={isPending || options.length === 0}
                  value={lesson.status}
                  onChange={(event) =>
                    void handleStatusChange(lesson.id, event.target.value as LessonStatus)
                  }
                >
                  <option value={lesson.status}>{formatLessonStatus(lesson.status)}</option>
                  {options.map((status) => (
                    <option key={status} value={status}>
                      {formatLessonStatus(status)}
                    </option>
                  ))}
                </select>

                {options.some((status) => STATUS_REQUIRES_REASON.has(status)) ? (
                  <input
                    type="text"
                    placeholder="변경 사유 (필요 시)"
                    className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                    value={reasonByLesson[lesson.id] ?? ''}
                    onChange={(event) =>
                      setReasonByLesson((prev) => ({
                        ...prev,
                        [lesson.id]: event.target.value,
                      }))
                    }
                    disabled={isPending}
                  />
                ) : null}

                {isPending ? <p className="text-sm text-slate-500">저장 중…</p> : null}
                {errorByLesson[lesson.id] ? (
                  <p className="text-sm text-red-600" role="alert">
                    {errorByLesson[lesson.id]}
                  </p>
                ) : null}
              </div>
            </div>
          </article>
        );
      })}
    </div>
  );
}

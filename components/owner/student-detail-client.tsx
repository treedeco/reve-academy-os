'use client';

import Link from 'next/link';
import { useState } from 'react';
import { InitialEnrollmentPanel } from '@/components/owner/initial-enrollment-panel';
import { LessonOperationsPanel } from '@/components/owner/lesson-operations-panel';
import { StudentMasterPanel } from '@/components/owner/student-master-panel';
import { StudentOperationalHistoryPanel } from '@/components/owner/student-operational-history-panel';
import { StudentPassSummary } from '@/components/owner/student-pass-summary';
import { fetchStudentDetail } from '@/lib/data/owner-queries';
import { fetchOwnerStudentMasterRow } from '@/lib/data/owner-students';
import { formatDateTimeSeoul, formatLessonStatus } from '@/lib/domain/format';
import { formatLessonProgress } from '@/lib/domain/lesson-correction';
import type {
  LessonStatus,
  OwnerInitialEnrollmentResult,
  OwnerLessonOperationsRow,
  OwnerStudentRow,
  PassUsageSummary,
  StudentDetailData,
  StudentOperationalHistory,
} from '@/lib/domain/types';
import { WEEKDAY_LABELS } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/client';

export function StudentDetailClient({
  initialDetail,
  initialMaster,
  operationalHistory,
}: {
  initialDetail: StudentDetailData;
  initialMaster: OwnerStudentRow;
  operationalHistory: StudentOperationalHistory;
}) {
  const [detail, setDetail] = useState(initialDetail);
  const [master, setMaster] = useState(initialMaster);
  const [history, setHistory] = useState(operationalHistory);

  async function refreshAfterLessonOperation() {
    const supabase = createClient();
    const nextDetail = await fetchStudentDetail(supabase, master.id);
    setDetail(nextDetail);
  }

  function handleLessonUpdated(lessonId: string, patch: Partial<OwnerLessonOperationsRow>) {
    setDetail((prev) => ({
      ...prev,
      lessons: prev.lessons.map((lesson) =>
        lesson.id === lessonId ? { ...lesson, ...patch } : lesson,
      ),
    }));
    void refreshAfterLessonOperation();
  }

  function handlePassUsageUpdated(usage: PassUsageSummary) {
    setDetail((prev) => ({
      ...prev,
      current_pass: prev.current_pass?.pass_id === usage.pass_id ? usage : prev.current_pass,
    }));
  }

  async function refreshAfterEnrollment(_result: OwnerInitialEnrollmentResult) {
    const supabase = createClient();
    const [nextDetail, nextMaster, paymentsResult] = await Promise.all([
      fetchStudentDetail(supabase, master.id),
      fetchOwnerStudentMasterRow(supabase, master.id),
      supabase
        .from('payments')
        .select(
          'id, status, paid_amount_krw, paid_at, created_at, passes!payments_renewed_pass_id_fkey(pass_code, product_name_snapshot), courses(name)',
        )
        .eq('student_id', master.id)
        .order('created_at', { ascending: false }),
    ]);

    setDetail(nextDetail);
    setMaster(nextMaster);

    if (!paymentsResult.error && paymentsResult.data) {
      setHistory((prev) => ({
        ...prev,
        payments: paymentsResult.data!.map((row) => {
          const pass = Array.isArray(row.passes) ? row.passes[0] : row.passes;
          const course = Array.isArray(row.courses) ? row.courses[0] : row.courses;
          return {
            id: row.id,
            status: row.status,
            paid_amount_krw: row.paid_amount_krw,
            paid_at: row.paid_at,
            created_at: row.created_at,
            pass_code: pass?.pass_code ?? null,
            product_name: pass?.product_name_snapshot ?? null,
            course_name: course?.name ?? null,
          };
        }),
      }));
    }
  }

  return (
    <div className="space-y-6" data-testid="student-detail-client">
      <div>
        <Link href="/students" className="text-sm text-brand-700">
          ← 학생 목록
        </Link>
        <h1 className="mt-3 text-2xl font-semibold">{detail.student.name}</h1>
        <p className="mt-1 text-sm text-slate-600">
          {detail.student.student_code} · {detail.student.operational_status}
        </p>
        {detail.teacher_name ? (
          <p className="mt-1 text-sm text-slate-600">담당 강사: {detail.teacher_name}</p>
        ) : null}
      </div>

      <StudentMasterPanel student={master} onStudentChange={setMaster} />

      {master.operational_status === 'active' && !detail.current_pass ? (
        <InitialEnrollmentPanel
          student={master}
          onEnrollmentComplete={refreshAfterEnrollment}
        />
      ) : null}

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-lg font-semibold">현재 회차권</h2>
        {detail.current_pass ? (
          <StudentPassSummary pass={detail.current_pass} />
        ) : (
          <p className="mt-3 text-sm text-slate-600" data-testid="student-no-current-pass">
            현재 active/reserved pass가 없습니다.
          </p>
        )}
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-lg font-semibold">고정 일정</h2>
        {detail.schedule_slots.length === 0 ? (
          <p className="mt-3 text-sm text-slate-600" data-testid="student-no-schedule">
            등록된 고정 일정이 없습니다.
          </p>
        ) : (
          <ul className="mt-3 space-y-2" data-testid="student-schedule-slots">
            {detail.schedule_slots.map((slot) => (
              <li key={slot.id} className="text-sm" data-testid={`student-schedule-slot-${slot.id}`}>
                {WEEKDAY_LABELS[slot.weekday]} {slot.local_start_time.slice(0, 5)} ·{' '}
                {slot.duration_minutes}분 · {slot.teacher_name}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-lg font-semibold">수업 이력</h2>
        {detail.lessons.length === 0 ? (
          <p className="mt-3 text-sm text-slate-600" data-testid="student-no-lessons">
            등록된 수업이 없습니다.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto">
            <table className="min-w-full text-sm" data-testid="student-lessons-table">
              <thead>
                <tr className="border-b border-slate-200 text-left text-slate-500">
                  <th className="px-2 py-2">회차</th>
                  <th className="px-2 py-2">일시</th>
                  <th className="px-2 py-2">상태</th>
                  <th className="px-2 py-2">작업</th>
                </tr>
              </thead>
              <tbody>
                {detail.lessons.map((lesson) => (
                  <tr
                    key={lesson.id}
                    className="border-b border-slate-100"
                    data-testid={`student-lesson-${lesson.sequence_number}`}
                    data-lesson-id={lesson.id}
                  >
                    <td className="px-2 py-2">
                      {formatLessonProgress(lesson.registered_lesson_count, lesson.sequence_number)}
                    </td>
                    <td className="px-2 py-2">{formatDateTimeSeoul(lesson.scheduled_at)}</td>
                    <td className="px-2 py-2">
                      {formatLessonStatus(lesson.status as LessonStatus)}
                    </td>
                    <td className="px-2 py-2">
                      <LessonOperationsPanel
                        lesson={{
                          ...lesson,
                          student_name: detail.student.name,
                        }}
                        passUsage={detail.current_pass}
                        onLessonUpdated={handleLessonUpdated}
                        onPassUsageUpdated={handlePassUsageUpdated}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {detail.lesson_notes.length > 0 ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-lg font-semibold">최근 수업 메모</h2>
          <ul className="mt-3 space-y-3">
            {detail.lesson_notes.map((note) => (
              <li key={note.id} className="rounded-md bg-slate-50 p-3 text-sm">
                {note.body}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {detail.previous_passes.length > 0 ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-lg font-semibold">이전 회차권</h2>
          <ul className="mt-3 space-y-2 text-sm">
            {detail.previous_passes.map((pass) => (
              <li key={pass.id}>
                {pass.pass_code} · {pass.status} · seq {pass.sequence_number}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <StudentOperationalHistoryPanel history={history} />
    </div>
  );
}

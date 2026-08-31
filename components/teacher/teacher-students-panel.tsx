'use client';

import type { TeacherAssignedStudentSummary } from '@/lib/data/teacher-queries';

const PASS_STATUS_LABELS: Record<string, string> = {
  reserved: '예약',
  active: '활성',
  completed: '완료',
  expired: '만료',
  cancelled: '취소',
};

export function TeacherStudentsPanel({
  students,
}: {
  students: TeacherAssignedStudentSummary[];
}) {
  if (students.length === 0) {
    return (
      <p className="text-sm text-slate-600" data-testid="teacher-students-empty">
        담당 학생이 없습니다.
      </p>
    );
  }

  return (
    <div className="space-y-3" data-testid="teacher-students-list">
      {students.map((student) => (
        <article
          key={`${student.student_id}-${student.pass_id}`}
          className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
          data-testid={`teacher-student-${student.student_code}`}
        >
          <h2 className="text-lg font-semibold">{student.student_name}</h2>
          <p className="text-sm text-slate-600">
            {student.student_code} · {student.course_name}
          </p>
          <p className="mt-2 text-sm">
            회차: {student.used_lesson_count}/{student.registered_lesson_count} (잔여{' '}
            {student.remaining_lesson_count})
          </p>
          <p className="text-sm text-slate-600">
            회차권: {student.pass_code} · {PASS_STATUS_LABELS[student.pass_status] ?? student.pass_status}
          </p>
        </article>
      ))}
    </div>
  );
}

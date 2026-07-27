'use client';

import { useCallback, useState } from 'react';
import { useRouter } from 'next/navigation';
import { OwnerScheduleChangeDialog } from '@/components/owner/owner-schedule-change-dialog';
import { WeeklyTimetableView } from '@/components/owner/weekly-timetable-view';
import {
  fetchPassScheduleSlotsWithTeachers,
  fetchLessonScheduleEditContext,
} from '@/lib/data/owner-schedule-edit';
import { fetchWeeklyTimetableLessons } from '@/lib/data/owner-queries';
import { groupTimetableLessonsByWeekday } from '@/lib/domain/weekly-timetable';
import type { WeeklyTimetableDayColumn, WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import { createClient } from '@/lib/supabase/client';

export function WeeklyTimetableClient({
  initialColumns,
  weekContextLabel,
}: {
  initialColumns: WeeklyTimetableDayColumn[];
  weekContextLabel: string;
}) {
  const router = useRouter();
  const [columns, setColumns] = useState(initialColumns);
  const [selectedLesson, setSelectedLesson] = useState<WeeklyTimetableLesson | null>(null);
  const [scheduleDialogOpen, setScheduleDialogOpen] = useState(false);
  const [dialogLesson, setDialogLesson] = useState<{
    id: string;
    scheduled_at: string;
    updated_at: string;
    status: WeeklyTimetableLesson['lesson_status'];
    duration_minutes: number;
    pass_id: string;
    pass_updated_at: string;
    sequence_number: number;
    registered_lesson_count: number;
  } | null>(null);
  const [dialogSlots, setDialogSlots] = useState<
    Array<{
      id: string;
      weekday: number;
      local_start_time: string;
      duration_minutes: number;
      teacher_id: string;
      teacher_name: string;
    }>
  >([]);
  const [weeklyFrequency, setWeeklyFrequency] = useState(1);
  const [remainingCount, setRemainingCount] = useState<number | null>(null);

  const refreshTimetable = useCallback(async () => {
    const supabase = createClient();
    const lessons = await fetchWeeklyTimetableLessons(supabase);
    setColumns(groupTimetableLessonsByWeekday(lessons));
    router.refresh();
  }, [router]);

  async function openScheduleChange(lesson: WeeklyTimetableLesson) {
    const supabase = createClient();
    const context = await fetchLessonScheduleEditContext(supabase, lesson.lesson_id);
    if (!context) {
      return;
    }

    const slots = await fetchPassScheduleSlotsWithTeachers(supabase, context.pass_id);
    setSelectedLesson(lesson);
    setDialogLesson({
      id: context.id,
      scheduled_at: context.scheduled_at,
      updated_at: context.updated_at,
      status: lesson.lesson_status,
      duration_minutes: lesson.duration_minutes,
      pass_id: context.pass_id,
      pass_updated_at: context.pass_updated_at,
      sequence_number: lesson.sequence_number,
      registered_lesson_count: lesson.registered_lesson_count,
    });
    setDialogSlots(slots);
    setWeeklyFrequency(context.weekly_frequency);
    setRemainingCount(context.remaining_lesson_count);
    setScheduleDialogOpen(true);
  }

  return (
    <>
      <WeeklyTimetableView
        columns={columns}
        weekContextLabel={weekContextLabel}
        onLessonSelect={(lesson) => {
          setSelectedLesson(lesson);
        }}
        onScheduleChange={(lesson) => void openScheduleChange(lesson)}
        selectedLessonId={selectedLesson?.lesson_id ?? null}
      />

      {selectedLesson ? (
        <section
          className="rounded-lg border border-slate-200 bg-white p-4"
          data-testid="weekly-lesson-detail-panel"
        >
          <h2 className="text-lg font-semibold">수업 상세</h2>
          <dl className="mt-3 space-y-2 text-sm">
            <div>
              <dt className="inline text-slate-500">학생명 </dt>
              <dd className="inline font-medium">{selectedLesson.student_name}</dd>
            </div>
            <div>
              <dt className="inline text-slate-500">과목 </dt>
              <dd className="inline">{selectedLesson.course_name}</dd>
            </div>
            <div>
              <dt className="inline text-slate-500">강사 </dt>
              <dd className="inline">{selectedLesson.teacher_name}</dd>
            </div>
            <div>
              <dt className="inline text-slate-500">현재 수업 날짜·시간 </dt>
              <dd className="inline">
                {new Intl.DateTimeFormat('ko-KR', {
                  timeZone: 'Asia/Seoul',
                  year: 'numeric',
                  month: 'long',
                  day: 'numeric',
                  weekday: 'long',
                  hour: '2-digit',
                  minute: '2-digit',
                }).format(new Date(selectedLesson.scheduled_at))}
              </dd>
            </div>
          </dl>
          <button
            type="button"
            className="mt-4 rounded-md bg-brand-700 px-4 py-2 text-sm font-medium text-white"
            onClick={() => void openScheduleChange(selectedLesson)}
            data-testid="weekly-lesson-schedule-change"
          >
            수업 일정 변경
          </button>
        </section>
      ) : null}

      {scheduleDialogOpen && dialogLesson ? (
        <OwnerScheduleChangeDialog
          open={scheduleDialogOpen}
          onClose={() => setScheduleDialogOpen(false)}
          studentName={selectedLesson?.student_name ?? ''}
          courseName={selectedLesson?.course_name ?? ''}
          teacherName={selectedLesson?.teacher_name ?? ''}
          remainingLessonCount={remainingCount}
          lesson={dialogLesson}
          scheduleSlots={dialogSlots}
          weeklyFrequency={weeklyFrequency}
          onSuccess={() => {
            setScheduleDialogOpen(false);
            void refreshTimetable();
          }}
        />
      ) : null}
    </>
  );
}

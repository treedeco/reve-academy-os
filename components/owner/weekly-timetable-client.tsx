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
import {
  buildWeekContextLabel,
  buildWeeklyTimetableColumns,
} from '@/lib/domain/weekly-timetable';
import type { WeeklyTimetableDayColumn, WeeklyTimetableLesson } from '@/lib/domain/weekly-timetable';
import { createClient } from '@/lib/supabase/client';

function addDaysToDateKey(dateKey: string, days: number): string {
  const base = new Date(`${dateKey}T12:00:00+09:00`);
  base.setUTCDate(base.getUTCDate() + days);
  return base.toISOString().slice(0, 10);
}

export function WeeklyTimetableClient({
  initialColumns,
  weekReferenceDateKey,
  weekContextLabel,
  isCurrentWeek,
}: {
  initialColumns: WeeklyTimetableDayColumn[];
  weekReferenceDateKey: string;
  weekContextLabel: string;
  isCurrentWeek: boolean;
}) {
  const router = useRouter();
  const [columns, setColumns] = useState(initialColumns);
  const [weekLabel, setWeekLabel] = useState(weekContextLabel);
  const [viewingCurrentWeek, setViewingCurrentWeek] = useState(isCurrentWeek);
  const [activeWeekDateKey, setActiveWeekDateKey] = useState(weekReferenceDateKey);
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
  const [pendingWeekNav, setPendingWeekNav] = useState(false);

  const loadWeek = useCallback(
    async (mondayDateKey: string | null) => {
      setPendingWeekNav(true);
      try {
        const weekReference = mondayDateKey
          ? new Date(`${mondayDateKey}T12:00:00+09:00`)
          : new Date();
        const supabase = createClient();
        const lessons = await fetchWeeklyTimetableLessons(supabase, { weekReference });
        setColumns(buildWeeklyTimetableColumns(lessons, weekReference));
        setWeekLabel(buildWeekContextLabel(weekReference));
        setActiveWeekDateKey(
          mondayDateKey ??
            buildWeeklyTimetableColumns(lessons, weekReference)[0]?.date_key ??
            weekReferenceDateKey,
        );
        setViewingCurrentWeek(mondayDateKey === null);

        const nextUrl = mondayDateKey ? `/schedule?week=${mondayDateKey}` : '/schedule';
        router.replace(nextUrl);
        router.refresh();
      } finally {
        setPendingWeekNav(false);
      }
    },
    [router, weekReferenceDateKey],
  );

  const refreshTimetable = useCallback(async () => {
    await loadWeek(viewingCurrentWeek ? null : activeWeekDateKey);
  }, [activeWeekDateKey, viewingCurrentWeek, loadWeek]);

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

  const mondayKey =
    columns[0]?.date_key ??
    activeWeekDateKey ??
    weekReferenceDateKey;

  return (
    <>
      <div className="flex flex-wrap items-center gap-2" data-testid="weekly-timetable-nav">
        <button
          type="button"
          className="rounded-md border border-slate-300 px-3 py-1.5 text-sm disabled:opacity-50"
          disabled={pendingWeekNav}
          onClick={() => void loadWeek(addDaysToDateKey(mondayKey, -7))}
          data-testid="weekly-timetable-prev-week"
        >
          이전 주
        </button>
        <button
          type="button"
          className="rounded-md border border-slate-300 px-3 py-1.5 text-sm disabled:opacity-50"
          disabled={pendingWeekNav || viewingCurrentWeek}
          onClick={() => void loadWeek(null)}
          data-testid="weekly-timetable-current-week"
        >
          이번 주
        </button>
        <button
          type="button"
          className="rounded-md border border-slate-300 px-3 py-1.5 text-sm disabled:opacity-50"
          disabled={pendingWeekNav}
          onClick={() => void loadWeek(addDaysToDateKey(mondayKey, 7))}
          data-testid="weekly-timetable-next-week"
        >
          다음 주
        </button>
      </div>

      <WeeklyTimetableView
        columns={columns}
        weekContextLabel={weekLabel}
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

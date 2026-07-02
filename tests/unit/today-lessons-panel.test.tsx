import { cleanup, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi, beforeEach } from 'vitest';
import { TodayLessonsPanel } from '@/components/owner/today-lessons-panel';
import type { TodayLessonRow } from '@/lib/domain/types';

const rpc = vi.fn();
const from = vi.fn();

vi.mock('@/lib/supabase/client', () => ({
  createClient: () => ({ rpc, from }),
}));

function buildLesson(overrides: Partial<TodayLessonRow> & Pick<TodayLessonRow, 'id'>): TodayLessonRow {
  return {
    scheduled_at: new Date().toISOString(),
    status: 'scheduled',
    updated_at: new Date().toISOString(),
    sequence_number: 1,
    student_id: '44444444-4444-4444-4444-44444444441a1',
    student_name: 'Alpha Student',
    course_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee1a1',
    course_name: 'Alpha Vocal Course',
    teacher_id: '22222222-2222-2222-2222-2222222221a1',
    teacher_name: 'Alpha Teacher',
    pass_id: '66666666-6666-6666-6666-6666666661a1',
    memo_summary: null,
    ...overrides,
  };
}

const lessonA = buildLesson({
  id: '99999999-9999-9999-9999-9999999991a1',
  student_name: 'Alpha Student',
  memo_summary: 'Alpha seed memo',
});

const lessonB = buildLesson({
  id: '99999999-9999-9999-9999-9999999991b2',
  student_name: 'Beta Student',
  sequence_number: 2,
});

describe('TodayLessonsPanel', () => {
  afterEach(() => {
    cleanup();
  });

  beforeEach(() => {
    rpc.mockReset();
    from.mockReset();
  });

  it('renders today lessons', () => {
    render(<TodayLessonsPanel initialLessons={[lessonA]} />);
    expect(screen.getByText('Alpha Student')).toBeInTheDocument();
    expect(screen.getByText(/Alpha seed memo/)).toBeInTheDocument();
  });

  it('rolls back failed status changes', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'REVE_INVALID_TRANSITION' } });
    render(<TodayLessonsPanel initialLessons={[lessonA]} />);

    await userEvent.selectOptions(within(screen.getByTestId(`today-lesson-${lessonA.id}`)).getByLabelText('상태 변경'), 'completed');

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('허용되지 않는');
    });
    expect(within(screen.getByTestId(`today-lesson-${lessonA.id}`)).getByLabelText('상태 변경')).toHaveValue('scheduled');
    expect(from).not.toHaveBeenCalled();
  });

  it('shows pending state while saving', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    rpc.mockImplementation(
      () =>
        new Promise((resolve) => {
          setTimeout(
            () =>
              resolve({
                data: [
                  {
                    new_status: 'completed',
                    lesson_updated_at: new Date().toISOString(),
                  },
                ],
                error: null,
              }),
            50,
          );
        }),
    );

    render(<TodayLessonsPanel initialLessons={[lessonA]} />);
    await userEvent.selectOptions(within(screen.getByTestId(`today-lesson-${lessonA.id}`)).getByLabelText('상태 변경'), 'completed');

    expect(screen.getByText('저장 중…')).toBeInTheDocument();
    await vi.runAllTimersAsync();
    vi.useRealTimers();
  });

  it('updates only the target lesson on success without broad refetch', async () => {
    const updatedAt = '2026-07-02T10:00:00.000Z';
    rpc.mockResolvedValueOnce({
      data: [
        {
          new_status: 'completed',
          lesson_updated_at: updatedAt,
        },
      ],
      error: null,
    });

    render(<TodayLessonsPanel initialLessons={[lessonA, lessonB]} />);

    const lessonACard = screen.getByTestId(`today-lesson-${lessonA.id}`);
    const lessonBCard = screen.getByTestId(`today-lesson-${lessonB.id}`);

    await userEvent.selectOptions(within(lessonACard).getByLabelText('상태 변경'), 'completed');

    await waitFor(() => {
      expect(within(lessonACard).getByLabelText('상태 변경')).toHaveValue('completed');
    });

    expect(within(lessonBCard).getByLabelText('상태 변경')).toHaveValue('scheduled');
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(from).not.toHaveBeenCalled();
  });
});

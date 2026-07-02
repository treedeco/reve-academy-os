import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { TodayLessonsPanel } from '@/components/owner/today-lessons-panel';
import type { TodayLessonRow } from '@/lib/domain/types';

const refresh = vi.fn();

vi.mock('next/navigation', () => ({
  useRouter: () => ({ refresh }),
}));

const rpc = vi.fn();

vi.mock('@/lib/supabase/client', () => ({
  createClient: () => ({ rpc }),
}));

const lesson: TodayLessonRow = {
  id: '99999999-9999-9999-9999-9999999991a1',
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
  memo_summary: 'Alpha seed memo',
};

describe('TodayLessonsPanel', () => {
  beforeEach(() => {
    rpc.mockReset();
    refresh.mockReset();
  });

  it('renders today lessons', () => {
    render(<TodayLessonsPanel initialLessons={[lesson]} />);
    expect(screen.getByText('Alpha Student')).toBeInTheDocument();
    expect(screen.getByText(/Alpha seed memo/)).toBeInTheDocument();
  });

  it('rolls back failed status changes', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'REVE_INVALID_TRANSITION' } });
    render(<TodayLessonsPanel initialLessons={[lesson]} />);

    await userEvent.selectOptions(screen.getByLabelText('상태 변경'), 'completed');

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('허용되지 않는');
    });
    expect(screen.getByLabelText('상태 변경')).toHaveValue('scheduled');
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

    render(<TodayLessonsPanel initialLessons={[lesson]} />);
    await userEvent.selectOptions(screen.getByLabelText('상태 변경'), 'completed');

    expect(screen.getByText('저장 중…')).toBeInTheDocument();
    await vi.runAllTimersAsync();
    vi.useRealTimers();
  });
});

import { cleanup, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { LessonNoteField } from '@/components/shared/lesson-note-field';

const insert = vi.fn();
const update = vi.fn();
const eq = vi.fn();
const select = vi.fn();
const single = vi.fn();
const maybeSingle = vi.fn();

vi.mock('@/lib/supabase/client', () => ({
  createClient: () => ({
    from: () => ({
      insert: (...args: unknown[]) => {
        insert(...args);
        return {
          select: (...selectArgs: unknown[]) => {
            select(...selectArgs);
            return { single };
          },
        };
      },
      update: (...args: unknown[]) => {
        update(...args);
        return {
          eq: (...eqArgs: unknown[]) => {
            eq(...eqArgs);
            return {
              select: (...selectArgs: unknown[]) => {
                select(...selectArgs);
                return { maybeSingle };
              },
            };
          },
        };
      },
    }),
  }),
}));

describe('LessonNoteField', () => {
  afterEach(() => {
    cleanup();
  });

  beforeEach(() => {
    insert.mockReset();
    update.mockReset();
    eq.mockReset();
    select.mockReset();
    single.mockReset();
    maybeSingle.mockReset();
  });

  it('creates a new lesson note', async () => {
    single.mockResolvedValueOnce({
      data: {
        id: 'note-1',
        lesson_id: 'lesson-1',
        body: 'Saved note',
        visibility: 'internal',
        author_profile_id: 'profile-1',
        created_at: '2026-01-01T00:00:00.000Z',
        updated_at: '2026-01-01T00:00:00.000Z',
      },
      error: null,
    });

    render(
      <LessonNoteField
        lessonId="lesson-1"
        authorProfileId="profile-1"
        initialBody={null}
        initialNoteId={null}
      />,
    );

    await userEvent.type(screen.getByLabelText('수업 내용'), 'Saved note');
    await userEvent.click(screen.getByTestId('lesson-note-save-lesson-1'));

    await waitFor(() => {
      expect(screen.getByRole('status')).toHaveTextContent('저장됨');
    });
    expect(insert).toHaveBeenCalled();
  });

  it('updates an existing lesson note', async () => {
    maybeSingle.mockResolvedValueOnce({
      data: {
        id: 'note-1',
        lesson_id: 'lesson-1',
        body: 'Updated note',
        visibility: 'internal',
        author_profile_id: 'profile-1',
        created_at: '2026-01-01T00:00:00.000Z',
        updated_at: '2026-01-01T00:00:01.000Z',
      },
      error: null,
    });

    render(
      <LessonNoteField
        lessonId="lesson-1"
        authorProfileId="profile-1"
        initialBody="Original"
        initialNoteId="note-1"
      />,
    );

    const textarea = screen.getByLabelText('수업 내용');
    await userEvent.clear(textarea);
    await userEvent.type(textarea, 'Updated note');
    await userEvent.click(screen.getByTestId('lesson-note-save-lesson-1'));

    await waitFor(() => {
      expect(screen.getByRole('status')).toHaveTextContent('저장됨');
    });
    expect(update).toHaveBeenCalled();
  });

  it('creates a new note when update is not permitted for the existing note', async () => {
    maybeSingle.mockResolvedValueOnce({ data: null, error: null });
    single.mockResolvedValueOnce({
      data: {
        id: 'note-2',
        lesson_id: 'lesson-1',
        body: 'Teacher note',
        visibility: 'internal',
        author_profile_id: 'profile-teacher',
        created_at: '2026-01-01T00:00:00.000Z',
        updated_at: '2026-01-01T00:00:00.000Z',
      },
      error: null,
    });

    render(
      <LessonNoteField
        lessonId="lesson-1"
        authorProfileId="profile-teacher"
        initialBody="Owner note"
        initialNoteId="note-owner"
      />,
    );

    const textarea = screen.getByLabelText('수업 내용');
    await userEvent.clear(textarea);
    await userEvent.type(textarea, 'Teacher note');
    await userEvent.click(screen.getByTestId('lesson-note-save-lesson-1'));

    await waitFor(() => {
      expect(screen.getByRole('status')).toHaveTextContent('저장됨');
    });
    expect(update).toHaveBeenCalled();
    expect(insert).toHaveBeenCalled();
  });
});

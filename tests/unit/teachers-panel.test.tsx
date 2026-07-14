import { cleanup, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { TeachersPanel } from '@/components/owner/teachers-panel';
import type { OwnerTeacherRow } from '@/lib/domain/types';

const { createOwnerTeacher, updateOwnerTeacher, setOwnerTeacherActive } = vi.hoisted(() => ({
  createOwnerTeacher: vi.fn(),
  updateOwnerTeacher: vi.fn(),
  setOwnerTeacherActive: vi.fn(),
}));

vi.mock('@/lib/data/owner-teachers', () => ({
  createOwnerTeacher,
  updateOwnerTeacher,
  setOwnerTeacherActive,
}));

const activeTeacher: OwnerTeacherRow = {
  id: '22222222-2222-2222-2222-222222222199',
  teacher_code: 'T-UNASSGN',
  name: 'Unassigned Seed Teacher',
  phone: '010-0000-0000',
  email: 'unassigned@test.local',
  is_active: true,
  updated_at: '2026-07-01T00:00:00.000Z',
};

const inactiveTeacher: OwnerTeacherRow = {
  id: '22222222-2222-2222-2222-222222222198',
  teacher_code: 'T-INACT',
  name: 'Inactive Teacher',
  phone: null,
  email: null,
  is_active: false,
  updated_at: '2026-07-02T00:00:00.000Z',
};

describe('TeachersPanel', () => {
  afterEach(() => {
    cleanup();
  });

  beforeEach(() => {
    createOwnerTeacher.mockReset();
    updateOwnerTeacher.mockReset();
    setOwnerTeacherActive.mockReset();
    vi.stubGlobal('confirm', vi.fn(() => true));
  });

  it('renders teacher list and status badges', () => {
    render(<TeachersPanel initialTeachers={[activeTeacher, inactiveTeacher]} />);

    expect(screen.getByTestId('teachers-list')).toBeInTheDocument();
    expect(screen.getByTestId('teacher-status-T-UNASSGN')).toHaveTextContent('활성');
    expect(screen.getByTestId('teacher-status-T-INACT')).toHaveTextContent('비활성');
  });

  it('renders empty state', () => {
    render(<TeachersPanel initialTeachers={[]} />);
    expect(screen.getByTestId('teachers-empty')).toHaveTextContent('등록된 강사가 없습니다');
  });

  it('validates create form before submission', async () => {
    const user = userEvent.setup();
    render(<TeachersPanel initialTeachers={[]} />);

    await user.click(screen.getByTestId('teacher-create-submit'));
    expect(screen.getByTestId('teacher-create-error')).toHaveTextContent('강사 코드');
    expect(createOwnerTeacher).not.toHaveBeenCalled();
  });

  it('creates a teacher and appends it to the list', async () => {
    const user = userEvent.setup();
    createOwnerTeacher.mockResolvedValueOnce({
      ...activeTeacher,
      id: '22222222-2222-2222-2222-222222222197',
      teacher_code: 'T-NEW1',
      name: 'New Teacher',
      phone: '010-1111-2222',
      email: 'new@test.local',
    });

    render(<TeachersPanel initialTeachers={[activeTeacher]} />);

    await user.type(screen.getByTestId('teacher-create-code'), 'T-NEW1');
    await user.type(screen.getByTestId('teacher-create-name'), 'New Teacher');
    await user.type(screen.getByTestId('teacher-create-phone'), '010-1111-2222');
    await user.type(screen.getByTestId('teacher-create-email'), 'new@test.local');
    await user.click(screen.getByTestId('teacher-create-submit'));

    expect(createOwnerTeacher).toHaveBeenCalledTimes(1);
    expect(await screen.findByTestId('teacher-item-T-NEW1')).toBeInTheDocument();
  });

  it('shows create failure without clearing user input', async () => {
    const user = userEvent.setup();
    createOwnerTeacher.mockRejectedValueOnce(new Error('REVE_INVALID_CODE'));

    render(<TeachersPanel initialTeachers={[]} />);

    await user.type(screen.getByTestId('teacher-create-code'), 'bad');
    await user.type(screen.getByTestId('teacher-create-name'), 'Bad Teacher');
    await user.click(screen.getByTestId('teacher-create-submit'));

    expect(screen.getByTestId('teacher-create-error')).toHaveTextContent('코드');
    expect(screen.getByTestId('teacher-create-name')).toHaveValue('Bad Teacher');
  });

  it('updates a teacher and closes the edit form', async () => {
    const user = userEvent.setup();
    updateOwnerTeacher.mockResolvedValueOnce({
      ...activeTeacher,
      name: 'Renamed Teacher',
      phone: '010-9999-8888',
      email: 'renamed@test.local',
      updated_at: '2026-07-03T00:00:00.000Z',
    });

    render(<TeachersPanel initialTeachers={[activeTeacher]} />);
    await user.click(screen.getByTestId('teacher-edit-T-UNASSGN'));
    await user.clear(screen.getByTestId('teacher-edit-name-T-UNASSGN'));
    await user.type(screen.getByTestId('teacher-edit-name-T-UNASSGN'), 'Renamed Teacher');
    await user.click(screen.getByTestId('teacher-save-T-UNASSGN'));

    expect(updateOwnerTeacher).toHaveBeenCalledTimes(1);
    expect(screen.getByText('Renamed Teacher')).toBeInTheDocument();
    expect(screen.queryByTestId('teacher-save-T-UNASSGN')).not.toBeInTheDocument();
  });

  it('rolls back failed optimistic update with stale-state message', async () => {
    const user = userEvent.setup();
    updateOwnerTeacher.mockRejectedValueOnce(new Error('REVE_STALE_STATE'));

    render(<TeachersPanel initialTeachers={[activeTeacher]} />);
    await user.click(screen.getByTestId('teacher-edit-T-UNASSGN'));
    await user.clear(screen.getByTestId('teacher-edit-name-T-UNASSGN'));
    await user.type(screen.getByTestId('teacher-edit-name-T-UNASSGN'), 'Stale Teacher');
    await user.click(screen.getByTestId('teacher-save-T-UNASSGN'));

    expect(screen.getByTestId('teacher-error-T-UNASSGN')).toHaveTextContent('새로고침');
    expect(screen.getByTestId('teacher-edit-name-T-UNASSGN')).toHaveValue('Stale Teacher');
  });

  it('requires confirmation and reason before deactivation', async () => {
    const user = userEvent.setup();
    setOwnerTeacherActive.mockResolvedValueOnce({
      id: activeTeacher.id,
      teacher_code: activeTeacher.teacher_code,
      name: activeTeacher.name,
      phone: null,
      email: null,
      is_active: false,
      updated_at: '2026-07-04T00:00:00.000Z',
    });

    render(<TeachersPanel initialTeachers={[activeTeacher]} />);
    await user.click(screen.getByTestId('teacher-deactivate-T-UNASSGN'));
    expect(screen.getByTestId('teacher-error-T-UNASSGN')).toHaveTextContent('사유');

    await user.type(screen.getByTestId('teacher-status-reason-T-UNASSGN'), 'no longer teaching');
    await user.click(screen.getByTestId('teacher-deactivate-T-UNASSGN'));

    expect(setOwnerTeacherActive).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ isActive: false, reason: 'no longer teaching' }),
    );
    expect(screen.getByTestId('teacher-status-T-UNASSGN')).toHaveTextContent('비활성');
  });

  it('shows blocked deactivation errors', async () => {
    const user = userEvent.setup();
    setOwnerTeacherActive.mockRejectedValueOnce(new Error('REVE_ACTIVE_ASSIGNMENTS_EXIST'));

    render(<TeachersPanel initialTeachers={[activeTeacher]} />);
    await user.type(screen.getByTestId('teacher-status-reason-T-UNASSGN'), 'attempt blocked');
    await user.click(screen.getByTestId('teacher-deactivate-T-UNASSGN'));

    expect(screen.getByTestId('teacher-error-T-UNASSGN')).toHaveTextContent('배정');
  });

  it('reactivates an inactive teacher', async () => {
    const user = userEvent.setup();
    setOwnerTeacherActive.mockResolvedValueOnce({
      id: inactiveTeacher.id,
      teacher_code: inactiveTeacher.teacher_code,
      name: inactiveTeacher.name,
      phone: null,
      email: null,
      is_active: true,
      updated_at: '2026-07-05T00:00:00.000Z',
    });

    render(<TeachersPanel initialTeachers={[inactiveTeacher]} />);
    await user.type(screen.getByTestId('teacher-status-reason-T-INACT'), 'returning teacher');
    await user.click(screen.getByTestId('teacher-reactivate-T-INACT'));

    expect(setOwnerTeacherActive).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ isActive: true }),
    );
    expect(screen.getByTestId('teacher-status-T-INACT')).toHaveTextContent('활성');
  });

  it('prevents duplicate submit while create is pending', async () => {
    const user = userEvent.setup();
    let resolveCreate: ((value: OwnerTeacherRow) => void) | undefined;
    createOwnerTeacher.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveCreate = resolve;
        }),
    );

    render(<TeachersPanel initialTeachers={[]} />);
    await user.type(screen.getByTestId('teacher-create-code'), 'T-PEND');
    await user.type(screen.getByTestId('teacher-create-name'), 'Pending Teacher');
    await user.click(screen.getByTestId('teacher-create-submit'));
    await user.click(screen.getByTestId('teacher-create-submit'));

    expect(createOwnerTeacher).toHaveBeenCalledTimes(1);
    resolveCreate?.({
      id: '22222222-2222-2222-2222-222222222197',
      teacher_code: 'T-PEND',
      name: 'Pending Teacher',
      phone: null,
      email: null,
      is_active: true,
      updated_at: '2026-07-06T00:00:00.000Z',
    });
  });

  it('does not expose delete actions', () => {
    render(<TeachersPanel initialTeachers={[activeTeacher]} />);
    const panel = screen.getByTestId('teachers-panel');
    expect(within(panel).queryByRole('button', { name: /삭제/ })).toBeNull();
  });
});

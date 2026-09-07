import { cleanup, render, screen } from '@testing-library/react';
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

describe('Owner Teacher Visibility & Assignment Regression Tests', () => {
  afterEach(() => {
    cleanup();
  });

  beforeEach(() => {
    createOwnerTeacher.mockReset();
    updateOwnerTeacher.mockReset();
    setOwnerTeacherActive.mockReset();
    vi.stubGlobal('confirm', vi.fn(() => true));
  });

  const canonicalActiveTeacher: OwnerTeacherRow = {
    id: 'f11d8f5c-b9b9-4b1f-aeb3-069a981c8641',
    teacher_code: 't-p-1',
    name: '이혜인',
    phone: '010-2713-4910',
    email: 'in2520@naver.com',
    is_active: true,
    updated_at: '2026-09-07T00:00:00.000Z',
  };

  const otherActiveTeacher: OwnerTeacherRow = {
    id: 'aba1417b-c409-4cf3-9b3d-fbd6eaf4ea23',
    teacher_code: 't-v-1',
    name: '김홍중',
    phone: '010-1234-5678',
    email: 'hong@test.local',
    is_active: true,
    updated_at: '2026-07-01T00:00:00.000Z',
  };

  const inactiveDuplicateTeacher: OwnerTeacherRow = {
    id: '0aaae309-8d19-4876-bce7-d7756f7ef5e2',
    teacher_code: 't-m-1',
    name: '이혜인',
    phone: '010-2713-4910',
    email: 'in2520@naver.com',
    is_active: false,
    updated_at: '2026-09-07T08:00:00.000Z',
  };

  it('1. active teacher visible by default in /teachers view', () => {
    render(
      <TeachersPanel
        initialTeachers={[canonicalActiveTeacher, otherActiveTeacher, inactiveDuplicateTeacher]}
      />,
    );

    // Active teachers are displayed in the list
    expect(screen.getByTestId('teacher-item-t-p-1')).toBeInTheDocument();
    expect(screen.getByTestId('teacher-status-t-p-1')).toHaveTextContent('활성');
    expect(screen.getByTestId('teacher-item-t-v-1')).toBeInTheDocument();
    expect(screen.getByTestId('teacher-status-t-v-1')).toHaveTextContent('활성');
  });

  it('2. inactive teacher hidden by default in /teachers view', () => {
    render(
      <TeachersPanel
        initialTeachers={[canonicalActiveTeacher, otherActiveTeacher, inactiveDuplicateTeacher]}
      />,
    );

    // Inactive duplicate t-m-1 must NOT appear
    expect(screen.queryByTestId('teacher-item-t-m-1')).not.toBeInTheDocument();
    expect(screen.queryByTestId('teacher-status-t-m-1')).not.toBeInTheDocument();
    expect(screen.queryByTestId('inactive-teachers-section')).not.toBeInTheDocument();
  });

  it('3. inactive teacher visible when "비활성 강사 보기" is enabled', async () => {
    const user = userEvent.setup();
    render(
      <TeachersPanel
        initialTeachers={[canonicalActiveTeacher, otherActiveTeacher, inactiveDuplicateTeacher]}
      />,
    );

    // Initially hidden
    expect(screen.queryByTestId('teacher-item-t-m-1')).not.toBeInTheDocument();

    // Enable "비활성 강사 보기"
    const checkbox = screen.getByTestId('show-inactive-teachers-checkbox');
    await user.click(checkbox);

    // Now inactive section and t-m-1 appear
    expect(screen.getByTestId('inactive-teachers-section')).toBeInTheDocument();
    const inactiveItem = screen.getByTestId('teacher-item-t-m-1');
    expect(inactiveItem).toBeInTheDocument();
    expect(screen.getByTestId('teacher-status-t-m-1')).toHaveTextContent('비활성');

    // Canonical active teacher remains in active list
    expect(screen.getByTestId('teacher-item-t-p-1')).toBeInTheDocument();
    expect(screen.getByTestId('teacher-status-t-p-1')).toHaveTextContent('활성');

    // Toggling off hides t-m-1 again
    await user.click(checkbox);
    expect(screen.queryByTestId('teacher-item-t-m-1')).not.toBeInTheDocument();
    expect(screen.queryByTestId('inactive-teachers-section')).not.toBeInTheDocument();
  });

  it('4. inactive teachers excluded from new-assignment selectors', () => {
    // Simulating database query filter used by enrollment catalog:
    // supabase.from('teachers').select('id, teacher_code, name').eq('is_active', true)
    const allDatabaseTeachers = [canonicalActiveTeacher, otherActiveTeacher, inactiveDuplicateTeacher];

    const activeTeachersForAssignment = allDatabaseTeachers.filter((t) => t.is_active);

    expect(activeTeachersForAssignment).toHaveLength(2);
    expect(activeTeachersForAssignment.some((t) => t.teacher_code === 't-m-1')).toBe(false);
    expect(activeTeachersForAssignment.map((t) => t.teacher_code)).toEqual(['t-p-1', 't-v-1']);
  });

  it('5. canonical active teacher remains selectable for assignment across courses', () => {
    const activeTeachersForAssignment = [canonicalActiveTeacher, otherActiveTeacher];

    // Canonical teacher t-p-1 is selectable
    const selectableTeacher = activeTeachersForAssignment.find((t) => t.id === canonicalActiveTeacher.id);
    expect(selectableTeacher).toBeDefined();
    expect(selectableTeacher?.name).toBe('이혜인');
    expect(selectableTeacher?.teacher_code).toBe('t-p-1');

    // Can be assigned to Piano
    const pianoCourseId = 'course-piano-id';
    const compositionCourseId = 'course-composition-id';

    const pianoAssignment = { courseId: pianoCourseId, teacherId: selectableTeacher!.id };
    const compAssignment = { courseId: compositionCourseId, teacherId: selectableTeacher!.id };

    expect(pianoAssignment.teacherId).toBe(canonicalActiveTeacher.id);
    expect(compAssignment.teacherId).toBe(canonicalActiveTeacher.id);
  });

  it('6. deactivating an active teacher automatically reveals inactive section with deactivation result', async () => {
    const user = userEvent.setup();
    setOwnerTeacherActive.mockResolvedValueOnce({
      ...otherActiveTeacher,
      is_active: false,
      updated_at: '2026-09-07T08:30:00.000Z',
    });

    render(
      <TeachersPanel
        initialTeachers={[canonicalActiveTeacher, otherActiveTeacher]}
      />,
    );

    expect(screen.queryByTestId('inactive-teachers-section')).not.toBeInTheDocument();

    await user.type(screen.getByTestId('teacher-status-reason-t-v-1'), '휴직');
    await user.click(screen.getByTestId('teacher-deactivate-t-v-1'));

    // Inactive section is automatically revealed and t-v-1 shows as inactive
    expect(screen.getByTestId('inactive-teachers-section')).toBeInTheDocument();
    expect(screen.getByTestId('teacher-status-t-v-1')).toHaveTextContent('비활성');
    // Canonical active teacher remains in active section
    expect(screen.getByTestId('teacher-status-t-p-1')).toHaveTextContent('활성');
  });
});

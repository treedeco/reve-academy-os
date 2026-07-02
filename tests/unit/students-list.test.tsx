import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { StudentListRow } from '@/lib/domain/types';
import { formatDateTimeSeoul } from '@/lib/domain/format';

function StudentsListPreview({ students }: { students: StudentListRow[] }) {
  return (
    <div>
      <table>
        <tbody>
          {students.map((student) => (
            <tr key={student.id}>
              <td>{student.name}</td>
              <td>{student.operational_status}</td>
              <td>{student.course_name ?? '-'}</td>
              <td>{student.teacher_name ?? '-'}</td>
              <td>
                {student.next_lesson_at ? formatDateTimeSeoul(student.next_lesson_at) : '-'}
              </td>
              <td>{student.remaining_lesson_count ?? '-'}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <div>
        {students.map((student) => (
          <article key={`card-${student.id}`}>{student.name}</article>
        ))}
      </div>
    </div>
  );
}

const row: StudentListRow = {
  id: '44444444-4444-4444-4444-444444444101',
  name: 'Alpha Student',
  student_code: 'S1A1',
  operational_status: 'active',
  course_id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeee101',
  course_name: 'Alpha Vocal Course',
  teacher_name: 'Alpha Teacher',
  next_lesson_at: '2026-06-26T01:00:00.000Z',
  remaining_lesson_count: 4,
  pass_id: '66666666-6666-6666-6666-666666666101',
};

describe('Students list rendering', () => {
  it('renders student list fields', () => {
    render(<StudentsListPreview students={[row]} />);
    expect(screen.getAllByText('Alpha Student')).toHaveLength(2);
    expect(screen.getByText('Alpha Vocal Course')).toBeInTheDocument();
    expect(screen.getByText('Alpha Teacher')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
  });
});

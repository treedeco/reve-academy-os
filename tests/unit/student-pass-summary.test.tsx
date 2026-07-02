import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { StudentPassSummary } from '@/components/owner/student-pass-summary';
import type { PassUsageSummary } from '@/lib/domain/types';

const pass: PassUsageSummary = {
  pass_id: '66666666-6666-6666-6666-666666666101',
  pass_code: 'V-S1A1-001',
  pass_status: 'active',
  registered_lesson_count: 4,
  used_lesson_count: 1,
  remaining_lesson_count: 3,
  next_lesson_at: '2026-06-26T01:00:00.000Z',
};

describe('StudentPassSummary', () => {
  it('renders derived used and remaining counts', () => {
    render(<StudentPassSummary pass={pass} />);
    expect(screen.getByTestId('used-count')).toHaveTextContent('1');
    expect(screen.getByTestId('remaining-count')).toHaveTextContent('3');
    expect(screen.getByText('V-S1A1-001')).toBeInTheDocument();
  });
});

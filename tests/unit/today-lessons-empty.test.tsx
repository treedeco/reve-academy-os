import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { EmptyState } from '@/components/ui/state-blocks';

describe('Today lessons empty state', () => {
  it('renders empty today-lessons message', () => {
    render(
      <EmptyState
        title="오늘 예정된 수업이 없습니다"
        description="새 수업이 등록되면 이 화면에 표시됩니다."
      />,
    );
    expect(screen.getByText('오늘 예정된 수업이 없습니다')).toBeInTheDocument();
  });
});

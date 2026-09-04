import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('weekly timetable event height guards', () => {
  it('clips absolute event overlays so card content cannot expand grid rows', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'components/owner/weekly-timetable-grid.tsx'),
      'utf8',
    );
    expect(source).toContain('computeTimetableEventBox');
    expect(source).toContain('overflow-hidden');
    expect(source).toContain('WEEKLY_TIMETABLE_ROW_HEIGHT_PX');
  });

  it('keeps compact cards height-bounded with truncation', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'components/owner/weekly-timetable-lesson-card.tsx'),
      'utf8',
    );
    expect(source).toContain('h-full min-h-0 overflow-hidden');
    expect(source).toContain('truncate');
  });
});

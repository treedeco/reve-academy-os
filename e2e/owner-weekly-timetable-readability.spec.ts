import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
import { applySqlFixture } from './helpers/apply-sql-fixture';
import path from 'node:path';

const FIXTURE_WEEK = '2026-07-27';
const ALPHA_LESSON_ID = '99999999-9999-9999-9999-999999999101';

test.describe('Owner weekly timetable readability', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-reset-weekly-timetable.sql');
  });

  test('60-minute lesson card shows prominent student name without console errors', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await loginAsOwner(page);
    await page.goto(`/schedule?week=${FIXTURE_WEEK}`);

    const placement = page.getByTestId(`weekly-timetable-placement-${ALPHA_LESSON_ID}`);
    const card = placement.getByTestId(`weekly-timetable-lesson-${ALPHA_LESSON_ID}`);
    await expect(card).toBeVisible();
    await expect(card.getByText('Alpha Student')).toBeVisible();
    await expect(card.getByTestId('lesson-progress-label')).toBeVisible();
    await expect(placement.getByTestId(`weekly-lesson-detail-open-${ALPHA_LESSON_ID}`)).toBeVisible();
    await expect(placement.getByTestId(`weekly-lesson-schedule-open-${ALPHA_LESSON_ID}`)).toBeVisible();

    const box = await placement.boundingBox();
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(78);

    const nameStyles = await card.getByText('Alpha Student').evaluate((el) => {
      const style = window.getComputedStyle(el);
      return {
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
      };
    });
    expect(Number.parseFloat(nameStyles.fontSize)).toBeGreaterThanOrEqual(14);
    expect(Number.parseInt(nameStyles.fontWeight, 10)).toBeGreaterThanOrEqual(600);

    await page.screenshot({
      path: path.join('artifacts', 'weekly-timetable-readability.png'),
      fullPage: true,
    });

    await page.getByTestId('weekly-timetable-next-week').click();
    await expect(page.getByTestId('weekly-timetable-header-1')).toContainText('월 8/3');
    await page.getByTestId('weekly-timetable-prev-week').click();
    await expect(page.getByTestId('weekly-timetable-header-2')).toContainText('화 7/28');

    expect(consoleErrors).toEqual([]);
  });
});

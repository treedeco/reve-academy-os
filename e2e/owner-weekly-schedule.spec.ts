import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
import { applySqlFixture } from './helpers/apply-sql-fixture';

test.describe('Owner weekly timetable', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-reset-weekly-timetable.sql');
  });

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/schedule');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders desktop timetable grid with aligned hours and progress notation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule');

    await expect(page.getByRole('heading', { name: '주간 시간표' })).toBeVisible();
    await expect(page.getByTestId('weekly-timetable-grid')).toBeVisible();
    await expect(page.getByTestId('weekly-timetable-row-780')).toContainText('13:00');
    await expect(page.getByTestId('weekly-timetable-range-label')).toContainText('13:00–22:00');
    await expect(page.getByTestId('weekly-timetable-row-1320')).toHaveCount(0);

    const monday = page.getByTestId('weekly-timetable-day-1');
    await expect(monday.getByText('Alpha Student')).toBeVisible();
    await expect(monday.getByTestId('lesson-progress-label').first()).toHaveText('4-1');

    const wednesday = page.getByTestId('weekly-timetable-day-3');
    await expect(wednesday.getByText('Beta Student')).toHaveCount(2);
    await expect(wednesday.getByText('주 2회')).toHaveCount(0);
  });

  test('uses mobile weekday list on narrow viewport', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/schedule');

    await expect(page.getByTestId('weekly-timetable-mobile')).toBeVisible();
    await expect(page.getByTestId('weekly-timetable-mobile-day-3')).toBeVisible();
    await expect(page.getByTestId('weekly-timetable-mobile').getByText('Beta Student')).toHaveCount(2);
  });
});

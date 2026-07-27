import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
import { applySqlFixture } from './helpers/apply-sql-fixture';

const FIXTURE_WEEK = '2026-07-27';
const ALPHA_LESSON_ID = '99999999-9999-9999-9999-999999999101';
const NEXT_WEEK_LESSON_ID = '99999999-9999-9999-9999-999999999102';

test.describe('Owner weekly timetable', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-reset-weekly-timetable.sql');
  });

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/schedule');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders weekday date headers and 10:00 timetable rows', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/schedule?week=${FIXTURE_WEEK}`);

    await expect(page.getByRole('heading', { name: '주간 시간표' })).toBeVisible();
    await expect(page.getByTestId('weekly-timetable-grid')).toBeVisible();
    await expect(page.getByTestId('weekly-timetable-row-600')).toContainText('10:00');
    await expect(page.getByTestId('weekly-timetable-range-label')).toContainText('10:00–22:00');

    await expect(page.getByTestId('weekly-timetable-header-1')).toContainText('월 7/27');
    await expect(page.getByTestId('weekly-timetable-header-2')).toContainText('화 7/28');
    await expect(page.getByTestId('weekly-timetable-header-3')).toContainText('수 7/29');
    await expect(page.getByTestId('weekly-timetable-header-5')).toContainText('금 7/31');
    await expect(page.getByTestId('weekly-timetable-header-6')).toContainText('토 8/1');
  });

  test('places Tuesday and Wednesday 10:00 lessons in the correct columns', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/schedule?week=${FIXTURE_WEEK}`);

    const tuesday = page.getByTestId('weekly-timetable-day-2');
    await expect(tuesday.getByText('Alpha Student')).toBeVisible();
    await expect(tuesday.getByTestId(`weekly-timetable-placement-${ALPHA_LESSON_ID}`)).toBeVisible();

    const wednesday = page.getByTestId('weekly-timetable-day-3');
    await expect(wednesday.getByText('Beta Student')).toHaveCount(2);
  });

  test('excludes next-week Monday lesson until navigating forward', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/schedule?week=${FIXTURE_WEEK}`);

    await expect(page.getByTestId(`weekly-timetable-placement-${NEXT_WEEK_LESSON_ID}`)).toHaveCount(0);

    await page.getByTestId('weekly-timetable-next-week').click();
    await expect(page.getByTestId('weekly-timetable-header-1')).toContainText('월 8/3');
    await expect(page.getByTestId(`weekly-timetable-placement-${NEXT_WEEK_LESSON_ID}`)).toBeVisible();
  });

  test('navigates previous, current, and next week together with labels', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/schedule?week=${FIXTURE_WEEK}`);

    await expect(page.getByTestId('weekly-timetable-header-2')).toContainText('화 7/28');

    await page.getByTestId('weekly-timetable-prev-week').click();
    await expect(page.getByTestId('weekly-timetable-header-2')).not.toContainText('7/28');

    await page.getByTestId('weekly-timetable-next-week').click();
    await expect(page.getByTestId('weekly-timetable-header-2')).toContainText('화 7/28');

    await page.getByTestId('weekly-timetable-next-week').click();
    await expect(page.getByTestId('weekly-timetable-header-1')).toContainText('월 8/3');
  });

  test('uses mobile weekday list on narrow viewport', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto(`/schedule?week=${FIXTURE_WEEK}`);

    await expect(page.getByTestId('weekly-timetable-mobile')).toBeVisible();
    await expect(page.getByTestId('weekly-timetable-mobile-header-2')).toContainText('화 7/28');
    await expect(page.getByTestId('weekly-timetable-mobile').getByText('Beta Student')).toHaveCount(2);
  });
});

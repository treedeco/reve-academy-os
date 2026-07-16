import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
import { applySqlFixture } from './helpers/apply-sql-fixture';

const BETA_STUDENT_ID = '44444444-4444-4444-4444-444444444102';
const BETA_LESSON_1_ID = '99999999-9999-9999-9999-999999999201';

test.describe('Owner lesson rescheduling', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-reset-weekly-timetable.sql');
  });

  test('moves a single lesson and persists after reload', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${BETA_STUDENT_ID}`);

    await page.getByTestId(`lesson-reschedule-open-${BETA_LESSON_1_ID}`).click();
    await expect(page.getByTestId('lesson-reschedule-dialog')).toBeVisible();

    await page.getByTestId('reschedule-date').fill('2026-08-15');
    await page.getByTestId('reschedule-time').fill('14:00');
    await page.getByTestId('reschedule-reason').fill('E2E direct reschedule');
    await page.getByTestId('reschedule-confirm').click();

    await expect(page.getByTestId('lesson-reschedule-dialog')).toHaveCount(0, { timeout: 10_000 });
    await page.reload();
    await expect(page.getByTestId('student-lesson-1')).toContainText('8. 15');
    await expect(page.getByTestId('student-lesson-1')).toContainText('2:00');
  });

  test('rejects lesson start at 22:00', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${BETA_STUDENT_ID}`);

    await page.getByTestId(`lesson-reschedule-open-${BETA_LESSON_1_ID}`).click();
    await page.getByTestId('reschedule-date').fill('2026-08-15');
    await page.getByTestId('reschedule-time').fill('22:00');
    await page.getByTestId('reschedule-reason').fill('E2E invalid time');
    await page.getByTestId('reschedule-confirm').click();

    await expect(page.getByTestId('reschedule-error')).toContainText('22:00');
  });

  test('accepts 21:00 start within academy hours', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${BETA_STUDENT_ID}`);

    await page.getByTestId(`lesson-reschedule-open-${BETA_LESSON_1_ID}`).click();
    await page.getByTestId('reschedule-date').fill('2026-08-16');
    await page.getByTestId('reschedule-time').fill('21:00');
    await page.getByTestId('reschedule-reason').fill('E2E 21:00 slot');
    await page.getByTestId('reschedule-confirm').click();

    await expect(page.getByTestId('lesson-reschedule-dialog')).toHaveCount(0, { timeout: 10_000 });
  });
});

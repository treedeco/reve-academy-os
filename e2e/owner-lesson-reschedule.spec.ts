import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
import { applySqlFixture } from './helpers/apply-sql-fixture';

const BETA_STUDENT_ID = '44444444-4444-4444-4444-444444444102';
const BETA_LESSON_1_ID = '99999999-9999-9999-9999-999999999201';

async function saveSingleScheduleChange(
  page: import('@playwright/test').Page,
  date: string,
  time: string,
  reason: string,
) {
  await page.getByTestId('schedule-change-date').fill(date);
  await page.getByTestId('schedule-change-time').selectOption(time);
  await page.getByTestId('schedule-change-reason').fill(reason);
  await page.getByTestId('schedule-change-next').click();
  await page.getByTestId('schedule-change-save').click();
}

test.describe('Owner lesson rescheduling', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-reset-weekly-timetable.sql');
  });

  test('moves a single lesson and persists after reload', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${BETA_STUDENT_ID}`);

    await page.getByTestId(`lesson-reschedule-open-${BETA_LESSON_1_ID}`).click();
    await expect(page.getByTestId('owner-schedule-change-dialog')).toBeVisible();

    await saveSingleScheduleChange(page, '2026-08-15', '14:00', 'E2E direct reschedule');

    await expect(page.getByTestId('owner-schedule-change-dialog')).toHaveCount(0, {
      timeout: 10_000,
    });
    await page.reload();
    await expect(page.getByTestId('student-lesson-1')).toContainText('8. 15');
    await expect(page.getByTestId('student-lesson-1')).toContainText('2:00');
  });

  test('rejects lesson start at 22:00', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${BETA_STUDENT_ID}`);

    await page.getByTestId(`lesson-reschedule-open-${BETA_LESSON_1_ID}`).click();
    await page.getByTestId('schedule-change-date').fill('2026-08-15');
    await expect(page.getByTestId('schedule-change-time').locator('option[value="22:00"]')).toHaveCount(
      0,
    );
  });

  test('accepts 21:00 start within academy hours', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${BETA_STUDENT_ID}`);

    await page.getByTestId(`lesson-reschedule-open-${BETA_LESSON_1_ID}`).click();
    await saveSingleScheduleChange(page, '2026-08-16', '21:00', 'E2E 21:00 slot');

    await expect(page.getByTestId('owner-schedule-change-dialog')).toHaveCount(0, {
      timeout: 10_000,
    });
  });

  test('opens schedule change from student summary button with mode selection', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${BETA_STUDENT_ID}`);

    await page.getByTestId('student-schedule-change-open').click();
    await expect(page.getByTestId('schedule-change-mode-single')).toBeVisible();
    await expect(page.getByTestId('schedule-change-mode-recurring')).toBeVisible();
  });
});

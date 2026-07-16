import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
import { applySqlFixture } from './helpers/apply-sql-fixture';

const ALPHA_TODAY_LESSON_ID = '99999999-9999-9999-9999-999999999101';
const ALPHA_STUDENT_ID = '44444444-4444-4444-4444-444444444101';

test.describe.configure({ mode: 'serial' });

test.describe('Owner lesson status correction', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-reset-owner-alpha-today-lesson.sql');
  });

  test('corrects a completed lesson back to scheduled with reason', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/lessons/today');

    const row = page.getByTestId(`today-lesson-${ALPHA_TODAY_LESSON_ID}`);
    await expect(row).toBeVisible();

    await row.getByLabel('상태 변경').selectOption({ label: '완료' });
    await expect(row.getByTestId(`today-lesson-correction-${ALPHA_TODAY_LESSON_ID}`)).toBeVisible({
      timeout: 10_000,
    });

    await row.getByTestId(`today-lesson-correction-${ALPHA_TODAY_LESSON_ID}`).click();
    await expect(page.getByTestId('lesson-status-correction-dialog')).toBeVisible();
    await page.getByTestId('correction-target-status').selectOption('scheduled');
    await page.getByTestId('correction-reason').fill('E2E owner correction to scheduled');
    await page.getByTestId('correction-confirm').click();

    await expect(page.getByTestId('lesson-status-correction-dialog')).toHaveCount(0, {
      timeout: 10_000,
    });
    await expect(row.getByLabel('상태 변경')).toHaveValue('scheduled');

    await page.goto(`/students/${ALPHA_STUDENT_ID}`);
    await expect(page.getByTestId('used-count')).toHaveText('0');
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
  });

  test('requires correction reason', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/lessons/today');

    const row = page.getByTestId(`today-lesson-${ALPHA_TODAY_LESSON_ID}`);
    await row.getByLabel('상태 변경').selectOption({ label: '완료' });
    await expect(row.getByTestId(`today-lesson-correction-${ALPHA_TODAY_LESSON_ID}`)).toBeVisible({
      timeout: 10_000,
    });

    await row.getByTestId(`today-lesson-correction-${ALPHA_TODAY_LESSON_ID}`).click();
    await page.getByTestId('correction-confirm').click();
    await expect(page.getByTestId('correction-error')).toContainText('사유');
  });
});

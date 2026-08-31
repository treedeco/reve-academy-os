import { test, expect } from '@playwright/test';
import { seedOwnerAlphaFixture } from './helpers/apply-sql-fixture';
import { loginAsOwner } from './helpers/login-as-owner';
import { loginAsTeacher } from './helpers/login-as-teacher';

const ALPHA_TODAY_LESSON_ID = '99999999-9999-9999-9999-999999999101';

test.describe.configure({ mode: 'serial' });

test.describe('Immediate teacher operations', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test.beforeAll(() => {
    seedOwnerAlphaFixture();
  });

  test('teacher login lands on today lessons at 390px', async ({ page }) => {
    await loginAsTeacher(page);
    await expect(page.getByRole('heading', { name: '오늘의 수업' })).toBeVisible();
    await expect(page.getByTestId(`teacher-today-lesson-${ALPHA_TODAY_LESSON_ID}`)).toBeVisible();
  });

  test('teacher can change status and save lesson content', async ({ page }) => {
    await loginAsTeacher(page);
    const card = page.getByTestId(`teacher-today-lesson-${ALPHA_TODAY_LESSON_ID}`);
    await card.click();

    const statusSelect = card.getByLabel('출석 / 상태');
    await statusSelect.selectOption({ label: '완료' });

    const noteBody = `E2E teacher note ${Date.now()}`;
    await card.getByLabel('수업 내용').fill(noteBody);
    await card.getByTestId(`lesson-note-save-${ALPHA_TODAY_LESSON_ID}`).click();
    await expect(card.getByRole('status')).toHaveText('저장됨', { timeout: 10_000 });

    await page.reload();
    await card.click();
    await expect(card.getByLabel('수업 내용')).toHaveValue(noteBody);
  });

  test('teacher cannot access owner dashboard', async ({ page }) => {
    await loginAsTeacher(page);
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/login/);
  });

  test('owner can save lesson content on today lessons', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/lessons/today');
    const row = page.getByTestId(`today-lesson-${ALPHA_TODAY_LESSON_ID}`);
    const noteBody = `E2E owner note ${Date.now()}`;
    await row.getByLabel('수업 내용').fill(noteBody);
    await row.getByTestId(`lesson-note-save-${ALPHA_TODAY_LESSON_ID}`).click();
    await expect(row.getByRole('status')).toHaveText('저장됨', { timeout: 10_000 });

    await page.reload();
    await expect(row.getByLabel('수업 내용')).toHaveValue(noteBody);
  });
});

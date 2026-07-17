import { test, expect } from '@playwright/test';
import { seedOwnerAlphaFixture, applySqlFixture } from './helpers/apply-sql-fixture';
import { loginAsOwner } from './helpers/login-as-owner';
import { OWNER_LOGIN_USERNAME } from '@/lib/auth/owner-login';
import { getOwnerPasswordFromEnv } from '@/lib/auth/owner-credentials';

const ALPHA_STUDENT_ID = '44444444-4444-4444-4444-444444444101';
const ALPHA_TODAY_LESSON_ID = '99999999-9999-9999-9999-999999999101';

function alphaTodayLessonStatusSelect(page: import('@playwright/test').Page) {
  return page
    .getByTestId(`today-lesson-${ALPHA_TODAY_LESSON_ID}`)
    .getByLabel('상태 변경');
}

test.describe.configure({ mode: 'serial' });

test.describe('Owner Alpha', () => {
  test.beforeAll(() => {
    seedOwnerAlphaFixture();
  });

  test.beforeEach(() => {
    applySqlFixture('fixture-reset-owner-alpha-today-lesson.sql');
  });

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/login/);
  });

  test('failed mutation displays error and restores previous value', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/lessons/today');
    await expect(page.getByTestId(`today-lesson-${ALPHA_TODAY_LESSON_ID}`)).toBeVisible();
    await expect(page.getByText('Alpha Student')).toBeVisible();

    const statusSelect = alphaTodayLessonStatusSelect(page);
    await expect(statusSelect).toHaveValue('scheduled');

    await page.route('**/rest/v1/rpc/reve_transition_lesson_status', async (route) => {
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          code: 'P0001',
          message: 'REVE_INVALID_TRANSITION',
        }),
      });
    });

    await statusSelect.selectOption({ label: '완료' });
    await expect(page.locator('p.text-red-600[role="alert"]')).toContainText('허용되지 않는', {
      timeout: 10_000,
    });
    await expect(statusSelect).toHaveValue('scheduled');
  });

  test('owner can log in and manage today lessons', async ({ page }) => {
    await loginAsOwner(page);

    await page.goto('/lessons/today');
    await expect(page.getByRole('heading', { name: '오늘의 수업' })).toBeVisible();
    const row = page.getByTestId(`today-lesson-${ALPHA_TODAY_LESSON_ID}`);
    await expect(row).toBeVisible();

    const statusSelect = alphaTodayLessonStatusSelect(page);
    await expect(statusSelect).toHaveValue('scheduled');
    await statusSelect.selectOption({ label: '완료' });
    await expect(row.getByTestId(`today-lesson-correction-${ALPHA_TODAY_LESSON_ID}`)).toBeVisible({
      timeout: 10_000,
    });

    await page.reload();
    await expect(row.getByTestId(`today-lesson-correction-${ALPHA_TODAY_LESSON_ID}`)).toBeVisible();

    await row.getByRole('link', { name: '학생 상세 보기' }).click();
    await expect(page).toHaveURL(new RegExp(`/students/${ALPHA_STUDENT_ID}`), { timeout: 15_000 });
    await expect(page.getByTestId('used-count')).toHaveText('1');
    await expect(page.getByTestId('remaining-count')).toHaveText('3');
  });

  test('mobile layout remains usable', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/students');
    await expect(page.getByRole('heading', { name: '학생', exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: /Alpha Student/ }).first()).toBeVisible();
  });

  test('rejects legacy owner credentials', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('사용자 이름').fill('owner-alpha@test.local');
    await page.getByLabel('비밀번호').fill(getOwnerPasswordFromEnv());
    await page.getByRole('button', { name: '로그인' }).click();
    await expect(page.locator('p[role="alert"]')).toContainText('사용자 이름 또는 비밀번호');
  });

  test('rejects incorrect username', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('사용자 이름').fill('not-reve');
    await page.getByLabel('비밀번호').fill(getOwnerPasswordFromEnv());
    await page.getByRole('button', { name: '로그인' }).click();
    await expect(page.locator('p[role="alert"]')).toContainText('사용자 이름 또는 비밀번호');
  });

  test('rejects incorrect password', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('사용자 이름').fill(OWNER_LOGIN_USERNAME);
    await page.getByLabel('비밀번호').fill('wrong-password');
    await page.getByRole('button', { name: '로그인' }).click();
    await expect(page.locator('p[role="alert"]')).toContainText('사용자 이름 또는 비밀번호');
  });
});

import { test, expect } from '@playwright/test';

const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';

async function loginAsOwner(page: import('@playwright/test').Page) {
  await page.goto('/login');
  await page.getByLabel('이메일').fill(ownerEmail);
  await page.getByLabel('비밀번호').fill(ownerPassword);
  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 15_000 });
}

test.describe.configure({ mode: 'serial' });

test.describe('Owner Alpha', () => {
  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/login/);
  });

  test('failed mutation displays error and restores previous value', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/lessons/today');
    await expect(page.getByText('Alpha Student')).toBeVisible();

    const statusSelect = page.getByLabel('상태 변경').first();
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
    await expect(page.getByText('Alpha Student')).toBeVisible();

    const statusSelect = page.getByLabel('상태 변경').first();
    await statusSelect.selectOption({ label: '완료' });
    await expect(statusSelect).toHaveValue('completed', { timeout: 10_000 });

    await page.reload();
    await expect(page.getByLabel('상태 변경').first()).toHaveValue('completed');

    await page.getByRole('link', { name: '학생 상세 보기' }).first().click();
    await expect(page).toHaveURL(/\/students\//, { timeout: 15_000 });
    await expect(page.getByTestId('used-count')).toHaveText('1');
    await expect(page.getByTestId('remaining-count')).toHaveText('3');
  });

  test('mobile layout remains usable', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/students');
    await expect(page.getByRole('heading', { name: '학생' })).toBeVisible();
    await expect(page.getByRole('link', { name: /Alpha Student/ }).first()).toBeVisible();
  });
});

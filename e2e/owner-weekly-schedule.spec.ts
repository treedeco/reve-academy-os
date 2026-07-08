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

test.describe('Owner weekly schedule', () => {
  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/schedule');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders desktop weekly schedule with ordered entries', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule');

    await expect(page.getByRole('heading', { name: '주간 시간표' })).toBeVisible();
    await expect(page.getByRole('link', { name: '주간 시간표' })).toBeVisible();
    const desktop = page.getByTestId('weekly-schedule-desktop');
    await expect(desktop).toBeVisible();
    await expect(desktop.getByText('Alpha Student')).toBeVisible();
    await expect(desktop.getByText('Beta Student')).toHaveCount(2);
    await expect(desktop.getByText('Delta Student')).toBeVisible();
    await expect(page.getByText('Gamma Student')).toHaveCount(0);

    const mondayColumn = page.getByTestId('weekly-schedule-desktop-day-1');
    await expect(mondayColumn.getByText('Alpha Student')).toBeVisible();
    await expect(mondayColumn.locator('p.tabular-nums').first()).toContainText('10:00');

    const wednesdayColumn = page.getByTestId('weekly-schedule-desktop-day-3');
    await expect(wednesdayColumn.getByText('Beta Student')).toHaveCount(2);
  });

  test('uses mobile list layout on narrow viewport', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/schedule');

    const mobile = page.getByTestId('weekly-schedule-mobile');
    await expect(mobile).toBeVisible();
    await expect(page.getByTestId('weekly-schedule-day-3')).toBeVisible();
    await expect(mobile.getByText('Beta Student')).toHaveCount(2);
  });
});

import { execSync } from 'node:child_process';
import path from 'node:path';
import { expect, test } from '@playwright/test';

const TEST_EMAIL = 'password-change-owner@test.local';
const INITIAL_PASSWORD = 'PasswordChangeTest123!';
const UPDATED_PASSWORD = 'UpdatedPassword123!';

function applyPasswordChangeFixture() {
  const repoRoot = path.resolve(__dirname, '..');
  const container = execSync('node scripts/resolve-supabase-db-container.mjs', {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();
  const fixturePath = path.join(repoRoot, 'scripts', 'fixture-password-change-test-user.sql');
  execSync(`docker cp "${fixturePath}" ${container}:/tmp/fixture-password-change-test-user.sql`, {
    cwd: repoRoot,
    stdio: 'inherit',
  });
  execSync(
    `docker exec ${container} psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/fixture-password-change-test-user.sql`,
    { cwd: repoRoot, stdio: 'inherit' },
  );
}

async function loginAsPasswordChangeOwner(page: import('@playwright/test').Page) {
  applyPasswordChangeFixture();
  const { loginWithAuthEmailAndOpenDashboard } = await import('./helpers/login-with-auth-email');
  await loginWithAuthEmailAndOpenDashboard(page, TEST_EMAIL, INITIAL_PASSWORD);
}

test.describe('Owner password change', () => {
  test.beforeAll(() => {
    applyPasswordChangeFixture();
  });

  test.afterAll(() => {
    applyPasswordChangeFixture();
  });

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/account/password');
    await expect(page).toHaveURL(/\/login/);
  });

  test('login page shows password-changed success message', async ({ page }) => {
    await page.goto('/login?passwordChanged=1');
    await expect(page.getByRole('status')).toContainText('비밀번호가 변경되었습니다');
  });

  test('shows validation and current-password failure on the password page', async ({ page }) => {
    await loginAsPasswordChangeOwner(page);
    await page.goto('/account/password');

    await expect(page.getByRole('heading', { name: '비밀번호 변경' })).toBeVisible();
    await page.getByRole('button', { name: '비밀번호 변경' }).click();
    await expect(page.locator('p[role="alert"]')).toContainText('모든 비밀번호 입력란');

    await page.getByLabel('현재 비밀번호').fill('WrongCurrentPassword123!');
    await page.getByLabel('새 비밀번호', { exact: true }).fill('UpdatedPassword123!');
    await page.getByLabel('새 비밀번호 확인').fill('UpdatedPassword123!');
    await page.getByRole('button', { name: '비밀번호 변경' }).click();
    await expect(page.locator('p[role="alert"]')).toContainText('현재 비밀번호가 올바르지 않습니다');
  });

  test('supports successful password change, logout, and login with new password', async ({ page }) => {
    await loginAsPasswordChangeOwner(page);
    await page.goto('/account/password');

    await page.getByLabel('현재 비밀번호').fill(INITIAL_PASSWORD);
    await page.getByLabel('새 비밀번호', { exact: true }).fill(UPDATED_PASSWORD);
    await page.getByLabel('새 비밀번호 확인').fill(UPDATED_PASSWORD);
    await page.getByRole('button', { name: '비밀번호 변경' }).click();

    await expect(page).toHaveURL(/\/login\?passwordChanged=1/);
    await expect(page.getByRole('status')).toContainText('비밀번호가 변경되었습니다');

    const { loginWithAuthEmailAndOpenDashboard } = await import('./helpers/login-with-auth-email');
    await loginWithAuthEmailAndOpenDashboard(page, TEST_EMAIL, UPDATED_PASSWORD);
  });

  test('mobile layout remains usable around 390px', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsPasswordChangeOwner(page);
    await page.goto('/account/password');

    await expect(page.getByRole('heading', { name: '비밀번호 변경' })).toBeVisible();
    await expect(page.getByLabel('현재 비밀번호')).toBeVisible();
    await expect(page.getByRole('button', { name: '비밀번호 변경' })).toBeVisible();
  });
});

import { test, expect } from '@playwright/test';
import { seedOwnerAlphaFixture, seedOwnerOnlyAlphaFixture } from './helpers/apply-sql-fixture';

const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';
const assignedTeacherCode = 'T-A1';

async function loginAsOwner(page: import('@playwright/test').Page) {
  await page.goto('/login');
  await page.getByLabel('이메일').fill(ownerEmail);
  await page.getByLabel('비밀번호').fill(ownerPassword);
  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 15_000 });
}

test.describe.configure({ mode: 'serial' });

test.describe('Owner teacher master data', () => {
  const createdCode = `T-E2E${Date.now().toString().slice(-6)}`;
  const createdName = `E2E Teacher ${createdCode}`;

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/teachers');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders teacher list and navigation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');

    await expect(page.getByRole('heading', { name: '강사', exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: '강사' })).toBeVisible();
    await expect(page.getByTestId('teachers-panel')).toBeVisible();
    await expect(page.getByTestId(`teacher-item-${assignedTeacherCode}`)).toBeVisible();
  });

  test('creates a teacher without full-page reload', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');

    await page.getByTestId('teacher-create-code').fill(createdCode);
    await page.getByTestId('teacher-create-name').fill(createdName);
    await page.getByTestId('teacher-create-phone').fill('010-1234-5678');
    await page.getByTestId('teacher-create-email').fill(`${createdCode.toLowerCase()}@test.local`);
    await page.getByTestId('teacher-create-submit').click();

    await expect(page.getByTestId(`teacher-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId(`teacher-status-${createdCode}`)).toHaveText('활성');
  });

  test('persists created teacher after reload', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');
    await expect(page.getByTestId(`teacher-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });

    await page.reload();
    await expect(page.getByTestId(`teacher-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });
  });

  test('edits teacher details and persists after reload', async ({ page }) => {
    const updatedName = `${createdName} Updated`;

    await loginAsOwner(page);
    await page.goto('/teachers');
    await expect(page.getByTestId(`teacher-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });

    await page.getByTestId(`teacher-edit-${createdCode}`).click();
    await page.getByTestId(`teacher-edit-name-${createdCode}`).fill(updatedName);
    await page.getByTestId(`teacher-edit-phone-${createdCode}`).fill('010-9999-0000');
    await page.getByTestId(`teacher-save-${createdCode}`).click();

    await expect(page.getByText(updatedName)).toBeVisible({ timeout: 10_000 });

    await page.reload();
    await expect(page.getByText(updatedName)).toBeVisible({ timeout: 10_000 });
  });

  test('deactivates an unassigned teacher', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');
    await expect(page.getByTestId(`teacher-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });

    page.once('dialog', (dialog) => dialog.accept());
    await page.getByTestId(`teacher-status-reason-${createdCode}`).fill('E2E deactivate unassigned teacher');
    await page.getByTestId(`teacher-deactivate-${createdCode}`).click();

    await expect(page.getByTestId(`teacher-status-${createdCode}`)).toHaveText('비활성', {
      timeout: 10_000,
    });

    await page.reload();
    await expect(page.getByTestId(`teacher-status-${createdCode}`)).toHaveText('비활성');
  });

  test('reactivates a teacher', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');
    await expect(page.getByTestId(`teacher-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });

    await page.getByTestId(`teacher-status-reason-${createdCode}`).fill('E2E reactivate teacher');
    await page.getByTestId(`teacher-reactivate-${createdCode}`).click();

    await expect(page.getByTestId(`teacher-status-${createdCode}`)).toHaveText('활성', {
      timeout: 10_000,
    });
  });

  test('shows blocked deactivation error for assigned teacher', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');

    const assignedRow = page.getByTestId(`teacher-item-${assignedTeacherCode}`);
    await expect(assignedRow).toBeVisible();

    page.once('dialog', (dialog) => dialog.accept());
    await assignedRow.getByTestId(`teacher-status-reason-${assignedTeacherCode}`).fill('E2E blocked deactivate');
    await assignedRow.getByTestId(`teacher-deactivate-${assignedTeacherCode}`).click();

    await expect(assignedRow.getByTestId(`teacher-error-${assignedTeacherCode}`)).toContainText('배정', {
      timeout: 10_000,
    });
    await expect(assignedRow.getByTestId(`teacher-status-${assignedTeacherCode}`)).toHaveText('활성');
  });

  test('does not expose delete actions', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');

    await expect(page.getByRole('button', { name: /삭제/ })).toHaveCount(0);
  });

  test('mobile layout remains usable without horizontal overflow', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/teachers');

    await expect(page.getByTestId('teachers-panel')).toBeVisible();
    await expect(page.getByTestId('teacher-create-section')).toBeVisible();

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    expect(overflow).toBe(false);
  });

  test('existing owner pages still open from teachers page', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');
    await expect(page.getByRole('heading', { name: '강사', exact: true })).toBeVisible();

    await page.getByRole('link', { name: '학생' }).click();
    await expect(page).toHaveURL(/\/students/, { timeout: 15_000 });
    await expect(page.getByRole('heading', { name: '학생', exact: true })).toBeVisible();
  });
});

test.describe('Owner teacher empty state fixture', () => {
  test.beforeAll(() => {
    seedOwnerOnlyAlphaFixture();
  });

  test.afterAll(() => {
    seedOwnerAlphaFixture();
  });

  test('renders empty state when no teachers exist', async ({ page }) => {
    const consoleErrors: string[] = [];
    const pageErrors: string[] = [];
    const failedRequests: string[] = [];

    page.on('console', (message) => {
      if (message.type() === 'error') {
        consoleErrors.push(message.text());
      }
    });
    page.on('pageerror', (error) => {
      pageErrors.push(error.message);
    });
    page.on('response', (response) => {
      const url = response.url();
      if (response.status() >= 400 && !url.includes('favicon')) {
        failedRequests.push(`${response.status()} ${url}`);
      }
    });

    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/teachers');

    await expect(page.getByRole('heading', { name: '강사', exact: true })).toBeVisible();
    await expect(page.getByTestId('teachers-panel')).toBeVisible();
    await expect(page.getByTestId('teachers-empty')).toContainText('등록된 강사가 없습니다');
    await expect(page.locator('[data-testid^="teacher-item-"]')).toHaveCount(0);
    await expect(page.getByTestId('teacher-create-section')).toBeVisible();
    await expect(page.getByTestId('teacher-create-code')).toBeEnabled();
    await expect(page.getByTestId('teacher-create-submit')).toBeEnabled();

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    expect(overflow).toBe(false);

    expect(consoleErrors, consoleErrors.join('\n')).toEqual([]);
    expect(pageErrors, pageErrors.join('\n')).toEqual([]);
    expect(failedRequests, failedRequests.join('\n')).toEqual([]);
  });
});

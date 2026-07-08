import { test, expect } from '@playwright/test';

const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';
const submittedRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa301';
const approvedRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa302';

async function loginAsOwner(page: import('@playwright/test').Page) {
  await page.goto('/login');
  await page.getByLabel('이메일').fill(ownerEmail);
  await page.getByLabel('비밀번호').fill(ownerPassword);
  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 15_000 });
}

test.describe.configure({ mode: 'serial' });

test.describe('Owner schedule change requests', () => {
  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/schedule-requests');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders actionable requests and navigation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    await expect(page.getByRole('heading', { name: '일정 변경 요청' })).toBeVisible();
    await expect(page.getByRole('link', { name: '일정 변경 요청' })).toBeVisible();

    const panel = page.getByTestId('schedule-change-requests-panel');
    await expect(panel).toBeVisible();
    await expect(panel.getByText('Beta Student')).toBeVisible();
    await expect(panel.getByText('Delta Student')).toBeVisible();
    await expect(panel.getByText('Alpha seed rejected request')).toHaveCount(0);
    await expect(panel.getByText('Alpha seed already applied request')).toHaveCount(0);
  });

  test('requires approval note and approved time before enabling approve', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    const row = page.getByTestId(`schedule-request-item-${submittedRequestId}`);
    const approveButton = row.getByTestId(`approve-${submittedRequestId}`);
    await expect(approveButton).toBeDisabled();

    await row.getByTestId(`approval-note-${submittedRequestId}`).fill('Owner Playwright approval note');
    await expect(approveButton).toBeEnabled();
  });

  test('requires rejection reason before enabling reject', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    const row = page.getByTestId(`schedule-request-item-${submittedRequestId}`);
    const rejectButton = row.getByTestId(`reject-${submittedRequestId}`);
    await expect(rejectButton).toBeDisabled();

    await row.getByTestId(`rejection-reason-${submittedRequestId}`).fill('Owner Playwright rejection reason');
    await expect(rejectButton).toBeEnabled();
  });

  test('approves submitted request and applies pre-approved request with persistence', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    const panel = page.getByTestId('schedule-change-requests-panel');
    const submittedRow = panel.getByTestId(`schedule-request-item-${submittedRequestId}`);

    await submittedRow.getByTestId(`approval-note-${submittedRequestId}`).fill('Owner Playwright approval note');
    await submittedRow.getByTestId(`approve-${submittedRequestId}`).click();
    await expect(submittedRow.getByText('승인됨 (적용 전)')).toBeVisible({ timeout: 10_000 });

    page.once('dialog', (dialog) => dialog.accept());

    const approvedRow = panel.getByTestId(`schedule-request-item-${approvedRequestId}`);
    await approvedRow.getByTestId(`apply-${approvedRequestId}`).click();

    await expect(panel.getByTestId(`schedule-request-item-${approvedRequestId}`)).toHaveCount(0, {
      timeout: 10_000,
    });

    await page.reload();
    await expect(page.getByTestId('schedule-change-requests-panel').getByText('Delta Student')).toHaveCount(0);
    await expect(page.getByTestId(`schedule-request-item-${submittedRequestId}`)).toBeVisible();

    await page.goto('/schedule');
    await expect(page.getByRole('heading', { name: '주간 시간표' })).toBeVisible();
  });

  test('mobile layout remains usable', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    const panel = page.getByTestId('schedule-change-requests-panel');
    await expect(panel).toBeVisible();
    await expect(panel.getByRole('button', { name: /승인$|일정 변경 적용/ }).first()).toBeVisible();
    await expect(panel.getByText(/Beta Student|Delta Student/).first()).toBeVisible();
  });
});

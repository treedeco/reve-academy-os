import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';

const submittedRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa301';
const approvedRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa302';
const cascadePendingRequestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaa305';

test.describe.configure({ mode: 'serial' });

test.describe('Owner schedule change requests', () => {
  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/schedule-requests');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders review and cascade sections with navigation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    await expect(page.getByRole('heading', { name: '일정 변경 요청' })).toBeVisible();
    await expect(page.getByRole('link', { name: '일정 변경 요청' })).toBeVisible();

    const panel = page.getByTestId('schedule-change-requests-panel');
    await expect(panel).toBeVisible();
    await expect(page.getByTestId('schedule-review-section')).toBeVisible();
    await expect(page.getByTestId('schedule-cascade-pending-section')).toBeVisible();
    await expect(panel.getByTestId(`schedule-request-item-${submittedRequestId}`)).toBeVisible();
    await expect(panel.getByTestId(`schedule-request-item-${approvedRequestId}`)).toBeVisible();
    await expect(panel.getByTestId(`schedule-cascade-item-${cascadePendingRequestId}`)).toBeVisible();
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

  test('requires cascade reason before enabling cascade', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    const row = page.getByTestId(`schedule-cascade-item-${cascadePendingRequestId}`);
    const cascadeButton = row.getByTestId(`cascade-${cascadePendingRequestId}`);
    await expect(cascadeButton).toBeDisabled();

    await row.getByTestId(`cascade-reason-${cascadePendingRequestId}`).fill('Owner Playwright cascade reason');
    await expect(cascadeButton).toBeEnabled();
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
    await expect(panel.getByTestId(`schedule-cascade-item-${approvedRequestId}`)).toBeVisible({
      timeout: 10_000,
    });

    await page.reload();
    await expect(page.getByTestId(`schedule-cascade-item-${approvedRequestId}`)).toBeVisible();
    await expect(page.getByTestId(`schedule-request-item-${submittedRequestId}`)).toBeVisible();

    await page.goto('/schedule');
    await expect(page.getByRole('heading', { name: '주간 시간표' })).toBeVisible();
  });

  test('executes cascade for pending request', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    const row = page.getByTestId(`schedule-cascade-item-${cascadePendingRequestId}`);
    await row.getByTestId(`cascade-reason-${cascadePendingRequestId}`).fill('Owner Playwright cascade reason');

    page.once('dialog', (dialog) => dialog.accept());
    await row.getByTestId(`cascade-${cascadePendingRequestId}`).click();

    await expect(page.getByTestId(`schedule-cascade-item-${cascadePendingRequestId}`)).toHaveCount(0, {
      timeout: 10_000,
    });
  });

  test('mobile layout remains usable', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/schedule-requests');

    const panel = page.getByTestId('schedule-change-requests-panel');
    await expect(panel).toBeVisible();
    await expect(panel.getByRole('button', { name: /승인$|일정 변경 적용|연쇄 재배치 실행/ }).first()).toBeVisible();
    await expect(panel.getByText(/Beta Student|Delta Student/).first()).toBeVisible();
  });
});

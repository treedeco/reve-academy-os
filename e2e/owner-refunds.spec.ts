import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';

const epsilonPaymentId = '12121212-1212-1212-1212-121212121105';

test.describe.configure({ mode: 'serial' });

test.describe('Owner payment refund', () => {
  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/refunds');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders eligible refundable payments and navigation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/refunds');

    await expect(page.getByRole('heading', { name: '환불 처리' })).toBeVisible();
    await expect(page.getByRole('link', { name: '환불 처리' })).toBeVisible();

    const panel = page.getByTestId('refundable-payments-panel');
    await expect(panel).toBeVisible();
    await expect(panel.getByText('Delta Student')).toBeVisible();
    await expect(panel.getByText('Beta Student')).toBeVisible();
    await expect(panel.getByText('Epsilon Student')).toBeVisible();
    await expect(panel.getByText('Alpha Student')).toHaveCount(0);
    await expect(panel.getByText('Zeta Student')).toHaveCount(0);
  });

  test('requires reason before enabling refund confirmation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/refunds');

    const epsilonRow = page.getByTestId(`refund-item-${epsilonPaymentId}`);
    const confirmButton = epsilonRow.getByTestId(`refund-confirm-${epsilonPaymentId}`);
    await expect(confirmButton).toBeDisabled();

    await epsilonRow.getByTestId(`refund-reason-${epsilonPaymentId}`).fill('Owner Playwright refund test');
    await expect(confirmButton).toBeEnabled();
  });

  test('processes full refund with persisted result', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/refunds');

    page.once('dialog', (dialog) => dialog.accept());

    const panel = page.getByTestId('refundable-payments-panel');
    const epsilonRow = panel.getByTestId(`refund-item-${epsilonPaymentId}`);
    await epsilonRow.getByTestId(`refund-reason-${epsilonPaymentId}`).fill('Owner Playwright refund test');
    await epsilonRow.getByTestId(`refund-confirm-${epsilonPaymentId}`).click();

    await expect(panel.getByTestId(`refund-item-${epsilonPaymentId}`)).toHaveCount(0, {
      timeout: 10_000,
    });

    await page.reload();
    await expect(page.getByTestId('refundable-payments-panel').getByText('Epsilon Student')).toHaveCount(0);
    await expect(page.getByTestId('refundable-payments-panel').getByText('Delta Student')).toBeVisible();
  });

  test('mobile layout remains usable', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/refunds');

    const panel = page.getByTestId('refundable-payments-panel');
    await expect(panel).toBeVisible();
    await expect(panel.getByLabel('환불 사유').first()).toBeVisible();
    await expect(panel.getByRole('button', { name: /전액 환불/ }).first()).toBeVisible();
  });
});

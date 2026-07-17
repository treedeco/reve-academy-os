import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';

const deltaStudentId = '44444444-4444-4444-4444-444444444104';
const gammaStudentId = '44444444-4444-4444-4444-444444444103';
const zetaStudentId = '44444444-4444-4444-4444-444444444106';

test.describe.configure({ mode: 'serial' });

test.describe('Owner student operational history', () => {
  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto(`/students/${deltaStudentId}`);
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders operational history sections for a student with history', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${deltaStudentId}`);

    await expect(page.getByRole('heading', { name: 'Delta Student' })).toBeVisible();
    await expect(page.getByRole('heading', { name: '현재 회차권' })).toBeVisible();
    await expect(page.getByRole('heading', { name: '고정 일정' })).toBeVisible();
    await expect(page.getByRole('heading', { name: '수업 이력' })).toBeVisible();

    const historyPanel = page.getByTestId('student-operational-history');
    await expect(historyPanel).toBeVisible();

    const paymentSection = page.getByTestId('payment-history-section');
    await expect(paymentSection).toBeVisible();
    await expect(paymentSection.getByTestId('payment-history-row')).toHaveCount(1);
    await expect(paymentSection.getByText('V-S1D1-001')).toBeVisible();

    const refundSection = page.getByTestId('refund-history-section');
    await expect(refundSection).toBeVisible();
    await expect(refundSection.getByTestId('refund-history-empty')).toBeVisible();

    const scheduleSection = page.getByTestId('schedule-request-history-section');
    await expect(scheduleSection).toBeVisible();
    await expect(scheduleSection.getByTestId('schedule-request-history-row').count()).resolves.toBeGreaterThan(
      0,
    );
    await expect(scheduleSection.getByText('Alpha seed Delta pre-approved request')).toBeVisible();

    await expect(historyPanel.getByRole('button')).toHaveCount(0);
  });

  test('renders refund history for a refunded student', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${zetaStudentId}`);

    const refundSection = page.getByTestId('refund-history-section');
    await expect(refundSection.getByTestId('refund-history-row')).toHaveCount(1);
    await expect(refundSection.getByText('Alpha seed already refunded payment')).toBeVisible();
  });

  test('renders empty operational history sections when no history exists', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${gammaStudentId}`);

    await expect(page.getByTestId('payment-history-empty')).toBeVisible();
    await expect(page.getByTestId('refund-history-empty')).toBeVisible();
    await expect(page.getByTestId('schedule-request-history-empty')).toBeVisible();
  });

  test('mobile layout remains usable', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: /Delta Student/ }).click();

    await expect(page.getByTestId('student-operational-history')).toBeVisible();
    await expect(page.getByTestId('payment-history-section')).toBeVisible();
    await expect(page.getByTestId('refund-history-section')).toBeVisible();
    await expect(page.getByTestId('schedule-request-history-section')).toBeVisible();
  });
});

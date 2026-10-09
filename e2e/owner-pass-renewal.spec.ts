import { test, expect } from '@playwright/test';
import { applySqlFixture } from './helpers/apply-sql-fixture';
import { loginAsOwner } from './helpers/login-as-owner';
import { loginAsTeacher } from './helpers/login-as-teacher';

const renewalStudentId = '44444444-4444-4444-4444-444444444201';

test.describe.configure({ mode: 'serial' });

test.describe('Owner pass renewal', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-owner-pass-renewal.sql');
  });

  test('Owner renews completed vocal pass V-S1RN1-001 → V-S1RN1-002 without full reload', async ({
    page,
  }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${renewalStudentId}`);

    await expect(page.getByRole('heading', { name: 'Renewal E2E Student' })).toBeVisible();
    await expect(page.getByTestId('student-no-current-pass')).toBeVisible();
    await expect(page.getByTestId('pass-renewal-section')).toBeVisible();
    await expect(page.getByTestId('renewable-pass-V-S1RN1-001')).toBeVisible();

    // Vocal remains a renewal path, not Add Course.
    const enrollmentCourse = page.getByTestId('enrollment-course');
    if (await enrollmentCourse.count()) {
      await expect(enrollmentCourse).not.toContainText('Alpha Vocal Course');
    }

    await page.getByTestId('pass-renewal-open-V-S1RN1-001').click();
    await expect(page.getByTestId('pass-renewal-panel')).toBeVisible();
    await expect(page.getByTestId('pass-renewal-previous-pass')).toHaveText('V-S1RN1-001');
    await expect(page.getByTestId('pass-renewal-catalog-loading')).toHaveCount(0, {
      timeout: 15_000,
    });

    await page.getByTestId('pass-renewal-product').selectOption({
      label: 'Alpha 4 Lessons · 4회 · 주 1회 · 200,000원',
    });
    await page.getByTestId('pass-renewal-payment-method').selectOption('cash');
    await page.getByTestId('pass-renewal-submit').click();

    await expect(page.getByTestId('pass-renewal-success')).toContainText('V-S1RN1-002', {
      timeout: 20_000,
    });
    await expect(page.getByTestId('student-no-current-pass')).toHaveCount(0);
    await expect(page.getByTestId('used-count')).toHaveText('0');
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
    await expect(page.getByTestId('current-pass-code')).toHaveText('V-S1RN1-002');
    // Historical -001 lessons remain visible with the new -002 lesson rows.
    await expect(page.getByTestId('student-lessons-table').locator('tbody tr')).toHaveCount(8, {
      timeout: 10_000,
    });
    await expect(page.getByTestId('previous-pass-V-S1RN1-001')).toBeVisible();
    await expect(page.getByTestId('payment-history-row').filter({ hasText: 'V-S1RN1-002' })).toBeVisible();
    await expect(page.getByTestId('renewable-pass-V-S1RN1-001')).toHaveCount(0);
    await expect(page.getByTestId('renewable-pass-V-S1RN1-002')).toBeVisible();
  });

  test('idempotent resubmission does not create duplicate pass', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${renewalStudentId}`);
    await page.getByTestId('pass-renewal-open-V-S1RN1-001').click();
    await expect(page.getByTestId('pass-renewal-catalog-loading')).toHaveCount(0, {
      timeout: 15_000,
    });
    await page.getByTestId('pass-renewal-product').selectOption({
      label: 'Alpha 4 Lessons · 4회 · 주 1회 · 200,000원',
    });

    await page.getByTestId('pass-renewal-submit').click();
    await expect(page.getByTestId('pass-renewal-success')).toContainText('V-S1RN1-002', {
      timeout: 20_000,
    });

    await expect(page.getByTestId('previous-pass-V-S1RN1-001')).toBeVisible();
    await expect(page.getByTestId('current-pass-code')).toHaveText('V-S1RN1-002');
    await expect(page.getByTestId('used-count')).toHaveCount(1);
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
    await expect(page.getByTestId('payment-history-row').filter({ hasText: 'V-S1RN1-002' })).toHaveCount(1);
  });

  test('Teacher cannot open Owner renewal UI', async ({ page }) => {
    await loginAsTeacher(page);
    await page.goto(`/students/${renewalStudentId}`);
    await expect(page).not.toHaveURL(new RegExp(`/students/${renewalStudentId}`));
    await expect(page.getByTestId('pass-renewal-section')).toHaveCount(0);
  });
});

import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
test.describe.configure({ mode: 'serial' });

test.describe('Owner student master and initial enrollment', () => {
  const suffix = Date.now().toString().slice(-6);
  const studentCode4 = `S-E4${suffix}`;
  const studentName4 = `E2E Vocal Student ${suffix}`;
  const studentCode8 = `S-E8${suffix}`;
  const studentName8 = `E2E Piano Student ${suffix}`;
  const scheduleStartDate = '2026-08-10';
  const enrollTeacherCode = `T-ENR${suffix}`;
  const enrollTeacherName = `Enrollment Teacher ${suffix}`;
  const enrollTeacherBCode = `T-EN2${suffix}`;
  const enrollTeacherBName = `Enrollment Teacher B ${suffix}`;

  async function createEnrollmentTeacher(page: import('@playwright/test').Page, code: string, name: string) {
    await page.goto('/teachers');
    await page.getByTestId('teacher-create-code').fill(code);
    await page.getByTestId('teacher-create-name').fill(name);
    await page.getByTestId('teacher-create-submit').click();
    await expect(page.getByTestId(`teacher-item-${code}`)).toBeVisible({ timeout: 10_000 });
  }

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/students');
    await expect(page).toHaveURL(/\/login/);
  });

  test('creates a student from the students page', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');

    await expect(page.getByTestId('student-create-section')).toBeVisible();
    await page.getByTestId('student-create-code').fill(studentCode4);
    await page.getByTestId('student-create-name').fill(studentName4);
    await page.getByTestId('student-create-phone').fill('010-2000-3000');
    await page.getByTestId('student-create-submit').click();

    await expect(page).toHaveURL(new RegExp(`/students/[0-9a-f-]+$`), { timeout: 15_000 });
    await expect(page.getByTestId('student-detail-client')).toBeVisible();
    await expect(page.getByTestId('student-display-name')).toHaveText(studentName4);
  });

  test('persists created student after reload', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: studentName4 }).click();
    await expect(page.getByTestId('student-display-name')).toHaveText(studentName4);

    await page.reload();
    await expect(page.getByTestId('student-display-name')).toHaveText(studentName4);
  });

  test('edits student details and persists after reload', async ({ page }) => {
    const updatedName = `${studentName4} Updated`;

    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: studentName4 }).click();

    await page.getByTestId('student-edit-open').click();
    await page.getByTestId('student-edit-name').fill(updatedName);
    await page.getByTestId('student-edit-save').click();

    await expect(page.getByTestId('student-display-name')).toHaveText(updatedName, { timeout: 10_000 });
    await page.reload();
    await expect(page.getByTestId('student-display-name')).toHaveText(updatedName);
  });

  test('creates a four-lesson weekly initial enrollment', async ({ page }) => {
    await loginAsOwner(page);
    await createEnrollmentTeacher(page, enrollTeacherCode, enrollTeacherName);
    await page.goto('/students');
    await page.getByRole('link', { name: `${studentName4} Updated` }).click();

    await expect(page.getByTestId('initial-enrollment-panel')).toBeVisible();
    await page.getByTestId('enrollment-course').selectOption({ label: 'Alpha Vocal Course (VOC-A1)' });
    await page.getByTestId('enrollment-product').selectOption({ label: 'Alpha 4 Lessons · 4회 · 주 1회 · 200,000원' });
    await page.getByTestId('enrollment-start-date').fill(scheduleStartDate);
    await page.getByTestId('enrollment-slot-teacher-1').selectOption({
      label: `${enrollTeacherName} (${enrollTeacherCode})`,
    });
    await page.getByTestId('enrollment-slot-weekday-1').selectOption('6');
    await page.getByTestId('enrollment-slot-time-1').fill('16:00');
    await page.getByTestId('enrollment-submit').click();

    await expect(page.getByTestId('used-count')).toHaveText('0', { timeout: 15_000 });
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
    await expect(page.getByTestId('student-lessons-table').locator('tbody tr')).toHaveCount(4);
    await expect(page.getByTestId('student-schedule-slots').locator('li')).toHaveCount(1);
    await expect(page.getByTestId('initial-enrollment-panel')).toHaveCount(0);
  });

  test('persists four-lesson enrollment after reload', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: `${studentName4} Updated` }).click();

    await expect(page.getByTestId('used-count')).toHaveText('0');
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
    await expect(page.getByTestId('student-lessons-table').locator('tbody tr')).toHaveCount(4);

    await page.reload();
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
    await expect(page.getByTestId('student-lessons-table').locator('tbody tr')).toHaveCount(4);
  });

  test('deactivates and reactivates an enrolled student without a linked profile', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: `${studentName4} Updated` }).click();

    page.once('dialog', (dialog) => dialog.accept());
    await page.getByTestId('student-status-reason').fill('E2E deactivate enrolled student');
    await page.getByTestId('student-deactivate').click();
    await expect(page.getByTestId('student-status-badge')).toHaveText('비활성', { timeout: 10_000 });

    await page.getByTestId('student-status-reason').fill('E2E reactivate enrolled student');
    await page.getByTestId('student-reactivate').click();
    await expect(page.getByTestId('student-status-badge')).toHaveText('활성', { timeout: 10_000 });
  });

  test('creates an eight-lesson twice-weekly initial enrollment', async ({ page }) => {
    await loginAsOwner(page);
    await createEnrollmentTeacher(page, enrollTeacherBCode, enrollTeacherBName);
    await page.goto('/students');

    await page.getByTestId('student-create-code').fill(studentCode8);
    await page.getByTestId('student-create-name').fill(studentName8);
    await page.getByTestId('student-create-submit').click();
    await expect(page).toHaveURL(new RegExp(`/students/[0-9a-f-]+$`), { timeout: 15_000 });

    await page.getByTestId('enrollment-course').selectOption({ label: 'Alpha Piano Course (PIA-A1)' });
    await page.getByTestId('enrollment-product').selectOption({ label: 'Alpha 8 Lessons · 8회 · 주 2회 · 400,000원' });
    await page.getByTestId('enrollment-start-date').fill(scheduleStartDate);
    await page.getByTestId('enrollment-slot-teacher-1').selectOption({
      label: `${enrollTeacherName} (${enrollTeacherCode})`,
    });
    await page.getByTestId('enrollment-slot-weekday-1').selectOption('6');
    await page.getByTestId('enrollment-slot-time-1').fill('09:00');
    await page.getByTestId('enrollment-slot-teacher-2').selectOption({
      label: `${enrollTeacherBName} (${enrollTeacherBCode})`,
    });
    await page.getByTestId('enrollment-slot-weekday-2').selectOption('0');
    await page.getByTestId('enrollment-slot-time-2').fill('11:00');
    await page.getByTestId('enrollment-submit').click();

    await expect(page.getByTestId('used-count')).toHaveText('0', { timeout: 15_000 });
    await expect(page.getByTestId('remaining-count')).toHaveText('8');
    await expect(page.getByTestId('student-lessons-table').locator('tbody tr')).toHaveCount(8);
    await expect(page.getByTestId('student-schedule-slots').locator('li')).toHaveCount(2);
  });

  test('shows validation failure without partial enrollment records', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');

    const invalidCode = `S-VAL${Date.now().toString().slice(-6)}`;
    await page.getByTestId('student-create-code').fill(invalidCode);
    await page.getByTestId('student-create-name').fill(`Validation Student ${invalidCode}`);
    await page.getByTestId('student-create-submit').click();
    await expect(page).toHaveURL(new RegExp(`/students/[0-9a-f-]+$`), { timeout: 15_000 });

    await page.getByTestId('enrollment-course').selectOption({ label: 'Alpha Vocal Course (VOC-A1)' });
    await page.getByTestId('enrollment-product').selectOption({ label: 'Alpha 4 Lessons · 4회 · 주 1회 · 200,000원' });
    await page.getByTestId('enrollment-start-date').fill(scheduleStartDate);
    await page.getByTestId('enrollment-slot-teacher-1').selectOption('');
    await page.getByTestId('enrollment-submit').click();

    await expect(page.getByTestId('enrollment-error')).toContainText('강사', { timeout: 10_000 });
    await expect(page.getByTestId('student-no-current-pass')).toBeVisible();
    await expect(page.getByTestId('student-no-lessons')).toBeVisible();
  });

  test('does not expose delete actions', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await expect(page.getByRole('button', { name: /삭제/ })).toHaveCount(0);
  });

  test('mobile layout remains usable without horizontal overflow', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/students');

    await expect(page.getByTestId('student-create-section')).toBeVisible();
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    expect(overflow).toBe(false);
  });

  test('existing owner pages still open from students page', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await expect(page.getByRole('heading', { name: '학생', exact: true })).toBeVisible();

    await page.getByRole('link', { name: '강사' }).click();
    await expect(page).toHaveURL(/\/teachers/, { timeout: 15_000 });
    await expect(page.getByRole('heading', { name: '강사', exact: true })).toBeVisible();
  });

  test('has no blocking console or network errors on student detail', async ({ page }) => {
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

    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: `${studentName4} Updated` }).click();
    await expect(page.getByTestId('student-detail-client')).toBeVisible();

    expect(consoleErrors, consoleErrors.join('\n')).toEqual([]);
    expect(pageErrors, pageErrors.join('\n')).toEqual([]);
    expect(failedRequests, failedRequests.join('\n')).toEqual([]);
  });
});

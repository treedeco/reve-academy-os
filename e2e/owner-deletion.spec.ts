import { test, expect, type Page } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';

test.describe.configure({ mode: 'serial' });

test.describe('Owner permanent deletion and fixed-schedule removal', () => {
  const suffix = Date.now().toString().slice(-6);
  const scheduleStudentName = `E2E ScheduleDel Student ${suffix}`;
  const deleteStudentName = `E2E PermDel Student ${suffix}`;
  const enrollTeacherCode = `T-SDEL${suffix}`;
  const enrollTeacherName = `Schedule Delete Teacher ${suffix}`;
  const targetTeacherCode = `T-TDEL${suffix}`;
  const targetTeacherName = `Target Delete Teacher ${suffix}`;
  const replacementTeacherCode = `T-TREP${suffix}`;
  const replacementTeacherName = `Replacement Teacher ${suffix}`;
  const scheduleStartDate = '2026-08-17';

  async function createTeacher(page: Page, code: string, name: string) {
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

  test('creates supporting teacher fixtures', async ({ page }) => {
    await loginAsOwner(page);
    await createTeacher(page, enrollTeacherCode, enrollTeacherName);
    await createTeacher(page, targetTeacherCode, targetTeacherName);
    await createTeacher(page, replacementTeacherCode, replacementTeacherName);
  });

  test('removes a fixed pass schedule while preserving lesson and usage history', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByTestId('student-create-name').fill(scheduleStudentName);
    await page.getByTestId('student-create-phone').fill('010-3000-4000');
    await page.getByTestId('student-create-submit').click();
    await expect(page).toHaveURL(/\/students\/[0-9a-f-]+$/, { timeout: 15_000 });

    await expect(page.getByTestId('initial-enrollment-panel')).toBeVisible();
    await expect(page.getByTestId('enrollment-course-loading')).toHaveCount(0, { timeout: 15_000 });
    await page.getByTestId('enrollment-course').selectOption({ label: 'Alpha Vocal Course (VOC-A1)' });
    await page.getByTestId('enrollment-product').selectOption({
      label: 'Alpha 4 Lessons · 4회 · 주 1회 · 200,000원',
    });
    await page.getByTestId('enrollment-start-date').fill(scheduleStartDate);
    await page.getByTestId('enrollment-slot-teacher-1').selectOption({
      label: `${enrollTeacherName} (${enrollTeacherCode})`,
    });
    await page.getByTestId('enrollment-slot-weekday-1').selectOption('2');
    await page.getByTestId('enrollment-slot-time-1').fill('15:00');
    await page.getByTestId('enrollment-submit').click();

    await expect(page.getByTestId('used-count')).toHaveText('0', { timeout: 15_000 });
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
    await expect(page.getByTestId('student-schedule-slots').locator('li')).toHaveCount(1);

    // Fixed pass-schedule removal: preview auto-loads on open, then confirm and submit.
    await expect(page.getByTestId('remove-fixed-schedule-panel')).toBeVisible();
    await page.getByTestId('remove-fixed-schedule-open').click();

    const dialog = page.getByTestId('danger-zone-dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.getByTestId('danger-removed-items')).toBeVisible({ timeout: 15_000 });

    await page.getByTestId('danger-reason').fill('E2E fixed schedule removal');
    await page.getByTestId('danger-confirmed').check();
    await expect(page.getByTestId('danger-submit')).toBeEnabled({ timeout: 15_000 });
    await page.getByTestId('danger-submit').click();

    await expect(page.getByTestId('danger-success')).toBeVisible({ timeout: 15_000 });
    await page.getByTestId('danger-cancel').click();
    await expect(dialog).toHaveCount(0);

    // Schedule slots are gone, but usage counts and lesson history are untouched.
    await expect(page.getByTestId('student-no-schedule')).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId('used-count')).toHaveText('0');
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
    await expect(page.getByTestId('student-lessons-table').locator('tbody tr')).toHaveCount(4);

    await page.reload();
    await expect(page.getByTestId('student-no-schedule')).toBeVisible();
    await expect(page.getByTestId('used-count')).toHaveText('0');
    await expect(page.getByTestId('remaining-count')).toHaveText('4');
  });

  test('permanently deletes a student and removes it from the student list', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByTestId('student-create-name').fill(deleteStudentName);
    await page.getByTestId('student-create-submit').click();
    await expect(page).toHaveURL(/\/students\/[0-9a-f-]+$/, { timeout: 15_000 });

    await expect(page.getByTestId('student-permanent-delete-section')).toBeVisible();
    await page.getByTestId('student-permanent-delete-open').click();

    const dialog = page.getByTestId('danger-zone-dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.getByTestId('danger-removed-items')).toBeVisible({ timeout: 15_000 });

    await page.getByTestId('danger-reason').fill('E2E permanent student deletion');
    await page.getByTestId('danger-confirmed').check();
    await expect(page.getByTestId('danger-submit')).toBeEnabled({ timeout: 15_000 });
    await page.getByTestId('danger-submit').click();

    // Success redirects the owner back to the student list.
    await expect(page).toHaveURL(/\/students$/, { timeout: 15_000 });
    await expect(page.getByRole('link', { name: deleteStudentName })).toHaveCount(0);
  });

  test('permanently deletes a teacher with reassignment to a replacement teacher', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/teachers');

    const targetRow = page.getByTestId(`teacher-item-${targetTeacherCode}`);
    await expect(targetRow).toBeVisible();
    await targetRow.getByRole('button', { name: '강사 영구 삭제' }).click();

    const dialog = page.getByTestId('danger-zone-dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.getByTestId('teacher-replacement-select')).toBeVisible({ timeout: 15_000 });

    await dialog.getByTestId('teacher-replacement-select').selectOption({
      label: `${replacementTeacherName} (${replacementTeacherCode})`,
    });

    await page.getByTestId('danger-reason').fill('E2E permanent teacher deletion (reassign)');
    await page.getByTestId('danger-confirmed').check();
    await expect(page.getByTestId('danger-submit')).toBeEnabled({ timeout: 15_000 });
    await page.getByTestId('danger-submit').click();

    await expect(targetRow).toHaveCount(0, { timeout: 15_000 });

    await page.reload();
    await expect(page.getByTestId(`teacher-item-${targetTeacherCode}`)).toHaveCount(0);
    await expect(page.getByTestId(`teacher-item-${replacementTeacherCode}`)).toBeVisible();
  });
});

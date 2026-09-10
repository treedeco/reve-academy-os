import { test, expect } from '@playwright/test';
import { loginAsOwner } from './helpers/login-as-owner';
import { applySqlFixture } from './helpers/apply-sql-fixture';

const STUDENT_ID = '44444444-4444-4444-4444-444444444801';
const TEACHER_ID = '22222222-2222-2222-2222-222222222101';

test.describe('Owner fixed-schedule re-register with conflict override', () => {
  test.beforeEach(() => {
    applySqlFixture('fixture-fixed-schedule-reregister.sql');
  });

  test('shows create CTA, warns on conflict, then saves with override', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto(`/students/${STUDENT_ID}`);

    await expect(page.getByTestId('student-no-schedule')).toBeVisible();
    await expect(page.getByTestId('student-fixed-schedule-create-open-section')).toBeVisible();

    await page.getByTestId('student-fixed-schedule-create-open-section').click();
    await expect(page.getByTestId('owner-schedule-change-dialog')).toBeVisible();
    await expect(
      page.getByTestId('owner-schedule-change-dialog').getByRole('heading', { name: '새 고정 일정 등록' }),
    ).toBeVisible();

    await page.getByTestId('schedule-slot-weekday-0').selectOption('2');
    await page.getByTestId('schedule-slot-time-0').selectOption('19:00');
    await page.getByTestId('schedule-slot-teacher-0').selectOption(TEACHER_ID);
    await page.getByTestId('schedule-change-reason').fill('E2E 고정 일정 재등록');
    await page.getByTestId('schedule-change-next').click();
    await page.getByTestId('schedule-change-save').click();

    await expect(page.getByTestId('schedule-conflict-warning')).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId('schedule-conflict-warning')).toContainText(
      '같은 시간에 다른 수업이 있습니다.',
    );

    await page.getByTestId('schedule-conflict-override').click();
    await expect(page.getByTestId('owner-schedule-change-dialog')).toHaveCount(0, {
      timeout: 15_000,
    });

    await page.reload();
    await expect(page.getByTestId('student-schedule-slots')).toBeVisible();
    await expect(page.getByTestId('student-schedule-slots')).toContainText('화');
    await expect(page.getByTestId('student-schedule-slots')).toContainText('19:00');
    await expect(page.getByTestId('student-lesson-1')).not.toContainText('일정 미정');
  });
});

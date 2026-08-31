import type { Page } from '@playwright/test';
import { expect } from '@playwright/test';

export async function loginAsTeacher(page: Page): Promise<void> {
  await page.goto('/login');
  await page.getByLabel('사용자 이름').fill('teacher-alpha@test.local');
  await page.getByLabel('비밀번호').fill('TeacherAlpha123!');
  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL(/\/teacher\/lessons\/today/, { timeout: 20_000 });
}

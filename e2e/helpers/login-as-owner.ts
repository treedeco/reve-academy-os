import type { Page } from '@playwright/test';
import { expect } from '@playwright/test';
import { getOwnerPasswordFromEnv } from '@/lib/auth/owner-credentials';
import { OWNER_LOGIN_USERNAME } from '@/lib/auth/owner-login';

export async function loginAsOwner(page: Page): Promise<void> {
  await page.goto('/login');

  const usernameField = page.getByLabel('사용자 이름');
  const passwordField = page.getByLabel('비밀번호');

  await expect(usernameField).toBeVisible();
  await usernameField.fill(OWNER_LOGIN_USERNAME);
  await expect(usernameField).toHaveValue(OWNER_LOGIN_USERNAME);
  await passwordField.fill(getOwnerPasswordFromEnv());
  await expect(passwordField).not.toHaveValue('');

  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 20_000 });
}

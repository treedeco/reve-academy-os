import type { Page } from '@playwright/test';
import { expect } from '@playwright/test';

const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';

export async function loginAsOwner(page: Page): Promise<void> {
  await page.goto('/login');

  const emailField = page.getByLabel('이메일');
  const passwordField = page.getByLabel('비밀번호');

  await expect(emailField).toBeVisible();
  await emailField.fill(ownerEmail);
  await expect(emailField).toHaveValue(ownerEmail);
  await passwordField.fill(ownerPassword);
  await expect(passwordField).toHaveValue(ownerPassword);

  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 20_000 });
}

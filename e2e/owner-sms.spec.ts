import { test, expect } from '@playwright/test';
import { seedOwnerAlphaFixture } from './helpers/apply-sql-fixture';

const ownerEmail = process.env.E2E_OWNER_EMAIL ?? 'owner-alpha@test.local';
const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? 'OwnerAlphaTest123!';
const betaSmsId = '88888888-8888-8888-8888-888888888102';
const betaMessage = '[Beta] Alpha 4 Lessons 수강권 갱신 안내 SMS';

async function loginAsOwner(page: import('@playwright/test').Page) {
  await page.goto('/login');
  await page.getByLabel('이메일').fill(ownerEmail);
  await page.getByLabel('비밀번호').fill(ownerPassword);
  await page.getByRole('button', { name: '로그인' }).click();
  await expect(page).toHaveURL(/\/dashboard/, { timeout: 15_000 });
}

test.describe.configure({ mode: 'serial' });

test.describe('Owner SMS sent confirmation', () => {
  test.beforeAll(() => {
    seedOwnerAlphaFixture();
  });

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/sms');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders eligible SMS notifications and navigation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/sms');

    await expect(page.getByRole('heading', { name: 'SMS 발송 확인' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'SMS 발송 확인' })).toBeVisible();

    const panel = page.getByTestId('sms-notifications-panel');
    await expect(panel).toBeVisible();
    await expect(panel.getByText('Beta Student')).toBeVisible();
    await expect(panel.getByText('Gamma Student')).toBeVisible();
    await expect(panel.getByText('Alpha Student')).toHaveCount(0);
    await expect(panel.getByText(betaMessage)).toBeVisible();
  });

  test('supports copy and confirm sent with persisted update', async ({ page, context }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await loginAsOwner(page);
    await page.goto('/sms');

    const panel = page.getByTestId('sms-notifications-panel');
    const betaRow = panel.getByTestId(`sms-item-${betaSmsId}`);
    await expect(betaRow).toBeVisible();

    await betaRow.getByTestId(`sms-copy-${betaSmsId}`).click();
    await expect(betaRow.getByTestId(`sms-copy-${betaSmsId}`)).toHaveText('복사됨');

    await betaRow.getByTestId(`sms-confirm-${betaSmsId}`).click();
    await expect(panel.getByTestId(`sms-item-${betaSmsId}`)).toHaveCount(0, { timeout: 10_000 });

    await page.reload();
    await expect(page.getByTestId('sms-notifications-panel').getByText('Beta Student')).toHaveCount(0);
    await expect(page.getByTestId('sms-notifications-panel').getByText('Gamma Student')).toBeVisible();
  });

  test('mobile layout remains usable', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/sms');

    const panel = page.getByTestId('sms-notifications-panel');
    await expect(panel).toBeVisible();
    await expect(panel.getByRole('button', { name: '메시지 복사' }).first()).toBeVisible();
    await expect(panel.getByRole('button', { name: '발송 확인' }).first()).toBeVisible();
  });
});

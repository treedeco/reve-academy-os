import { test, expect } from '@playwright/test';
import {
  seedOwnerAlphaFixture,
  seedOwnerProductsEmptyFixture,
} from './helpers/apply-sql-fixture';
import { loginAsOwner } from './helpers/login-as-owner';

test.describe.configure({ mode: 'serial' });

test.describe('Owner course products empty state fixture', () => {
  test.beforeAll(() => {
    seedOwnerProductsEmptyFixture();
  });

  test.afterAll(() => {
    seedOwnerAlphaFixture();
  });

  test('renders empty state when no course products exist', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/course-products');

    await expect(page.getByRole('heading', { name: '수강 상품', exact: true })).toBeVisible();
    await expect(page.getByTestId('course-products-panel')).toBeVisible();
    await expect(page.getByTestId('course-products-empty')).toContainText('등록된 수강 상품이 없습니다');
    await expect(page.getByTestId('product-create-section')).toBeVisible();
  });
});

test.describe('Owner course product management', () => {
  test.beforeAll(() => {
    seedOwnerAlphaFixture();
  });

  const createdCode = `V-E2E${Date.now().toString().slice(-6)}`;
  const createdName = `E2E Vocal Product ${createdCode}`;

  test('redirects unauthenticated users to login', async ({ page }) => {
    await page.goto('/course-products');
    await expect(page).toHaveURL(/\/login/);
  });

  test('renders product list and navigation entry', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/course-products');

    await expect(page.getByRole('heading', { name: '수강 상품', exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: '수강 상품' })).toBeVisible();
    await expect(page.getByTestId('course-products-panel')).toBeVisible();
    await expect(page.getByTestId('product-item-VOC-4-A1')).toBeVisible();
  });

  test('creates a course product without full-page reload', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/course-products');

    const courseSelect = page.getByTestId('product-create-course');
    const courseLabels = await courseSelect.locator('option').allTextContents();
    const vocalIndex = courseLabels.findIndex((label) => /보컬|Vocal|\(V\)/.test(label));
    expect(vocalIndex).toBeGreaterThan(0);
    await courseSelect.selectOption({ index: vocalIndex });
    await page.getByTestId('product-create-code').fill(createdCode);
    await page.getByTestId('product-create-name').fill(createdName);
    await page.getByTestId('product-create-lesson-count').fill('4');
    await page.getByTestId('product-create-weekly-frequency').fill('1');
    await page.getByTestId('product-create-tuition').fill('250000');
    await page.getByTestId('product-create-submit').click();

    await expect(page.getByTestId(`product-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId(`product-status-${createdCode}`)).toHaveText('활성');
  });

  test('shows created product in initial enrollment selector', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: /Alpha Student|S0001|하율/ }).first().click();

    await expect(page.getByTestId('initial-enrollment-panel')).toBeVisible({ timeout: 10_000 });
    await page.getByTestId('enrollment-course').selectOption({ index: 1 });
    await expect(page.getByTestId('enrollment-product')).toBeVisible();
    await expect(page.locator('[data-testid="enrollment-product"] option').filter({ hasText: createdName })).toHaveCount(1);
  });

  test('edits product details and persists after reload', async ({ page }) => {
    const updatedName = `${createdName} Updated`;

    await loginAsOwner(page);
    await page.goto('/course-products');
    await expect(page.getByTestId(`product-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });

    await page.getByTestId(`product-edit-${createdCode}`).click();
    await page.getByTestId(`product-edit-name-${createdCode}`).fill(updatedName);
    await page.getByTestId(`product-save-${createdCode}`).click();

    await expect(page.getByText(updatedName)).toBeVisible({ timeout: 10_000 });
    await page.reload();
    await expect(page.getByText(updatedName)).toBeVisible({ timeout: 10_000 });
  });

  test('deactivates a product with confirmation', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/course-products');
    await expect(page.getByTestId(`product-item-${createdCode}`)).toBeVisible({ timeout: 10_000 });

    page.once('dialog', (dialog) => dialog.accept());
    await page.getByTestId(`product-status-reason-${createdCode}`).fill('E2E deactivate product');
    await page.getByTestId(`product-deactivate-${createdCode}`).click();

    await expect(page.getByTestId(`product-status-${createdCode}`)).toHaveText('비활성', {
      timeout: 10_000,
    });
  });

  test('hides inactive products from initial enrollment selector', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: /Alpha Student|S0001|하율/ }).first().click();

    await expect(page.getByTestId('initial-enrollment-panel')).toBeVisible({ timeout: 10_000 });
    await page.getByTestId('enrollment-course').selectOption({ index: 1 });
    await expect(page.locator('[data-testid="enrollment-product"] option').filter({ hasText: createdCode })).toHaveCount(0);
  });

  test('shows product management link on enrollment empty state', async ({ page }) => {
    await loginAsOwner(page);
    await page.goto('/students');
    await page.getByRole('link', { name: /Alpha Student|S0001|하율/ }).first().click();

    await expect(page.getByTestId('initial-enrollment-panel')).toBeVisible({ timeout: 10_000 });

    const courseSelect = page.getByTestId('enrollment-course');
    const optionCount = await courseSelect.locator('option').count();
    for (let index = 1; index < optionCount; index += 1) {
      await courseSelect.selectOption({ index });
      const emptyVisible = await page.getByTestId('enrollment-product-empty').isVisible();
      if (emptyVisible) {
        await expect(page.getByTestId('course-products-manage-link')).toBeVisible();
        return;
      }
    }

    test.skip(true, 'No course without active products in current fixture');
  });

  test('mobile layout remains usable without horizontal overflow', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await loginAsOwner(page);
    await page.goto('/course-products');

    await expect(page.getByTestId('course-products-panel')).toBeVisible();
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    expect(overflow).toBe(false);
  });
});

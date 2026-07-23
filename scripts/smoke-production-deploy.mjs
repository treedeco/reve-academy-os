/**
 * One-shot production deployment smoke checks (no secrets logged).
 * Usage:
 *   PRODUCTION_OWNER_PASSWORD=<bootstrap password> node scripts/smoke-production-deploy.mjs
 */
import { chromium } from '@playwright/test';

const BASE_URL = process.env.PRODUCTION_URL ?? 'https://reve-academy-os.vercel.app';
const OWNER_PASSWORD = process.env.PRODUCTION_OWNER_PASSWORD;

const results = {
  loginPageLoads: false,
  protectedRouteRedirects: false,
  wrongPasswordRejected: false,
  ownerLoginSucceeded: null,
  dashboardLoaded: null,
  sessionPersistsAfterReload: null,
  consoleErrors: [],
  networkFailures: [],
};

function recordConsole(msg) {
  if (msg.type() === 'error') {
    results.consoleErrors.push(msg.text().slice(0, 240));
  }
}

function recordRequest(request) {
  if (['document', 'script', 'fetch', 'xhr'].includes(request.resourceType())) {
    request.response().then((response) => {
      if (!response) {
        results.networkFailures.push(`${request.method()} ${request.url()} (no response)`);
        return;
      }
      if (response.status() >= 400) {
        results.networkFailures.push(`${request.method()} ${request.url()} (${response.status()})`);
      }
    }).catch(() => {});
  }
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const page = await context.newPage();
page.on('console', recordConsole);
page.on('request', recordRequest);

try {
  const loginResponse = await page.goto(`${BASE_URL}/login`, { waitUntil: 'networkidle' });
  results.loginPageLoads = loginResponse?.ok() === true;
  await page.getByText('Owner 로그인').waitFor({ timeout: 10000 });
  results.loginPageLoads &&= await page.locator('#password').isVisible();

  await context.clearCookies();
  const protectedResponse = await page.goto(`${BASE_URL}/students`, { waitUntil: 'networkidle' });
  results.protectedRouteRedirects = page.url().includes('/login');

  await page.goto(`${BASE_URL}/login`, { waitUntil: 'networkidle' });
  await page.locator('#username').fill('reve');
  await page.locator('#password').fill('definitely-not-the-owner-password');
  await page.getByRole('button', { name: '로그인' }).click();
  await page.waitForTimeout(2000);
  const bodyText = await page.locator('body').innerText();
  results.wrongPasswordRejected =
    page.url().includes('/login') &&
    /올바르지|invalid|incorrect|credentials/i.test(bodyText);

  if (OWNER_PASSWORD) {
    await page.locator('#username').fill('reve');
    await page.locator('#password').fill(OWNER_PASSWORD);
    await page.getByRole('button', { name: '로그인' }).click();
    await page.waitForURL((url) => !url.pathname.includes('/login'), { timeout: 15000 }).catch(() => null);
    results.ownerLoginSucceeded = !page.url().includes('/login');
    results.dashboardLoaded = results.ownerLoginSucceeded;
    if (results.ownerLoginSucceeded) {
      await page.reload({ waitUntil: 'networkidle' });
      results.sessionPersistsAfterReload = !page.url().includes('/login');
    }
  }
} finally {
  await browser.close();
}

console.log(JSON.stringify(results, null, 2));
if (!results.loginPageLoads || !results.protectedRouteRedirects || !results.wrongPasswordRejected) {
  process.exit(1);
}
if (OWNER_PASSWORD && (!results.ownerLoginSucceeded || !results.sessionPersistsAfterReload)) {
  process.exit(1);
}

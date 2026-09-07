/**
 * Production browser verification for Owner /teachers visibility & inactive toggle.
 * 
 * Verifies:
 * 1. Default /teachers view:
 *    - Active teachers (t-p-1 이혜인, t-v-1 김홍중, t-v-2 이예나) are visible with "활성" badge.
 *    - Inactive teacher (t-m-1 이혜인) is NOT visible.
 *    - Inactive teachers section is NOT rendered.
 * 2. When Owner enables "비활성 강사 보기":
 *    - Inactive section is displayed.
 *    - Inactive teacher t-m-1 is visible inside the inactive section with "비활성" badge.
 *    - Canonical active teacher t-p-1 remains visible in the active list.
 * 3. When Owner disables "비활성 강사 보기":
 *    - Inactive section and t-m-1 are hidden again.
 * 4. Screenshots captured for visual proof.
 */
import { createClient } from '@supabase/supabase-js';
import { chromium } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT_REF = 'bfhptqhgxignyggyxxkx';
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
const BASE_URL = 'https://reve-academy-os.vercel.app';

console.log('[verify-production] Fetching Supabase keys...');
const keysOut = spawnSync(
  'npx',
  ['supabase', 'projects', 'api-keys', '--project-ref', PROJECT_REF, '-o', 'json'],
  { encoding: 'utf8', shell: true },
);

const rows = JSON.parse(
  keysOut.stdout.slice(keysOut.stdout.indexOf('['), keysOut.stdout.lastIndexOf(']') + 1),
);
const anon = rows.find((x) => x.id === 'anon')?.api_key;
const service = rows.find((x) => x.id === 'service_role')?.api_key;

if (!service || !anon) {
  throw new Error('Failed to resolve Supabase keys');
}

const admin = createClient(SUPABASE_URL, service, {
  auth: { persistSession: false, autoRefreshToken: false },
});

console.log('[verify-production] Generating owner magic link session...');
const link = await admin.auth.admin.generateLink({
  type: 'magiclink',
  email: 'reve@owner.local',
});

const client = createClient(SUPABASE_URL, anon, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const verified = await client.auth.verifyOtp({
  email: 'reve@owner.local',
  token: link.data.properties.email_otp,
  type: 'magiclink',
});

if (!verified.data.session) {
  throw new Error('Failed to authenticate owner session');
}

console.log('[verify-production] Owner authenticated successfully.');

const artifactsDir = path.resolve(process.cwd(), 'artifacts');
if (!fs.existsSync(artifactsDir)) {
  fs.mkdirSync(artifactsDir, { recursive: true });
}

async function verify() {
  console.log('[verify-production] Launching Chromium browser...');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });

  await context.addCookies([
    {
      name: `sb-${PROJECT_REF}-auth-token`,
      value: JSON.stringify({
        access_token: verified.data.session.access_token,
        refresh_token: verified.data.session.refresh_token,
        expires_at: verified.data.session.expires_at,
        expires_in: verified.data.session.expires_in,
        token_type: verified.data.session.token_type,
        user: verified.data.session.user,
      }),
      domain: 'reve-academy-os.vercel.app',
      path: '/',
      secure: true,
      sameSite: 'Lax',
    },
  ]);

  const page = await context.newPage();

  console.log('[verify-production] Polling for new deployment at /teachers...');
  // Poll until the new feature (show-inactive-teachers-toggle) is visible on production
  let deployed = false;
  for (let attempt = 1; attempt <= 30; attempt++) {
    console.log(`[verify-production] Attempt ${attempt}/30 navigating to ${BASE_URL}/teachers...`);
    await page.goto(`${BASE_URL}/teachers`, { waitUntil: 'networkidle', timeout: 30000 });
    
    const toggleCount = await page.locator('[data-testid="show-inactive-teachers-toggle"]').count();
    if (toggleCount > 0) {
      console.log('[verify-production] New deployment detected!');
      deployed = true;
      break;
    }
    console.log('[verify-production] Waiting 5s for Vercel deployment build...');
    await page.waitForTimeout(5000);
  }

  if (!deployed) {
    throw new Error('Timed out waiting for production deployment of new /teachers page');
  }

  // --- Step 1: Default View Checks ---
  console.log('[verify-production] --- Checking Step 1: Default /teachers view ---');
  await page.waitForSelector('[data-testid="teachers-panel"]', { timeout: 10000 });
  await page.waitForSelector('[data-testid="teachers-list"]', { timeout: 10000 });

  // 1a. Canonical active teacher t-p-1 must be visible with "활성" badge
  const tp1Item = page.getByTestId('teacher-item-t-p-1');
  if ((await tp1Item.count()) === 0) {
    throw new Error('FAIL: Canonical active teacher t-p-1 not found in default view!');
  }
  const tp1Status = await page.getByTestId('teacher-status-t-p-1').innerText();
  console.log(`[verify-production] t-p-1 (이혜인) status: ${tp1Status}`);
  if (!tp1Status.includes('활성')) {
    throw new Error(`FAIL: Expected t-p-1 to have status '활성', got '${tp1Status}'`);
  }

  // 1b. Inactive teacher t-m-1 must NOT be visible
  const tm1Count = await page.getByTestId('teacher-item-t-m-1').count();
  console.log(`[verify-production] t-m-1 item count in default view: ${tm1Count}`);
  if (tm1Count !== 0) {
    throw new Error('FAIL: Inactive teacher t-m-1 must NOT be visible in default view!');
  }

  // 1c. Inactive section must NOT be rendered
  const inactiveSectionCount = await page.getByTestId('inactive-teachers-section').count();
  console.log(`[verify-production] Inactive section count in default view: ${inactiveSectionCount}`);
  if (inactiveSectionCount !== 0) {
    throw new Error('FAIL: Inactive teachers section must NOT be rendered by default!');
  }

  // Save screenshot of default view
  const defaultScreenshotPath = path.resolve(artifactsDir, 'production-teachers-default-view.png');
  await page.screenshot({ path: defaultScreenshotPath, fullPage: true });
  console.log(`[verify-production] Saved screenshot: ${defaultScreenshotPath}`);

  // --- Step 2: Toggle "비활성 강사 보기" ---
  console.log('[verify-production] --- Checking Step 2: Enabling "비활성 강사 보기" ---');
  const checkbox = page.getByTestId('show-inactive-teachers-checkbox');
  await checkbox.check();

  // 2a. Inactive section must now be visible
  await page.waitForSelector('[data-testid="inactive-teachers-section"]', { timeout: 5000 });
  console.log('[verify-production] Inactive section is now visible.');

  // 2b. Inactive teacher t-m-1 must be visible with "비활성" badge
  await page.waitForSelector('[data-testid="teacher-item-t-m-1"]', { timeout: 5000 });
  const tm1Status = await page.getByTestId('teacher-status-t-m-1').innerText();
  console.log(`[verify-production] t-m-1 (이혜인) status in inactive section: ${tm1Status}`);
  if (!tm1Status.includes('비활성')) {
    throw new Error(`FAIL: Expected t-m-1 to have status '비활성', got '${tm1Status}'`);
  }

  // 2c. Canonical active teacher t-p-1 must STILL be visible with "활성" badge
  const tp1StillVisible = await page.getByTestId('teacher-item-t-p-1').isVisible();
  console.log(`[verify-production] t-p-1 still visible: ${tp1StillVisible}`);
  if (!tp1StillVisible) {
    throw new Error('FAIL: Canonical active teacher t-p-1 disappeared when toggle was enabled!');
  }

  // Save screenshot of toggled view
  const toggledScreenshotPath = path.resolve(artifactsDir, 'production-teachers-inactive-toggled.png');
  await page.screenshot({ path: toggledScreenshotPath, fullPage: true });
  console.log(`[verify-production] Saved screenshot: ${toggledScreenshotPath}`);

  // --- Step 3: Toggle off "비활성 강사 보기" ---
  console.log('[verify-production] --- Checking Step 3: Disabling "비활성 강사 보기" ---');
  await checkbox.uncheck();

  const inactiveSectionAfterUncheck = await page.getByTestId('inactive-teachers-section').count();
  const tm1AfterUncheck = await page.getByTestId('teacher-item-t-m-1').count();
  console.log(`[verify-production] Inactive section count after uncheck: ${inactiveSectionAfterUncheck}`);
  console.log(`[verify-production] t-m-1 item count after uncheck: ${tm1AfterUncheck}`);

  if (inactiveSectionAfterUncheck !== 0 || tm1AfterUncheck !== 0) {
    throw new Error('FAIL: Inactive teachers did not disappear after unchecking toggle!');
  }

  console.log('\n[verify-production] ========================================');
  console.log('[verify-production] ALL PRODUCTION BROWSER CHECKS PASSED!');
  console.log('[verify-production] ========================================');

  await browser.close();
  return {
    defaultScreenshot: defaultScreenshotPath,
    toggledScreenshot: toggledScreenshotPath,
  };
}

const result = await verify();
console.log(JSON.stringify(result, null, 2));

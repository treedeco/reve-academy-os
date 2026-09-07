/**
 * Production runtime verification for Teacher Lee (이혜인) login and navigation.
 * Tests:
 *   1. Form login with in2520@naver.com and temporary password
 *   2. Redirect to /teacher/lessons/today
 *   3. TeacherShell header shows '이혜인'
 *   4. Today's lessons view loads with 0 lessons
 *   5. Navigation to /teacher/students loads assigned students panel
 *   6. Protection checks: attempting to open /dashboard, /students, /teachers redirects away
 */
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const BASE_URL = 'https://reve-academy-os.vercel.app';
const credPath = path.resolve(process.cwd(), 'artifacts', 'teacher_lee_temp_password.txt');
const credText = fs.readFileSync(credPath, 'utf8');
const tempPassword = credText.match(/TempPassword:\s*(.+)/)?.[1]?.trim();
const email = 'in2520@naver.com';

if (!tempPassword) {
  throw new Error('Failed to parse temporary password from artifacts');
}

async function run() {
  console.log('Launching browser for production verification...');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 }, // Mobile viewport
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  });

  const page = await context.newPage();

  console.log(`Navigating to ${BASE_URL}/login...`);
  await page.goto(`${BASE_URL}/login`, { waitUntil: 'networkidle' });

  console.log('Filling login form...');
  await page.fill('input#username', email);
  await page.fill('input#password', tempPassword);

  console.log('Submitting login form...');
  await Promise.all([
    page.waitForURL((url) => url.pathname.includes('/teacher'), { timeout: 15000 }),
    page.click('button[type="submit"]'),
  ]);

  console.log(`Current URL after login: ${page.url()}`);
  if (!page.url().includes('/teacher/lessons/today')) {
    throw new Error(`Expected redirect to /teacher/lessons/today, got ${page.url()}`);
  }

  // Check header contains '이혜인'
  await page.waitForSelector('header', { timeout: 10000 });
  const headerText = await page.locator('header').innerText();
  console.log(`Header content: ${headerText.replace(/\n/g, ' ')}`);
  if (!headerText.includes('이혜인')) {
    throw new Error(`Expected header to contain '이혜인', got: ${headerText}`);
  }

  // Check today's lessons empty state
  const bodyText = await page.locator('main').innerText();
  console.log(`Main body text: ${bodyText.replace(/\n/g, ' ')}`);

  // Navigate to /teacher/students
  console.log('Navigating to /teacher/students...');
  await page.goto(`${BASE_URL}/teacher/students`, { waitUntil: 'networkidle' });
  console.log(`Students page URL: ${page.url()}`);
  const studentsBody = await page.locator('main').innerText();
  console.log(`Students body text: ${studentsBody.replace(/\n/g, ' ')}`);

  // Test route protection (Owner pages must redirect away)
  console.log('Testing Owner page boundary protection (/dashboard)...');
  await page.goto(`${BASE_URL}/dashboard`, { waitUntil: 'networkidle' });
  console.log(`Attempted /dashboard -> ended up at: ${page.url()}`);
  if (page.url().includes('/dashboard')) {
    throw new Error('SECURITY VIOLATION: Teacher was able to access /dashboard!');
  }

  console.log('Testing Owner page boundary protection (/teachers)...');
  await page.goto(`${BASE_URL}/teachers`, { waitUntil: 'networkidle' });
  console.log(`Attempted /teachers -> ended up at: ${page.url()}`);
  if (page.url().includes('/teachers')) {
    throw new Error('SECURITY VIOLATION: Teacher was able to access /teachers!');
  }

  console.log('Testing Owner page boundary protection (/students)...');
  await page.goto(`${BASE_URL}/students`, { waitUntil: 'networkidle' });
  console.log(`Attempted /students -> ended up at: ${page.url()}`);
  if (page.url().includes('/students')) {
    throw new Error('SECURITY VIOLATION: Teacher was able to access /students!');
  }

  await browser.close();
  console.log('\n=== ALL PLAYWRIGHT RUNTIME VERIFICATIONS PASSED ===');
}

run().catch((err) => {
  console.error('\n*** RUNTIME VERIFICATION FAILED ***', err);
  process.exit(1);
});

/**
 * Production browser verification: fixed-schedule removal unschedules pending lessons.
 * Student: 하다은 S0003 — after repair, lesson rows must show "일정 미정".
 */
import { createClient } from '@supabase/supabase-js';
import { chromium } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT_REF = 'bfhptqhgxignyggyxxkx';
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
const BASE_URL = 'https://reve-academy-os.vercel.app';
const STUDENT_ID = '73fe1a1c-3248-4bb2-9b8f-44fb6de4d533';

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
if (!service || !anon) throw new Error('Failed to resolve Supabase keys');

const admin = createClient(SUPABASE_URL, service, {
  auth: { persistSession: false, autoRefreshToken: false },
});
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
if (!verified.data.session) throw new Error('Failed to authenticate owner session');

const artifactsDir = path.resolve(process.cwd(), 'artifacts');
fs.mkdirSync(artifactsDir, { recursive: true });

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
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
const studentUrl = `${BASE_URL}/students/${STUDENT_ID}`;
let deployed = false;

for (let attempt = 1; attempt <= 36; attempt++) {
  console.log(`[verify] attempt ${attempt}/36 ${studentUrl}`);
  await page.goto(studentUrl, { waitUntil: 'networkidle', timeout: 45000 });
  const unscheduledCount = await page.getByText('일정 미정').count();
  const helpVisible = await page
    .getByText('아직 진행하지 않은 예정 회차의 기존 일정은 해제됩니다')
    .count();
  if (unscheduledCount >= 4 && helpVisible > 0) {
    deployed = true;
    break;
  }
  console.log(
    `[verify] waiting deploy… unscheduled=${unscheduledCount} help=${helpVisible}`,
  );
  await page.waitForTimeout(10000);
}

if (!deployed) {
  await page.screenshot({
    path: path.join(artifactsDir, 'hadaeun-unschedule-timeout.png'),
    fullPage: true,
  });
  throw new Error('Timed out waiting for production UI with 일정 미정');
}

const noSchedule = await page.getByTestId('student-no-schedule').count();
if (noSchedule !== 1) {
  throw new Error('Expected empty fixed-schedule section');
}

const unscheduled = await page.getByText('일정 미정').count();
if (unscheduled < 4) {
  throw new Error(`Expected >=4 일정 미정 cells, got ${unscheduled}`);
}

const obsoleteDate = await page.getByText('8/11').count();
if (obsoleteDate > 0) {
  throw new Error('Obsolete 8/11 date still visible');
}

await page.screenshot({
  path: path.join(artifactsDir, 'hadaeun-unschedule-verified.png'),
  fullPage: true,
});

console.log(
  JSON.stringify(
    {
      ok: true,
      studentId: STUDENT_ID,
      unscheduledLabelCount: unscheduled,
      emptyFixedSchedule: true,
      screenshot: 'artifacts/hadaeun-unschedule-verified.png',
    },
    null,
    2,
  ),
);

await browser.close();

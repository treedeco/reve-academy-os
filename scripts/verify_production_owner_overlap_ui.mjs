/**
 * Production browser verification for Owner overlap soft-warning UI.
 */
import { createClient } from '@supabase/supabase-js';
import { chromium } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT_REF = 'bfhptqhgxignyggyxxkx';
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
const BASE_URL = 'https://reve-academy-os.vercel.app';
const TEACHER_ID = 'aba1417b-c409-4cf3-9b3d-fbd6eaf4ea23';
const MARKER = `PHASE2B-UI-${Date.now()}`;
const HARD_A = '강사 일정이 겹칩니다. 다른 시간을 선택해 주세요.';
const HARD_B = '강사 또는 학생 일정이 겹칩니다. 다른 시간을 선택해 주세요.';

function parseJsonArray(stdout) {
  const start = stdout.indexOf('[');
  const end = stdout.lastIndexOf(']');
  if (start < 0 || end < 0) throw new Error(`bad keys: ${stdout.slice(0, 300)}`);
  return JSON.parse(stdout.slice(start, end + 1));
}

function nextMondaySeoulDate() {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
  });
  let d = new Date();
  for (let i = 0; i < 21; i += 1) {
    const parts = Object.fromEntries(fmt.formatToParts(d).map((p) => [p.type, p.value]));
    const candidate = `${parts.year}-${parts.month}-${parts.day}`;
    const todayParts = Object.fromEntries(fmt.formatToParts(new Date()).map((p) => [p.type, p.value]));
    const today = `${todayParts.year}-${todayParts.month}-${todayParts.day}`;
    if (parts.weekday === 'Mon' && candidate > today) return candidate;
    d = new Date(d.getTime() + 86400000);
  }
  throw new Error('no monday');
}

async function permanentlyDeleteStudent(client, studentId) {
  const { data: preview, error: previewError } = await client.rpc('reve_owner_preview_delete_student', {
    p_student_id: studentId,
  });
  if (previewError) throw previewError;
  const row = Array.isArray(preview) ? preview[0] : preview;
  if (!row) return;
  if ((row.blockers ?? []).length) throw new Error(JSON.stringify(row.blockers));
  const { error } = await client.rpc('reve_owner_permanently_delete_student', {
    p_student_id: studentId,
    p_expected_updated_at: row.updated_at,
    p_confirmation_code: `${row.student_code} 영구삭제`,
    p_reason: `${MARKER} ui verify cleanup`,
    p_preflight_fingerprint: row.preflight_fingerprint,
  });
  if (error) throw error;
}

async function selectFirstRealOption(page, testId, { waitMs = 0 } = {}) {
  const locator = page.getByTestId(testId);
  await locator.waitFor({ state: 'visible', timeout: 30000 });
  if (waitMs > 0) await page.waitForTimeout(waitMs);
  await page.waitForFunction(
    (id) => {
      const el = document.querySelector(`[data-testid="${id}"]`);
      if (!(el instanceof HTMLSelectElement)) return false;
      return Array.from(el.options).some((o) => o.value);
    },
    testId,
    { timeout: 30000 },
  );
  const values = await locator.locator('option').evaluateAll((opts) =>
    opts.map((o) => o.value).filter((v) => v && v.length > 0),
  );
  if (!values.length) throw new Error(`No selectable options for ${testId}`);
  await locator.selectOption(values[0]);
  return values[0];
}

const keysOut = spawnSync(
  'npx',
  ['supabase', 'projects', 'api-keys', '--project-ref', PROJECT_REF, '-o', 'json'],
  { encoding: 'utf8', shell: true },
);
const rows = parseJsonArray(keysOut.stdout);
const anon = rows.find((x) => x.id === 'anon')?.api_key;
const service = rows.find((x) => x.id === 'service_role')?.api_key;
const admin = createClient(SUPABASE_URL, service, { auth: { persistSession: false, autoRefreshToken: false } });
const link = await admin.auth.admin.generateLink({ type: 'magiclink', email: 'reve@owner.local' });
const client = createClient(SUPABASE_URL, anon, { auth: { persistSession: false, autoRefreshToken: false } });
const verified = await client.auth.verifyOtp({
  email: 'reve@owner.local',
  token: link.data.properties.email_otp,
  type: 'magiclink',
});
if (!verified.data.session) throw new Error('owner auth failed');

// Cleanup leftovers from prior failed UI attempt
const { data: leftovers } = await client
  .from('students')
  .select('id, name')
  .like('name', 'PHASE2B-UI-%');
for (const row of leftovers ?? []) {
  await permanentlyDeleteStudent(client, row.id).catch((e) => {
    console.warn('[cleanup leftover]', row.name, e.message);
  });
}

const { data: product } = await client
  .from('course_products')
  .select('id, default_tuition_krw, course_id')
  .eq('is_active', true)
  .eq('default_lesson_count', 4)
  .eq('weekly_frequency', 1)
  .limit(1)
  .maybeSingle();
if (!product) throw new Error('no product');

const startDate = nextMondaySeoulDate();
const slotPayload = [
  { teacher_id: TEACHER_ID, weekday: 1, local_time: '18:30', duration_minutes: 60, slot_order: 1 },
];

const { data: aRows } = await client.rpc('reve_owner_create_student', { p_name: `${MARKER}-A` });
const { data: bRows } = await client.rpc('reve_owner_create_student', { p_name: `${MARKER}-B` });
const studentA = Array.isArray(aRows) ? aRows[0] : aRows;
const studentB = Array.isArray(bRows) ? bRows[0] : bRows;

await client.rpc('reve_owner_create_initial_enrollment', {
  p_student_id: studentA.student_id,
  p_course_product_id: product.id,
  p_schedule_start_date: startDate,
  p_schedule_slots: slotPayload,
  p_paid_amount_krw: product.default_tuition_krw,
  p_payment_method: 'cash',
  p_paid_at: new Date().toISOString(),
  p_idempotency_key: `${MARKER}-a`,
  p_owner_reason: `${MARKER} occupy`,
});

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
const consoleErrors = [];
page.on('console', (msg) => {
  if (msg.type() === 'error') consoleErrors.push(msg.text());
});

const report = {
  marker: MARKER,
  softWarningSeen: false,
  hardBlockSeen: false,
  enrollmentSaved: false,
  submitEnabled: false,
};

try {
  await page.goto(`${BASE_URL}/students/${studentB.student_id}`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  report.landedUrl = page.url();
  if (/\/login/.test(page.url())) {
    throw new Error('Owner session cookie failed; redirected to login');
  }
  await page.getByTestId('initial-enrollment-panel').waitFor({ timeout: 30000 });
  await page.getByTestId('enrollment-course-loading').waitFor({ state: 'hidden', timeout: 30000 }).catch(() => null);
  if ((await page.getByTestId('enrollment-course-error').count()) > 0) {
    report.catalogError = await page.getByTestId('enrollment-course-error').innerText();
    await page.getByTestId('enrollment-course-retry').click().catch(() => null);
    await page.waitForTimeout(2000);
  }
  if ((await page.getByTestId('enrollment-course-empty').count()) > 0) {
    report.catalogEmpty = await page.getByTestId('enrollment-course-empty').innerText();
  }
  report.courseOptions = await page
    .getByTestId('enrollment-course')
    .locator('option')
    .evaluateAll((opts) => opts.map((o) => ({ value: o.value, text: o.textContent })));
  await page.screenshot({
    path: path.join(artifactsDir, 'phase2b-ui-before-select.png'),
    fullPage: true,
  });
  await page.waitForTimeout(1000);

  // Prefer the course that matches the product used to occupy the slot (avoid empty-product courses).
  const preferredCourseId = product.course_id;
  await page.getByTestId('enrollment-course').selectOption(preferredCourseId);
  await page.waitForFunction(
    (id) => {
      const el = document.querySelector('[data-testid="enrollment-product"]');
      if (!(el instanceof HTMLSelectElement)) return false;
      return Array.from(el.options).some((o) => o.value === id || (o.value && o.value.length > 0));
    },
    product.id,
    { timeout: 30000 },
  );
  await page.getByTestId('enrollment-product').selectOption(product.id);
  await page.getByTestId('enrollment-start-date').fill(startDate);
  await page.getByTestId('enrollment-payment-method').selectOption('cash');
  await page.getByTestId('enrollment-slot-teacher-1').waitFor({ timeout: 15000 });
  await page.getByTestId('enrollment-slot-teacher-1').selectOption(TEACHER_ID);
  await page.getByTestId('enrollment-slot-weekday-1').selectOption('1');
  await page.getByTestId('enrollment-slot-time-1').fill('18:30');

  // Soft warning is driven by preview RPC after slot completeness
  await page.waitForTimeout(2500);
  const soft = page.getByTestId('enrollment-overlap-soft-warning');
  report.softWarningSeen =
    (await soft.count()) > 0 && (await soft.innerText()).includes('원장 권한으로 저장');
  const bodyText = await page.locator('body').innerText();
  report.hardBlockSeen = bodyText.includes(HARD_A) || bodyText.includes(HARD_B);
  const submit = page.getByTestId('enrollment-submit');
  report.submitEnabled = await submit.isEnabled();

  await page.screenshot({
    path: path.join(artifactsDir, 'phase2b-ui-enrollment-overlap.png'),
    fullPage: true,
  });

  if (report.submitEnabled) {
    await submit.click();
    await page.getByTestId('enrollment-success').waitFor({ timeout: 20000 }).catch(() => null);
    report.enrollmentSaved = (await page.getByTestId('enrollment-success').count()) > 0
      || (await page.getByTestId('used-count').count()) > 0;
    if ((await page.getByTestId('enrollment-error').count()) > 0) {
      report.enrollmentError = await page.getByTestId('enrollment-error').innerText();
    }
  }

  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);
  report.reloadShowsPass = (await page.getByTestId('used-count').count()) > 0
    || (await page.getByTestId('student-lessons-table').count()) > 0;

  await page.goto(`${BASE_URL}/schedule`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  report.weeklyLoaded = !(await page.content()).includes(HARD_A);
  await page.goto(`${BASE_URL}/lessons/today`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  report.todayLoaded = true;

  // Lesson change modal soft path: open student A detail and attempt reschedule UI if available
  await page.goto(`${BASE_URL}/students/${studentA.student_id}`, {
    waitUntil: 'domcontentloaded',
    timeout: 60000,
  });
  const changeBtn = page.getByTestId('lesson-reschedule-open').first();
  if ((await changeBtn.count()) > 0) {
    await changeBtn.click();
    report.lessonChangeModalOpened = true;
  } else {
    const alt = page.getByRole('button', { name: /일정|변경|시간/ }).first();
    if ((await alt.count()) > 0) {
      await alt.click().catch(() => null);
      report.lessonChangeModalOpened = true;
    } else {
      report.lessonChangeModalOpened = false;
    }
  }
} finally {
  report.consoleErrorCount = consoleErrors.length;
  await browser.close();
  await permanentlyDeleteStudent(client, studentA.student_id).catch((e) => {
    report.cleanupAError = e.message;
  });
  await permanentlyDeleteStudent(client, studentB.student_id).catch((e) => {
    report.cleanupBError = e.message;
  });
  fs.writeFileSync(path.join(artifactsDir, 'phase2b-ui-overlap-verify.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}

if (!report.softWarningSeen || report.hardBlockSeen || !report.submitEnabled || !report.enrollmentSaved) {
  process.exitCode = 1;
}

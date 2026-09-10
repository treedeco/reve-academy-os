/**
 * Production verification: fixed-schedule re-register + conflict override for V-S0030-001.
 * 1) Report Tuesday 19:00 conflicts
 * 2) Confirm UI CTA
 * 3) Assign Tue 19:00 via Owner RPC with override when needed
 * 4) Assert same lesson IDs / usage unchanged
 */
import { createClient } from '@supabase/supabase-js';
import { chromium } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT_REF = 'bfhptqhgxignyggyxxkx';
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
const BASE_URL = 'https://reve-academy-os.vercel.app';
const STUDENT_ID = 'c2923276-f567-476a-9efd-a6903b609fc0';
const PASS_ID = '32fcdce3-e0e1-47c0-877e-439fdd71a404';
const TEACHER_ID = 'aba1417b-c409-4cf3-9b3d-fbd6eaf4ea23';
const EXPECTED_LESSON_IDS = [
  '24b0e729-f6d6-41d7-b40c-b1a9fade8a1b',
  'e98cea02-5e2a-43a0-8708-9f3e66d249de',
  '0b6e6df9-d201-47a4-809a-61de8ed503ef',
  'a988c321-debf-48e7-b1e2-9ae1dadd18b0',
];

function parseJsonArray(stdout) {
  const start = stdout.indexOf('[');
  const end = stdout.lastIndexOf(']');
  if (start < 0 || end < 0) {
    throw new Error(`Failed to parse JSON array from: ${stdout.slice(0, 400)}`);
  }
  return JSON.parse(stdout.slice(start, end + 1));
}

const keysOut = spawnSync(
  'npx',
  ['supabase', 'projects', 'api-keys', '--project-ref', PROJECT_REF, '-o', 'json'],
  { encoding: 'utf8', shell: true },
);
const rows = parseJsonArray(keysOut.stdout);
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

const slotPayload = [
  {
    teacher_id: TEACHER_ID,
    weekday: 2,
    local_time: '19:00',
    duration_minutes: 60,
    slot_order: 1,
  },
];

const { data: beforePass, error: beforePassError } = await client
  .from('passes')
  .select('id, pass_code, status, updated_at, registered_lesson_count_snapshot')
  .eq('id', PASS_ID)
  .single();
if (beforePassError) throw beforePassError;

const { data: beforeLessons, error: beforeLessonsError } = await client
  .from('lessons')
  .select('id, sequence_number, status, scheduled_at')
  .eq('pass_id', PASS_ID)
  .order('sequence_number');
if (beforeLessonsError) throw beforeLessonsError;

const beforeIds = beforeLessons.map((row) => row.id).sort();
const expectedSorted = [...EXPECTED_LESSON_IDS].sort();
if (JSON.stringify(beforeIds) !== JSON.stringify(expectedSorted)) {
  throw new Error(`Unexpected lesson IDs before mutation: ${JSON.stringify(beforeIds)}`);
}

const { data: conflicts, error: conflictError } = await client.rpc(
  'reve_owner_preview_pass_schedule_collisions',
  {
    p_pass_id: PASS_ID,
    p_schedule_slots: slotPayload,
  },
);
if (conflictError) {
  console.error('[verify] conflict preview failed (migration may not be deployed yet):', conflictError.message);
  throw conflictError;
}

console.log('[verify] Tuesday 19:00 conflicts:', JSON.stringify(conflicts, null, 2));
fs.writeFileSync(
  path.join(artifactsDir, 'v-s0030-tue-1900-conflicts.json'),
  JSON.stringify(conflicts, null, 2),
  'utf8',
);

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
let uiReady = false;
for (let attempt = 1; attempt <= 36; attempt += 1) {
  console.log(`[verify] UI attempt ${attempt}/36 ${studentUrl}`);
  await page.goto(studentUrl, { waitUntil: 'networkidle', timeout: 45000 });
  const cta = await page.getByTestId('student-fixed-schedule-create-open-section').count();
  const noSchedule = await page.getByTestId('student-no-schedule').count();
  if (cta > 0 && noSchedule > 0) {
    uiReady = true;
    break;
  }
  await page.waitForTimeout(10000);
}
await page.screenshot({
  path: path.join(artifactsDir, 'v-s0030-reregister-before.png'),
  fullPage: true,
});
if (!uiReady) {
  await browser.close();
  throw new Error('Production UI CTA for 새 고정 일정 등록 not deployed yet');
}

const todaySeoul = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Seoul',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
}).format(new Date());

const { data: changeRows, error: changeError } = await client.rpc(
  'reve_owner_change_fixed_pass_schedule',
  {
    p_pass_id: PASS_ID,
    p_expected_pass_updated_at: beforePass.updated_at,
    p_effective_from: todaySeoul,
    p_schedule_slots: slotPayload,
    p_reason: 'Production verify: 화 19:00 고정 일정 재등록 (Owner override if needed)',
    p_allow_conflict_override: (conflicts?.length ?? 0) > 0,
  },
);
if (changeError) {
  await browser.close();
  throw changeError;
}
console.log('[verify] change result:', JSON.stringify(changeRows, null, 2));

const { data: afterLessons, error: afterLessonsError } = await client
  .from('lessons')
  .select('id, sequence_number, status, scheduled_at')
  .eq('pass_id', PASS_ID)
  .order('sequence_number');
if (afterLessonsError) throw afterLessonsError;

const afterIds = afterLessons.map((row) => row.id).sort();
if (JSON.stringify(afterIds) !== JSON.stringify(expectedSorted)) {
  throw new Error(`Lesson IDs changed after mutation: ${JSON.stringify(afterIds)}`);
}
if (afterLessons.some((row) => row.scheduled_at == null)) {
  throw new Error('Some lessons remain unscheduled after assignment');
}
if (afterLessons.length !== 4) {
  throw new Error(`Expected 4 lessons, got ${afterLessons.length}`);
}

const usedStatuses = ['completed', 'same_day_cancelled', 'makeup_completed'];
const used = afterLessons.filter((row) => usedStatuses.includes(row.status)).length;
if (used !== 0) {
  throw new Error(`used count changed unexpectedly: ${used}`);
}

const { data: auditRows, error: auditError } = await admin
  .from('audit_logs')
  .select('action, resource_id, new_value, created_at')
  .eq('resource_id', PASS_ID)
  .eq('action', 'pass.schedule_conflict_overridden')
  .order('created_at', { ascending: false })
  .limit(3);
if (auditError) throw auditError;

await page.reload({ waitUntil: 'networkidle' });
await page.screenshot({
  path: path.join(artifactsDir, 'v-s0030-reregister-after.png'),
  fullPage: true,
});
const scheduleSlotsVisible = await page.getByTestId('student-schedule-slots').count();
const unscheduledRemaining = await page.getByText('일정 미정').count();
await browser.close();

const report = {
  pass_code: beforePass.pass_code,
  conflicts,
  changeRows,
  beforeLessonIds: beforeIds,
  afterLessonIds: afterIds,
  used,
  remaining: beforePass.registered_lesson_count_snapshot - used,
  auditOverrideCount: auditRows?.length ?? 0,
  scheduleSlotsVisible,
  unscheduledRemaining,
};
fs.writeFileSync(
  path.join(artifactsDir, 'v-s0030-reregister-report.json'),
  JSON.stringify(report, null, 2),
  'utf8',
);
console.log('[verify] READY', JSON.stringify(report, null, 2));

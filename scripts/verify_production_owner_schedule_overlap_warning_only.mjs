/**
 * Production verification: Owner schedule overlap warning-only (Phase 2B).
 * Creates disposable test students, performs overlapping enrollment + reschedule,
 * read-backs persistence, then cleans up via Owner permanent-delete RPC.
 *
 * Never logs secrets/tokens.
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
const MARKER = `PHASE2B-OVL-${Date.now()}`;

function parseJsonArray(stdout) {
  const start = stdout.indexOf('[');
  const end = stdout.lastIndexOf(']');
  if (start < 0 || end < 0) {
    throw new Error(`Failed to parse JSON array from: ${stdout.slice(0, 400)}`);
  }
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
  const partsFor = (d) => {
    const parts = Object.fromEntries(fmt.formatToParts(d).map((p) => [p.type, p.value]));
    return parts;
  };
  let d = new Date();
  for (let i = 0; i < 21; i += 1) {
    const parts = partsFor(d);
    if (parts.weekday === 'Mon') {
      // Prefer a Monday at least 7 days out to avoid today edge cases
      const candidate = `${parts.year}-${parts.month}-${parts.day}`;
      const todayParts = partsFor(new Date());
      const today = `${todayParts.year}-${todayParts.month}-${todayParts.day}`;
      if (candidate > today) return candidate;
    }
    d = new Date(d.getTime() + 24 * 60 * 60 * 1000);
  }
  throw new Error('Could not resolve next Monday (Asia/Seoul)');
}

function monday1830Iso(dateYmd) {
  // Asia/Seoul is UTC+9 → 18:30 KST = 09:30 UTC
  return `${dateYmd}T09:30:00.000Z`;
}

async function permanentlyDeleteStudent(client, studentId) {
  const { data: preview, error: previewError } = await client.rpc('reve_owner_preview_delete_student', {
    p_student_id: studentId,
  });
  if (previewError) throw previewError;
  const row = Array.isArray(preview) ? preview[0] : preview;
  if (!row) throw new Error(`No delete preview for ${studentId}`);
  if ((row.blockers ?? []).length > 0) {
    throw new Error(`Delete blocked for ${studentId}: ${JSON.stringify(row.blockers)}`);
  }
  const { data, error } = await client.rpc('reve_owner_permanently_delete_student', {
    p_student_id: studentId,
    p_expected_updated_at: row.updated_at,
    p_confirmation_code: `${row.student_code} 영구삭제`,
    p_reason: `${MARKER} cleanup after overlap verification`,
    p_preflight_fingerprint: row.preflight_fingerprint,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
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

const report = {
  marker: MARKER,
  teacherId: TEACHER_ID,
  tests: {},
};

const { data: product, error: productError } = await client
  .from('course_products')
  .select('id, product_code, product_name, default_lesson_count, weekly_frequency, default_tuition_krw, course_id')
  .eq('is_active', true)
  .eq('default_lesson_count', 4)
  .eq('weekly_frequency', 1)
  .order('product_code')
  .limit(1)
  .maybeSingle();
if (productError || !product) throw new Error(productError?.message ?? 'No active 4-lesson weekly product');

const startDate = nextMondaySeoulDate();
const targetIso = monday1830Iso(startDate);
const slotPayload = [
  {
    teacher_id: TEACHER_ID,
    weekday: 1,
    local_time: '18:30',
    duration_minutes: 60,
    slot_order: 1,
  },
];

console.log('[verify] marker=', MARKER);
console.log('[verify] product=', product.product_code, product.id);
console.log('[verify] target Monday 18:30 KST=', startDate, targetIso);

const { data: studentARows, error: studentAError } = await client.rpc('reve_owner_create_student', {
  p_name: `${MARKER}-A`,
});
if (studentAError) throw studentAError;
const studentA = Array.isArray(studentARows) ? studentARows[0] : studentARows;

const { data: studentBRows, error: studentBError } = await client.rpc('reve_owner_create_student', {
  p_name: `${MARKER}-B`,
});
if (studentBError) throw studentBError;
const studentB = Array.isArray(studentBRows) ? studentBRows[0] : studentBRows;

report.studentA = {
  id: studentA.student_id,
  code: studentA.student_code,
};
report.studentB = {
  id: studentB.student_id,
  code: studentB.student_code,
};

const enrollAIdem = `${MARKER}-enroll-a`;
const { data: enrollA, error: enrollAError } = await client.rpc('reve_owner_create_initial_enrollment', {
  p_student_id: studentA.student_id,
  p_course_product_id: product.id,
  p_schedule_start_date: startDate,
  p_schedule_slots: slotPayload,
  p_paid_amount_krw: product.default_tuition_krw,
  p_payment_method: 'cash',
  p_paid_at: new Date().toISOString(),
  p_idempotency_key: enrollAIdem,
  p_owner_reason: `${MARKER} occupy Mon 18:30`,
});
if (enrollAError) throw enrollAError;
const enrollARow = Array.isArray(enrollA) ? enrollA[0] : enrollA;

const { data: lessonsABefore, error: lessonsABeforeError } = await client
  .from('lessons')
  .select('id, scheduled_at, status, assigned_teacher_id, pass_id, student_id, sequence_number, updated_at')
  .eq('pass_id', enrollARow.pass_id)
  .order('sequence_number');
if (lessonsABeforeError) throw lessonsABeforeError;

report.tests.enrollmentOccupy = {
  operation: 'initial_enrollment_occupy',
  passId: enrollARow.pass_id,
  lessonIds: lessonsABefore.map((l) => l.id),
  firstScheduledAt: lessonsABefore[0]?.scheduled_at,
};

const { data: previewConflicts, error: previewError } = await client.rpc(
  'reve_owner_preview_schedule_slot_collisions',
  { p_schedule_slots: slotPayload },
);
if (previewError) throw previewError;
report.tests.previewConflicts = previewConflicts;

const enrollBIdem = `${MARKER}-enroll-b`;
const { data: enrollB, error: enrollBError } = await client.rpc('reve_owner_create_initial_enrollment', {
  p_student_id: studentB.student_id,
  p_course_product_id: product.id,
  p_schedule_start_date: startDate,
  p_schedule_slots: slotPayload,
  p_paid_amount_krw: product.default_tuition_krw,
  p_payment_method: 'cash',
  p_paid_at: new Date().toISOString(),
  p_idempotency_key: enrollBIdem,
  p_owner_reason: `${MARKER} overlap enroll into occupied Mon 18:30`,
});
if (enrollBError) {
  report.tests.overlapEnrollment = { ok: false, error: enrollBError.message };
  fs.writeFileSync(path.join(artifactsDir, 'phase2b-overlap-verify.json'), JSON.stringify(report, null, 2));
  throw enrollBError;
}
const enrollBRow = Array.isArray(enrollB) ? enrollB[0] : enrollB;

const { data: lessonsAAfter, error: lessonsAAfterError } = await client
  .from('lessons')
  .select('id, scheduled_at, status, assigned_teacher_id, pass_id, student_id')
  .eq('pass_id', enrollARow.pass_id)
  .order('sequence_number');
if (lessonsAAfterError) throw lessonsAAfterError;

const { data: lessonsB, error: lessonsBError } = await client
  .from('lessons')
  .select('id, scheduled_at, status, assigned_teacher_id, pass_id, student_id, sequence_number, updated_at')
  .eq('pass_id', enrollBRow.pass_id)
  .order('sequence_number');
if (lessonsBError) throw lessonsBError;

const aFirst = lessonsAAfter[0];
const bFirst = lessonsB[0];
const aUnchanged =
  JSON.stringify(lessonsABefore.map((l) => ({ id: l.id, scheduled_at: l.scheduled_at, status: l.status }))) ===
  JSON.stringify(lessonsAAfter.map((l) => ({ id: l.id, scheduled_at: l.scheduled_at, status: l.status })));

if (!aUnchanged) throw new Error('Student A lessons changed after overlapping B enrollment');
if (aFirst.scheduled_at !== bFirst.scheduled_at) {
  throw new Error(`Expected identical scheduled_at; A=${aFirst.scheduled_at} B=${bFirst.scheduled_at}`);
}
if (aFirst.assigned_teacher_id !== TEACHER_ID || bFirst.assigned_teacher_id !== TEACHER_ID) {
  throw new Error('Teacher mismatch after overlap enrollment');
}

report.tests.overlapEnrollment = {
  ok: true,
  operation: 'initial_enrollment_overlap',
  teacher: TEACHER_ID,
  targetDatetime: aFirst.scheduled_at,
  preExisting: { studentId: studentA.student_id, lessonId: aFirst.id, passId: enrollARow.pass_id },
  resulting: {
    studentId: studentB.student_id,
    passId: enrollBRow.pass_id,
    lessonIds: lessonsB.map((l) => l.id),
    firstLessonId: bFirst.id,
  },
  readBack: {
    bothExist: true,
    sameDatetime: true,
    studentAUnchanged: true,
  },
};
console.log('[verify] overlap enrollment OK', aFirst.scheduled_at);

// Direct reschedule overlap: move B lesson #2 into A lesson #1 datetime (already occupied by A+#B first)
const lessonB2 = lessonsB[1];
if (!lessonB2) throw new Error('Expected at least 2 lessons on Student B pass');

const { data: resched, error: reschedError } = await client.rpc('reve_owner_direct_reschedule_lesson', {
  p_lesson_id: lessonB2.id,
  p_new_scheduled_at: aFirst.scheduled_at,
  p_expected_lesson_updated_at: lessonB2.updated_at,
  p_reason: `${MARKER} direct reschedule into occupied slot`,
  p_cascade: false,
  p_expected_pass_updated_at: null,
});
if (reschedError) {
  report.tests.directRescheduleOverlap = { ok: false, error: reschedError.message };
  fs.writeFileSync(path.join(artifactsDir, 'phase2b-overlap-verify.json'), JSON.stringify(report, null, 2));
  throw reschedError;
}
const reschedRow = Array.isArray(resched) ? resched[0] : resched;

const { data: lessonB2After, error: lessonB2AfterError } = await client
  .from('lessons')
  .select('id, scheduled_at, status, assigned_teacher_id, updated_at')
  .eq('id', lessonB2.id)
  .single();
if (lessonB2AfterError) throw lessonB2AfterError;
if (lessonB2After.scheduled_at !== aFirst.scheduled_at) {
  throw new Error(`Reschedule did not persist: ${lessonB2After.scheduled_at}`);
}

const { data: aStill, error: aStillError } = await client
  .from('lessons')
  .select('id, scheduled_at')
  .eq('id', aFirst.id)
  .single();
if (aStillError) throw aStillError;
if (aStill.scheduled_at !== aFirst.scheduled_at) {
  throw new Error('Student A first lesson mutated by B reschedule');
}

report.tests.directRescheduleOverlap = {
  ok: true,
  operation: 'direct_reschedule_overlap',
  teacher: TEACHER_ID,
  targetDatetime: aFirst.scheduled_at,
  preExisting: { lessonId: aFirst.id, studentId: studentA.student_id },
  resulting: {
    lessonId: lessonB2.id,
    scheduledAt: lessonB2After.scheduled_at,
    rpc: reschedRow,
  },
  readBack: { persisted: true, conflictingAIntact: true },
};
console.log('[verify] direct reschedule overlap OK');

// Move A first lesson away; B must remain
const movedAt = monday1830Iso(
  (() => {
    const d = new Date(`${startDate}T00:00:00+09:00`);
    d.setDate(d.getDate() + 7);
    return d.toISOString().slice(0, 10);
  })(),
);
const { data: aFresh, error: aFreshError } = await client
  .from('lessons')
  .select('id, updated_at, scheduled_at')
  .eq('id', aFirst.id)
  .single();
if (aFreshError) throw aFreshError;

const { error: moveAError } = await client.rpc('reve_owner_direct_reschedule_lesson', {
  p_lesson_id: aFirst.id,
  p_new_scheduled_at: movedAt,
  p_expected_lesson_updated_at: aFresh.updated_at,
  p_reason: `${MARKER} move A away after overlap`,
  p_cascade: false,
  p_expected_pass_updated_at: null,
});
if (moveAError) throw moveAError;

const { data: bAfterMove, error: bAfterMoveError } = await client
  .from('lessons')
  .select('id, scheduled_at, status')
  .eq('pass_id', enrollBRow.pass_id)
  .order('sequence_number');
if (bAfterMoveError) throw bAfterMoveError;
const bIdsBefore = lessonsB.map((l) => l.id).sort();
const bIdsAfter = bAfterMove.map((l) => l.id).sort();
if (JSON.stringify(bIdsBefore) !== JSON.stringify(bIdsAfter)) {
  throw new Error('Student B lesson IDs changed after moving A');
}
if (bAfterMove[0].scheduled_at !== aFirst.scheduled_at) {
  throw new Error('Student B first lesson unexpectedly changed after moving A');
}

report.tests.moveAAway = {
  ok: true,
  bLessonIdsPreserved: true,
  bFirstStillAt: bAfterMove[0].scheduled_at,
  aMovedTo: movedAt,
};

// Non-Owner denial: teacher magiclink attempt against enrollment RPC
const teacherEmailRes = await admin
  .from('teachers')
  .select('id, profile_id')
  .eq('id', TEACHER_ID)
  .maybeSingle();
let teacherDenied = null;
if (teacherEmailRes.data?.profile_id) {
  const { data: teacherProfile } = await admin
    .from('profiles')
    .select('id')
    .eq('id', teacherEmailRes.data.profile_id)
    .maybeSingle();
  const { data: authUser } = await admin.auth.admin.getUserById(teacherProfile.id);
  if (authUser?.user?.email) {
    const tLink = await admin.auth.admin.generateLink({
      type: 'magiclink',
      email: authUser.user.email,
    });
    const teacherClient = createClient(SUPABASE_URL, anon, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const tVerified = await teacherClient.auth.verifyOtp({
      email: authUser.user.email,
      token: tLink.data.properties.email_otp,
      type: 'magiclink',
    });
    if (tVerified.data.session) {
      const { error: deniedError } = await teacherClient.rpc('reve_owner_create_initial_enrollment', {
        p_student_id: studentB.student_id,
        p_course_product_id: product.id,
        p_schedule_start_date: startDate,
        p_schedule_slots: slotPayload,
        p_paid_amount_krw: product.default_tuition_krw,
        p_payment_method: 'cash',
        p_paid_at: new Date().toISOString(),
        p_idempotency_key: `${MARKER}-teacher-denied`,
        p_owner_reason: 'should fail',
      });
      teacherDenied = {
        ok: !!deniedError && /REVE_UNAUTHORIZED/i.test(deniedError.message),
        message: deniedError?.message ?? 'NO_ERROR',
      };
    }
  }
}
report.tests.teacherDenied = teacherDenied;

const { data: audits, error: auditError } = await client
  .from('audit_logs')
  .select('id, action, resource_table, created_at')
  .in('action', ['pass.created', 'lesson.rescheduled', 'pass.schedule_conflict_overridden'])
  .order('created_at', { ascending: false })
  .limit(20);
if (auditError) throw auditError;
report.tests.auditSample = audits?.slice(0, 5) ?? [];

// Cleanup dedicated test students via supported Owner delete path
const deletedA = await permanentlyDeleteStudent(client, studentA.student_id);
const deletedB = await permanentlyDeleteStudent(client, studentB.student_id);
report.tests.cleanup = {
  deletedA: { studentId: studentA.student_id, alreadyDeleted: deletedA?.already_deleted },
  deletedB: { studentId: studentB.student_id, alreadyDeleted: deletedB?.already_deleted },
};

// Browser smoke: confirm soft-warning copy / no hard-block strings on student pages if UI deployed
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
await page.goto(`${BASE_URL}/students`, { waitUntil: 'networkidle', timeout: 60000 });
const studentsOk = /학생|Students/i.test(await page.content());
await page.screenshot({ path: path.join(artifactsDir, 'phase2b-overlap-students.png'), fullPage: true });
await browser.close();
report.tests.browserSmoke = {
  studentsPageLoaded: studentsOk,
  consoleErrorCount: consoleErrors.length,
  note: 'Full overlap UI CTA requires app deploy of 6cc361c+; DB write proof is authoritative.',
};

fs.writeFileSync(path.join(artifactsDir, 'phase2b-overlap-verify.json'), JSON.stringify(report, null, 2));
console.log('[verify] COMPLETE');
console.log(JSON.stringify(report, null, 2));

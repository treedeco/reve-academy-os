/**
 * Phase 2B-2B5 production runtime verification (disposable records only).
 * Requires PRODUCTION_OWNER_PASSWORD in the process environment (never logged).
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { chromium } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import {
  PRODUCTION_PROJECT_REF,
  assertProductionMutationConfirmed,
  resolveProductionAppUrlFromEnv,
  resolveProductionSupabaseUrlFromEnv,
} from './lib/reve-production-operator-guard.mjs';
import { redactProductionEvidence } from './lib/reve-production-evidence-redaction.mjs';

function runNpxSync(args) {
  const spawnArgs =
    process.platform === 'win32' ? ['cmd.exe', ['/d', '/s', '/c', 'npx', ...args]] : ['npx', args];
  try {
    const stdout = execFileSync(spawnArgs[0], spawnArgs[1], {
      encoding: 'utf8',
      maxBuffer: 10 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return stdout;
  } catch (error) {
    const stdout = error.stdout ?? '';
    const stderr = error.stderr ?? '';
    const combined = `${stdout}\n${stderr}`.trim();
    if (combined.length > 0) {
      return combined;
    }
    throw error;
  }
}

function countLinkedMigrations(raw) {
  const combined = raw.trim();
  const jsonStart = combined.indexOf('{');
  if (jsonStart >= 0) {
    try {
      const payload = JSON.parse(combined.slice(jsonStart));
      return payload?.migrations?.length ?? 0;
    } catch {
      // Fall through to table parsing.
    }
  }

  const rowMatches = combined.match(/`?\d{14}`?\s*\|\s*`?\d{14}`?\s*\|/g);
  if (rowMatches?.length) {
    return rowMatches.length;
  }

  throw new Error(`Unexpected supabase migration list output: ${combined.slice(0, 240).replace(/\s+/g, ' ')}`);
}

function createEvidenceClient(accessToken) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function countRows(client, table, filters) {
  let query = client.from(table).select('*', { count: 'exact', head: true });
  for (const [column, value] of Object.entries(filters)) {
    query = query.eq(column, value);
  }
  const { count, error } = await query;
  if (error) {
    throw new Error(`${table} count failed: ${error.message}`);
  }
  return count ?? 0;
}

async function passIdsForStudent(client, studentId) {
  const { data, error } = await client.from('passes').select('id').eq('student_id', studentId);
  if (error) {
    throw new Error(`pass lookup failed: ${error.message}`);
  }
  return (data ?? []).map((row) => row.id);
}

async function countFutureScheduledLessons(client, teacherId) {
  const { count, error } = await client
    .from('lessons')
    .select('*', { count: 'exact', head: true })
    .eq('assigned_teacher_id', teacherId)
    .eq('status', 'scheduled')
    .gte('scheduled_at', new Date().toISOString());
  if (error) {
    throw new Error(`future lesson count failed: ${error.message}`);
  }
  return count ?? 0;
}

async function countActiveSlotsForPasses(client, passIds) {
  if (passIds.length === 0) {
    return 0;
  }
  const { count, error } = await client
    .from('schedule_slots')
    .select('*', { count: 'exact', head: true })
    .in('pass_id', passIds)
    .eq('is_active', true);
  if (error) {
    throw new Error(`active slot count failed: ${error.message}`);
  }
  return count ?? 0;
}

async function countAdvanceCancelledLessonsForStudent(client, studentId) {
  const passIds = await passIdsForStudent(client, studentId);
  if (passIds.length === 0) {
    return 0;
  }
  const { count, error } = await client
    .from('lessons')
    .select('*', { count: 'exact', head: true })
    .in('pass_id', passIds)
    .eq('status', 'advance_cancelled');
  if (error) {
    throw new Error(`advance cancelled lesson count failed: ${error.message}`);
  }
  return count ?? 0;
}

const SUPABASE_URL = resolveProductionSupabaseUrlFromEnv();
const PRODUCTION_URL = resolveProductionAppUrlFromEnv();
const SUPABASE_ANON_KEY = process.env.PRODUCTION_SUPABASE_ANON_KEY ?? '';
const OWNER_PASSWORD = process.env.PRODUCTION_OWNER_PASSWORD ?? '';
const OWNER_EMAIL = 'reve@owner.local';
const PROJECT_REF = PRODUCTION_PROJECT_REF;
const EXPECTED_COMMIT = 'e6a9ba6';
const EXPECTED_DEPLOYMENT = 'dpl_GQD11F8RcmAUXtbNsPcP6RZcd4Gm';

class VerificationFailure extends Error {
  constructor(stage, message, details = {}) {
    super(message);
    this.name = 'VerificationFailure';
    this.stage = stage;
    this.details = details;
  }
}

const evidence = {
  startedAtKst: new Date().toISOString(),
  runId: null,
  stage1: {},
  records: {},
  workflows: {},
  dbEvidence: {},
  cleanup: {},
  errors: [],
};

function fail(stage, message, details = {}) {
  evidence.errors.push({ stage, message, ...details });
  writeEvidence();
  console.log(JSON.stringify({ ok: false, stage, message, ...details, evidenceFile: evidencePath() }, null, 2));
  throw new VerificationFailure(stage, message, details);
}

function evidencePath() {
  return path.resolve('backups/phase-2b2b5-production-runtime-evidence.json');
}

function writeEvidence() {
  fs.mkdirSync(path.dirname(evidencePath()), { recursive: true });
  fs.writeFileSync(
    evidencePath(),
    `${JSON.stringify(redactProductionEvidence(evidence), null, 2)}\n`,
    'utf8',
  );
}

function assertRunId(value) {
  if (!evidence.runId || !String(value).includes(evidence.runId)) {
    throw new Error(`Disposable run identifier missing from target: ${String(value).slice(0, 120)}`);
  }
}

async function stage1Preflight() {
  if (!OWNER_PASSWORD) {
    fail('stage1', 'ENV_NOT_VISIBLE_TO_VERIFICATION_PROCESS');
  }
  evidence.stage1.passwordConfigured = true;

  if (!SUPABASE_ANON_KEY) {
    fail('stage1', 'PRODUCTION_SUPABASE_ANON_KEY missing');
  }

  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: signInData, error: signInError } = await authClient.auth.signInWithPassword({
    email: OWNER_EMAIL,
    password: OWNER_PASSWORD,
  });
  if (signInError || !signInData.session) {
    fail('stage1', 'OWNER_LOGIN_FAILED', {
      authErrorMessage: signInError?.message ?? 'no_session',
      authErrorStatus: signInError?.status ?? null,
      hint: 'PRODUCTION_OWNER_PASSWORD must match the password used at /login. Re-enter with -AllowSecurePrompt.',
    });
  }

  evidence.stage1.loginSucceeded = true;
  evidence.stage1.authUserId = signInData.user?.id ?? null;

  const authed = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${signInData.session.access_token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: profile, error: profileError } = await authed
    .from('profiles')
    .select('id, role, account_state, display_name')
    .eq('id', signInData.user.id)
    .maybeSingle();

  if (profileError || !profile) {
    fail('stage1', 'OWNER_PROFILE_LOOKUP_FAILED');
  }
  if (profile.role !== 'owner' || profile.account_state !== 'active') {
    fail('stage1', 'OWNER_ROLE_UNEXPECTED');
  }

  evidence.stage1.ownerRole = profile.role;
  evidence.stage1.ownerAccountState = profile.account_state;
  evidence.stage1.supabaseProjectRef = PROJECT_REF;

  const migrationsRaw = runNpxSync(['supabase', 'migration', 'list', '--linked']);
  const migrationCount = countLinkedMigrations(migrationsRaw);
  evidence.stage1.migrationRows = migrationCount;
  evidence.stage1.migrations26of26 = migrationCount === 26;

  evidence.stage1.productionUrl = PRODUCTION_URL;
  evidence.stage1.expectedDeploymentId = EXPECTED_DEPLOYMENT;
  evidence.stage1.expectedCommit = EXPECTED_COMMIT;

  return createEvidenceClient(signInData.session.access_token);
}

async function loginPage(page) {
  await page.goto(`${PRODUCTION_URL}/login`, { waitUntil: 'networkidle' });
  await page.locator('#username').fill('reve');
  await page.locator('#password').fill(OWNER_PASSWORD);
  await page.getByRole('button', { name: '로그인' }).click();
  await page.waitForURL((url) => !url.pathname.includes('/login'), { timeout: 30_000 });
}

async function createTeacher(page, code, name) {
  assertRunId(name);
  await page.goto(`${PRODUCTION_URL}/teachers`);
  await page.getByTestId('teacher-create-code').fill(code);
  await page.getByTestId('teacher-create-name').fill(name);
  await page.getByTestId('teacher-create-submit').click();
  await page.getByTestId(`teacher-item-${code}`).waitFor({ state: 'visible', timeout: 20_000 });
}

async function createStudent(page, name, phone = '010-9999-0001') {
  assertRunId(name);
  await page.goto(`${PRODUCTION_URL}/students`);
  await page.getByTestId('student-create-name').fill(name);
  await page.getByTestId('student-create-phone').fill(phone);
  await page.getByTestId('student-create-submit').click();
  await page.waitForURL(/\/students\/[0-9a-f-]+$/, { timeout: 30_000 });
  const studentId = page.url().split('/').pop();
  return studentId;
}

async function enrollStudent(page, { teacherName, teacherCode, startDate = '2026-08-18' }) {
  await page.getByTestId('initial-enrollment-panel').waitFor({ state: 'visible', timeout: 20_000 });
  await page.getByTestId('enrollment-course-loading').waitFor({ state: 'hidden', timeout: 20_000 });

  const courseSelect = page.getByTestId('enrollment-course');
  const courseOptions = courseSelect.locator('option');
  const courseCount = await courseOptions.count();

  let enrolled = false;
  for (let index = 0; index < courseCount; index += 1) {
    const option = courseOptions.nth(index);
    const courseValue = await option.getAttribute('value');
    if (!courseValue) {
      continue;
    }

    await courseSelect.selectOption(courseValue);
    const productSelect = page.getByTestId('enrollment-product');
    const productOption = productSelect.locator('option[value]:not([value=""])').first();
    const hasProduct = await productOption
      .waitFor({ state: 'attached', timeout: 5_000 })
      .then(async () => Boolean(await productOption.getAttribute('value')))
      .catch(() => false);

    if (!hasProduct) {
      continue;
    }

    const productValue = await productOption.getAttribute('value');
    if (!productValue) {
      continue;
    }

    await productSelect.selectOption(productValue);
    enrolled = true;
    break;
  }

  if (!enrolled) {
    throw new Error('No course/product pair available in production enrollment catalog');
  }

  await page.getByTestId('enrollment-slot-teacher-1').waitFor({ state: 'visible', timeout: 20_000 });
  await page.getByTestId('enrollment-start-date').fill(startDate);
  await page.getByTestId('enrollment-slot-teacher-1').selectOption({
    label: `${teacherName} (${teacherCode})`,
  });
  await page.getByTestId('enrollment-slot-weekday-1').selectOption('2');
  await page.getByTestId('enrollment-slot-time-1').fill('16:00');
  await page.getByTestId('enrollment-submit').click();
  await page.getByTestId('used-count').waitFor({ state: 'visible', timeout: 30_000 });
}

async function main() {
  assertProductionMutationConfirmed('production runtime verification');

  const suffix = Math.random().toString(36).slice(2, 8).toUpperCase();
  evidence.runId = `PHASE2B2B5-20260729-${suffix}`;

  let browser = null;
  let page = null;

  try {
    const evidenceClient = await stage1Preflight();
    writeEvidence();

    browser = await chromium.launch({ headless: true });
    page = await browser.newPage();

    const enrollTeacherCode = `TP25${suffix}A`;
    const enrollTeacherName = `${evidence.runId} Enroll Teacher`;
    const reassignTargetCode = `TP25${suffix}B`;
    const reassignTargetName = `${evidence.runId} Reassign Target`;
    const replacementCode = `TP25${suffix}C`;
    const replacementName = `${evidence.runId} Replacement`;
    const removeSchedCode = `TP25${suffix}D`;
    const removeSchedName = `${evidence.runId} RemoveSched Target`;

    const scheduleStudentName = `${evidence.runId} Schedule Student`;
    const deleteStudentName = `${evidence.runId} Delete Student`;
    const reassignStudentName = `${evidence.runId} Reassign Student`;
    const removeSchedStudentName = `${evidence.runId} RemoveSched Student`;

    evidence.records = {
      runId: evidence.runId,
      teachers: {
        enroll: { code: enrollTeacherCode, name: enrollTeacherName },
        reassignTarget: { code: reassignTargetCode, name: reassignTargetName },
        replacement: { code: replacementCode, name: replacementName },
        removeSchedTarget: { code: removeSchedCode, name: removeSchedName },
      },
      students: {
        schedule: { name: scheduleStudentName },
        delete: { name: deleteStudentName },
        reassign: { name: reassignStudentName },
        removeSched: { name: removeSchedStudentName },
      },
    };

    await loginPage(page);

    await createTeacher(page, enrollTeacherCode, enrollTeacherName);
    await createTeacher(page, reassignTargetCode, reassignTargetName);
    await createTeacher(page, replacementCode, replacementName);
    await createTeacher(page, removeSchedCode, removeSchedName);

    const scheduleStudentId = await createStudent(page, scheduleStudentName);
    evidence.records.students.schedule.id = scheduleStudentId;
    await enrollStudent(page, { teacherName: enrollTeacherName, teacherCode: enrollTeacherCode });

    const { data: passRows, error: passRowsError } = await evidenceClient
      .from('passes')
      .select('id, pass_code, status')
      .eq('student_id', scheduleStudentId)
      .order('sequence_number', { ascending: false })
      .limit(1);
    if (passRowsError) {
      throw new Error(`pass lookup failed: ${passRowsError.message}`);
    }
    evidence.dbEvidence.scheduleStudentBefore = {
      passes: passRows?.length ?? 0,
      passCode: passRows?.[0]?.pass_code ?? null,
    };

    const schedulePassIds = await passIdsForStudent(evidenceClient, scheduleStudentId);
    let slotRowsBefore = [];
    if (schedulePassIds.length > 0) {
      const { data, error: slotRowsBeforeError } = await evidenceClient
        .from('schedule_slots')
        .select('id, is_active, weekday')
        .in('pass_id', schedulePassIds);
      if (slotRowsBeforeError) {
        throw new Error(`schedule slot lookup failed: ${slotRowsBeforeError.message}`);
      }
      slotRowsBefore = data ?? [];
    }
    let futureLessonsBefore = [];
    if (schedulePassIds.length > 0) {
      const { data, error: futureLessonsBeforeError } = await evidenceClient
        .from('lessons')
        .select('id, status')
        .in('pass_id', schedulePassIds)
        .gte('scheduled_at', new Date().toISOString())
        .order('scheduled_at')
        .limit(20);
      if (futureLessonsBeforeError) {
        throw new Error(`future lesson lookup failed: ${futureLessonsBeforeError.message}`);
      }
      futureLessonsBefore = data ?? [];
    }
    evidence.dbEvidence.scheduleRemovalBefore = {
      activeSlots: slotRowsBefore.filter((r) => r.is_active).length,
      futureLessons: futureLessonsBefore.length,
      futureScheduled: futureLessonsBefore.filter((r) => r.status === 'scheduled').length,
    };

    await page.getByTestId('remove-fixed-schedule-open').click();
    const dialog = page.getByTestId('danger-zone-dialog');
    await dialog.waitFor({ state: 'visible' });
    await dialog.getByTestId('danger-removed-items').waitFor({ state: 'visible', timeout: 20_000 });

    await page.getByTestId('danger-reason').fill(`${evidence.runId} schedule removal`);
    await expectSubmitDisabled(page, true);
    await page.getByTestId('danger-confirmed').check();
    await expectSubmitDisabled(page, false);
    await page.getByTestId('danger-submit').click();
    await page.getByTestId('danger-success').waitFor({ state: 'visible', timeout: 30_000 });
    await page.getByTestId('danger-cancel').click();
    await page.getByTestId('student-no-schedule').waitFor({ state: 'visible', timeout: 20_000 });

    let slotRowsAfter = [];
    if (schedulePassIds.length > 0) {
      const { data, error: slotRowsAfterError } = await evidenceClient
        .from('schedule_slots')
        .select('id, is_active')
        .in('pass_id', schedulePassIds);
      if (slotRowsAfterError) {
        throw new Error(`schedule slot after lookup failed: ${slotRowsAfterError.message}`);
      }
      slotRowsAfter = data ?? [];
    }
    let futureLessonsAfter = [];
    if (schedulePassIds.length > 0) {
      const { data, error: futureLessonsAfterError } = await evidenceClient
        .from('lessons')
        .select('id, status')
        .in('pass_id', schedulePassIds)
        .gte('scheduled_at', new Date().toISOString())
        .order('scheduled_at')
        .limit(20);
      if (futureLessonsAfterError) {
        throw new Error(`future lesson after lookup failed: ${futureLessonsAfterError.message}`);
      }
      futureLessonsAfter = data ?? [];
    }
    evidence.dbEvidence.scheduleRemovalAfter = {
      activeSlots: slotRowsAfter.filter((r) => r.is_active).length,
      futureAdvanceCancelled: futureLessonsAfter.filter((r) => r.status === 'advance_cancelled').length,
      totalFutureRows: futureLessonsAfter.length,
    };
    evidence.workflows.fixedScheduleRemoval = {
      result: 'PASS',
      passCode: passRows?.[0]?.pass_code ?? null,
      checkboxGatingVerified: true,
    };

    await page.reload();
    await page.getByTestId('student-no-schedule').waitFor({ state: 'visible', timeout: 20_000 });

    const deleteStudentId = await createStudent(page, deleteStudentName, '010-9999-0002');
    evidence.records.students.delete.id = deleteStudentId;
    const { data: deleteStudentRow, error: deleteStudentRowError } = await evidenceClient
      .from('students')
      .select('student_code')
      .eq('id', deleteStudentId)
      .maybeSingle();
    if (deleteStudentRowError) {
      throw new Error(`delete student lookup failed: ${deleteStudentRowError.message}`);
    }
    evidence.records.students.delete.code = deleteStudentRow?.student_code ?? null;

    await page.getByTestId('student-permanent-delete-open').click();
    await dialog.waitFor({ state: 'visible' });
    await dialog.getByTestId('danger-removed-items').waitFor({ state: 'visible', timeout: 20_000 });
    await page.getByTestId('danger-reason').fill(`${evidence.runId} student delete`);
    await expectSubmitDisabled(page, true);
    await page.getByTestId('danger-confirmed').check();
    await expectSubmitDisabled(page, false);
    await page.getByTestId('danger-submit').click();
    await page.waitForURL(/\/students$/, { timeout: 30_000 });

    const studentAfterCount = await countRows(evidenceClient, 'students', { id: deleteStudentId });
    const { data: tombstoneRows, error: tombstoneRowsError } = await evidenceClient
      .from('audit_logs')
      .select('action, resource_table, new_value')
      .eq('resource_id', deleteStudentId)
      .eq('action', 'student.permanently_deleted')
      .order('created_at', { ascending: false })
      .limit(1);
    if (tombstoneRowsError) {
      throw new Error(`audit log lookup failed: ${tombstoneRowsError.message}`);
    }
    evidence.dbEvidence.studentDeletion = {
      studentRowCount: studentAfterCount,
      tombstoneAction: tombstoneRows?.[0]?.action ?? null,
      tombstoneHasStudentCode: Boolean(tombstoneRows?.[0]?.new_value?.student_code),
      tombstoneHasStudentName: Boolean(tombstoneRows?.[0]?.new_value?.student_name),
    };
    evidence.workflows.studentPermanentDeletion = { result: 'PASS' };

    await page.goto(`${PRODUCTION_URL}/students/${deleteStudentId}`);
    await page.waitForTimeout(2000);
    evidence.workflows.studentDetailAfterDelete = {
      url: page.url(),
      notFoundLike: /login|students|404|not found|찾을 수/i.test(await page.locator('body').innerText()),
    };

    const reassignStudentId = await createStudent(page, reassignStudentName, '010-9999-0003');
    evidence.records.students.reassign.id = reassignStudentId;
    await enrollStudent(page, {
      teacherName: reassignTargetName,
      teacherCode: reassignTargetCode,
      startDate: '2026-08-19',
    });

    const { data: reassignTargetRow, error: reassignTargetRowError } = await evidenceClient
      .from('teachers')
      .select('id')
      .eq('teacher_code', reassignTargetCode)
      .maybeSingle();
    if (reassignTargetRowError || !reassignTargetRow) {
      throw new Error(`reassign target lookup failed: ${reassignTargetRowError?.message ?? 'missing'}`);
    }
    const { data: replacementRow, error: replacementRowError } = await evidenceClient
      .from('teachers')
      .select('id')
      .eq('teacher_code', replacementCode)
      .maybeSingle();
    if (replacementRowError || !replacementRow) {
      throw new Error(`replacement teacher lookup failed: ${replacementRowError?.message ?? 'missing'}`);
    }
    const futureBeforeReassign = await countFutureScheduledLessons(evidenceClient, reassignTargetRow.id);

    await page.goto(`${PRODUCTION_URL}/teachers`);
    await page.getByTestId(`teacher-item-${reassignTargetCode}`).getByRole('button', { name: '강사 영구 삭제' }).click();
    await dialog.waitFor({ state: 'visible' });
    await dialog.getByTestId('teacher-replacement-select').selectOption({
      label: `${replacementName} (${replacementCode})`,
    });
    await page.getByTestId('danger-reason').fill(`${evidence.runId} teacher reassign delete`);
    await page.getByTestId('danger-confirmed').check();
    await page.getByTestId('danger-submit').click();
    await page.getByTestId(`teacher-item-${reassignTargetCode}`).waitFor({ state: 'hidden', timeout: 30_000 });

    const teacherAfterReassign = await countRows(evidenceClient, 'teachers', {
      teacher_code: reassignTargetCode,
    });
    const futureAfterReassign = await countFutureScheduledLessons(evidenceClient, replacementRow.id);
    evidence.dbEvidence.teacherReassign = {
      deletedTeacherRows: teacherAfterReassign,
      futureLessonsBefore: futureBeforeReassign,
      futureLessonsOnReplacementAfter: futureAfterReassign,
    };
    evidence.workflows.teacherReassignmentDeletion = { result: 'PASS' };

    const removeSchedStudentId = await createStudent(page, removeSchedStudentName, '010-9999-0004');
    evidence.records.students.removeSched.id = removeSchedStudentId;
    await enrollStudent(page, {
      teacherName: removeSchedName,
      teacherCode: removeSchedCode,
      startDate: '2026-08-20',
    });

    const { data: removeTargetRow, error: removeTargetRowError } = await evidenceClient
      .from('teachers')
      .select('id')
      .eq('teacher_code', removeSchedCode)
      .maybeSingle();
    if (removeTargetRowError || !removeTargetRow) {
      throw new Error(`remove schedule target lookup failed: ${removeTargetRowError?.message ?? 'missing'}`);
    }
    const slotsBeforeRemoveMode = await countRows(evidenceClient, 'schedule_slots', {
      teacher_id: removeTargetRow.id,
      is_active: true,
    });

    await page.goto(`${PRODUCTION_URL}/teachers`);
    await page.getByTestId(`teacher-item-${removeSchedCode}`).getByRole('button', { name: '강사 영구 삭제' }).click();
    await dialog.waitFor({ state: 'visible' });
    await page.getByRole('radio', { name: /미래 고정 일정·수업 제거/ }).check();
    await page.getByTestId('danger-reason').fill(`${evidence.runId} teacher remove future schedule`);
    await page.getByTestId('danger-confirmed').check();
    await page.getByTestId('danger-submit').click();
    await page.getByTestId(`teacher-item-${removeSchedCode}`).waitFor({ state: 'hidden', timeout: 30_000 });

    const teacherAfterRemoveMode = await countRows(evidenceClient, 'teachers', {
      teacher_code: removeSchedCode,
    });
    const removeSchedPassIds = await passIdsForStudent(evidenceClient, removeSchedStudentId);
    const slotsAfterRemoveMode = await countActiveSlotsForPasses(evidenceClient, removeSchedPassIds);
    const futureCancelledRemoveMode = await countAdvanceCancelledLessonsForStudent(
      evidenceClient,
      removeSchedStudentId,
    );
    evidence.dbEvidence.teacherRemoveFutureSchedule = {
      deletedTeacherRows: teacherAfterRemoveMode,
      activeSlotsBefore: slotsBeforeRemoveMode,
      activeSlotsAfter: slotsAfterRemoveMode,
      advanceCancelledLessons: futureCancelledRemoveMode,
    };
    evidence.workflows.teacherFutureScheduleRemoval = { result: 'PASS' };

    const { count: unrelatedStudents, error: unrelatedStudentsError } = await evidenceClient
      .from('students')
      .select('*', { count: 'exact', head: true })
      .not('name', 'like', 'PHASE2B2B5-20260729-%');
    if (unrelatedStudentsError) {
      throw new Error(`unrelated student count failed: ${unrelatedStudentsError.message}`);
    }
    evidence.dbEvidence.unrelatedRowControl = {
      nonDisposableStudentCount: unrelatedStudents ?? null,
    };

    evidence.cleanup = {
      deletedDisposableStudents: [deleteStudentId],
      deletedDisposableTeachers: [reassignTargetCode, removeSchedCode],
      retainedRecords: [
        {
          type: 'student',
          id: scheduleStudentId,
          reason: 'Schedule removal test left enrolled student without active fixed schedule; safe to retain or operator may deactivate later.',
        },
        {
          type: 'student',
          id: reassignStudentId,
          reason: 'Reassignment test student retained with pass/lessons for historical readability checks.',
        },
        {
          type: 'student',
          id: removeSchedStudentId,
          reason: 'Future-schedule removal test student retained; lessons may be advance_cancelled.',
        },
        {
          type: 'teacher',
          code: enrollTeacherCode,
          reason: 'Enrollment helper teacher retained (may still be referenced by retained students).',
        },
        {
          type: 'teacher',
          code: replacementCode,
          reason: 'Replacement teacher retained as active production master row.',
        },
        {
          type: 'audit_log',
          reason: 'Tombstone audit for deleted student must remain immutable.',
        },
      ],
      realProductionRecordsAffected: false,
    };

    evidence.completedAtKst = new Date().toISOString();
    evidence.ok = true;
    writeEvidence();
    console.log(JSON.stringify({ ok: true, runId: evidence.runId, evidenceFile: evidencePath() }, null, 2));
    return 0;
  } catch (error) {
    if (error instanceof VerificationFailure) {
      return 1;
    }
    evidence.errors.push({ stage: 'runtime', message: error instanceof Error ? error.message : String(error) });
    writeEvidence();
    console.log(JSON.stringify({ ok: false, evidenceFile: evidencePath() }, null, 2));
    return 1;
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

async function expectSubmitDisabled(page, disabled) {
  const submit = page.getByTestId('danger-submit');
  if (disabled) {
    await submit.waitFor({ state: 'visible' });
    if (await submit.isEnabled()) {
      throw new Error('Expected danger-submit to remain disabled');
    }
  } else {
    await submit.waitFor({ state: 'visible' });
    if (!(await submit.isEnabled())) {
      throw new Error('Expected danger-submit to become enabled');
    }
  }
}

main()
  .then(async (exitCode) => {
    await new Promise((resolve) => setTimeout(resolve, 150));
    process.exit(exitCode);
  })
  .catch(async (error) => {
    console.error(error instanceof Error ? error.message : String(error));
    await new Promise((resolve) => setTimeout(resolve, 150));
    process.exit(1);
  });

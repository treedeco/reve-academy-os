/**
 * Dry-run (default) or apply cleanup for production disposable Phase 2B-2B5 records.
 *
 * Requires:
 *   PRODUCTION_SUPABASE_URL / PRODUCTION_SUPABASE_ANON_KEY / PRODUCTION_OWNER_PASSWORD
 *
 * Apply additionally requires:
 *   REVE_CONFIRM_PRODUCTION=1
 *   REVE_CLEANUP_APPLY_RUN_ID=<run id printed by dry-run>
 */
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DISPOSABLE_NAME_PREFIX,
  assertDisposableName,
  assertProductionMutationConfirmed,
  resolveProductionAppUrlFromEnv,
  resolveProductionSupabaseUrlFromEnv,
} from './lib/reve-production-operator-guard.mjs';
import { redactProductionEvidence, redactUuid } from './lib/reve-production-evidence-redaction.mjs';
import { logStage } from './lib/reve-production-operator-io.mjs';
import {
  createProductionOwnerSession,
  permanentlyDeleteStudent,
  permanentlyDeleteTeacher,
  previewDeleteStudent,
  previewDeleteTeacher,
} from './lib/reve-production-owner-session.mjs';

export function buildCleanupRunId(date = new Date()) {
  const stamp = date.toISOString().slice(0, 10).replace(/-/g, '');
  return `CLEANUP-PHASE2B2B5-${stamp}-${randomUUID().slice(0, 6).toUpperCase()}`;
}

async function countNonDisposableStudents(client) {
  logStage('candidate_query_start', 'non_disposable_student_count');
  const { count, error } = await client
    .from('students')
    .select('*', { count: 'exact', head: true })
    .not('name', 'like', `${DISPOSABLE_NAME_PREFIX}%`);
  if (error) {
    throw new Error(`non-disposable student count failed: ${error.message}`);
  }
  logStage('candidate_query_complete', 'non_disposable_student_count');
  return count ?? 0;
}

async function loadDisposableStudents(client) {
  logStage('candidate_query_start', 'disposable_students');
  const { data, error } = await client
    .from('students')
    .select('id, name, student_code, updated_at')
    .like('name', `${DISPOSABLE_NAME_PREFIX}%`)
    .order('name');
  if (error) {
    throw new Error(`disposable student lookup failed: ${error.message}`);
  }
  logStage('candidate_query_complete', 'disposable_students');
  return data ?? [];
}

async function loadDisposableTeachers(client) {
  logStage('candidate_query_start', 'disposable_teachers');
  const { data, error } = await client
    .from('teachers')
    .select('id, teacher_code, name, updated_at, is_active')
    .like('name', `${DISPOSABLE_NAME_PREFIX}%`)
    .order('name');
  if (error) {
    throw new Error(`disposable teacher lookup failed: ${error.message}`);
  }
  logStage('candidate_query_complete', 'disposable_teachers');
  return data ?? [];
}

async function buildStudentPlan(client, student) {
  assertDisposableName(student.name, 'student');
  const preview = await previewDeleteStudent(client, student.id);
  return {
    kind: 'student',
    id: student.id,
    name: student.name,
    code: student.student_code,
    updatedAt: student.updated_at,
    preview,
    action: 'reve_owner_permanently_delete_student',
  };
}

async function buildTeacherPlan(client, teacher) {
  assertDisposableName(teacher.name, 'teacher');
  const preview = await previewDeleteTeacher(client, teacher.id);
  const linkHandlingMode = 'remove_future_schedule';
  return {
    kind: 'teacher',
    id: teacher.id,
    name: teacher.name,
    code: teacher.teacher_code,
    updatedAt: teacher.updated_at,
    preview,
    linkHandlingMode,
    action: 'reve_owner_permanently_delete_teacher',
  };
}

function assertPlanSafety(plan, baselineNonDisposableCount, currentNonDisposableCount) {
  for (const row of plan.students) {
    assertDisposableName(row.name, 'student');
  }
  for (const row of plan.teachers) {
    assertDisposableName(row.name, 'teacher');
  }
  if (currentNonDisposableCount !== baselineNonDisposableCount) {
    throw new Error(
      `Safety check failed: non-disposable student count changed (${baselineNonDisposableCount} -> ${currentNonDisposableCount}).`,
    );
  }
}

async function applyPlan(client, plan, runId) {
  const reason = `${runId} disposable production cleanup`;
  const results = [];

  for (const row of plan.students) {
    const confirmationCode = `${row.code} 영구삭제`;
    const result = await permanentlyDeleteStudent(client, {
      studentId: row.id,
      expectedUpdatedAt: row.updatedAt,
      confirmationCode,
      reason,
      preflightFingerprint: row.preview.preflight_fingerprint,
    });
    results.push({ kind: 'student', id: row.id, alreadyDeleted: result.already_deleted });
  }

  for (const row of plan.teachers) {
    const confirmationCode = `${row.code} 영구삭제`;
    const result = await permanentlyDeleteTeacher(client, {
      teacherId: row.id,
      expectedUpdatedAt: row.updatedAt,
      linkHandlingMode: row.linkHandlingMode,
      replacementTeacherId: null,
      confirmationCode,
      reason,
      preflightFingerprint: row.preview.preflight_fingerprint,
    });
    results.push({ kind: 'teacher', id: row.id, alreadyDeleted: result.already_deleted });
  }

  return results;
}

function summarizePlan(plan) {
  return {
    students: plan.students.map((row) => ({
      name: row.name,
      code: row.code,
      id: redactUuid(row.id),
      lessons: row.preview.lesson_count,
      passes: row.preview.pass_count,
      payments: row.preview.payment_count,
      sms: row.preview.sms_notification_count,
      scheduleSlots: row.preview.schedule_slot_count,
      scheduleChanges: row.preview.schedule_change_request_count,
      lessonNotes: row.preview.lesson_note_count,
      action: row.action,
    })),
    teachers: plan.teachers.map((row) => ({
      name: row.name,
      code: row.code,
      id: redactUuid(row.id),
      futureLessons: row.preview.future_eligible_lesson_count,
      activeScheduleSlots: row.preview.active_schedule_slot_count,
      linkHandlingMode: row.linkHandlingMode,
      action: row.action,
    })),
  };
}

export async function runCleanupProductionDisposables({
  apply = false,
  applyRunId = '',
  buildRunId = buildCleanupRunId,
  createSession = createProductionOwnerSession,
  outputWriter = (payload) => {
    console.log(JSON.stringify(redactProductionEvidence(payload), null, 2));
  },
} = {}) {
  logStage('cleanup_start', apply ? 'apply' : 'dry-run');
  resolveProductionSupabaseUrlFromEnv();
  resolveProductionAppUrlFromEnv();
  logStage('production_guard_complete');

  const runId = apply ? applyRunId : buildRunId();
  if (apply && !runId) {
    throw new Error('Apply requires REVE_CLEANUP_APPLY_RUN_ID from a prior dry-run.');
  }

  const { client } = await createSession();

  const baselineNonDisposableCount = await countNonDisposableStudents(client);
  const disposableStudents = await loadDisposableStudents(client);
  const disposableTeachers = await loadDisposableTeachers(client);

  logStage('dry_run_result_build_start');
  const studentPlans = [];
  for (const student of disposableStudents) {
    studentPlans.push(await buildStudentPlan(client, student));
  }

  const teacherPlans = [];
  for (const teacher of disposableTeachers) {
    teacherPlans.push(await buildTeacherPlan(client, teacher));
  }

  const plan = { students: studentPlans, teachers: teacherPlans };
  const currentNonDisposableCount = await countNonDisposableStudents(client);
  assertPlanSafety(plan, baselineNonDisposableCount, currentNonDisposableCount);
  logStage('dry_run_result_build_complete');

  const payload = {
    ok: true,
    mode: apply ? 'apply' : 'dry-run',
    runId,
    disposablePrefix: DISPOSABLE_NAME_PREFIX,
    nonDisposableStudentCount: baselineNonDisposableCount,
    totals: {
      students: plan.students.length,
      teachers: plan.teachers.length,
    },
    plan: summarizePlan(plan),
  };

  if (!apply) {
    payload.nextStep = {
      applyRequires: ['REVE_CONFIRM_PRODUCTION=1', `REVE_CLEANUP_APPLY_RUN_ID=${runId}`, '--apply'],
      runnerExample:
        'powershell -ExecutionPolicy Bypass -File scripts/run_cleanup_phase_2b2b5_production_disposables.ps1 -ConfirmProduction -Apply -RunId <runId>',
    };
    logStage('output_write_start');
    outputWriter(payload);
    logStage('output_write_complete');
    logStage('cleanup_complete');
    return 0;
  }

  if (!applyRunId || applyRunId !== runId) {
    throw new Error(
      'Apply requires REVE_CLEANUP_APPLY_RUN_ID matching the dry-run runId for this invocation.',
    );
  }

  assertProductionMutationConfirmed('disposable cleanup apply');
  const applyResults = await applyPlan(client, plan, runId);
  const afterStudents = await loadDisposableStudents(client);
  const afterTeachers = await loadDisposableTeachers(client);
  const afterNonDisposableCount = await countNonDisposableStudents(client);
  if (afterNonDisposableCount !== baselineNonDisposableCount) {
    throw new Error(
      `Safety check failed after apply: non-disposable student count changed (${baselineNonDisposableCount} -> ${afterNonDisposableCount}).`,
    );
  }

  payload.applyResults = applyResults.map((row) => ({ ...row, id: redactUuid(row.id) }));
  payload.remaining = {
    students: afterStudents.length,
    teachers: afterTeachers.length,
  };
  payload.completedAt = new Date().toISOString();
  logStage('output_write_start');
  outputWriter(payload);
  logStage('output_write_complete');
  logStage('cleanup_complete');
  return 0;
}

const isDirectExecution =
  process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectExecution) {
  const APPLY = process.argv.includes('--apply');
  const APPLY_RUN_ID = process.env.REVE_CLEANUP_APPLY_RUN_ID ?? '';

  runCleanupProductionDisposables({ apply: APPLY, applyRunId: APPLY_RUN_ID })
    .then((exitCode) => {
      process.exit(exitCode);
    })
    .catch((error) => {
      logStage('cleanup_failed');
      console.log(
        JSON.stringify(
          {
            ok: false,
            message: error instanceof Error ? error.message : String(error),
          },
          null,
          2,
        ),
      );
      process.exit(1);
    });
}

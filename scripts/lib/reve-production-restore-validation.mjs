/**
 * Deterministic post-restore validation queries and manifest comparison.
 */
import {
  EXPECTED_MIGRATION_COUNT,
  REQUIRED_PUBLIC_TABLES,
  RLS_REQUIRED_TABLES,
} from './reve-production-backup-contract.mjs';

export const RESTORE_VALIDATION_QUERIES = Object.freeze({
  publicTableCount: `
    SELECT count(*)::int AS table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE';
  `,
  requiredTablesPresent: `
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
      AND table_name = ANY($1::text[])
    ORDER BY table_name;
  `,
  migrationCount: `
    SELECT count(*)::int AS migration_count
    FROM supabase_migrations.schema_migrations;
  `,
  latestMigrationVersion: `
    SELECT version
    FROM supabase_migrations.schema_migrations
    ORDER BY version DESC
    LIMIT 1;
  `,
  rowCounts: `
    SELECT table_name, count_value
    FROM (
      SELECT 'profiles'::text AS table_name, (SELECT count(*)::bigint FROM public.profiles) AS count_value
      UNION ALL SELECT 'students', (SELECT count(*)::bigint FROM public.students)
      UNION ALL SELECT 'teachers', (SELECT count(*)::bigint FROM public.teachers)
      UNION ALL SELECT 'courses', (SELECT count(*)::bigint FROM public.courses)
      UNION ALL SELECT 'course_products', (SELECT count(*)::bigint FROM public.course_products)
      UNION ALL SELECT 'passes', (SELECT count(*)::bigint FROM public.passes)
      UNION ALL SELECT 'schedule_slots', (SELECT count(*)::bigint FROM public.schedule_slots)
      UNION ALL SELECT 'lessons', (SELECT count(*)::bigint FROM public.lessons)
      UNION ALL SELECT 'payments', (SELECT count(*)::bigint FROM public.payments)
      UNION ALL SELECT 'payment_refunds', (SELECT count(*)::bigint FROM public.payment_refunds)
      UNION ALL SELECT 'sms_notifications', (SELECT count(*)::bigint FROM public.sms_notifications)
      UNION ALL SELECT 'schedule_change_requests', (SELECT count(*)::bigint FROM public.schedule_change_requests)
      UNION ALL SELECT 'lesson_schedule_changes', (SELECT count(*)::bigint FROM public.lesson_schedule_changes)
      UNION ALL SELECT 'lesson_notes', (SELECT count(*)::bigint FROM public.lesson_notes)
      UNION ALL SELECT 'audit_logs', (SELECT count(*)::bigint FROM public.audit_logs)
    ) counts
    ORDER BY table_name;
  `,
  foreignKeyViolations: `
    SELECT conrelid::regclass::text AS table_name, conname
    FROM pg_constraint
    WHERE contype = 'f'
      AND connamespace = 'public'::regnamespace
      AND NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        WHERE c.oid = pg_constraint.oid
      );
  `,
  fkIntegrityProbe: `
    SELECT
      (SELECT count(*)::int FROM public.lessons l
        LEFT JOIN public.passes p ON p.id = l.pass_id
        WHERE p.id IS NULL) AS orphan_lessons_by_pass,
      (SELECT count(*)::int FROM public.lessons l
        LEFT JOIN public.students s ON s.id = l.student_id
        WHERE s.id IS NULL) AS orphan_lessons_by_student,
      (SELECT count(*)::int FROM public.lessons l
        LEFT JOIN public.teachers t ON t.id = l.assigned_teacher_id
        WHERE t.id IS NULL) AS orphan_lessons_by_teacher,
      (SELECT count(*)::int FROM public.payments p
        LEFT JOIN public.passes ps ON ps.id = p.pass_id
        WHERE ps.id IS NULL) AS orphan_payments_by_pass,
      (SELECT count(*)::int FROM public.schedule_slots ss
        LEFT JOIN public.passes p ON p.id = ss.pass_id
        WHERE p.id IS NULL) AS orphan_schedule_slots_by_pass,
      (SELECT count(*)::int FROM public.sms_notifications sn
        LEFT JOIN public.passes p ON p.id = sn.pass_id
        WHERE p.id IS NULL) AS orphan_sms_by_pass;
  `,
  activePassUniqueness: `
    SELECT student_id, course_id, count(*)::int AS active_count
    FROM public.passes
    WHERE status = 'active'
    GROUP BY student_id, course_id
    HAVING count(*) > 1;
  `,
  reservedPassUniqueness: `
    SELECT student_id, course_id, count(*)::int AS reserved_count
    FROM public.passes
    WHERE status = 'reserved'
    GROUP BY student_id, course_id
    HAVING count(*) > 1;
  `,
  passUsageConsistency: `
    SELECT p.id AS pass_id,
      p.registered_lesson_count_snapshot AS registered,
      count(l.id)::int AS lesson_count
    FROM public.passes p
    LEFT JOIN public.lessons l ON l.pass_id = p.id
    GROUP BY p.id, p.registered_lesson_count_snapshot
    HAVING count(l.id) > p.registered_lesson_count_snapshot + 50;
  `,
  paymentsPassLinkage: `
    SELECT count(*)::int AS completed_without_pass
    FROM public.payments
    WHERE status = 'completed'
      AND pass_id IS NULL;
  `,
  scheduleSlotsActiveLessons: `
    SELECT count(*)::int AS active_slots_without_pass
    FROM public.schedule_slots ss
    LEFT JOIN public.passes p ON p.id = ss.pass_id
    WHERE p.id IS NULL;
  `,
  smsNotificationLinkage: `
    SELECT count(*)::int AS sms_without_pass
    FROM public.sms_notifications sn
    LEFT JOIN public.passes p ON p.id = sn.pass_id
    WHERE p.id IS NULL;
  `,
  auditLogPresence: `
    SELECT count(*)::int AS audit_log_count
    FROM public.audit_logs;
  `,
  rlsEnabled: `
    SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname = ANY($1::text[])
    ORDER BY c.relname;
  `,
  ownerAuthPresence: `
    SELECT count(*)::int AS owner_auth_users
    FROM auth.users
    WHERE lower(email) = 'reve@owner.local';
  `,
  ownerProfilePresence: `
    SELECT count(*)::int AS active_owner_profiles
    FROM public.profiles
    WHERE role = 'owner'
      AND account_state = 'active';
  `,
  rlsPolicyCount: `
    SELECT count(*)::int AS public_policy_count
    FROM pg_policies
    WHERE schemaname = 'public';
  `,
});

export function buildRestoreValidationReport(rawResults) {
  return {
    publicTableCount: rawResults.publicTableCount?.table_count ?? null,
    requiredTablesPresent: rawResults.requiredTablesPresent ?? [],
    migrationCount: rawResults.migrationCount?.migration_count ?? null,
    latestMigrationVersion: rawResults.latestMigrationVersion?.version ?? null,
    rowCounts: rawResults.rowCounts ?? [],
    fkIntegrity: rawResults.fkIntegrityProbe ?? {},
    activePassDuplicates: rawResults.activePassUniqueness ?? [],
    reservedPassDuplicates: rawResults.reservedPassUniqueness ?? [],
    passUsageOverflow: rawResults.passUsageConsistency ?? [],
    completedPaymentsWithoutPass: rawResults.paymentsPassLinkage?.completed_without_pass ?? null,
    activeSlotsWithoutPass: rawResults.scheduleSlotsActiveLessons?.active_slots_without_pass ?? null,
    smsWithoutPass: rawResults.smsNotificationLinkage?.sms_without_pass ?? null,
    auditLogCount: rawResults.auditLogPresence?.audit_log_count ?? null,
    rls: rawResults.rlsEnabled ?? [],
    ownerAuthUsers: rawResults.ownerAuthPresence?.owner_auth_users ?? null,
    activeOwnerProfiles: rawResults.ownerProfilePresence?.active_owner_profiles ?? null,
    publicPolicyCount: rawResults.rlsPolicyCount?.public_policy_count ?? null,
  };
}

export function validateRestoreReport(report, manifest, options = {}) {
  const failures = [];
  const expectedMigrationCount = manifest?.migrationCount ?? EXPECTED_MIGRATION_COUNT;
  const expectedCheckpoint = manifest?.migrationCheckpoint ?? options.expectedMigrationCheckpoint ?? null;

  if ((report.publicTableCount ?? 0) < REQUIRED_PUBLIC_TABLES.length) {
    failures.push('public_table_count_low');
  }

  const present = new Set((report.requiredTablesPresent ?? []).map((row) => row.table_name ?? row));
  for (const table of REQUIRED_PUBLIC_TABLES) {
    if (!present.has(table)) {
      failures.push(`missing_table:${table}`);
    }
  }

  if (report.migrationCount !== expectedMigrationCount) {
    failures.push('migration_count_mismatch');
  }

  if (expectedCheckpoint && report.latestMigrationVersion !== expectedCheckpoint) {
    failures.push('migration_checkpoint_mismatch');
  }

  const fk = report.fkIntegrity ?? {};
  for (const [key, value] of Object.entries(fk)) {
    if ((value ?? 0) > 0) {
      failures.push(`fk_integrity:${key}`);
    }
  }

  if ((report.activePassDuplicates ?? []).length > 0) {
    failures.push('active_pass_uniqueness');
  }
  if ((report.reservedPassDuplicates ?? []).length > 0) {
    failures.push('reserved_pass_uniqueness');
  }
  if ((report.passUsageOverflow ?? []).length > 0) {
    failures.push('pass_usage_overflow');
  }
  if ((report.completedPaymentsWithoutPass ?? 0) > 0) {
    failures.push('payments_pass_linkage');
  }
  if ((report.activeSlotsWithoutPass ?? 0) > 0) {
    failures.push('schedule_slots_pass_linkage');
  }
  if ((report.smsWithoutPass ?? 0) > 0) {
    failures.push('sms_pass_linkage');
  }
  if ((report.auditLogCount ?? 0) <= 0) {
    failures.push('audit_log_missing');
  }

  for (const table of RLS_REQUIRED_TABLES) {
    const row = (report.rls ?? []).find((entry) => entry.table_name === table);
    if (!row?.rls_enabled) {
      failures.push(`rls_disabled:${table}`);
    }
  }

  if ((report.ownerAuthUsers ?? 0) < 1) {
    failures.push('owner_auth_missing');
  }
  if ((report.activeOwnerProfiles ?? 0) < 1) {
    failures.push('owner_profile_missing');
  }

  if ((report.publicPolicyCount ?? 0) <= 0) {
    failures.push('rls_policies_missing');
  }

  if (failures.length > 0) {
    throw new Error(`Restore validation failed: ${failures.join(', ')}`);
  }

  return report;
}

export function compareManifestRowCounts(manifest, report, tables = REQUIRED_PUBLIC_TABLES) {
  const mismatches = [];
  const manifestCounts = manifest?.rowCounts ?? {};
  const restoredMap = new Map(
    (report.rowCounts ?? []).map((row) => [row.table_name, Number(row.count_value ?? row.estimated_rows ?? row.count ?? 0)]),
  );

  for (const table of tables) {
    const expected = manifestCounts[table];
    const actual = restoredMap.get(table);
    if (typeof expected !== 'number' || typeof actual !== 'number') {
      mismatches.push(`${table}:missing_count`);
      continue;
    }

    const delta = Math.abs(actual - expected);
    const tolerance = 0;
    if (delta > tolerance) {
      mismatches.push(`${table}:expected~${expected},actual~${actual}`);
    }
  }

  if (mismatches.length > 0) {
    throw new Error(`Manifest row-count comparison failed: ${mismatches.join('; ')}`);
  }

  return true;
}

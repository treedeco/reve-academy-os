import { describe, expect, it } from 'vitest';
import {
  buildRestoreValidationReport,
  compareManifestRowCounts,
  validateRestoreReport,
} from '../../scripts/lib/reve-production-restore-validation.mjs';

function buildPassingReport(overrides = {}) {
  return {
    publicTableCount: 15,
    requiredTablesPresent: [
      'audit_logs',
      'course_products',
      'courses',
      'lesson_notes',
      'lesson_schedule_changes',
      'lessons',
      'passes',
      'payment_refunds',
      'payments',
      'profiles',
      'schedule_change_requests',
      'schedule_slots',
      'sms_notifications',
      'students',
      'teachers',
    ].map((table_name) => ({ table_name })),
    migrationCount: 26,
    latestMigrationVersion: '20260728120000',
    rowCounts: [
      { table_name: 'students', count_value: 7 },
      { table_name: 'teachers', count_value: 18 },
      { table_name: 'profiles', count_value: 1 },
      { table_name: 'courses', count_value: 1 },
      { table_name: 'course_products', count_value: 1 },
      { table_name: 'passes', count_value: 2 },
      { table_name: 'schedule_slots', count_value: 2 },
      { table_name: 'lessons', count_value: 10 },
      { table_name: 'payments', count_value: 2 },
      { table_name: 'payment_refunds', count_value: 0 },
      { table_name: 'sms_notifications', count_value: 0 },
      { table_name: 'schedule_change_requests', count_value: 0 },
      { table_name: 'lesson_schedule_changes', count_value: 0 },
      { table_name: 'lesson_notes', count_value: 0 },
      { table_name: 'audit_logs', count_value: 3 },
    ],
    fkIntegrity: {
      orphan_lessons_by_pass: 0,
      orphan_lessons_by_student: 0,
      orphan_lessons_by_teacher: 0,
      orphan_payments_by_pass: 0,
      orphan_schedule_slots_by_pass: 0,
      orphan_sms_by_pass: 0,
    },
    activePassDuplicates: [],
    reservedPassDuplicates: [],
    passUsageOverflow: [],
    completedPaymentsWithoutPass: 0,
    activeSlotsWithoutPass: 0,
    smsWithoutPass: 0,
    auditLogCount: 3,
    rls: [
      'profiles',
      'students',
      'teachers',
      'courses',
      'course_products',
      'passes',
      'schedule_slots',
      'lessons',
      'payments',
      'payment_refunds',
      'sms_notifications',
      'schedule_change_requests',
      'lesson_schedule_changes',
      'lesson_notes',
      'audit_logs',
    ].map((table_name) => ({ table_name, rls_enabled: true, rls_forced: false })),
    ownerAuthUsers: 1,
    activeOwnerProfiles: 1,
    publicPolicyCount: 5,
    ...overrides,
  };
}

describe('reve-production-restore-validation', () => {
  it('builds a structured restore validation report', () => {
    const report = buildRestoreValidationReport({
      publicTableCount: { table_count: 15 },
      migrationCount: { migration_count: 26 },
      latestMigrationVersion: { version: '20260728120000' },
      auditLogPresence: { audit_log_count: 2 },
      ownerAuthPresence: { owner_auth_users: 1 },
      ownerProfilePresence: { active_owner_profiles: 1 },
      fkIntegrityProbe: { orphan_lessons_by_pass: 0 },
      rlsEnabled: [{ table_name: 'students', rls_enabled: true, rls_forced: false }],
      rowCounts: [{ table_name: 'students', count_value: 4 }],
    });

    expect(report.publicTableCount).toBe(15);
    expect(report.migrationCount).toBe(26);
    expect(report.ownerAuthUsers).toBe(1);
  });

  it('passes deterministic validation for a healthy restore', () => {
    const report = buildPassingReport();
    const manifest = {
      migrationCount: 26,
      migrationCheckpoint: '20260728120000',
      rowCounts: Object.fromEntries(report.rowCounts.map((row) => [row.table_name, row.count_value])),
    };

    expect(() => validateRestoreReport(report, manifest)).not.toThrow();
    expect(compareManifestRowCounts(manifest, report)).toBe(true);
  });

  it('fails closed on FK integrity and active-pass uniqueness violations', () => {
    const report = buildPassingReport({
      fkIntegrity: { orphan_lessons_by_pass: 1 },
      activePassDuplicates: [{ student_id: 's1', course_id: 'c1', active_count: 2 }],
    });

    expect(() => validateRestoreReport(report, { migrationCount: 26, migrationCheckpoint: '20260728120000' })).toThrow(
      /fk_integrity:orphan_lessons_by_pass/,
    );

    const report2 = buildPassingReport({
      activePassDuplicates: [{ student_id: 's1', course_id: 'c1', active_count: 2 }],
    });
    expect(() => validateRestoreReport(report2, { migrationCount: 26, migrationCheckpoint: '20260728120000' })).toThrow(
      /active_pass_uniqueness/,
    );
  });

  it('fails closed when RLS policies are missing after restore', () => {
    const report = buildPassingReport({ publicPolicyCount: 0 });
    expect(() => validateRestoreReport(report, { migrationCount: 26, migrationCheckpoint: '20260728120000' })).toThrow(
      /rls_policies_missing/,
    );
  });
});

/**
 * Production backup baseline capture (counts only — no personal data).
 */
import {
  CRITICAL_ROW_COUNT_TABLES,
  EXPECTED_MIGRATION_COUNT,
} from './reve-production-backup-contract.mjs';
import { logStage } from './reve-production-operator-io.mjs';

export function countLinkedMigrations(raw) {
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

  throw new Error(
    `Unexpected supabase migration list output: ${combined.slice(0, 240).replace(/\s+/g, ' ')}`,
  );
}

export function assertExpectedMigrationCount(count, expected = EXPECTED_MIGRATION_COUNT) {
  if (count !== expected) {
    throw new Error(`Migration checkpoint mismatch: expected ${expected}, got ${count}.`);
  }
  return count;
}

async function countTableRows(client, table) {
  const { count, error } = await client.from(table).select('*', { count: 'exact', head: true });
  if (error) {
    throw new Error(`${table} count failed: ${error.message}`);
  }
  return count ?? 0;
}

export async function collectProductionRowCounts(client, tables = CRITICAL_ROW_COUNT_TABLES) {
  logStage('backup_baseline_row_counts_start');
  const rowCounts = {};

  for (const table of tables) {
    rowCounts[table] = await countTableRows(client, table);
  }

  logStage('backup_baseline_row_counts_complete');
  return rowCounts;
}

export async function collectProductionBaselineExtras(client) {
  logStage('backup_baseline_extras_start');

  const [{ count: disposableStudents, error: disposableStudentsError }, { count: nonDisposableStudents, error: nonDisposableError }] =
    await Promise.all([
      client
        .from('students')
        .select('*', { count: 'exact', head: true })
        .like('name', 'PHASE2B2B5-%'),
      client
        .from('students')
        .select('*', { count: 'exact', head: true })
        .not('name', 'like', 'PHASE2B2B5-%'),
    ]);

  if (disposableStudentsError) {
    throw new Error(`disposable student count failed: ${disposableStudentsError.message}`);
  }
  if (nonDisposableError) {
    throw new Error(`non-disposable student count failed: ${nonDisposableError.message}`);
  }

  const { count: ownerProfiles, error: ownerProfileError } = await client
    .from('profiles')
    .select('*', { count: 'exact', head: true })
    .eq('role', 'owner')
    .eq('account_state', 'active');

  if (ownerProfileError) {
    throw new Error(`owner profile count failed: ${ownerProfileError.message}`);
  }

  logStage('backup_baseline_extras_complete');
  return {
    disposableStudentCount: disposableStudents ?? 0,
    nonDisposableStudentCount: nonDisposableStudents ?? 0,
    activeOwnerProfileCount: ownerProfiles ?? 0,
  };
}

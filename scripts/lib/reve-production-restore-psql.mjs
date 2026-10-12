/**
 * Local Supabase restore-validation psql user contract.
 *
 * On Supabase local Docker, role `postgres` is NOT a superuser. Cluster role
 * dumps from hosted projects may include ALTER/GRANT on reserved roles such as
 * `supabase_admin`, which require a superuser session.
 *
 * Compatibility rule (fail-closed, no artifact mutation):
 * - CREATE/DROP of the disposable validation database: `postgres`
 * - APPLY of decrypted backup SQL artifacts: `supabase_admin` (local superuser)
 * - Encrypted backup artifacts are never rewritten; reserved-role statements are
 *   replayed under a privileged local session, not stripped.
 */

export const RESTORE_VALIDATION_BOOTSTRAP_USER = 'postgres';
export const RESTORE_VALIDATION_ARTIFACT_APPLY_USER = 'supabase_admin';

/** Reserved / managed roles that non-superusers cannot modify on Supabase Postgres. */
export const RESERVED_SUPABASE_ROLES = Object.freeze([
  'supabase_admin',
  'supabase_auth_admin',
  'supabase_storage_admin',
  'supabase_functions_admin',
  'authenticator',
  'pgbouncer',
  'supabase_realtime_admin',
]);

const RESERVED_ROLE_PATTERN = new RegExp(
  `\\b(?:CREATE|ALTER|DROP|GRANT|REVOKE)\\b[\\s\\S]{0,200}?\\b(?:${RESERVED_SUPABASE_ROLES.join('|')})\\b`,
  'i',
);

export function resolveRestoreValidationPsqlUser(purpose) {
  if (purpose === 'bootstrap') {
    return RESTORE_VALIDATION_BOOTSTRAP_USER;
  }
  if (purpose === 'apply_artifact') {
    return RESTORE_VALIDATION_ARTIFACT_APPLY_USER;
  }
  throw new Error(`Unknown restore validation psql purpose: ${purpose}`);
}

/**
 * Detect whether plaintext roles SQL touches reserved/managed roles.
 * Used for diagnostics and tests — never used to strip backup contents.
 */
export function rolesSqlTouchesReservedRole(sql) {
  return RESERVED_ROLE_PATTERN.test(String(sql ?? ''));
}

export function listReservedRolesReferenced(sql) {
  const text = String(sql ?? '');
  return RESERVED_SUPABASE_ROLES.filter((role) =>
    new RegExp(`\\b${role}\\b`, 'i').test(text),
  );
}

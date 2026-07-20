import { execSync } from 'node:child_process';

const LOCAL_DB_HOSTS = new Set(['', '127.0.0.1', '::1', 'local']);

export function assertLocalSupabaseApiUrl(apiUrl) {
  const url = apiUrl ?? process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  if (!url) {
    return;
  }

  const lower = url.toLowerCase();
  if (/supabase\.co|supabase\.in|\.amazonaws\.com|\.azure\.|\.gcp\./.test(lower)) {
    throw new Error(`Refusing integration cleanup against hosted Supabase URL: ${url}`);
  }
  if (!/127\.0\.0\.1|localhost/.test(lower)) {
    throw new Error(`Refusing integration cleanup against non-local Supabase URL: ${url}`);
  }
}

export function assertLocalSupabaseContainerHost(container, execSyncImpl = execSync) {
  const dbHost = execSyncImpl(
    `docker exec -i ${container} psql -U postgres -d postgres -t -A -c "SELECT COALESCE(inet_server_addr()::text, 'local');"`,
    { encoding: 'utf8' },
  ).trim();

  if (!LOCAL_DB_HOSTS.has(dbHost)) {
    throw new Error(
      `Refusing integration cleanup: database host '${dbHost}' does not look local.`,
    );
  }
}

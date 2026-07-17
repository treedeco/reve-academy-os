import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

function loadEnvLocal(): void {
  const envLocalPath = path.resolve(__dirname, '../.env.local');
  if (!existsSync(envLocalPath)) {
    return;
  }

  for (const line of readFileSync(envLocalPath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    const separator = trimmed.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    const name = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim().replace(/^["']|["']$/g, '');
    if (name && process.env[name] === undefined) {
      process.env[name] = value;
    }
  }
}

export default async function globalSetup() {
  const repoRoot = path.resolve(__dirname, '..');
  loadEnvLocal();

  const seedPath = path.join(repoRoot, 'scripts', 'seed-owner-alpha.sql');

  let container: string;
  try {
    container = execSync('node scripts/resolve-supabase-db-container.mjs', {
      cwd: repoRoot,
      encoding: 'utf8',
    }).trim();
  } catch (error) {
    throw new Error(
      `Local Supabase DB container not available. Run 'npx supabase start' before Playwright tests. ${error}`,
    );
  }

  const apiUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  if (apiUrl) {
    const lower = apiUrl.toLowerCase();
    if (/supabase\.co|supabase\.in|\.amazonaws\.com/.test(lower)) {
      throw new Error(`Refusing Playwright setup against hosted Supabase URL: ${apiUrl}`);
    }
    if (!/127\.0\.0\.1|localhost/.test(lower)) {
      throw new Error(`Refusing Playwright setup against non-local Supabase URL: ${apiUrl}`);
    }
  }

  execSync(
    'powershell -ExecutionPolicy Bypass -File scripts/seed-owner-alpha.ps1',
    { cwd: repoRoot, stdio: 'inherit' },
  );

  const authApiUrl = apiUrl || 'http://127.0.0.1:54321';
  await waitForLocalSupabaseAuth(authApiUrl);
}

async function waitForLocalSupabaseAuth(
  apiUrl: string,
  maxAttempts = 30,
  delayMs = 2000,
): Promise<void> {
  const ownerEmail = 'reve@owner.local';
  const ownerPassword = process.env.E2E_OWNER_PASSWORD ?? process.env.OWNER_PASSWORD;
  if (!ownerPassword) {
    throw new Error('OWNER_PASSWORD must be set in .env.local for Playwright auth readiness checks.');
  }
  const anonKey =
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ??
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const response = await fetch(`${apiUrl}/auth/v1/token?grant_type=password`, {
        method: 'POST',
        headers: {
          apikey: anonKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email: ownerEmail, password: ownerPassword }),
      });

      if (response.ok) {
        const payload = (await response.json()) as { access_token?: string };
        if (payload.access_token) {
          return;
        }
      }
    } catch {
      // Auth container may still be restarting after db reset.
    }

    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }

  throw new Error(`Supabase Auth did not become ready after ${maxAttempts} attempts.`);
}

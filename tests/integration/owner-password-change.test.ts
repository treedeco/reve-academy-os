import { execSync } from 'node:child_process';
import path from 'node:path';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { changeOwnerPassword } from '@/lib/auth/change-owner-password';
import { ownerMustChangePassword } from '@/lib/auth/owner-password-metadata';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const integrationEnabled = Boolean(supabaseUrl && supabaseAnonKey);

const TEST_EMAIL = 'password-change-owner@test.local';
const INITIAL_PASSWORD = 'PasswordChangeTest123!';
const UPDATED_PASSWORD = 'UpdatedPassword123!';

function applyPasswordChangeFixture() {
  const repoRoot = path.resolve(process.cwd());
  const container = execSync('node scripts/resolve-supabase-db-container.mjs', {
    cwd: repoRoot,
    encoding: 'utf8',
  }).trim();
  const fixturePath = path.join(repoRoot, 'scripts', 'fixture-password-change-test-user.sql');
  execSync(`docker cp "${fixturePath}" ${container}:/tmp/fixture-password-change-test-user.sql`, {
    cwd: repoRoot,
    stdio: 'inherit',
  });
  execSync(
    `docker exec ${container} psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/fixture-password-change-test-user.sql`,
    { cwd: repoRoot, stdio: 'inherit' },
  );
}

function createAuthClient(storageKey: string): SupabaseClient {
  return createClient(supabaseUrl!, supabaseAnonKey!, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      storageKey,
    },
  });
}

describe.skipIf(!integrationEnabled)('Owner password change integration', () => {
  beforeAll(() => {
    applyPasswordChangeFixture();
  });

  afterAll(() => {
    applyPasswordChangeFixture();
  });

  it('rejects incorrect current password without changing auth state', async () => {
    const client = createAuthClient('reve-test-password-change-wrong');
    const signIn = await client.auth.signInWithPassword({ email: TEST_EMAIL, password: INITIAL_PASSWORD });
    expect(signIn.error).toBeNull();

    const result = await changeOwnerPassword(client, {
      currentPassword: 'WrongCurrentPassword123!',
      newPassword: UPDATED_PASSWORD,
      confirmPassword: UPDATED_PASSWORD,
    });

    expect(result.status).toBe('incorrect_current_password');

    const relogin = await client.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: INITIAL_PASSWORD,
    });
    expect(relogin.error).toBeNull();
    await client.auth.signOut();
  });

  it('changes password, clears must_change_password, and requires re-login', async () => {
    const client = createAuthClient('reve-test-password-change-success');
    const signIn = await client.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: INITIAL_PASSWORD,
    });
    expect(signIn.error).toBeNull();
    expect(ownerMustChangePassword(signIn.data.user?.user_metadata)).toBe(true);

    const result = await changeOwnerPassword(client, {
      currentPassword: INITIAL_PASSWORD,
      newPassword: UPDATED_PASSWORD,
      confirmPassword: UPDATED_PASSWORD,
    });
    expect(result.status).toBe('success');

    const staleSession = await client.auth.getUser();
    expect(staleSession.data.user).toBeNull();

    const oldLogin = await client.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: INITIAL_PASSWORD,
    });
    expect(oldLogin.error).toBeTruthy();

    const newClient = createAuthClient('reve-test-password-change-new-login');
    const newLogin = await newClient.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: UPDATED_PASSWORD,
    });
    expect(newLogin.error).toBeNull();
    expect(ownerMustChangePassword(newLogin.data.user?.user_metadata)).toBe(false);

    await newClient.auth.signOut();
  });
});

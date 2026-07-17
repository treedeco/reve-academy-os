import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  LEGACY_OWNER_AUTH_EMAIL,
  OWNER_AUTH_EMAIL,
  OWNER_LOGIN_USERNAME,
} from '@/lib/auth/owner-login';
import { getOwnerTestPassword } from '@/tests/helpers/owner-test-credentials';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const integrationEnabled = Boolean(supabaseUrl && supabaseAnonKey);

function createAuthClient(storageKey: string) {
  return createClient(supabaseUrl!, supabaseAnonKey!, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      storageKey,
    },
  });
}

describe.skipIf(!integrationEnabled)('Owner login integration', () => {
  let client: SupabaseClient;

  beforeAll(() => {
    client = createAuthClient('reve-test-owner-login');
  });

  it('authenticates reve credentials against Supabase Auth', async () => {
    const password = getOwnerTestPassword();
    const { data, error } = await client.auth.signInWithPassword({
      email: OWNER_AUTH_EMAIL,
      password,
    });

    expect(error).toBeNull();
    expect(data.session?.access_token).toBeTruthy();
  });

  it('rejects legacy owner credentials', async () => {
    const password = getOwnerTestPassword();
    const { error } = await client.auth.signInWithPassword({
      email: LEGACY_OWNER_AUTH_EMAIL,
      password,
    });

    expect(error).toBeTruthy();
    expect(error?.message.toLowerCase() ?? '').toContain('invalid login credentials');
  });

  it('rejects incorrect password for reve auth email', async () => {
    const { error } = await client.auth.signInWithPassword({
      email: OWNER_AUTH_EMAIL,
      password: 'definitely-wrong-password',
    });

    expect(error?.message.toLowerCase()).toContain('invalid login credentials');
  });

  it('exposes configured username constant only', () => {
    expect(OWNER_LOGIN_USERNAME).toBe('reve');
  });
});

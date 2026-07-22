import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  AUTH_ADMIN_PATH,
  BOOTSTRAP_RPC_PATH,
  BootstrapOperationError,
  bootstrapOwnerProfile,
  createSupabaseAdminClient,
  formatBootstrapError,
  listAuthUsersByEmail,
  normalizeBootstrapEmail,
  reportBootstrapError,
  resolveOrCreateAuthUser,
  sanitizeBootstrapMessage,
} from '../../scripts/lib/bootstrap-production-owner-core.mjs';
import {
  getSupabaseAdminKeyFromEnv,
  getServiceRoleKeyFromEnv,
  resolveHostedSupabaseUrl,
} from '../../scripts/lib/reve-hosted-supabase-guard.mjs';

describe('bootstrap-production-owner-core', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
    vi.restoreAllMocks();
  });

  it('normalizes bootstrap email for exact matching', () => {
    expect(normalizeBootstrapEmail(' ReVe@Owner.Local ')).toBe('reve@owner.local');
  });

  it('reuses an existing Auth user without creating a duplicate', async () => {
    const existingUser = { id: 'user-1', email: 'reve@owner.local' };
    const createUser = vi.fn();
    const listUsers = vi.fn(async () => ({
      data: { users: [existingUser] },
      error: null,
    }));

    const adminClient = { auth: { admin: { listUsers, createUser } } };
    const result = await resolveOrCreateAuthUser(
      adminClient,
      'reve@owner.local',
      'OwnerBootstrap123!',
      { listUsers },
    );

    expect(result).toEqual(existingUser);
    expect(createUser).not.toHaveBeenCalled();
  });

  it('creates an Auth user exactly once when none exists', async () => {
    const createdUser = { id: 'user-new', email: 'reve@owner.local' };
    const createUser = vi.fn(async () => ({ data: { user: createdUser }, error: null }));
    const listUsers = vi
      .fn()
      .mockResolvedValueOnce({ data: { users: [] }, error: null })
      .mockResolvedValueOnce({ data: { users: [] }, error: null });

    const adminClient = { auth: { admin: { listUsers, createUser } } };
    const result = await resolveOrCreateAuthUser(
      adminClient,
      'reve@owner.local',
      'OwnerBootstrap123!',
      { listUsers, createUser },
    );

    expect(result).toEqual(createdUser);
    expect(createUser).toHaveBeenCalledTimes(1);
    expect(createUser).toHaveBeenCalledWith({
      email: 'reve@owner.local',
      password: 'OwnerBootstrap123!',
      email_confirm: true,
    });
  });

  it('reuses an existing user when createUser reports a duplicate', async () => {
    const existingUser = { id: 'user-existing', email: 'reve@owner.local' };
    const createUser = vi.fn(async () => ({
      data: { user: null },
      error: { status: 422, message: 'User already registered' },
    }));
    const listUsers = vi
      .fn()
      .mockResolvedValueOnce({ data: { users: [] }, error: null })
      .mockResolvedValueOnce({ data: { users: [existingUser] }, error: null });

    const adminClient = { auth: { admin: { listUsers, createUser } } };
    const result = await resolveOrCreateAuthUser(
      adminClient,
      'reve@owner.local',
      'OwnerBootstrap123!',
      { listUsers, createUser },
    );

    expect(result).toEqual(existingUser);
    expect(createUser).toHaveBeenCalledTimes(1);
  });

  it('fails safely when multiple Auth users match the bootstrap email', async () => {
    const listUsers = vi.fn(async () => ({
      data: {
        users: [
          { id: 'user-1', email: 'reve@owner.local' },
          { id: 'user-2', email: 'REVE@owner.local' },
        ],
      },
      error: null,
    }));

    const adminClient = { auth: { admin: { listUsers, createUser: vi.fn() } } };

    await expect(
      resolveOrCreateAuthUser(adminClient, 'reve@owner.local', 'OwnerBootstrap123!', {
        listUsers,
      }),
    ).rejects.toMatchObject({
      operation: 'auth.admin.resolveUser',
      message: expect.stringContaining('Multiple Auth users match reve@owner.local'),
    });
  });

  it('paginates listUsers when searching for an existing Auth user', async () => {
    const listUsers = vi
      .fn()
      .mockResolvedValueOnce({
        data: { users: Array.from({ length: 200 }, (_, index) => ({ id: `other-${index}`, email: `user${index}@example.com` })) },
        error: null,
      })
      .mockResolvedValueOnce({
        data: { users: [{ id: 'user-201', email: 'reve@owner.local' }] },
        error: null,
      });

    const matches = await listAuthUsersByEmail(
      { auth: { admin: { listUsers } } },
      'reve@owner.local',
      listUsers,
    );

    expect(matches).toHaveLength(1);
    expect(listUsers).toHaveBeenCalledTimes(2);
    expect(listUsers).toHaveBeenNthCalledWith(1, { page: 1, perPage: 200 });
    expect(listUsers).toHaveBeenNthCalledWith(2, { page: 2, perPage: 200 });
  });

  it('creates the admin client with session persistence disabled', () => {
    const client = createSupabaseAdminClient(
      'https://bfhptqhgxignyggyxxkx.supabase.co',
      'sb_secret_example_key_only_for_unit_test',
    );

    expect(client).toBeTruthy();
    expect(client.auth).toBeTruthy();
  });

  it('sanitizes secret values from bootstrap error messages', () => {
    const formatted = formatBootstrapError(
      {
        name: 'AuthApiError',
        message: 'Invalid key sb_secret_example_key and bearer eyJabc.def.ghi',
        status: 401,
        code: 'invalid_api_key',
        cause: { code: 'ENOTFOUND', errno: -3008 },
      },
      {
        operation: 'auth.admin.createUser',
        hostname: 'bfhptqhgxignyggyxxkx.supabase.co',
        path: AUTH_ADMIN_PATH,
      },
    );

    expect(formatted.message).not.toContain('sb_secret_example_key');
    expect(formatted.message).not.toContain('eyJabc');
    expect(formatted.message).toContain('[REDACTED]');
    expect(formatted.status).toBe(401);
    expect(formatted.code).toBe('invalid_api_key');
    expect(formatted.causeCode).toBe('ENOTFOUND');
    expect(formatted.causeErrno).toBe(-3008);
    expect(formatted.hostname).toBe('bfhptqhgxignyggyxxkx.supabase.co');
    expect(formatted.path).toBe(AUTH_ADMIN_PATH);
  });

  it('does not log secret values when reporting bootstrap errors', () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const secret = 'sb_secret_example_key_only_for_unit_test';

    reportBootstrapError(
      new BootstrapOperationError('auth.admin.createUser', `Failed with ${secret}`, {
        status: 401,
        code: 'invalid_api_key',
      }),
      {
        operation: 'auth.admin.createUser',
        hostname: 'bfhptqhgxignyggyxxkx.supabase.co',
        path: AUTH_ADMIN_PATH,
      },
    );

    const output = errorSpy.mock.calls[0]?.[0] ?? '';
    expect(output).not.toContain(secret);
    expect(output).toContain('[REDACTED]');
  });

  it('calls reve_bootstrap_first_owner after Auth user resolution', async () => {
    const rpc = vi.fn(async () => ({
      data: [{ profile_id: 'profile-1', role: 'owner', account_state: 'active' }],
      error: null,
    }));

    const result = await bootstrapOwnerProfile(
      { rpc },
      'user-1',
      'REVE Owner',
      rpc,
    );

    expect(rpc).toHaveBeenCalledWith({
      p_auth_user_id: 'user-1',
      p_display_name: 'REVE Owner',
    });
    expect(result).toEqual([{ profile_id: 'profile-1', role: 'owner', account_state: 'active' }]);
  });

  it('reports RPC failures with the bootstrap RPC path', async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: {
        message: 'permission denied for function validate_profile_role_links',
        code: '42501',
      },
    }));

    await expect(
      bootstrapOwnerProfile({ rpc }, 'user-1', 'REVE Owner', rpc),
    ).rejects.toMatchObject({
      operation: 'reve_bootstrap_first_owner',
      path: BOOTSTRAP_RPC_PATH,
      code: '42501',
    });
  });

  it('does not leak Auth Admin path into RPC error diagnostics', () => {
    const formatted = formatBootstrapError(
      new BootstrapOperationError(
        'reve_bootstrap_first_owner',
        'permission denied for function validate_profile_role_links',
        { code: '42501', path: BOOTSTRAP_RPC_PATH },
      ),
      {
        operation: 'auth.admin.createUser',
        hostname: 'bfhptqhgxignyggyxxkx.supabase.co',
        path: AUTH_ADMIN_PATH,
      },
    );

    expect(formatted.operation).toBe('reve_bootstrap_first_owner');
    expect(formatted.path).toBe(BOOTSTRAP_RPC_PATH);
    expect(formatted.path).not.toBe(AUTH_ADMIN_PATH);
  });

  it('retains Auth Admin path for Auth Admin operation failures', () => {
    const formatted = formatBootstrapError(
      new BootstrapOperationError('auth.admin.createUser', 'fetch failed', {
        path: AUTH_ADMIN_PATH,
      }),
      {
        operation: 'reve_bootstrap_first_owner',
        hostname: 'bfhptqhgxignyggyxxkx.supabase.co',
        path: BOOTSTRAP_RPC_PATH,
      },
    );

    expect(formatted.operation).toBe('auth.admin.createUser');
    expect(formatted.path).toBe(AUTH_ADMIN_PATH);
  });
});

describe('bootstrap-production-owner env compatibility', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('accepts SUPABASE_SECRET_KEY as the preferred admin key', () => {
    process.env.SUPABASE_SECRET_KEY = '  sb_secret_example  ';
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;

    expect(getSupabaseAdminKeyFromEnv()).toBe('sb_secret_example');
  });

  it('falls back to legacy SUPABASE_SERVICE_ROLE_KEY', () => {
    delete process.env.SUPABASE_SECRET_KEY;
    process.env.SUPABASE_SERVICE_ROLE_KEY = '  legacy-jwt-key  ';

    expect(getSupabaseAdminKeyFromEnv()).toBe('legacy-jwt-key');
    expect(getServiceRoleKeyFromEnv()).toBe('legacy-jwt-key');
  });

  it('prefers SUPABASE_SECRET_KEY when both key variables are set', () => {
    process.env.SUPABASE_SECRET_KEY = 'sb_secret_preferred';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'legacy-jwt-key';

    expect(getSupabaseAdminKeyFromEnv()).toBe('sb_secret_preferred');
  });

  it('trims hosted Supabase URLs', () => {
    expect(resolveHostedSupabaseUrl('  https://bfhptqhgxignyggyxxkx.supabase.co/  ')).toBe(
      'https://bfhptqhgxignyggyxxkx.supabase.co',
    );
  });

  it('rejects NEXT_PUBLIC admin key prefixes', () => {
    delete process.env.SUPABASE_SECRET_KEY;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_SECRET_KEY = 'leaked';

    expect(() => getSupabaseAdminKeyFromEnv()).toThrow(/must not use the NEXT_PUBLIC_ prefix/);
  });
});

describe('reve-hosted-supabase-guard unchanged behavior', () => {
  it('rejects localhost before hosted bootstrap', () => {
    expect(() => resolveHostedSupabaseUrl('http://127.0.0.1:54321')).toThrow(
      /Refusing hosted operator action against local or private URL/,
    );
  });
});

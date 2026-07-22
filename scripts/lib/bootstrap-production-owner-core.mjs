import { createClient } from '@supabase/supabase-js';

export const OWNER_AUTH_EMAIL_DEFAULT = 'reve@owner.local';
export const AUTH_ADMIN_PATH = '/auth/v1/admin/users';
export const BOOTSTRAP_RPC_PATH = '/rest/v1/rpc/reve_bootstrap_first_owner';

const SECRET_PATTERNS = [
  /sb_[a-z_]+_[A-Za-z0-9_-]+/gi,
  /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,
];

export function normalizeBootstrapEmail(email) {
  return email.trim().toLowerCase();
}

export function createSupabaseAdminClient(supabaseUrl, secretKey) {
  return createClient(supabaseUrl, secretKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

export function sanitizeBootstrapMessage(message) {
  if (!message) {
    return null;
  }

  let sanitized = String(message);
  for (const pattern of SECRET_PATTERNS) {
    sanitized = sanitized.replace(pattern, '[REDACTED]');
  }
  return sanitized.slice(0, 240);
}

export function formatBootstrapError(error, context) {
  const hostname = context.hostname ?? null;
  const path = error?.path ?? context.path ?? null;

  if (error && typeof error === 'object' && error.name === 'BootstrapOperationError') {
    return {
      operation: error.operation,
      errorClass: error.errorClass ?? 'BootstrapOperationError',
      status: error.status ?? null,
      code: error.code ?? null,
      message: sanitizeBootstrapMessage(error.message),
      causeCode: error.causeCode ?? null,
      causeErrno: error.causeErrno ?? null,
      hostname,
      path,
    };
  }

  const authError = error;
  return {
    operation: context.operation,
    errorClass: error?.constructor?.name ?? 'Error',
    status: authError?.status ?? null,
    code: authError?.code ?? null,
    message: sanitizeBootstrapMessage(error?.message ?? String(error)),
    causeCode: error?.cause?.code ?? null,
    causeErrno: error?.cause?.errno ?? null,
    hostname,
    path,
  };
}

export class BootstrapOperationError extends Error {
  constructor(operation, message, details = {}) {
    super(message);
    this.name = 'BootstrapOperationError';
    this.operation = operation;
    this.errorClass = details.errorClass ?? 'BootstrapOperationError';
    this.status = details.status ?? null;
    this.code = details.code ?? null;
    this.causeCode = details.causeCode ?? null;
    this.causeErrno = details.causeErrno ?? null;
    this.path = details.path ?? null;
  }
}

function wrapBootstrapOperationError(operation, error, path) {
  throw new BootstrapOperationError(operation, error.message ?? 'Bootstrap operation failed.', {
    errorClass: error?.constructor?.name ?? 'AuthApiError',
    status: error.status ?? null,
    code: error.code ?? null,
    causeCode: error?.cause?.code ?? null,
    causeErrno: error?.cause?.errno ?? null,
    path,
  });
}

export async function listAuthUsersByEmail(adminClient, normalizedEmail, listUsersImpl) {
  const listUsers = listUsersImpl ?? ((options) => adminClient.auth.admin.listUsers(options));
  const matches = [];
  let page = 1;
  const perPage = 200;

  while (true) {
    const { data, error } = await listUsers({ page, perPage });
    if (error) {
      wrapBootstrapOperationError('auth.admin.listUsers', error, AUTH_ADMIN_PATH);
    }

    const users = data?.users ?? [];
    for (const user of users) {
      if (normalizeBootstrapEmail(user.email ?? '') === normalizedEmail) {
        matches.push(user);
      }
    }

    if (users.length < perPage) {
      break;
    }
    page += 1;
  }

  return matches;
}

function isDuplicateAuthUserError(error) {
  const message = error?.message ?? '';
  return (
    error?.status === 422 ||
    /already|exists|registered|duplicate/i.test(message)
  );
}

export async function resolveOrCreateAuthUser(adminClient, email, password, deps = {}) {
  const normalizedEmail = normalizeBootstrapEmail(email);
  const listUsersByEmail = deps.listAuthUsersByEmail ?? listAuthUsersByEmail;
  const createUser = deps.createUser ?? ((payload) => adminClient.auth.admin.createUser(payload));

  let matches = await listUsersByEmail(adminClient, normalizedEmail, deps.listUsers);

  if (matches.length > 1) {
    throw new BootstrapOperationError(
      'auth.admin.resolveUser',
      `Multiple Auth users match ${normalizedEmail}. Resolve duplicates before bootstrap.`,
      { errorClass: 'BootstrapOperationError' },
    );
  }

  if (matches.length === 1) {
    return matches[0];
  }

  const { data, error } = await createUser({
    email: normalizedEmail,
    password,
    email_confirm: true,
  });

  if (!error) {
    if (!data?.user?.id) {
      throw new BootstrapOperationError(
        'auth.admin.createUser',
        'Auth user creation returned no user id.',
        { errorClass: 'BootstrapOperationError' },
      );
    }
    return data.user;
  }

  if (isDuplicateAuthUserError(error)) {
    matches = await listUsersByEmail(adminClient, normalizedEmail, deps.listUsers);
    if (matches.length === 1) {
      return matches[0];
    }
    if (matches.length > 1) {
      throw new BootstrapOperationError(
        'auth.admin.resolveUser',
        `Multiple Auth users match ${normalizedEmail}. Resolve duplicates before bootstrap.`,
        { errorClass: 'BootstrapOperationError' },
      );
    }
  }

  wrapBootstrapOperationError('auth.admin.createUser', error, AUTH_ADMIN_PATH);
}

export async function bootstrapOwnerProfile(adminClient, authUserId, displayName, rpcImpl) {
  const rpc = rpcImpl ?? ((params) => adminClient.rpc('reve_bootstrap_first_owner', params));
  const { data, error } = await rpc({
    p_auth_user_id: authUserId,
    p_display_name: displayName,
  });

  if (error) {
    wrapBootstrapOperationError('reve_bootstrap_first_owner', error, BOOTSTRAP_RPC_PATH);
  }

  return data;
}

export function reportBootstrapError(error, context) {
  console.error(JSON.stringify(formatBootstrapError(error, context), null, 2));
}

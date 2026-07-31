/**
 * Fail-closed guards for production operator scripts (runtime verify, cleanup, rotation).
 */

import { resolveHostedSupabaseUrl } from './reve-hosted-supabase-guard.mjs';

export const PRODUCTION_PROJECT_REF = 'bfhptqhgxignyggyxxkx';
export const PRODUCTION_SUPABASE_HOST = `${PRODUCTION_PROJECT_REF}.supabase.co`;
export const PRODUCTION_SUPABASE_URL = `https://${PRODUCTION_SUPABASE_HOST}`;
export const PRODUCTION_APP_URL = 'https://reve-academy-os.vercel.app';
export const DISPOSABLE_NAME_PREFIX = 'PHASE2B2B5-';

function parseHostname(url) {
  return new URL(url).hostname.toLowerCase();
}

function isLocalHostname(hostname) {
  return (
    hostname === 'localhost' ||
    hostname === '127.0.0.1' ||
    hostname === '::1' ||
    hostname.endsWith('.local')
  );
}

export function assertProductionSupabaseUrl(apiUrl) {
  const normalized = resolveHostedSupabaseUrl(apiUrl);
  const hostname = parseHostname(normalized);
  if (hostname !== PRODUCTION_SUPABASE_HOST) {
    throw new Error(
      `Refusing production operator action: expected Supabase host ${PRODUCTION_SUPABASE_HOST}, got ${hostname}.`,
    );
  }
  return normalized;
}

export function assertProductionAppUrl(appUrl) {
  const url = (appUrl ?? process.env.PRODUCTION_URL ?? '').trim();
  if (!url) {
    throw new Error('PRODUCTION_URL is required for production operator scripts.');
  }

  const hostname = parseHostname(url);
  if (isLocalHostname(hostname)) {
    throw new Error(`Refusing production operator action against local app URL: ${url}`);
  }
  if (hostname !== parseHostname(PRODUCTION_APP_URL)) {
    throw new Error(
      `Refusing production operator action: expected app host ${parseHostname(PRODUCTION_APP_URL)}, got ${hostname}.`,
    );
  }
  return url.replace(/\/$/, '');
}

export function isProductionMutationConfirmed() {
  const flag = (process.env.REVE_CONFIRM_PRODUCTION ?? '').trim().toLowerCase();
  return flag === '1' || flag === 'true' || flag === 'yes';
}

export function assertProductionMutationConfirmed(actionLabel = 'production mutation') {
  if (!isProductionMutationConfirmed()) {
    throw new Error(
      `${actionLabel} requires explicit confirmation. Set REVE_CONFIRM_PRODUCTION=1 (PowerShell: -ConfirmProduction).`,
    );
  }
}

export function assertDisposableName(name, label = 'record') {
  const normalized = String(name ?? '').trim();
  if (!normalized.startsWith(DISPOSABLE_NAME_PREFIX)) {
    throw new Error(
      `Refusing ${label} action: name must start with ${DISPOSABLE_NAME_PREFIX} (got ${normalized.slice(0, 48)}).`,
    );
  }
  return normalized;
}

export function resolveProductionSupabaseUrlFromEnv() {
  const url = process.env.PRODUCTION_SUPABASE_URL ?? process.env.SUPABASE_URL ?? PRODUCTION_SUPABASE_URL;
  return assertProductionSupabaseUrl(url);
}

export function resolveProductionAppUrlFromEnv() {
  return assertProductionAppUrl(process.env.PRODUCTION_URL ?? PRODUCTION_APP_URL);
}

import { describe, expect, it } from 'vitest';
import { scanFileForSecrets, scanTextForSecrets } from '../../scripts/lib/reve-production-backup-secrets-scan.mjs';

describe('reve-production-backup-secrets-scan', () => {
  it('passes clean SQL text', () => {
    expect(scanTextForSecrets('CREATE TABLE public.students (id uuid);')).toEqual([]);
  });

  it('detects JWT-like material', () => {
    const jwt =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiIn0.abcdefghijklmnopqrstuvwxyz1234567890ABCDEF';
    expect(() => scanTextForSecrets(jwt)).toThrow(/Secret scan failed: jwt_token/);
  });

  it('detects Supabase secret keys', () => {
    expect(() => scanTextForSecrets('key=sb_secret_abcdefghijklmnopqrstuvwxyz123456')).toThrow(
      /supabase_secret_key/,
    );
  });

  it('supports non-throwing scans', () => {
    const violations = scanTextForSecrets('sb_publishable_notmatched', { failOnViolation: false });
    expect(violations).toEqual([]);
  });

  it('exposes scanFileForSecrets for dump verification', () => {
    expect(typeof scanFileForSecrets).toBe('function');
  });
});

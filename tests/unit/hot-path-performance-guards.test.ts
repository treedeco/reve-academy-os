import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('production hot-path performance guards', () => {
  it('pins Vercel serverless region to icn1 (Seoul) beside Supabase ap-northeast-2', () => {
    const raw = readFileSync(resolve(process.cwd(), 'vercel.json'), 'utf8');
    const config = JSON.parse(raw) as { regions?: string[] };
    expect(config.regions).toEqual(['icn1']);
  });

  it('memoizes owner auth resolution with react cache (layout+page share one lookup)', () => {
    const source = readFileSync(resolve(process.cwd(), 'lib/auth/owner-session.ts'), 'utf8');
    expect(source).toContain("import { cache } from 'react'");
    expect(source).toMatch(/export const getAuthenticatedOwner = cache\(/);
  });

  it('memoizes teacher auth resolution with react cache', () => {
    const source = readFileSync(resolve(process.cwd(), 'lib/auth/teacher-session.ts'), 'utf8');
    expect(source).toContain("import { cache } from 'react'");
    expect(source).toMatch(/export const getAuthenticatedTeacher = cache\(/);
  });

  it('memoizes createClient per request so auth cache is not defeated', () => {
    const source = readFileSync(resolve(process.cwd(), 'lib/supabase/server.ts'), 'utf8');
    expect(source).toContain("import { cache } from 'react'");
    expect(source).toMatch(/export const createClient = cache\(/);
  });

  it('disables Owner shell nav Link prefetch to avoid RSC prefetch storms', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'components/owner/owner-shell.tsx'),
      'utf8',
    );
    expect(source).toContain('prefetch={false}');
  });

  it('disables Teacher shell nav Link prefetch', () => {
    const source = readFileSync(
      resolve(process.cwd(), 'components/teacher/teacher-shell.tsx'),
      'utf8',
    );
    expect(source).toContain('prefetch={false}');
  });

  it('owner layout does not call auth.getUser a second time after getAuthenticatedOwner', () => {
    const source = readFileSync(resolve(process.cwd(), 'app/(owner)/layout.tsx'), 'utf8');
    expect(source).toContain('getAuthenticatedOwner()');
    expect(source).not.toContain('supabase.auth.getUser');
  });
});

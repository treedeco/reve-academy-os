import type { SupabaseClient, User } from '@supabase/supabase-js';
import { cache } from 'react';
import type { OwnerProfile } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/server';

export type AuthenticatedOwnerResult = {
  profile: OwnerProfile | null;
  user: User | null;
  error: string | null;
};

async function resolveAuthenticatedOwner(
  supabase: SupabaseClient,
): Promise<AuthenticatedOwnerResult> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return { profile: null, user: null, error: '세션이 만료되었습니다. 다시 로그인해 주세요.' };
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, role, display_name, account_state')
    .eq('id', user.id)
    .maybeSingle();

  if (profileError || !profile) {
    return { profile: null, user, error: '프로필을 불러올 수 없습니다.' };
  }

  if (profile.role !== 'owner' || profile.account_state !== 'active') {
    return { profile: null, user, error: 'Owner 권한이 없는 계정입니다.' };
  }

  return { profile: profile as OwnerProfile, user, error: null };
}

/**
 * Deduped within a single RSC request so layout + page share one getUser + profile lookup.
 */
export const getAuthenticatedOwner = cache(async (): Promise<AuthenticatedOwnerResult> => {
  const supabase = await createClient();
  return resolveAuthenticatedOwner(supabase);
});

/** Test/helper entry that accepts an explicit client (integration tests). */
export async function getAuthenticatedOwnerWithClient(
  supabase: SupabaseClient,
): Promise<AuthenticatedOwnerResult> {
  return resolveAuthenticatedOwner(supabase);
}

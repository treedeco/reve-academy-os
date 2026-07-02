import type { SupabaseClient } from '@supabase/supabase-js';
import type { OwnerProfile } from '@/lib/domain/types';

export async function getAuthenticatedOwner(
  supabase: SupabaseClient,
): Promise<{ profile: OwnerProfile | null; error: string | null }> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return { profile: null, error: '세션이 만료되었습니다. 다시 로그인해 주세요.' };
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, role, display_name, account_state')
    .eq('id', user.id)
    .maybeSingle();

  if (profileError || !profile) {
    return { profile: null, error: '프로필을 불러올 수 없습니다.' };
  }

  if (profile.role !== 'owner' || profile.account_state !== 'active') {
    return { profile: null, error: 'Owner 권한이 없는 계정입니다.' };
  }

  return { profile: profile as OwnerProfile, error: null };
}

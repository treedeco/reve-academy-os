import type { SupabaseClient, User } from '@supabase/supabase-js';
import { cache } from 'react';
import type { OwnerProfile } from '@/lib/domain/types';
import { createClient } from '@/lib/supabase/server';

export interface TeacherProfile {
  id: string;
  role: 'teacher';
  display_name: string;
  account_state: string;
  teacher_id: string;
}

export type AuthenticatedTeacherResult = {
  profile: TeacherProfile | null;
  user: User | null;
  error: string | null;
};

async function resolveAuthenticatedTeacher(
  supabase: SupabaseClient,
): Promise<AuthenticatedTeacherResult> {
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

  if (profile.role !== 'teacher' || profile.account_state !== 'active') {
    return { profile: null, user, error: '강사 권한이 없는 계정입니다.' };
  }

  const { data: teacher, error: teacherError } = await supabase
    .from('teachers')
    .select('id, is_active')
    .eq('profile_id', user.id)
    .maybeSingle();

  if (teacherError || !teacher || !teacher.is_active) {
    return { profile: null, user, error: '활성 강사 계정이 아닙니다.' };
  }

  return {
    profile: {
      id: profile.id,
      role: 'teacher',
      display_name: profile.display_name,
      account_state: profile.account_state,
      teacher_id: teacher.id,
    },
    user,
    error: null,
  };
}

/**
 * Deduped within a single RSC request so layout + page share one auth/profile/teacher lookup.
 */
export const getAuthenticatedTeacher = cache(async (): Promise<AuthenticatedTeacherResult> => {
  const supabase = await createClient();
  return resolveAuthenticatedTeacher(supabase);
});

export async function getAuthenticatedTeacherWithClient(
  supabase: SupabaseClient,
): Promise<AuthenticatedTeacherResult> {
  return resolveAuthenticatedTeacher(supabase);
}

export const getAuthenticatedAppUser = cache(
  async (): Promise<
    | { role: 'owner'; profile: OwnerProfile; error: null }
    | { role: 'teacher'; profile: TeacherProfile; error: null }
    | { role: null; profile: null; error: string }
  > => {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { role: null, profile: null, error: 'unauthorized' };
    }

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('id, role, display_name, account_state')
      .eq('id', user.id)
      .maybeSingle();

    if (profileError || !profile || profile.account_state !== 'active') {
      return { role: null, profile: null, error: 'unauthorized' };
    }

    if (profile.role === 'owner') {
      return {
        role: 'owner',
        profile: profile as OwnerProfile,
        error: null,
      };
    }

    if (profile.role === 'teacher') {
      const { data: teacher, error: teacherError } = await supabase
        .from('teachers')
        .select('id, is_active')
        .eq('profile_id', user.id)
        .maybeSingle();

      if (teacherError || !teacher || !teacher.is_active) {
        return { role: null, profile: null, error: 'unauthorized' };
      }

      return {
        role: 'teacher',
        profile: {
          id: profile.id,
          role: 'teacher',
          display_name: profile.display_name,
          account_state: profile.account_state,
          teacher_id: teacher.id,
        },
        error: null,
      };
    }

    return { role: null, profile: null, error: 'unauthorized' };
  },
);

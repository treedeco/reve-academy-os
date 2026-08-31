import { getAuthenticatedAppUser } from '@/lib/auth/teacher-session';
import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';

export default async function HomePage() {
  const supabase = await createClient();
  const session = await getAuthenticatedAppUser(supabase);

  if (session.role === 'owner') {
    redirect('/dashboard');
  }

  if (session.role === 'teacher') {
    redirect('/teacher/lessons/today');
  }

  redirect('/login');
}

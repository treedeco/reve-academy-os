import { getAuthenticatedAppUser } from '@/lib/auth/teacher-session';
import { redirect } from 'next/navigation';

export default async function HomePage() {
  const session = await getAuthenticatedAppUser();

  if (session.role === 'owner') {
    redirect('/dashboard');
  }

  if (session.role === 'teacher') {
    redirect('/teacher/lessons/today');
  }

  redirect('/login');
}

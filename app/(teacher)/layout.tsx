import { TeacherShell } from '@/components/teacher/teacher-shell';
import { getAuthenticatedTeacher } from '@/lib/auth/teacher-session';
import { redirect } from 'next/navigation';

export default async function TeacherLayout({ children }: { children: React.ReactNode }) {
  const { profile, error } = await getAuthenticatedTeacher();

  if (!profile) {
    redirect(`/login?error=${encodeURIComponent(error ?? 'unauthorized')}`);
  }

  return <TeacherShell teacherName={profile.display_name}>{children}</TeacherShell>;
}

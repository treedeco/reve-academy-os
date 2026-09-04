import { redirect } from 'next/navigation';
import { OwnerShell } from '@/components/owner/owner-shell';
import { ownerMustChangePassword } from '@/lib/auth/owner-password-metadata';
import { getAuthenticatedOwner } from '@/lib/auth/owner-session';

export default async function OwnerLayout({ children }: { children: React.ReactNode }) {
  const { profile, user, error } = await getAuthenticatedOwner();

  if (!profile) {
    redirect(`/login?error=${encodeURIComponent(error ?? 'unauthorized')}`);
  }

  const mustChangePassword = ownerMustChangePassword(user?.user_metadata);

  return (
    <OwnerShell ownerName={profile.display_name} mustChangePassword={mustChangePassword}>
      {children}
    </OwnerShell>
  );
}

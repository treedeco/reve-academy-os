import { redirect } from 'next/navigation';
import { OwnerShell } from '@/components/owner/owner-shell';
import { ownerMustChangePassword } from '@/lib/auth/owner-password-metadata';
import { getAuthenticatedOwner } from '@/lib/auth/owner-session';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { profile, error } = await getAuthenticatedOwner(supabase);

  if (!profile) {
    redirect(`/login?error=${encodeURIComponent(error ?? 'unauthorized')}`);
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const mustChangePassword = ownerMustChangePassword(user?.user_metadata);

  return (
    <OwnerShell ownerName={profile.display_name} mustChangePassword={mustChangePassword}>
      {children}
    </OwnerShell>
  );
}

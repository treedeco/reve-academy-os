import { redirect } from 'next/navigation';
import { OwnerShell } from '@/components/owner/owner-shell';
import { getAuthenticatedOwner } from '@/lib/auth/owner-session';
import { createClient } from '@/lib/supabase/server';

export default async function OwnerLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { profile, error } = await getAuthenticatedOwner(supabase);

  if (!profile) {
    redirect(`/login?error=${encodeURIComponent(error ?? 'unauthorized')}`);
  }

  return <OwnerShell ownerName={profile.display_name}>{children}</OwnerShell>;
}

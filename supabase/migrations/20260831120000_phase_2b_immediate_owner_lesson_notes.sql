-- Phase 2B immediate operations: owner lesson_notes write access (permissions matrix alignment)

CREATE POLICY lesson_notes_owner_insert ON public.lesson_notes
  FOR INSERT TO authenticated
  WITH CHECK (
    reve_private.is_owner()
    AND author_profile_id = (SELECT auth.uid())
    AND visibility IN ('internal', 'student_visible')
  );

CREATE POLICY lesson_notes_owner_update ON public.lesson_notes
  FOR UPDATE TO authenticated
  USING (reve_private.is_owner())
  WITH CHECK (
    reve_private.is_owner()
    AND visibility IN ('internal', 'student_visible')
  );

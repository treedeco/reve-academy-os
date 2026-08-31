import type { SupabaseClient } from '@supabase/supabase-js';

export interface LessonNoteRecord {
  id: string;
  lesson_id: string;
  body: string;
  visibility: string;
  author_profile_id: string;
  created_at: string;
  updated_at: string;
}

export async function saveLessonNote(
  supabase: SupabaseClient,
  input: {
    lessonId: string;
    authorProfileId: string;
    body: string;
    noteId?: string | null;
    visibility?: 'internal' | 'student_visible';
  },
): Promise<LessonNoteRecord> {
  const trimmedBody = input.body.trim();
  if (!trimmedBody) {
    throw new Error('REVE_LESSON_NOTE_EMPTY');
  }

  const visibility = input.visibility ?? 'internal';

  if (input.noteId) {
    const { data, error } = await supabase
      .from('lesson_notes')
      .update({ body: trimmedBody, visibility })
      .eq('id', input.noteId)
      .select('id, lesson_id, body, visibility, author_profile_id, created_at, updated_at')
      .maybeSingle();

    if (error) {
      throw new Error(error.message);
    }
    if (data) {
      return data;
    }
  }

  const { data, error } = await supabase
    .from('lesson_notes')
    .insert({
      lesson_id: input.lessonId,
      author_profile_id: input.authorProfileId,
      body: trimmedBody,
      visibility,
    })
    .select('id, lesson_id, body, visibility, author_profile_id, created_at, updated_at')
    .single();

  if (error) {
    throw new Error(error.message);
  }

  return data;
}

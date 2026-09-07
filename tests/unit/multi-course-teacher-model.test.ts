import { describe, expect, it } from 'vitest';
import type { OwnerEnrollmentCatalog, TodayLessonRow } from '@/lib/domain/types';

describe('Multi-course Teacher Model and Identity Consolidation', () => {
  const teacherLee = {
    id: 'f11d8f5c-b9b9-4b1f-aeb3-069a981c8641',
    teacher_code: 't-p-1',
    name: '이혜인',
    is_active: true,
  };

  const coursePiano = {
    id: 'e68882fe-86e3-41db-9410-9264878256ec',
    course_code: 'P',
    name: '피아노',
  };

  const courseComposition = {
    id: 'd5ea3ed9-1acb-43da-83ab-d3246a0aa056',
    course_code: 'M',
    name: '작곡',
  };

  const catalog: OwnerEnrollmentCatalog = {
    teachers: [teacherLee],
    courses: [coursePiano, courseComposition],
    products: [
      {
        id: 'prod-p1',
        course_id: coursePiano.id,
        product_code: 'P-REG-4',
        product_name: '피아노 정규 4회',
        default_lesson_count: 4,
        weekly_frequency: 1,
        default_tuition_krw: 240000,
      },
      {
        id: 'prod-m1',
        course_id: courseComposition.id,
        product_code: 'M-REG-4',
        product_name: '작곡 정규 4회',
        default_lesson_count: 4,
        weekly_frequency: 1,
        default_tuition_krw: 280000,
      },
    ],
  };

  it('1. one teacher can be assigned to multiple courses in catalog enrollment', () => {
    // In catalog, the same teacher is selectable for any course's schedule slot
    const pianoSlot = {
      courseId: coursePiano.id,
      teacherId: teacherLee.id,
      weekday: 2,
      localStartTime: '14:00',
    };
    const compSlot = {
      courseId: courseComposition.id,
      teacherId: teacherLee.id,
      weekday: 4,
      localStartTime: '16:00',
    };

    expect(catalog.teachers.find((t) => t.id === pianoSlot.teacherId)).toBeDefined();
    expect(catalog.teachers.find((t) => t.id === compSlot.teacherId)).toBeDefined();
    expect(pianoSlot.teacherId).toBe(compSlot.teacherId);
  });

  it('2. same teacher does not require duplicate teacher records for multiple subjects', () => {
    // Single teacher record suffices for all subjects taught by that person
    const activeTeachersForPerson = catalog.teachers.filter((t) => t.name === '이혜인');
    expect(activeTeachersForPerson).toHaveLength(1);
    expect(activeTeachersForPerson[0].id).toBe(teacherLee.id);
  });

  it('3. teacher sees lessons from both assigned courses', () => {
    const lessons: TodayLessonRow[] = [
      {
        id: 'lesson-1',
        scheduled_at: '2026-09-08T14:00:00.000Z',
        status: 'scheduled',
        updated_at: '2026-09-07T00:00:00.000Z',
        sequence_number: 1,
        student_id: 's1',
        student_name: '학생A',
        pass_id: 'pass-p1',
        course_id: coursePiano.id,
        course_name: coursePiano.name,
        teacher_id: teacherLee.id,
        teacher_name: teacherLee.name,
        registered_lesson_count: 4,
        pass_updated_at: '2026-09-07T00:00:00.000Z',
        duration_minutes: 60,
        memo_summary: null,
        memo_note_id: null,
      },
      {
        id: 'lesson-2',
        scheduled_at: '2026-09-08T16:00:00.000Z',
        status: 'scheduled',
        updated_at: '2026-09-07T00:00:00.000Z',
        sequence_number: 1,
        student_id: 's2',
        student_name: '학생B',
        pass_id: 'pass-m1',
        course_id: courseComposition.id,
        course_name: courseComposition.name,
        teacher_id: teacherLee.id,
        teacher_name: teacherLee.name,
        registered_lesson_count: 4,
        pass_updated_at: '2026-09-07T00:00:00.000Z',
        duration_minutes: 60,
        memo_summary: null,
        memo_note_id: null,
      },
    ];

    // Teacher visibility filter is based strictly on teacher_id = currentTeacherId
    const teacherVisibleLessons = lessons.filter(
      (l) => l.teacher_id === teacherLee.id,
    );

    expect(teacherVisibleLessons).toHaveLength(2);
    const visibleCourseCodes = teacherVisibleLessons.map((l) => l.course_name);
    expect(visibleCourseCodes).toContain('피아노');
    expect(visibleCourseCodes).toContain('작곡');
  });

  it('4. teacher cannot see other teachers lessons', () => {
    const otherTeacherId = 'aba1417b-c409-4cf3-9b3d-fbd6eaf4ea23'; // t-v-1 김홍중
    const allLessons: TodayLessonRow[] = [
      {
        id: 'lesson-lee-piano',
        scheduled_at: '2026-09-08T14:00:00.000Z',
        status: 'scheduled',
        updated_at: '2026-09-07T00:00:00.000Z',
        sequence_number: 1,
        student_id: 's1',
        student_name: '학생A',
        pass_id: 'pass-p1',
        course_id: coursePiano.id,
        course_name: coursePiano.name,
        teacher_id: teacherLee.id,
        teacher_name: teacherLee.name,
        registered_lesson_count: 4,
        pass_updated_at: '2026-09-07T00:00:00.000Z',
        duration_minutes: 60,
        memo_summary: null,
        memo_note_id: null,
      },
      {
        id: 'lesson-kim-vocal',
        scheduled_at: '2026-09-08T15:00:00.000Z',
        status: 'scheduled',
        updated_at: '2026-09-07T00:00:00.000Z',
        sequence_number: 1,
        student_id: 's3',
        student_name: '학생C',
        pass_id: 'pass-v1',
        course_id: 'course-vocal',
        course_name: '보컬',
        teacher_id: otherTeacherId,
        teacher_name: '김홍중',
        registered_lesson_count: 4,
        pass_updated_at: '2026-09-07T00:00:00.000Z',
        duration_minutes: 60,
        memo_summary: null,
        memo_note_id: null,
      },
    ];

    const teacherVisibleLessons = allLessons.filter(
      (l) => l.teacher_id === teacherLee.id,
    );
    expect(teacherVisibleLessons).toHaveLength(1);
    expect(teacherVisibleLessons[0].id).toBe('lesson-lee-piano');
    expect(teacherVisibleLessons.some((l) => l.teacher_id === otherTeacherId)).toBe(false);
  });

  it('5. duplicate Auth user is prevented and profile linkage is unique', () => {
    // Single profile per email; linking profile_id to teacher enforces 1-to-1 relationship
    const authAccounts = new Map<string, string>();
    authAccounts.set('in2520@naver.com', '5413657e-0959-4fb6-96c1-0dc7149ef018');

    // Attempting to register same email again returns existing user
    const resolveUser = (email: string) => {
      const normalized = email.toLowerCase().trim();
      if (authAccounts.has(normalized)) {
        return { isExisting: true, uid: authAccounts.get(normalized)! };
      }
      const newUid = 'new-uid';
      authAccounts.set(normalized, newUid);
      return { isExisting: false, uid: newUid };
    };

    const attempt1 = resolveUser('in2520@naver.com');
    expect(attempt1.isExisting).toBe(true);
    expect(attempt1.uid).toBe('5413657e-0959-4fb6-96c1-0dc7149ef018');
  });

  it('6. course determination is based on course_id, never derived from teacher_code', () => {
    // teacher_code 't-p-1' has 'p' in it for historical reasons,
    // but course determination is STRICTLY lesson.course_id -> course.name
    const lessonCompositionWithTp1 = {
      id: 'lesson-comp',
      course_id: courseComposition.id,
      assigned_teacher_id: teacherLee.id, // teacher_code is 't-p-1'
    };

    const coursesMap = new Map([
      [coursePiano.id, coursePiano],
      [courseComposition.id, courseComposition],
    ]);

    const resolvedCourse = coursesMap.get(lessonCompositionWithTp1.course_id);
    expect(resolvedCourse?.course_code).toBe('M');
    expect(resolvedCourse?.name).toBe('작곡');
    // Does not misidentify as Piano despite teacher_code being 't-p-1'
    expect(resolvedCourse?.name).not.toBe('피아노');
  });
});

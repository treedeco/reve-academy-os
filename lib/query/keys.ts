export const queryKeys = {
  todayLessons: ['owner', 'today-lessons'] as const,
  dashboard: ['owner', 'dashboard'] as const,
  students: (search: string) => ['owner', 'students', search] as const,
  studentDetail: (studentId: string) => ['owner', 'student-detail', studentId] as const,
  passUsage: (passId: string) => ['owner', 'pass-usage', passId] as const,
};

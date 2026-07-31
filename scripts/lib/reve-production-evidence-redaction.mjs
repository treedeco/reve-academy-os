/**
 * Redact sensitive fields from operator evidence payloads before writing to disk.
 */

export function redactUuid(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return value ?? null;
  }
  if (value.length <= 8) {
    return '…';
  }
  return `${value.slice(0, 8)}…`;
}

function redactStudentRecord(student) {
  if (!student || typeof student !== 'object') {
    return student;
  }
  return {
    ...student,
    id: student.id ? redactUuid(student.id) : student.id,
    code: student.code ?? null,
    name: student.name ?? null,
  };
}

function redactTeacherRecord(teacher) {
  if (!teacher || typeof teacher !== 'object') {
    return teacher;
  }
  return {
    ...teacher,
    code: teacher.code ?? null,
    name: teacher.name ?? null,
  };
}

export function redactProductionEvidence(evidence) {
  const copy = structuredClone(evidence);

  if (copy.stage1 && typeof copy.stage1 === 'object') {
    delete copy.stage1.passwordConfigured;
    delete copy.stage1.passwordLength;
    if (copy.stage1.authUserId) {
      copy.stage1.authUserId = redactUuid(copy.stage1.authUserId);
    }
  }

  if (copy.records?.students && typeof copy.records.students === 'object') {
    for (const key of Object.keys(copy.records.students)) {
      copy.records.students[key] = redactStudentRecord(copy.records.students[key]);
    }
  }

  if (copy.records?.teachers && typeof copy.records.teachers === 'object') {
    for (const key of Object.keys(copy.records.teachers)) {
      copy.records.teachers[key] = redactTeacherRecord(copy.records.teachers[key]);
    }
  }

  if (copy.cleanup?.deletedDisposableStudents) {
    copy.cleanup.deletedDisposableStudents = copy.cleanup.deletedDisposableStudents.map(redactUuid);
  }

  if (Array.isArray(copy.cleanup?.retainedRecords)) {
    copy.cleanup.retainedRecords = copy.cleanup.retainedRecords.map((row) => {
      if (!row || typeof row !== 'object') {
        return row;
      }
      if (row.id) {
        return { ...row, id: redactUuid(row.id) };
      }
      return row;
    });
  }

  return copy;
}

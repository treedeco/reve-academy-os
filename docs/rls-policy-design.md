# RLS Policy Design — REVE ACADEMY OS

Phase **0B-2** Row Level Security architecture. **No executable SQL.** Authority: [permissions-matrix.md](./permissions-matrix.md), [postgresql-physical-design.md](./postgresql-physical-design.md).

---

## 1. Global RLS rules

| Rule | Requirement |
|------|-------------|
| RLS on all tables | Every application table in `public` has `ENABLE ROW LEVEL SECURITY` |
| Default deny | No broad `authenticated` SELECT/INSERT/UPDATE/DELETE without explicit policy |
| Service role | `service_role` used only server-side; never exposed to clients |
| Historical DELETE | No DELETE policy for passes, lessons, payments, refunds, SMS, schedule events, audit_logs |
| Audit writes | No normal-client INSERT/UPDATE/DELETE on `audit_logs` |
| Sensitive transitions | Pass lifecycle, payment completion, lesson status (ordinary + correction), refund, cascade — **trusted operations only** |
| Anonymous | Deny all unless future public endpoint explicitly approved |
| Bypass | Trusted functions run as `SECURITY DEFINER` with fixed `search_path`; not callable with elevated scope by arbitrary SQL from clients |

---

## 2. Identity helper strategy (contracts)

Future helpers in `public` schema. **Design contracts only.**

| Function | Returns | Purpose |
|----------|---------|---------|
| `current_profile_id()` | uuid | `auth.uid()` mapped to profile (same as auth id) |
| `current_app_role()` | text | Role from `profiles` for current user |
| `is_owner()` | boolean | `current_app_role() = 'owner'` |
| `current_teacher_id()` | uuid | Teacher row id for current profile, or NULL |
| `current_student_id()` | uuid | Student row id for current profile, or NULL |
| `teacher_can_access_student(p_student_id uuid)` | boolean | Teacher assigned via lessons or active slots |
| `teacher_can_access_lesson(p_lesson_id uuid)` | boolean | `assigned_teacher_id` matches current teacher |
| `student_owns_pass(p_pass_id uuid)` | boolean | Pass belongs to current student |
| `student_owns_lesson(p_lesson_id uuid)` | boolean | Lesson student matches current student |

### SECURITY DEFINER requirements

- `SET search_path = public, pg_temp`
- Owner: fixed superuser or migration role; clients cannot `CREATE OR REPLACE`
- Minimal table grants inside function body only
- Fully qualified object names (`public.lessons`)
- No RLS recursion (helpers read profiles with `security_barrier` or bypass via controlled definer)
- `REVOKE ALL ON FUNCTION ... FROM PUBLIC`; grant `EXECUTE` only to `authenticated` where needed for read helpers; trusted mutators grant only to `service_role`

---

## 3. Per-table RLS matrix

Legend: **Y** = policy allows (with predicate); **—** = no policy (deny); **T** = trusted operation only (no direct table policy for mutation); **A** = audit required on allowed write.

### 3.1 `profiles`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate / notes |
|------|--------|--------|--------|--------|-------------------|
| Owner | Y | T | T† | — | All profiles; role/account_state via trusted; multi-owner allowed (OD-21 provisional) |
| Teacher | Y | — | Y | — | Own row; `display_name` only |
| Student | Y | — | Y | — | Own row; `display_name` only |
| Anonymous | — | — | — | — | |
| Trusted | T | T | T | — | Bootstrap, role assign |

Sensitive columns excluded from direct UPDATE: `role`, `account_state`.

> **Provisional policy — subject to owner review before executable migration** (OD-21): Multiple owner profiles allowed; at least one active owner; final active owner cannot remove own owner role.

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | Y A | Y A | — | All |
| Teacher | Y | — | — | — | `teacher_can_access_student(id)` |
| Student | Y | — | — | — | `profile_id = current_profile_id()` |
| Anonymous | — | — | — | — | |
| Trusted | Y | T | T | — | Profile link |

Excluded: operational/financial fields for Student (no UPDATE policy).

### 3.3 `teachers`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | Y | Y A | — | All |
| Teacher | Y | — | Y | — | Own `profile_id` |
| Student | Y | — | — | — | Minimal display: teachers on own lessons only (join via lesson) |
| Anonymous | — | — | — | — | |
| Trusted | Y | — | — | — | |

Student policy exposes only `id`, `name` (not phone/email) via view or column-limited policy pattern.

### 3.4 `courses` / `course_products`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | Y | Y A | — | All |
| Teacher | Y | — | — | — | `is_active = true` |
| Student | Y | — | — | — | Courses linked to own passes, active only |
| Trusted | Y | — | — | — | Snapshot read on pass create |

Pricing columns on products: Owner UPDATE only.

### 3.5 `passes`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | T | T† | — | All |
| Teacher | Y | — | — | — | Assigned student or assigned lesson on pass |
| Student | Y | — | — | — | `student_id = current_student_id()` |
| Trusted | Y | T | T | — | Lifecycle only |

No client INSERT/UPDATE for lifecycle fields or snapshots.

### 3.6 `schedule_slots`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | T | T | — | All |
| Teacher | Y | — | — | — | `teacher_id = current_teacher_id()` |
| Student | Y | — | — | — | Pass owned by student; pass status active or reserved |
| Trusted | Y | T | T | — | `replace_pass_schedule_slots` |

### 3.7 `lessons`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | T | T† | — | All |
| Teacher | Y | — | T | — | `teacher_can_access_lesson(id)`; status via trusted |
| Student | Y | — | — | — | `student_owns_lesson(id)` |
| Trusted | Y | T | T | — | Generation, correction, cascade |

Student: no UPDATE. Teacher: no direct UPDATE policy (use `transition_lesson_status`).

### 3.8 `payments`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | Y | T | — | All |
| Teacher | — | — | — | — | No financial access |
| Student | Y | — | — | — | Own `student_id`; payment-facing fields only |
| Trusted | Y | T | T | — | Completion, refund |

### 3.9 `payment_refunds`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | T | — | — | All |
| Teacher | — | — | — | — | |
| Student | Y | — | — | — | Own payment chain (optional MVP) |
| Trusted | Y | T | — | — | Insert only via refund op |

Append-only: no UPDATE/DELETE policies for any role.

### 3.10 `sms_notifications`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | T | T† | — | All; sent confirm |
| Teacher | — | — | — | — | Denied MVP |
| Student | Y† | — | — | — | Own current-pass row; `message_body_snapshot` only when UI exposes (OD-20 provisional). Status, target_date, actor fields **hidden** |
| Trusted | Y | T | T | — | Recalc |

### 3.11 `schedule_change_requests`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | Y | Y A | — | All; approve/reject |
| Teacher | Y | Y | Y | — | Assigned lessons; suggestion fields |
| Student | Y | Y | Y | — | Own eligible lessons |
| Trusted | Y | T | T | — | Apply approved |

Applied requests: immutable (no UPDATE after `applied`).

### 3.12 `lesson_schedule_changes`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | T | — | — | Scope via lesson |
| Teacher | Y | — | — | — | Assigned lessons |
| Student | Y | — | — | — | Own lessons |
| Trusted | Y | T | — | — | Append only |

### 3.13 `lesson_notes`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | — | Y | — | All |
| Teacher | Y | Y | Y A | — | Assigned lessons |
| Student | Y | — | — | — | `visibility = student_visible` AND own lesson |
| Trusted | — | — | — | — | |

### 3.14 `audit_logs`

| Role | SELECT | INSERT | UPDATE | DELETE | Predicate |
|------|--------|--------|--------|--------|-----------|
| Owner | Y | — | — | — | Administrative need |
| Teacher | — | — | — | — | |
| Student | — | — | — | — | |
| Anonymous | — | — | — | — | |
| Trusted | Y | T | — | — | Append only |

---

## 4. Policy naming convention

Pattern: `{table}_{role}_{command}` e.g. `lessons_teacher_select`, `payments_owner_select`.

Separate policies per command (SELECT, INSERT, UPDATE, DELETE) for clarity and testing.

---

## 5. Alignment with permissions matrix

| Matrix rule | RLS enforcement |
|-------------|-----------------|
| Teacher no revenue | No SELECT on payments for teacher role |
| Student no lesson status edit | No UPDATE on lessons for student |
| Pass renewal trusted | No INSERT on passes for client roles |
| Refund coordinated | No INSERT on payment_refunds except via definer |
| Audit append-only | INSERT only trusted; no UPDATE/DELETE policies |
| Physical delete prohibited | No DELETE policies on historical tables |

---

## Related documents

- [postgresql-physical-design.md](./postgresql-physical-design.md)
- [trusted-operation-contracts.md](./trusted-operation-contracts.md)
- [permissions-matrix.md](./permissions-matrix.md)
- [database-test-plan.md](./database-test-plan.md)

---

## 6. Phase 0B-3B-1 implementation status

**Implemented (Phase 0B-3B-1, tag `phase-0b3b1-identity-rls`):**

- Private authorization schema `reve_private` (not exposed via Supabase Data API)
- Identity helpers: `current_profile_id()`, `current_app_role()`, `is_owner()`, `current_teacher_id()`, `current_student_id()`, `teacher_can_access_student()`, `teacher_can_access_lesson()`, `teacher_can_access_schedule_slot()`, `teacher_can_access_schedule_request()`, `student_owns_lesson()`, `student_owns_schedule_slot()`, `student_owns_schedule_request()`
- Least-privilege `SELECT` grants for `authenticated` on all 15 application tables (RLS predicates enforce role scope)
- Role-scoped RLS policies targeting `authenticated` only (no `anon` policies; no `DELETE` policies)
- Direct client writes limited to:
  - Teacher `INSERT` / column-limited `UPDATE` on `lesson_notes`
  - Student and teacher `INSERT` on `schedule_change_requests` (submitted-only; decision fields protected)

**Intentionally deferred (not available through the client yet):**

| Deferred path | Reason |
|---------------|--------|
| Teacher pass-usage summary | Pass base table withheld from teachers (financial snapshots) |
| Student pass summary | Pass base table withheld from students |
| Student payment-facing summary | Payment base table withheld from students |
| Student teacher-display projection | Full `teachers` table withheld from students (internal contact fields) |
| Student SMS message projection | SMS base table withheld from students while OD-20 is provisional |
| Owner master-data mutation (students, teachers, courses, products) | No column-safe direct writes implemented; trusted operations pending |
| Profile provisioning and role changes | Trusted-operation-only |
| Profile `display_name` self-update | Not implemented in 0B-3B-1 |
| Lesson status transitions | Trusted-operation-only |
| Pass lifecycle changes | Trusted-operation-only |
| Payment completion and renewal | Trusted-operation-only |
| Refund processing | Trusted-operation-only |
| Schedule request approval / rejection / application | No direct UPDATE policies in 0B-3B-1 |
| Schedule cascading | Trusted-operation-only |
| SMS recalculation | Trusted-operation-only |
| Audit log insertion | Trusted-operation-only |
| Lesson schedule change event insertion | Trusted-operation-only |

Do not treat the above as client-available features until a later phase implements safe projections or trusted operations.

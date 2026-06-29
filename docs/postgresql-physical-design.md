# PostgreSQL Physical Design — REVE ACADEMY OS

Phase **0B-2** physical schema specification. **No executable SQL.** Logical source: [schema-dictionary.md](./schema-dictionary.md), [data-integrity-constraints.md](./data-integrity-constraints.md).

---

## 1. Schema and naming

| Element | Convention |
|---------|------------|
| Schema | `public` for all application tables (Supabase-accessible) |
| Internal helpers | `public` functions with `reve_` prefix; no extra schema unless security review requires |
| Tables | lowercase `snake_case`, plural where natural (`passes`, `lessons`) |
| Columns | lowercase `snake_case` |
| Primary keys | `{table_singular}_pkey` e.g. `passes_pkey` |
| Foreign keys | `{child_table}_{referenced_table}_fkey` |
| Unique | `{table}_{columns}_key` or `{table}_{purpose}_uniq` |
| Check | `{table}_{column}_check` |
| Partial unique | `{table}_{purpose}_partial_uniq` |
| Indexes | `{table}_{columns}_idx` |
| RLS policies | `{table}_{role}_{operation}` e.g. `lessons_teacher_select` |
| Functions | `reve_{verb}_{object}` e.g. `reve_complete_payment_and_renew_pass` |
| Triggers | `trg_{table}_{purpose}` |
| Views | `reve_{purpose}_v` e.g. `reve_pass_usage_summary_v` |

Identifiers: lowercase `snake_case` only.

---

## 2. Status representation

**Decision**: `text` columns + named `CHECK` constraints (not PostgreSQL `ENUM` types).

| Rationale | Detail |
|-----------|--------|
| Extensibility | New status values via migration adding CHECK without enum rewrite |
| Alignment | Exact canonical English values from [state-transitions.md](./state-transitions.md) |
| Supabase | Simple introspection and RLS predicates |

### Allowed value sets (approved)

| Column / domain | CHECK values |
|-----------------|--------------|
| `profiles.role` | `owner`, `teacher`, `student` |
| `profiles.account_state` | `active`, `inactive`, `suspended` |
| `students.operational_status` | `active`, `inactive`, `archived` |
| `passes.status` | `reserved`, `active`, `completed`, `expired`, `cancelled` |
| `lessons.status` | `scheduled`, `completed`, `same_day_cancelled`, `makeup_completed`, `postponed`, `advance_cancelled`, `teacher_cancelled`, `academy_closed` |
| `payments.status` | `pending`, `completed`, `cancelled`, `refunded` |
| `sms_notifications.status` | `normal`, `scheduled`, `target`, `exhausted_unsent`, `sent` |
| `schedule_change_requests.status` | `submitted`, `under_review`, `approved`, `rejected`, `cancelled`, `applied` |
| `lesson_schedule_changes.change_origin` | `direct_user`, `cascade_auto`, `trusted_system`, `correction` |
| `lesson_notes.visibility` | `internal`, `student_visible` |
| `payment_refunds.pass_disposition` | `reserved_cancelled`, `active_cancelled_future_advance_cancelled` (extend via migration only) |

### OD-18 — Payment method (Provisional policy — subject to owner review before executable migration)

| Rule | Detail |
|------|--------|
| Allowed values | `cash`, `bank_transfer`, `card`, `other` |
| Pending | `payment_method` **NULL** allowed |
| Completed | `payment_method` **required**; `other` requires note (TF/app validation) |
| Status | Provisional 2026-06-26 — review in payment UI phase |

See [open-decisions.md](./open-decisions.md) OD-18.

---

## 3. Authentication mapping

### Physical mapping (Phase 0B-2)

| Rule | Detail |
|------|--------|
| PK = Auth ID | `profiles.id` **is** `auth.users.id` (same UUID) |
| FK | `profiles.id` → `auth.users(id)` ON DELETE **RESTRICT** |
| Business records | `students.profile_id`, `teachers.profile_id` optional, **UNIQUE** when not null |
| Pre-login | Student/teacher rows may exist with `profile_id` NULL |
| Roles | `profiles.role` mutable only via trusted `reve_set_profile_role` |
| Secrets | No passwords/tokens in app tables |

**Schema-dictionary correction**: Phase 0B-1 separate `auth_user_id` column is **superseded** — single `id` column serves both roles.

### Deactivation vs deletion

> **Provisional policy — subject to owner review before executable migration** (OD-19)

| Action | Strategy |
|--------|----------|
| User logout / inactive | `profiles.account_state` → `inactive` or `suspended` |
| Auth user delete | **Prohibited in MVP** — deactivate only; no physical delete |
| Personal data | Anonymization = future owner-controlled workflow |
| Historical refs | Passes, lessons, payments, refunds, audit logs **preserved**; actor FKs may SET NULL with snapshot |
| Business retire | `students.operational_status` / `teachers.is_active` — no DELETE |

---

## 4. Physical table summary (15 tables)

Each table: RLS enabled; no client DELETE on historical entities. Details match [schema-dictionary.md](./schema-dictionary.md) unless noted below.

### 4.1 `profiles`

| Aspect | Specification |
|--------|---------------|
| PK | `id uuid` → `auth.users(id)` |
| Unique | — |
| Immutable | `id`, `created_at` |
| Trusted-only | `role`, `account_state` (normal client) |
| Indexes | `profiles_role_idx` (admin queries) |
| ON DELETE | RESTRICT from auth |

### 4.2 `students`

| Aspect | Specification |
|--------|---------------|
| PK | `id uuid` DEFAULT `gen_random_uuid()` |
| FK | `profile_id` → `profiles(id)` ON DELETE SET NULL, UNIQUE partial |
| Unique | `student_code` |
| Immutable | `student_code`, `created_at` |
| Indexes | `student_code` (unique), `profile_id` (unique where not null) |
| RLS path | Owner all; Teacher via assignment views; Student `profile_id = current_profile_id()` |

### 4.3 `teachers`

| Aspect | Specification |
|--------|---------------|
| PK | `id uuid` |
| FK | `profile_id` → `profiles(id)` ON DELETE SET NULL, UNIQUE |
| Unique | `teacher_code` |
| Indexes | `teacher_code`, `profile_id`, `is_active` |

### 4.4 `courses` / 4.5 `course_products`

| FK | `course_products.course_id` → `courses(id)` ON DELETE **RESTRICT** |
| Unique | `course_code`, `product_code` |
| CHECK | lesson_count > 0, weekly_frequency > 0, tuition >= 0 |
| ON DELETE | RESTRICT — deactivate via `is_active` |

### 4.6 `passes`

| PK | `id uuid` |
| FK | `student_id` → students RESTRICT; `course_id` → courses RESTRICT; `course_product_id` RESTRICT; `previous_pass_id`, `correction_source_pass_id` → passes RESTRICT |
| Unique | `pass_code`; `(student_id, course_id, sequence_number)`; partial `(student_id, course_id) WHERE status='active'`; partial WHERE `status='reserved'` |
| Composite parent key | **UNIQUE** `(id, student_id, course_id)` for lesson composite FK |
| Immutable | `pass_code`, snapshots, `sequence_number`, `student_id`, `course_id`, `course_product_id`, lifecycle timestamps once set |
| Trusted-only | CREATE, status transitions, cancel |
| Indexes | `(student_id, course_id, status)`, `pass_code`, `previous_pass_id` |

### 4.7 `schedule_slots`

| FK | `pass_id` → passes RESTRICT; `teacher_id` → teachers RESTRICT |
| Partial unique | active duplicate (pass_id, weekday, local_start_time, teacher_id) WHERE `is_active` |
| ON DELETE | RESTRICT |

### 4.8 `lessons`

| FK | `(pass_id, student_id, course_id)` → `passes(id, student_id, course_id)` RESTRICT; `assigned_teacher_id` → teachers RESTRICT; `schedule_slot_id` SET NULL; `makeup_source_lesson_id` → lessons RESTRICT |
| Unique | `(pass_id, sequence_number)` |
| Partial unique | `(makeup_source_lesson_id) WHERE status='makeup_completed'` |
| CHECK | `makeup_source_lesson_id <> id` |
| Immutable | `pass_id`, `student_id`, `course_id`, `sequence_number`, `makeup_source_lesson_id` |
| Trusted-only | status changes (ordinary + owner correction), cascade moves |
| Indexes | `(pass_id, sequence_number)`, `(assigned_teacher_id, scheduled_at)`, `(student_id, scheduled_at)`, `scheduled_at`, `makeup_source_lesson_id` |

### 4.9 `payments`

| FK | student, course, course_product RESTRICT; `related_pass_id`, `renewed_pass_id` → passes RESTRICT |
| Unique | `idempotency_key`; `renewed_pass_id` unique where not null (one pass per payment) |
| Trusted-only | complete, cancel, refund trigger |
| Indexes | `idempotency_key`, `(student_id, paid_at DESC)` |

### 4.10 `payment_refunds`

| FK | `payment_id` → payments RESTRICT **UNIQUE** (OD-13) |
| Append-only | no UPDATE/DELETE policies |
| Trusted-only | INSERT |

### 4.11 `sms_notifications`

| FK | student, pass RESTRICT |
| Composite | `(pass_id, student_id)` must match pass — enforced in trusted ops + optional CHECK via join in TF |
| Unique MVP | one row per `(pass_id, notification_type)` where type = `renewal_reminder` |

### 4.12 `schedule_change_requests`

| FK | `target_lesson_id` → lessons RESTRICT; `student_id` consistent with lesson (TF + composite lesson FK); `requesting_profile_id` → profiles RESTRICT |
| Immutable after apply | status, proposed times, decision fields |

### 4.13 `lesson_schedule_changes`

Append-only; FK lesson RESTRICT; optional request FK RESTRICT.

### 4.14 `lesson_notes`

FK lesson, author profile RESTRICT; visibility CHECK.

### 4.15 `audit_logs`

Append-only; no FK CASCADE deletes; `resource_id` uuid without FK (polymorphic) — integrity via trusted ops.

---

## 5. Foreign-key ON DELETE summary

| Relationship | ON DELETE | Reason |
|--------------|-----------|--------|
| passes → students/courses/products | RESTRICT | History preservation |
| lessons → passes | RESTRICT | No cascade delete lessons |
| payments → passes | RESTRICT | Financial history |
| payment_refunds → payments | RESTRICT | Refund history |
| profiles → auth.users | RESTRICT | Prevent orphan auth delete wiping app |
| students/teachers → profiles | SET NULL | Business record survives profile retire |
| schedule_slots → pass | RESTRICT | Slot history |
| audit_logs → profiles (actor) | SET NULL | Preserve log with snapshot |

**Never** ON DELETE CASCADE on passes, lessons, payments, refunds, SMS, schedule events, audit_logs.

---

## 6. Composite consistency

### Lessons → passes

```
passes: UNIQUE (id, student_id, course_id)
lessons: FK (pass_id, student_id, course_id) REFERENCES passes(id, student_id, course_id)
```

### Payments

Trusted creation sets `student_id`, `course_id` from payment context; optional CHECK that `related_pass_id` belongs to same student when set.

### SMS notifications

On insert (trusted): `student_id`, `pass_id` copied from pass row; optional trigger/TF validation.

### Schedule change requests

`student_id` must match `target_lesson_id` student — validated in TF before insert.

---

## 7. Pass sequence race safety

| Step | Mechanism |
|------|-----------|
| 1 | `SELECT ... FROM students WHERE id = ? FOR UPDATE` in renewal transaction |
| 2 | Read max `sequence_number` for (student_id, course_id) **inside** locked transaction |
| 3 | Insert pass with next sequence; unique constraints as backstop |
| 4 | On unique violation → rollback and surface error (no silent retry without idempotency) |
| 5 | Payment idempotency key returns existing pass on duplicate completion call |

Do **not** use unlocked `MAX()+1` outside transaction.

---

## 7.1 Reserved pass and lesson dates (OD-14)

> **Provisional policy — subject to owner review before executable migration**

| Phase | Behavior |
|-------|----------|
| Reserved pass created | `start_date` may be placeholder; **lesson rows not finalized** until activation |
| Activation | When current pass completes, first valid configured schedule slot **after completion** anchors first lesson |
| Review | Pass-renewal UI design |

---

## 7.2 Schedule slot copy (OD-15)

> **Provisional policy — subject to owner review before executable migration**

On renewal: copy **active** slots from current pass into new pass as **new independent rows** (snapshot). Owner may edit before activation. Prior pass slot changes do not affect new pass rows.

---

## 7.3 Lesson generation order (OD-16)

> **Provisional policy — subject to owner review before executable migration**

Sort occurrences **chronologically**; tie-break `slot_order`; assign `sequence_number` from sorted order.

---

## 7.4 Collision handling (OD-17)

> **Provisional policy — subject to owner review before executable migration**

On collision (overlap, closure, double-book): **abort** operation; return collision list; **no** automatic arbitrary reschedule. Owner fixes and retries.

---

## 8. Derived read models (non-authoritative)

| View / function (design name) | Purpose |
|------------------------------|---------|
| `reve_pass_usage_summary_v` | used/remaining per pass from lesson status |
| `reve_current_pass_summary_v` | active + reserved per student/course |
| `reve_teacher_student_assignments_v` | distinct students from lessons/slots |
| `reve_today_lessons_v` | lessons scheduled today Asia/Seoul |
| `reve_next_lesson_v` | next scheduled per student/pass |
| `reve_dashboard_counters_v` | Owner-scoped aggregates: enrolled students, active passes, today lesson count, SMS target/exhausted counts — **not** full-academy rebuild |

- **STABLE** read functions for parameterized queries (e.g. `reve_dashboard_counters_for_owner()`)
- No materialized views in MVP
- No stored used/remaining columns
- Dashboard values computed incrementally or scoped by filter — never global recalc after every row change

**Usage formula** (in view):

```sql
-- conceptual only
used = count(*) filter (status in ('completed','same_day_cancelled','makeup_completed'))
remaining = registered_lesson_count_snapshot - used
```

---

## 9. Index strategy

### 9.1 Required indexes (by query pattern)

| Pattern | Table | Index (design name) | Columns |
|---------|-------|---------------------|---------|
| Student lookup by code | `students` | `students_student_code_idx` | `student_code` (UK) |
| Teacher lookup by code | `teachers` | `teachers_teacher_code_idx` | `teacher_code` (UK) |
| Pass by student/course/status | `passes` | `passes_student_course_status_idx` | `(student_id, course_id, status)` |
| Lesson by pass + sequence | `lessons` | `lessons_pass_sequence_idx` | `(pass_id, sequence_number)` UK |
| Lesson by scheduled time | `lessons` | `lessons_scheduled_at_idx` | `scheduled_at` |
| Lesson by teacher + time | `lessons` | `lessons_teacher_scheduled_idx` | `(assigned_teacher_id, scheduled_at)` |
| Today's lessons | `lessons` | (partial) `lessons_today_seoul_idx` | `scheduled_at` WHERE date in Seoul = today — or rely on `scheduled_at` + app filter |
| Student lesson history | `lessons` | `lessons_student_scheduled_idx` | `(student_id, scheduled_at DESC)` |
| Payment idempotency | `payments` | `payments_idempotency_key_idx` | `idempotency_key` UK |
| Payment history by student | `payments` | `payments_student_paid_at_idx` | `(student_id, paid_at DESC)` |
| SMS state + target date | `sms_notifications` | `sms_status_target_date_idx` | `(status, target_date)` |
| Schedule requests by status | `schedule_change_requests` | `scr_status_idx` | `status` |
| Audit by resource + time | `audit_logs` | `audit_resource_created_idx` | `(resource_table, resource_id, created_at DESC)` |
| Lesson notes by lesson | `lesson_notes` | `lesson_notes_lesson_id_idx` | `lesson_id` |
| Makeup source lookup | `lessons` | `lessons_makeup_source_idx` | `makeup_source_lesson_id` |
| Schedule slot by pass + active | `schedule_slots` | `schedule_slots_pass_active_idx` | `(pass_id, is_active)` |

Constraint-backed partial uniques (pass active/reserved, slot duplicate, makeup) are listed in §4 and [data-integrity-constraints.md](./data-integrity-constraints.md).

### 9.2 Verification

See per-table indexes in §4 and Appendix A. Priority:

1. Unique / partial unique (constraint backing)
2. RLS join paths (teacher_id, student_id, profile_id)
3. Operational queries (scheduled_at, status filters)
4. Audit (resource_table, created_at)

Verify with `EXPLAIN` after implementation; avoid duplicate indexes on same column set.

---

## 10. Timestamp maintenance

| Column type | Strategy |
|-------------|----------|
| `created_at` | DEFAULT `now()` at insert; immutable |
| `updated_at` | DEFAULT `now()`; future `trg_set_updated_at` BEFORE UPDATE on mutable tables |
| Event timestamps (`refunded_at`, `sent_at`, `decided_at`, `applied_at`) | Set once in trusted op; immutable |
| Business dates | `date` / `timestamptz` set by domain rules; Asia/Seoul interpretation in app/TF |

**Trigger design** (future): single `reve_set_updated_at()` for tables with `updated_at` — not implemented in Phase 0B-2.

---

## Related documents

- [rls-policy-design.md](./rls-policy-design.md)
- [trusted-operation-contracts.md](./trusted-operation-contracts.md)
- [database-migration-plan.md](./database-migration-plan.md)

---

## Appendix A — Full physical column specification (15 tables)

Column definitions align with [schema-dictionary.md](./schema-dictionary.md). Types are PostgreSQL. **No CREATE TABLE.**

### A.1 `profiles`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index | Notes |
|--------|------|------|---------|----------|-----------|-------|-------|-------|
| `id` | uuid | NO | — | PK, FK→auth.users | RESTRICT | — | PK | = auth user id |
| `role` | text | NO | — | — | — | owner/teacher/student | role_idx | Trusted-only write |
| `display_name` | text | NO | — | — | — | length>0 | — | Self limited update |
| `account_state` | text | NO | active | — | — | active/inactive/suspended | — | Trusted-only |
| `created_at` | timestamptz | NO | now() | — | — | — | — | Immutable |
| `updated_at` | timestamptz | NO | now() | — | — | — | — | Trigger later |

### A.2 `students`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `student_code` | text | NO | — | UK | — | pattern TBD | UK |
| `profile_id` | uuid | YES | — | FK→profiles, UK partial | SET NULL | — | UK where not null |
| `name` | text | NO | — | — | — | length>0 | — |
| `phone` | text | YES | — | — | — | — | — |
| `email` | text | YES | — | — | — | — | — |
| `operational_status` | text | NO | active | — | — | active/inactive/archived | status_idx |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

RLS: `profile_id = current_profile_id()` for student self.

### A.3 `teachers`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `teacher_code` | text | NO | — | UK | — | — | UK |
| `profile_id` | uuid | YES | — | FK→profiles, UK | SET NULL | — | UK |
| `name` | text | NO | — | — | — | length>0 | — |
| `phone` | text | YES | — | — | — | — | — |
| `email` | text | YES | — | — | — | — | — |
| `is_active` | boolean | NO | true | — | — | — | is_active_idx |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

### A.4 `courses`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `course_code` | text | NO | — | UK | — | — | UK |
| `name` | text | NO | — | — | — | length>0 | — |
| `description` | text | YES | — | — | — | — | — |
| `is_active` | boolean | NO | true | — | — | — | is_active_idx |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

### A.5 `course_products`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `course_id` | uuid | NO | — | FK→courses | RESTRICT | — | course_id_idx |
| `product_code` | text | NO | — | UK | — | — | UK |
| `product_name` | text | NO | — | — | — | length>0 | — |
| `default_lesson_count` | integer | NO | — | — | — | >0 | — |
| `weekly_frequency` | integer | NO | — | — | — | >0 | — |
| `default_tuition_krw` | integer | NO | — | — | — | >=0 | — |
| `expiration_policy` | text | YES | — | — | — | — | — |
| `is_active` | boolean | NO | true | — | — | — | — |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

### A.6 `passes`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `pass_code` | text | NO | — | UK | — | — | UK |
| `student_id` | uuid | NO | — | FK→students | RESTRICT | — | (student,course,status) |
| `course_id` | uuid | NO | — | FK→courses | RESTRICT | — | composite UK |
| `course_product_id` | uuid | NO | — | FK→course_products | RESTRICT | — | — |
| `sequence_number` | integer | NO | — | UK(student,course,seq) | — | >0 | — |
| `status` | text | NO | — | partial UK active/reserved | — | pass statuses | status partial |
| `registered_lesson_count_snapshot` | integer | NO | — | — | — | >0 | — |
| `weekly_frequency_snapshot` | integer | NO | — | — | — | >0 | — |
| `product_name_snapshot` | text | NO | — | — | — | — | — |
| `tuition_amount_krw_snapshot` | integer | NO | — | — | — | >=0 | — |
| `discount_adjustment_krw_snapshot` | integer | YES | 0 | — | — | >=0 | — |
| `start_date` | date | NO | — | — | — | — | — |
| `expires_on` | date | YES | — | — | — | >=start_date | — |
| `activated_at` | timestamptz | YES | — | — | — | — | — |
| `completed_at` | timestamptz | YES | — | — | — | — | — |
| `cancelled_at` | timestamptz | YES | — | — | — | — | — |
| `previous_pass_id` | uuid | YES | — | FK→passes | RESTRICT | — | prev_idx |
| `correction_source_pass_id` | uuid | YES | — | FK→passes | RESTRICT | — | — |
| `creation_reason` | text | YES | — | — | — | — | — |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

**Composite parent key**: UNIQUE (`id`, `student_id`, `course_id`).

Trusted-only: create, status transitions, snapshots after create.

### A.7 `schedule_slots`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `pass_id` | uuid | NO | — | FK→passes | RESTRICT | — | (pass_id,is_active) |
| `teacher_id` | uuid | NO | — | FK→teachers | RESTRICT | — | teacher_idx |
| `weekday` | smallint | NO | — | partial UK | — | 0-6 | — |
| `local_start_time` | time | NO | — | partial UK | — | — | — |
| `duration_minutes` | integer | NO | — | — | — | >0 | — |
| `slot_order` | integer | NO | 1 | — | — | >=1 | — |
| `is_active` | boolean | NO | true | partial UK | — | — | — |
| `effective_from` | date | NO | — | — | — | — | — |
| `effective_until` | date | YES | — | — | — | >=effective_from | — |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

Partial UK: (pass_id, weekday, local_start_time, teacher_id) WHERE is_active.

### A.8 `lessons`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `pass_id` | uuid | NO | — | composite FK | RESTRICT | — | (pass_id,seq) |
| `student_id` | uuid | NO | — | composite FK | RESTRICT | — | (student,scheduled_at) |
| `course_id` | uuid | NO | — | composite FK | RESTRICT | — | — |
| `assigned_teacher_id` | uuid | NO | — | FK→teachers | RESTRICT | — | (teacher,scheduled_at) |
| `schedule_slot_id` | uuid | YES | — | FK→schedule_slots | SET NULL | — | — |
| `sequence_number` | integer | NO | — | UK(pass,seq) | — | >=1 | — |
| `scheduled_at` | timestamptz | **YES** (Phase 0B-3B-2B-2A) | — | — | — | null only for reserved-pass shells | scheduled_at_idx |
| `actual_start_at` | timestamptz | YES | — | — | — | — | — |
| `actual_end_at` | timestamptz | YES | — | — | — | end>=start | — |
| `status` | text | NO | scheduled | — | — | lesson statuses | status_idx |
| `change_reason` | text | YES | — | — | — | — | — |
| `makeup_source_lesson_id` | uuid | YES | — | FK→lessons | RESTRICT | not self | makeup_idx |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

Composite FK: (`pass_id`, `student_id`, `course_id`) → passes(`id`, `student_id`, `course_id`).

Partial UK: (`makeup_source_lesson_id`) WHERE status = `makeup_completed`.

### A.9 `payments`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `student_id` | uuid | NO | — | FK→students | RESTRICT | — | (student,paid_at) |
| `course_id` | uuid | NO | — | FK→courses | RESTRICT | — | — |
| `course_product_id` | uuid | NO | — | FK→course_products | RESTRICT | — | — |
| `related_pass_id` | uuid | YES | — | FK→passes | RESTRICT | — | — |
| `renewed_pass_id` | uuid | YES | — | FK→passes, UK | RESTRICT | — | UK |
| `paid_amount_krw` | integer | NO | — | — | — | >=0 | — |
| `payment_method` | text | YES | — | — | — | OD-18: NULL if pending; enum if set | — |
| `status` | text | NO | pending | — | — | payment statuses | status_idx |
| `paid_at` | timestamptz | YES | — | — | — | — | — |
| `idempotency_key` | text | NO | — | UK | — | — | UK |
| `processed_at` | timestamptz | YES | — | — | — | — | — |
| `created_by_profile_id` | uuid | YES | — | FK→profiles | SET NULL | — | — |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

TF validates `related_pass_id` student matches when set.

### A.10 `payment_refunds`

Append-only. UK on `payment_id` (OD-13).

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK |
|--------|------|------|---------|----------|-----------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — |
| `payment_id` | uuid | NO | — | FK→payments, UK | RESTRICT | — |
| `refunded_amount_krw` | integer | NO | — | — | — | >0 |
| `refunded_at` | timestamptz | NO | now() | — | — | — |
| `reason` | text | NO | — | — | — | length>0 |
| `actor_profile_id` | uuid | NO | — | FK→profiles | RESTRICT | — |
| `pass_disposition` | text | NO | — | — | — | disposition enum |
| `created_at` | timestamptz | NO | now() | — | — | — |

### A.11 `sms_notifications`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `student_id` | uuid | NO | — | FK→students | RESTRICT | match pass | — |
| `pass_id` | uuid | NO | — | FK→passes, UK(type) | RESTRICT | — | (pass_id,status) |
| `notification_type` | text | NO | renewal_reminder | UK partial | — | — | — |
| `status` | text | NO | normal | — | — | SMS statuses | (status,target_date) |
| `message_body_snapshot` | text | YES | — | — | — | — | — |
| `target_date` | date | YES | — | — | — | — | target_date_idx |
| `sent_at` | timestamptz | YES | — | — | — | — | — |
| `sent_confirmed_by_profile_id` | uuid | YES | — | FK→profiles | SET NULL | — | — |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

### A.12 `schedule_change_requests`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `student_id` | uuid | NO | — | FK→students | RESTRICT | match lesson | — |
| `target_lesson_id` | uuid | NO | — | FK→lessons | RESTRICT | — | lesson_idx |
| `requesting_profile_id` | uuid | NO | — | FK→profiles | RESTRICT | — | — |
| `request_source_role` | text | NO | — | — | — | teacher/student/owner | — |
| `status` | text | NO | submitted | — | — | request statuses | status_idx |
| `requested_reason` | text | NO | — | — | — | length>0 | — |
| `proposed_scheduled_at` | timestamptz | YES | — | — | — | — | — |
| `approved_scheduled_at` | timestamptz | YES | — | — | — | set on owner approve (3D-2A) | — |
| `teacher_suggestion_note` | text | YES | — | — | — | — | — |
| `owner_decision_note` | text | YES | — | — | — | — | — |
| `decided_by_profile_id` | uuid | YES | — | FK→profiles | SET NULL | — | — |
| `decided_at` | timestamptz | YES | — | — | — | — | — |
| `applied_at` | timestamptz | YES | — | — | — | — | — |
| `cascade_completed_at` | timestamptz | YES | — | — | — | set on owner cascade (3D-2B) | — |
| `cascade_completed_by_profile_id` | uuid | YES | — | FK→profiles | SET NULL | — | — |
| `cascaded_lesson_count` | integer | YES | — | — | — | ≥0 when set | — |
| `cascade_reason` | text | YES | — | — | — | — | — |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

### A.13 `lesson_schedule_changes`

Append-only event log.

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK |
|--------|------|------|---------|----------|-----------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — |
| `lesson_id` | uuid | NO | — | FK→lessons | RESTRICT | — |
| `schedule_change_request_id` | uuid | YES | — | FK→schedule_change_requests | RESTRICT | — |
| `change_origin` | text | NO | — | — | — | origin enum |
| `previous_scheduled_at` | timestamptz | NO | — | — | — | — |
| `new_scheduled_at` | timestamptz | NO | — | — | — | — |
| `reason` | text | YES | — | — | — | — |
| `actor_profile_id` | uuid | YES | — | FK→profiles | SET NULL | — |
| `created_at` | timestamptz | NO | now() | — | — | — |

### A.14 `lesson_notes`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `lesson_id` | uuid | NO | — | FK→lessons | RESTRICT | — | lesson_id_idx |
| `author_profile_id` | uuid | NO | — | FK→profiles | RESTRICT | — | — |
| `body` | text | NO | — | — | — | length>0 | — |
| `visibility` | text | NO | internal | — | — | internal/student_visible | — |
| `created_at` | timestamptz | NO | now() | — | — | — | — |
| `updated_at` | timestamptz | NO | now() | — | — | — | — |

### A.15 `audit_logs`

| Column | Type | Null | Default | PK/FK/UK | ON DELETE | CHECK | Index |
|--------|------|------|---------|----------|-----------|-------|-------|
| `id` | uuid | NO | gen_random_uuid() | PK | — | — | PK |
| `actor_profile_id` | uuid | YES | — | FK→profiles | SET NULL | — | — |
| `actor_role_snapshot` | text | YES | — | — | — | — | — |
| `action` | text | NO | — | — | — | — | — |
| `resource_table` | text | NO | — | — | — | — | (resource_table,resource_id) |
| `resource_id` | uuid | NO | — | — | — | — | created_at_idx |
| `previous_value` | jsonb | YES | — | — | — | — | — |
| `new_value` | jsonb | YES | — | — | — | — | — |
| `reason` | text | YES | — | — | — | — | — |
| `correlation_id` | uuid | YES | — | — | — | — | correlation_idx |
| `created_at` | timestamptz | NO | now() | — | — | — | (resource,created_at) |

No FK on `resource_id` (polymorphic). Append-only; no client writes.

---

## Appendix B — Per-table write restrictions and RLS paths

Summary of **immutable**, **trusted-only**, **append-only**, and **RLS ownership** for each table.

| Table | Immutable columns | Trusted-only mutations | Append-only | RLS ownership path |
|-------|-------------------|------------------------|-------------|-------------------|
| `profiles` | `id`, `created_at` | `role`, `account_state` | — | Self: `id = current_profile_id()` |
| `students` | `student_code`, `created_at` | `profile_id` link (optional trusted) | — | Student: `profile_id`; Teacher: assignment helper |
| `teachers` | `teacher_code`, `created_at` | — | — | Teacher: `profile_id`; Student: via lesson join |
| `courses` | `course_code`, `created_at` | — | — | Active catalog read |
| `course_products` | `course_id`, `product_code`, `created_at` | — | — | Active product read |
| `passes` | snapshots, codes, ids, sequence | CREATE, status lifecycle | — | Student: `student_id`; Teacher: assignment |
| `schedule_slots` | `pass_id`, `created_at` | INSERT/UPDATE via trusted slot ops | — | Teacher: `teacher_id`; Student: own pass |
| `lessons` | pass/student/course/seq, makeup FK | status, generation, cascade | — | Teacher: `assigned_teacher_id`; Student: `student_id` |
| `payments` | amounts, keys, renewed_pass_id | complete, refund | — | Student: `student_id`; Teacher: **denied** |
| `payment_refunds` | all business columns | INSERT refund only | **Yes** | Owner read; Student optional own chain |
| `sms_notifications` | student_id, pass_id, type | recalc, create on pass | — | Student: own message body only on current pass (OD-20 provisional); Teacher: denied |
| `schedule_change_requests` | submit fields after apply | apply | — | Student/Teacher: own scope; Owner: all |
| `lesson_schedule_changes` | all event fields | INSERT only | **Yes** | Scope via lesson |
| `lesson_notes` | `lesson_id`, `author_profile_id`, `created_at` | — | — | Teacher assigned; Student visible only |
| `audit_logs` | all | INSERT only | **Yes** | Owner read only |

**Normal-client write restrictions**: No role may DELETE historical rows. No Student/Teacher direct UPDATE on pass, lesson status, payment completion, refund, SMS recalc, or audit. Owner direct table UPDATE limited to master data and pending payments — lifecycle mutations require trusted operations.
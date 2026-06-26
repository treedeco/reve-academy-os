# Schema Dictionary — REVE ACADEMY OS

Phase **0B-1** column dictionary. PostgreSQL-oriented logical types. **Design only — no `CREATE TABLE`.**

Legend for **Client write authority**:

| Label | Meaning |
|-------|---------|
| **Owner** | Owner role via app/API |
| **Teacher** | Assigned scope only |
| **Student** | Own data read; limited create (requests) |
| **Trusted** | Server/database function only |
| **System** | Derived or system-maintained |
| **Immutable** | Set once; not client-updatable |
| **None** | Not client-writable |

Legend for **Mutability**: `mutable` | `immutable` | `append-only` | `derived-not-stored`

---

## `profiles`

**Phase 0B-2 physical mapping**: `id` **is** `auth.users.id` (same UUID). No separate `auth_user_id` column. See [postgresql-physical-design.md](./postgresql-physical-design.md) §3.

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | auth | Supabase Auth | immutable | PK; FK → auth.users(id) | | Trusted bootstrap |
| `role` | text | NO | — | Owner assign | mutable | `owner` \| `teacher` \| `student` | check enum | Trusted† |
| `display_name` | text | NO | — | User/Owner | mutable | Display name | non-empty | Owner, Self (limited) |
| `account_state` | text | NO | `active` | Owner | mutable | `active` \| `inactive` \| `suspended` | check | Trusted† |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

---

## `students`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `student_code` | text | NO | — | Owner | **immutable** | Business id e.g. `S006` | unique, pattern | Owner (create) |
| `profile_id` | uuid | YES | — | Owner | mutable | Optional login link | FK profiles, unique optional | Owner |
| `name` | text | NO | — | Owner | mutable | Legal/preferred name | non-empty | Owner |
| `phone` | text | YES | — | Owner | mutable | Contact | academy-required fields TBD UI | Owner |
| `email` | text | YES | — | Owner | mutable | Contact | format | Owner |
| `operational_status` | text | NO | `active` | Owner | mutable | `active` \| `inactive` \| `archived` | check | Owner |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

**Not stored**: pass counts, financial totals (derived).

**Privacy**: minimize PII; no unnecessary fields.

---

## `teachers`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `teacher_code` | text | NO | — | Owner | **immutable** | Business id | unique | Owner (create) |
| `profile_id` | uuid | YES | — | Owner | mutable | Optional login | FK profiles | Owner |
| `name` | text | NO | — | Owner | mutable | | non-empty | Owner |
| `phone` | text | YES | — | Owner | mutable | Contact | | Owner |
| `email` | text | YES | — | Owner | mutable | | | Owner |
| `is_active` | boolean | NO | true | Owner | mutable | Active teacher | | Owner |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

---

## `courses`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `course_code` | text | NO | — | Owner | **immutable** | e.g. `VOCAL` | unique | Owner (create) |
| `name` | text | NO | — | Owner | mutable | Course name | non-empty | Owner |
| `description` | text | YES | — | Owner | mutable | | | Owner |
| `is_active` | boolean | NO | true | Owner | mutable | | | Owner |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

**No** sole historical tuition column here (OD-08).

---

## `course_products`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `course_id` | uuid | NO | — | Owner | immutable | FK courses | | Owner (create) |
| `product_code` | text | NO | — | Owner | **immutable** | SKU-like code | unique | Owner (create) |
| `product_name` | text | NO | — | Owner | mutable | Display name | non-empty | Owner |
| `default_lesson_count` | integer | NO | — | Owner | mutable | e.g. 4, 8 | > 0 | Owner |
| `weekly_frequency` | integer | NO | — | Owner | mutable | Slots per week | > 0 | Owner |
| `default_tuition_krw` | integer | NO | — | Owner | mutable | KRW | >= 0 | Owner |
| `expiration_policy` | text | YES | — | Owner | mutable | Optional policy key/json | | Owner |
| `is_active` | boolean | NO | true | Owner | mutable | | | Owner |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

Product changes **do not** mutate pass snapshots.

---

## `passes`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `pass_code` | text | NO | — | Trusted | **immutable** | e.g. `V-S006-001` | globally unique | Trusted |
| `student_id` | uuid | NO | — | Trusted | immutable | FK students | | Trusted |
| `course_id` | uuid | NO | — | Trusted | immutable | FK courses | | Trusted |
| `course_product_id` | uuid | NO | — | Trusted | immutable | FK at creation | | Trusted |
| `sequence_number` | integer | NO | — | Trusted | **immutable** | Per student+course seq | unique pair | Trusted |
| `status` | text | NO | — | Trusted/Owner | mutable | see state-transitions | check enum | Trusted† |
| `registered_lesson_count_snapshot` | integer | NO | — | Product snapshot | **immutable** | Contract lessons | > 0 | Trusted |
| `weekly_frequency_snapshot` | integer | NO | — | Product snapshot | **immutable** | | > 0 | Trusted |
| `product_name_snapshot` | text | NO | — | Product snapshot | **immutable** | | | Trusted |
| `tuition_amount_krw_snapshot` | integer | NO | — | Product/payment | **immutable** | KRW | >= 0 | Trusted |
| `discount_adjustment_krw_snapshot` | integer | YES | 0 | Owner/trusted | **immutable** | Future discount | >= 0 | Trusted |
| `start_date` | date | NO | — | Owner/Trusted | mutable | Pass start (Seoul) | | Owner†, Trusted |
| `expires_on` | date | YES | — | Product/Owner | mutable | Optional (OD-03) | >= start_date | Owner† |
| `activated_at` | timestamptz | YES | — | Trusted | immutable | reserved→active | | Trusted |
| `completed_at` | timestamptz | YES | — | Trusted | immutable | | | Trusted |
| `cancelled_at` | timestamptz | YES | — | Trusted/Owner | immutable | Terminal cancel | | Trusted |
| `previous_pass_id` | uuid | YES | — | Trusted | **immutable** | Renewal chain | FK passes | Trusted |
| `correction_source_pass_id` | uuid | YES | — | Trusted | **immutable** | OD-11 correction link | FK passes | Trusted |
| `creation_reason` | text | YES | — | Trusted/Owner | immutable | payment, correction, etc. | | Trusted |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

**Derived-not-stored**: used count, remaining count.

---

## `schedule_slots`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `pass_id` | uuid | NO | — | Trusted | immutable | FK passes | | Trusted |
| `teacher_id` | uuid | NO | — | Owner/Trusted | mutable | FK teachers | | Owner† |
| `weekday` | smallint | NO | — | Owner/Trusted | mutable | 0=Sun..6=Sat (PG dow) | 0-6 | Owner† |
| `local_start_time` | time | NO | — | Owner/Trusted | mutable | Seoul local | | Owner† |
| `duration_minutes` | integer | NO | — | Owner/Trusted | mutable | | > 0 | Owner† |
| `slot_order` | integer | NO | 1 | Owner/Trusted | mutable | 1..N within pass | >= 1 | Owner† |
| `is_active` | boolean | NO | true | Owner | mutable | | | Owner |
| `effective_from` | date | NO | — | Owner/Trusted | mutable | | | Owner† |
| `effective_until` | date | YES | — | Owner | mutable | Optional end | >= effective_from | Owner |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

Rescheduling a **lesson** does not rewrite slot row by default.

---

## `lessons`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `pass_id` | uuid | NO | — | Trusted | immutable | FK passes | | Trusted |
| `student_id` | uuid | NO | — | Pass copy | immutable | Denorm for RLS | match pass | Trusted |
| `course_id` | uuid | NO | — | Pass copy | immutable | Denorm for RLS | match pass | Trusted |
| `assigned_teacher_id` | uuid | NO | — | Slot/Owner | mutable | FK teachers | | Owner, Teacher† |
| `schedule_slot_id` | uuid | YES | — | Generation | immutable | Originating slot | FK | Trusted |
| `sequence_number` | integer | NO | — | Trusted | **immutable** | Unique per pass | >= 1 | Trusted |
| `scheduled_at` | timestamptz | NO | — | Slot/trusted | mutable | Planned instant (Seoul) | | Owner†, Trusted |
| `actual_start_at` | timestamptz | YES | — | Teacher/Owner | mutable | | | Teacher†, Owner |
| `actual_end_at` | timestamptz | YES | — | Teacher/Owner | mutable | | >= start | Teacher†, Owner |
| `status` | text | NO | `scheduled` | Teacher/Owner/Trusted | mutable | Canonical status | check enum | Teacher†, Owner†, Trusted |
| `change_reason` | text | YES | — | Actor | mutable | Required when rules say | | Teacher†, Owner† |
| `makeup_source_lesson_id` | uuid | YES | — | Trusted | immutable | FK lessons self | required if makeup_completed | Trusted |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

**Derived-not-stored**: deduction boolean (from status only).

---

## `payments`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `student_id` | uuid | NO | — | Owner | immutable | FK students | | Owner (create) |
| `course_id` | uuid | NO | — | Owner | immutable | Context | FK courses | Owner |
| `course_product_id` | uuid | NO | — | Owner | immutable | Product purchased | FK | Owner |
| `related_pass_id` | uuid | YES | — | Owner/Trusted | immutable | Prior pass if renewal | FK passes | Owner, Trusted |
| `renewed_pass_id` | uuid | YES | — | Trusted | **immutable** | Created pass | FK; set once | Trusted |
| `paid_amount_krw` | integer | NO | — | Owner | **immutable** | KRW at completion | >= 0 | Owner (pending), Trusted (complete) |
| `payment_method` | text | YES | — | Owner | **immutable** | OD-18 provisional: `cash`, `bank_transfer`, `card`, `other`; NULL while pending | check when set | Owner (complete) |
| `status` | text | NO | `pending` | Owner/Trusted | mutable | pending/completed/cancelled/refunded | check | Owner†, Trusted |
| `paid_at` | timestamptz | YES | — | Trusted | **immutable** | Completion time | | Trusted |
| `idempotency_key` | text | NO | — | Owner | **immutable** | Unique business key | globally unique | Owner (create) |
| `processed_at` | timestamptz | YES | — | Trusted | immutable | Trusted completion | | Trusted |
| `created_by_profile_id` | uuid | YES | — | System | immutable | FK profiles | | System |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

---

## `payment_refunds`

Append-only immutable refund history. **Row existence = successfully completed refund** (OD-13). No separate refund status column.

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `payment_id` | uuid | NO | — | Trusted | **immutable** | FK → `payments`. **MVP unique** (0..1 refund per payment) | FK + UK (MVP) | **Trusted only** |
| `refunded_amount_krw` | integer | NO | — | Owner input | **immutable** | KRW refunded | > 0, <= payment.paid_amount_krw | Trusted |
| `refunded_at` | timestamptz | NO | now | Trusted | **immutable** | Refund completion instant | | Trusted |
| `reason` | text | NO | — | Owner | **immutable** | Mandatory (OD-12) | non-empty | Trusted |
| `actor_profile_id` | uuid | NO | — | Owner | **immutable** | FK profiles (actor) | | Trusted |
| `pass_disposition` | text | NO | — | Trusted | **immutable** | e.g. `active_cancelled_future_advance_cancelled`, `reserved_cancelled` | check | Trusted |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |

**Client write**: none for normal roles — insert only via trusted coordinated refund transaction. No UPDATE/DELETE.

---

## `sms_notifications`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `student_id` | uuid | NO | — | Pass | immutable | FK students | | Trusted |
| `pass_id` | uuid | NO | — | Pass | immutable | FK passes | | Trusted |
| `notification_type` | text | NO | `renewal_reminder` | System | immutable | MVP type | | Trusted |
| `status` | text | NO | `normal` | System/Owner | mutable | SMS states | check enum | Trusted, Owner† (sent) |
| `message_body_snapshot` | text | YES | — | System | mutable | Copy text for MVP | | Trusted, Owner |
| `target_date` | date | YES | — | Derived | mutable | Business target | | Trusted |
| `sent_at` | timestamptz | YES | — | Owner | immutable | Manual confirm | | Owner |
| `sent_confirmed_by_profile_id` | uuid | YES | — | Owner | immutable | FK profiles | | Owner |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

**MVP rule**: one primary `sms_notifications` row per pass for renewal lifecycle; new pass → new row; old pass rows preserved.

---

## `schedule_change_requests`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `student_id` | uuid | NO | — | Lesson | immutable | FK students | | System |
| `target_lesson_id` | uuid | NO | — | Submitter | immutable | FK lessons | | Teacher, Student |
| `requesting_profile_id` | uuid | NO | — | Submitter | immutable | FK profiles | | Teacher, Student |
| `request_source_role` | text | NO | — | Submitter | immutable | teacher/student/owner | check | Teacher, Student |
| `status` | text | NO | `submitted` | Workflow | mutable | see state-transitions | check | Owner†, Submitter† |
| `requested_reason` | text | NO | — | Submitter | immutable | | non-empty | Teacher, Student |
| `proposed_scheduled_at` | timestamptz | YES | — | Submitter | immutable | Suggested time | | Teacher, Student |
| `teacher_suggestion_note` | text | YES | — | Teacher | mutable | Before decision | | Teacher |
| `owner_decision_note` | text | YES | — | Owner | immutable | On decide | | Owner |
| `decided_by_profile_id` | uuid | YES | — | Owner | immutable | | | Owner |
| `decided_at` | timestamptz | YES | — | Owner | immutable | | | Owner |
| `applied_at` | timestamptz | YES | — | Trusted | immutable | | | Trusted |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | System |

---

## `lesson_schedule_changes`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `lesson_id` | uuid | NO | — | Trusted | immutable | FK lessons | | Trusted |
| `schedule_change_request_id` | uuid | YES | — | Trusted | immutable | FK if from request | | Trusted |
| `change_origin` | text | NO | — | Trusted | **immutable** | direct_user, cascade_auto, trusted_system, correction | check | Trusted |
| `previous_scheduled_at` | timestamptz | NO | — | Trusted | **immutable** | Audit | | Trusted |
| `new_scheduled_at` | timestamptz | NO | — | Trusted | **immutable** | | | Trusted |
| `reason` | text | YES | — | Actor | **immutable** | | | Trusted |
| `actor_profile_id` | uuid | YES | — | Actor | **immutable** | FK profiles | | Trusted |
| `created_at` | timestamptz | NO | now | System | immutable | Append-only | | None |

---

## `lesson_notes`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | Trusted |
| `lesson_id` | uuid | NO | — | Author | immutable | FK lessons | | Teacher |
| `author_profile_id` | uuid | NO | — | Author | immutable | FK profiles | | Teacher |
| `body` | text | NO | — | Author | mutable | Note content | non-empty | Teacher |
| `visibility` | text | NO | `internal` | Author | mutable | internal \| student_visible | check | Teacher, Owner† |
| `created_at` | timestamptz | NO | now | System | immutable | | | None |
| `updated_at` | timestamptz | NO | now | System | mutable | | | Teacher |

---

## `audit_logs`

| Column | Type | Null | Default | Source | Mutability | Description | Validation | Client write |
|--------|------|------|---------|--------|------------|-------------|------------|--------------|
| `id` | uuid | NO | gen | System | immutable | PK | | None |
| `actor_profile_id` | uuid | YES | — | Trusted | immutable | FK profiles | | Trusted |
| `actor_role_snapshot` | text | YES | — | Trusted | immutable | Role at action time | | Trusted |
| `action` | text | NO | — | Trusted | immutable | e.g. lesson.status_change | | Trusted |
| `resource_table` | text | NO | — | Trusted | immutable | Target table name | | Trusted |
| `resource_id` | uuid | NO | — | Trusted | immutable | Target PK | | Trusted |
| `previous_value` | jsonb | YES | — | Trusted | immutable | | | Trusted |
| `new_value` | jsonb | YES | — | Trusted | immutable | | | Trusted |
| `reason` | text | YES | — | Trusted | immutable | Required for sensitive ops | | Trusted |
| `correlation_id` | uuid | YES | — | Trusted | immutable | Transaction bundle id | | Trusted |
| `created_at` | timestamptz | NO | now | System | immutable | Append-only | | None |

---

## Derived values (not tables)

| Name | Definition | Storage |
|------|------------|---------|
| `used_lesson_count` | COUNT deductible statuses for pass | **Not stored** — view/function |
| `remaining_lesson_count` | snapshot count − used | **Not stored** |
| `lesson_is_deductible` | status ∈ deductible set | **Not stored** |

---

## Related documents

- [data-model.md](./data-model.md)
- [erd.md](./erd.md)
- [data-integrity-constraints.md](./data-integrity-constraints.md)
- [postgresql-physical-design.md](./postgresql-physical-design.md) (Phase 0B-2)

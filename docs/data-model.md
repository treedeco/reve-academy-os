# Logical Data Model — REVE ACADEMY OS

Phase **0B-1** logical database design. Authoritative domain rules: Phase 0A (OD-01 ~ OD-12). **No executable SQL** in this phase.

Related: [schema-dictionary.md](./schema-dictionary.md), [erd.md](./erd.md), [data-integrity-constraints.md](./data-integrity-constraints.md).

---

## 1. Modeling goals

- PostgreSQL as **single source of truth** for business state
- **Lesson status** as sole deduction source; no editable used/remaining columns
- **Immutable business identifiers** (student code, pass code) separate from UUID PKs
- **Financial and contractual snapshots** on passes and payments; product price changes do not rewrite history
- **No physical delete** for passes, lessons, payments, refunds, SMS history, schedule-change history, audit logs
- Clear **RLS ownership paths** for Owner / Teacher / Student
- **Trusted server/database functions** for payment renewal, refunds, cascade apply, owner corrections
- **Asia/Seoul** interpretation for business dates; fixed slots use local `time` + weekday, not arbitrary UTC slot storage

---

## 2. Aggregate boundaries

| Aggregate | Root entity | Consistency boundary |
|-----------|-------------|----------------------|
| **Student / course enrollment context** | `students` | Student master; optional profile link; no pass counts stored |
| **Pass / lesson / schedule slot** | `passes` | Pass lifecycle, lessons, fixed slots; one active + ≤1 reserved per (student, course) |
| **Payment / renewal / refund** | `payments` | Idempotent completion → pass renewal; refunds via `payment_refunds` + trusted op |
| **Schedule change** | `schedule_change_requests` | Request workflow; `lesson_schedule_changes` append events on apply |
| **SMS notification lifecycle** | `sms_notifications` | **One lifecycle record set per pass** (MVP); new pass → new rows; prior pass history preserved |
| **Audit trail** | `audit_logs` | Append-only; correlation id links multi-table trusted transactions |

Aggregates are **not** independent distributed transactions across unrelated client calls. Cross-aggregate consistency (e.g. payment + pass + lessons) requires a **single trusted PostgreSQL transaction**.

---

## 3. Entity descriptions

### `profiles`

Authenticated application identity (Supabase Auth). Role: `owner` | `teacher` | `student`. One profile = one primary role (MVP). No passwords in app tables.

### `students`

Business student record. May exist **before** login. Optional `profile_id`. Immutable `student_code` (e.g. `S006`).

### `teachers`

Business teacher record. Optional `profile_id`. Immutable `teacher_code`. Active flag.

### `courses`

Instructional subject/curriculum. Immutable `course_code`. **No** authoritative tuition on course alone (OD-08).

### `course_products`

Commercial package: lesson count, weekly frequency, default tuition (KRW integer), optional expiration policy. Snapshots copied to pass at creation.

### `passes`

Pass lifecycle and contractual snapshots. Immutable `pass_code` (e.g. `V-S006-001`). Status: `reserved` | `active` | `completed` | `expired` | `cancelled`. Self-FK: `previous_pass_id`, `correction_source_pass_id` (OD-11).

### `schedule_slots`

Fixed recurring slot per pass: weekday, local start time, duration, teacher, slot order. Multiple per pass (OD-04).

### `lessons`

Per-pass lesson rows. Status drives deduction. Optional `schedule_slot_id`, `makeup_source_lesson_id`. Denormalized `student_id`, `course_id` for RLS/performance with pass consistency enforced.

### `payments`

Payment intent and completion. Unique `idempotency_key`. Links to `renewed_pass_id` (at most once when completed). KRW integer amounts.

### `payment_refunds`

Separate refund history (OD-12, OD-13). **MVP**: one payment → **zero or one** refund row. Row existence means **successfully completed** refund; failed trusted attempts leave **no row**. Links to payment; records amount, reason, actor, disposition. Immutable; no separate refund status column.

### `sms_notifications`

Per-pass notification lifecycle (MVP: **one primary notification row per pass** per renewal cycle; status transitions on that row; historical rows on old passes retained).

### `schedule_change_requests`

Workflow: submit → owner approve/reject → trusted apply (OD-01).

### `lesson_schedule_changes`

Append-only schedule change events; distinguishes direct, cascade, trusted, correction origins.

### `lesson_notes`

Lesson-attached notes; visibility `internal` | `student_visible`.

### `audit_logs`

Append-only; `jsonb` previous/new values; optional `correlation_id` for trusted transactions.

---

## 4. Relationship rules

- `students` 1 — 0..1 `profiles` (optional login)
- `teachers` 1 — 0..1 `profiles` (optional login)
- `courses` 1 — N `course_products`
- `students` + `courses` → N `passes` (sequenced; uniqueness rules on active/reserved)
- `passes` 1 — N `schedule_slots`, N `lessons`, 0..N `sms_notifications` (typically 1 active lifecycle row per pass in MVP)
- `passes` 0..1 `previous_pass_id` → `passes`
- `lessons` N — 1 `passes`; `lessons.makeup_source_lesson_id` → `lessons` (self)
- `payments` N — 1 `students`; 0..1 `renewed_pass_id` → `passes`
- `payment_refunds` 0..1 — 1 `payments` (MVP: unique `payment_id`; OD-13)
- `schedule_change_requests` N — 1 `lessons` (target)
- `lesson_schedule_changes` N — 1 `lessons`; optional link to request
- `lesson_notes` N — 1 `lessons`

Teacher ↔ student **assignment** is **derived** from `lessons.assigned_teacher_id`, `schedule_slots.teacher_id`, and pass context — no separate assignment table in MVP unless later required.

---

## 5. Lifecycle ownership

| Entity | Created by | Terminal states | Reactivation |
|--------|------------|-------------------|--------------|
| Pass | Trusted (renewal) / Owner | `completed`, `expired`, `cancelled` | **No** for `cancelled` (OD-11) |
| Lesson | Trusted (renewal generation) | Status terminal per rules | Owner correction only (OD-02) |
| Payment | Owner | `cancelled`, `refunded` | No reuse of idempotency key for new pass |
| Schedule request | Teacher/Student/Owner | `rejected`, `cancelled`, `applied` | Applied immutable except documented correction |

---

## 6. History and immutability

- **Soft retirement**: `is_active`, `status`, `cancelled_at` — not DELETE
- **Immutable after set**: `student_code`, `pass_code`, pass/payment snapshots, `idempotency_key`, applied schedule request fields
- **Append-only**: `lesson_schedule_changes`, `audit_logs`
- **Refund / correction**: new rows or status transitions; no silent overwrite of financial history

---

## 7. Derived-value strategy

**Not stored** as normal editable columns:

- `used_lesson_count`
- `remaining_lesson_count`
- `is_deductible` (per lesson boolean source column)

**Derivation** (implementation Phase 3+):

```text
used = COUNT(lessons WHERE pass_id = ? AND status IN ('completed','same_day_cancelled','makeup_completed'))
remaining = passes.registered_lesson_count_snapshot - used
```

Expose via:

- SQL view or STABLE function (read-only)
- Scoped API responses after lesson status change

Optional future **trusted-maintained cache columns** on `passes` may be considered in Phase 3 only if documented as non-authoritative and updated exclusively by triggers/trusted functions — **not in MVP logical schema** as client-writable fields.

---

## 8. Financial snapshot strategy

At pass creation (trusted renewal):

- Copy from `course_products`: product id, name, registered lesson count, weekly frequency, default tuition
- Store on `passes`: `*_snapshot` columns (immutable after creation)
- Optional `discount_adjustment_krw_snapshot` when supported

At payment completion:

- Store `paid_amount_krw`, method, paid_at on `payments`
- Link `renewed_pass_id` once

Product price edits on `course_products` affect **new** passes only.

Refunds: `payment_refunds.refunded_amount_krw` immutable; payment → `refunded` status; pass/lesson updates via trusted op (OD-12).

### MVP refund cardinality (OD-13)

- One `payments` row has **zero or one** `payment_refunds` row.
- A refund row is created **only** when the coordinated trusted refund transaction **commits successfully**.
- Failed refund processing **rolls back**; no orphan refund row.
- Partial or multiple refunds per payment require a **future approved model extension**.
- Mistaken refund: correction workflow + audit; original refund row **preserved**.

All monetary values: **`integer` KRW** — no float.

---

## 9. Authentication / domain separation

| Layer | Table | Purpose |
|-------|-------|---------|
| Auth (Supabase) | `auth.users` | Credentials (not modeled here) |
| App identity | `profiles` | Role + link to auth user |
| Business | `students`, `teachers` | Operational records independent of login |

Rules:

- Student/teacher business record may exist with `profile_id` NULL
- When linked, `profiles.role` must align with record type (enforced in app + RLS Phase 0B-2)
- One profile must not hold multiple incompatible roles (MVP: single `role` column)

---

## 10. RLS ownership paths (future)

| Role | Primary path |
|------|----------------|
| **Owner** | Full read/write per permissions matrix (except physical delete) |
| **Teacher** | `lessons.assigned_teacher_id` → `teachers.id` → `teachers.profile_id` = `auth.uid()` profile; same via `schedule_slots.teacher_id`; schedule requests for assigned students |
| **Student** | `students.profile_id` = current profile → own `passes`, `lessons`, `payments` (read), own requests/visible notes |

Service role bypasses RLS only on server — never exposed to browser.

---

## 11. Transaction-sensitive aggregates

Must run in **one PostgreSQL transaction** (trusted function):

1. **Payment complete + pass renewal** — payment, prior pass update, new pass, lessons, slots, SMS row, audit
2. **Reserved pass activation** — pass status, audit
3. **Active-pass refund (OD-12)** — payment status/refund row, pass cancel, future lessons → `advance_cancelled`, SMS recalc, audit
4. **Owner lesson correction (OD-02)** — lesson status, pass-derived reads, SMS, audit
5. **Approved schedule apply** — lessons, `lesson_schedule_changes`, request → `applied`, audit

Client-side multi-request sequences for the above are **prohibited**.

---

## 12. Explicit non-goals (Phase 0B-1)

- Executable SQL, migrations, enums in code, triggers, RLS policies
- Supabase project initialization
- Used/remaining stored as user-editable source
- Credit balances, partial active-pass refund, lesson-count transfer (OD-12 exclusions)
- External SMS provider tables
- Generic EAV or speculative plugin tables

---

## Related documents

- [schema-dictionary.md](./schema-dictionary.md)
- [erd.md](./erd.md)
- [data-integrity-constraints.md](./data-integrity-constraints.md)
- [domain-rules.md](./domain-rules.md)
- [state-transitions.md](./state-transitions.md)

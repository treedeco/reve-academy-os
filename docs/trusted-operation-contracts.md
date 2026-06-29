# Trusted Operation Contracts — REVE ACADEMY OS

Phase **0B-2** server/database operation specifications. **No PL/pgSQL.** Names are design contracts (`reve_*` prefix in implementation).

Authority: [state-transitions.md](./state-transitions.md), [permissions-matrix.md](./permissions-matrix.md), [data-integrity-constraints.md](./data-integrity-constraints.md), [open-decisions.md](./open-decisions.md).

**Provisional policies (OD-14 ~ OD-21)**: Sections marked **Provisional policy — subject to owner review before executable migration** use safe defaults for Phase 0B-2 planning only. Not permanent owner-approved requirements.

---

## Conventions

| Field | Meaning |
|-------|---------|
| Caller | Role or execution context |
| Lock | Row-level locks within one transaction |
| Idempotency | Safe retry semantics |
| Correlation | Shared `audit_logs.correlation_id` |

### Optimistic concurrency (global)

**Mechanism**: Mutable business rows expose `updated_at`. Trusted mutators accept `expected_updated_at timestamptz` (or monotonic `version integer` if added later). If row `updated_at` differs, operation fails with stale-state error; client reloads.

**Justification**: Simpler than version column for MVP; aligns with timestamp trigger strategy. Prevents silent last-write-wins on lessons, passes, schedule requests, payments (pending).

---

## 1. Profile provisioning — **Implemented (0B-3B-2B-3A)**

`reve_bootstrap_first_owner` (service_role only), `reve_owner_provision_profile` (active owner). See migration `20260630120000_phase_0b3b2b3a_profile_people_master_data.sql`.

Legacy design reference (`provision_profile`):

| Aspect | Specification |
|--------|---------------|
| Purpose | Create profile row after Supabase Auth signup |
| Caller | Trusted (service role / auth hook) |
| Input | `auth_user_id uuid`, `display_name text`, optional initial `role` (default student) |
| Output | `profile_id uuid` |
| Preconditions | Auth user exists; no profile for id |
| Authorization | System bootstrap only |
| Locks | None |
| Transaction | Single INSERT |
| Idempotency | If profile exists for id → return existing |
| Audit | INSERT audit optional on first create |
| SMS | None |
| Failure | Rollback; no profile row |
| Retry | Safe |
| Prohibited | Storing secrets; removing last active owner’s role (OD-21 provisional) |

---

## 2. Profile role / account state — **Implemented (0B-3B-2B-3A)**

`reve_owner_set_profile_role`, `reve_owner_set_profile_active`, student/teacher owner RPCs.

Legacy design reference (`set_profile_role`):

| Aspect | Specification |
|--------|---------------|
| Purpose | Assign or change application role |
| Caller | Owner via trusted path |
| Input | `profile_id`, `new_role`, `reason`, `expected_updated_at` |
| Output | Updated profile |
| Preconditions | Caller is owner; target exists |
| Authorization | `is_owner()`; reject if target is last active owner removing own owner role (OD-21 provisional) |
| Locks | `profiles` FOR UPDATE |
| Steps | 1 Validate role 2 Check stale 3 UPDATE role 4 Audit |
| Audit | Required † |
| Failure | Rollback |
| Prohibited | Client direct UPDATE on role |

### Implemented RPCs (Phase 0B-3B-2B-3A)

Migration: `20260630120000_phase_0b3b2b3a_profile_people_master_data.sql`. Account link model: `students.profile_id` / `teachers.profile_id` → `profiles.id` (= `auth.users.id`). No separate link RPCs; provisioning and role change perform atomic link updates.

#### `public.reve_bootstrap_first_owner(p_auth_user_id, p_display_name)`

| Aspect | Specification |
|--------|---------------|
| Caller | **`service_role` only** — revoked from `PUBLIC`, `anon`, `authenticated` |
| Auth boundary | Accepts existing Auth user UUID only; verifies `auth.users`; does not insert Auth rows or store passwords |
| Preconditions | No active owner profile exists; Auth user exists; profile id unused |
| Output | `profile_id`, `role`, `account_state`, `display_name`, `updated_at`, `idempotent_replay` |
| Idempotency | Safe replay when same owner profile already exists with matching values; conflicting retry → `REVE_PROFILE_EXISTS` or `REVE_BOOTSTRAP_ALREADY_COMPLETED` |
| Audit | `profile.bootstrap_first_owner`; actor NULL (system); no credentials |
| Last-owner | Creates first owner only |

#### `public.reve_owner_provision_profile(p_auth_user_id, p_role, p_display_name, p_student_id?, p_teacher_id?)`

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner (`assert_active_owner_caller`; JWT role metadata ignored) |
| Roles | `owner` (no entity link), `teacher` (active unlinked teacher), `student` (active unlinked student) |
| Concurrency | Row lock on target entity before link |
| Audit | `profile.provisioned` with correlation id |
| Failure | `REVE_UNAUTHORIZED`, `REVE_AUTH_USER_NOT_FOUND`, `REVE_PROFILE_EXISTS`, `REVE_PROFILE_LINK_CONFLICT`, `REVE_ROLE_LINK_MISMATCH` |

#### `public.reve_owner_set_profile_role(p_profile_id, p_new_role, p_reason, p_expected_updated_at, p_student_id?, p_teacher_id?)`

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner |
| Concurrency | Lock profile FOR UPDATE; stale → `REVE_STALE_STATE` (`22000`) |
| Last-owner | Cannot demote/deactivate last active owner (`REVE_LAST_OWNER`; advisory lock) |
| Links | Atomic clear + set via `clear_profile_entity_links`; deferred constraint triggers validate role/link consistency |
| Audit | Previous and new role/link values; reason required |

#### `public.reve_owner_set_profile_active(p_profile_id, p_account_state, p_reason, p_expected_updated_at)`

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner |
| States | `active`, `inactive`, `suspended` (no physical DELETE — OD-19 provisional) |
| Last-owner | Cannot deactivate last active owner |
| Inactive access | Existing helpers (`current_app_role`, `current_student_id`, `current_teacher_id`) fail closed |
| Audit | State change with reason |

#### Student master data — `reve_owner_create_student`, `reve_owner_update_student`, `reve_owner_set_student_active`

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner only |
| Create | Validates unique `student_code` (immutable after create); requires name; default `operational_status = active`; no Auth/profile auto-create |
| Update | Mutable: name, phone, email only; optimistic concurrency |
| Deactivate | Rejects when active linked profile exists (`REVE_PROFILE_LINK_CONFLICT`); does not cancel passes/lessons |
| Output | Safe student projection including `linked_profile_id` |

#### Teacher master data — `reve_owner_create_teacher`, `reve_owner_update_teacher`, `reve_owner_set_teacher_active`

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner only |
| Create | Unique `teacher_code` (immutable); private phone/email in teacher columns only |
| Update | Mutable: name, phone, email only |
| Deactivate | Rejects future active lesson/slot assignments (`REVE_ACTIVE_ASSIGNMENTS_EXIST`); no silent reassignment or slot deletion |
| Linked profile | Deactivation rejected when active profile linked |

#### Security (all owner RPCs)

`SECURITY DEFINER`, `search_path = ''`, fully qualified objects, owned by `postgres`, no dynamic SQL, no base-table row return type, no audit JSON in results. Base-table INSERT/UPDATE/DELETE grants remain denied for `authenticated`/`anon`.

### Implemented RPCs (Phase 0B-3B-2B-3B)

Migration: `20260701120000_phase_0b3b2b3b_course_product_management.sql`. Pass and payment rows store immutable product/course snapshots at creation; product updates affect future enrollment/renewal only.

#### Course RPCs

| RPC | Caller | Mutable fields | Immutable | Deactivation |
|-----|--------|----------------|-----------|--------------|
| `reve_owner_create_course` | Active owner | — | — | Creates `is_active = true` |
| `reve_owner_update_course` | Active owner | `name`, `description` | `course_code`, PK | No-op → `REVE_NO_CHANGES` |
| `reve_owner_set_course_active` | Active owner | `is_active` | — | Blocks active products (`REVE_COURSE_HAS_ACTIVE_PRODUCTS`), operational deps (`REVE_ACTIVE_DEPENDENCIES_EXIST`) |

#### Product RPCs

| RPC | Caller | Mutable fields | Immutable | Notes |
|-----|--------|----------------|-----------|-------|
| `reve_owner_create_course_product` | Active owner | — | — | Parent course must be active; positive lesson count and frequency |
| `reve_owner_update_course_product` | Active owner | `product_name`, counts, price, `expiration_policy` | `product_code`, `course_id` | Pending payment → `REVE_PENDING_PAYMENT_EXISTS` for contractual fields |
| `reve_owner_set_course_product_active` | Active owner | `is_active` | — | Reactivation requires active parent course |

#### Renewal integration

`reve_private.complete_payment_and_renew_pass_internal` requires active course and active product for new completions; idempotent replay of completed payments unchanged when product later deactivated.

---

## 3. Initial enrollment — **Implemented (0B-3B-2B-3C)**

`public.reve_owner_create_initial_enrollment` — migration `20260702120000_phase_0b3b2b3c_initial_enrollment.sql`.

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner only |
| Purpose | First enrollment when **no** pass history exists for student+course |
| Inputs | `student_id`, `course_product_id`, `schedule_start_date` (Seoul business date), `schedule_slots` JSON array, payment fields, `idempotency_key`, optional `owner_reason` |
| Schedule JSON | `{teacher_id, weekday, local_time, duration_minutes, slot_order}` only; count must equal product `weekly_frequency` |
| Start boundary | `(schedule_start_date::timestamp AT TIME ZONE 'Asia/Seoul')` — inclusive first slot on that date after midnight |
| Output | payment/pass ids, code, sequence, counts, first/last lesson, SMS status, `idempotent_replay` |
| Pass | sequence `1`, code ends `001`, status `active`, product snapshots |
| Idempotency | Unique key; exact replay safe; conflict → `REVE_IDEMPOTENCY_CONFLICT` |
| Collision | `REVE_SCHEDULE_COLLISION` rolls back entire transaction |
| Rejection | Any existing pass (active/reserved/completed/cancelled) → `REVE_NOT_INITIAL_ENROLLMENT` |

Legacy design reference (`create_initial_pass`):

| Aspect | Specification |
|--------|---------------|
| Purpose | First pass for student+course without renewal payment path |
| Caller | Owner trusted |
| Input | student, course, product, start_date, schedule slots[], optional immediate active |
| Output | pass_id, pass_code |
| Preconditions | No conflicting active/reserved unless policy allows; student exists |
| Locks | Student FOR UPDATE; sequence generation |
| Steps | Generate code/sequence → snapshots → pass row → slots → lessons → SMS row |
| Audit | Required |
| Provisional (OD-14–17) | See §4 provisional policies below |

---

## 4. `complete_payment_and_renew_pass`

| Aspect | Specification |
|--------|---------------|
| Purpose | Idempotent payment completion + pass renewal |
| Caller | Owner trusted |
| **Status** | **Implemented** — `public.reve_complete_payment_and_renew_pass` (Phase 0B-3B-2B-2) |

### Input contract

- `p_payment_id uuid`
- `p_expected_payment_updated_at timestamptz`
- `p_paid_amount_krw integer` (must match payment row and product tuition)
- `p_payment_method text` (`cash`, `bank_transfer`, `card`, `other` — OD-18 provisional)
- `p_paid_at timestamptz`
- `p_idempotency_key text` (must match payment row)

### Output contract

| Field | Type |
|-------|------|
| `payment_id` | uuid |
| `payment_status` | text |
| `payment_updated_at` | timestamptz |
| `new_pass_id` | uuid |
| `new_pass_public_code` | text |
| `new_pass_sequence` | integer |
| `new_pass_status` | text |
| `registered_lesson_count` | integer |
| `lesson_rows_created` | integer |
| `schedule_slots_copied` | integer |
| `activation_required` | boolean |
| `activated_at` | timestamptz |
| `first_lesson_at` | timestamptz |
| `idempotent_replay` | boolean |

### Lock order

1. Owner profile validation
2. Payment `FOR UPDATE`
3. Transaction-scoped advisory lock on `(student_id, course_id)`
4. Existing active/reserved passes `FOR UPDATE`
5. Pass insert, slot copy, optional lesson generation, SMS, payment update, audit

### Active vs reserved

- Active pass with **remaining > 0** → new pass `reserved`; **lesson shells** created (`scheduled_at` null) in same transaction
- No active pass (or prior completed) → new pass `active`; lessons scheduled immediately

### Lesson shells (Phase 0B-3B-2B-2A)

- Payment completion always creates exactly `registered_lesson_count` lesson rows.
- Reserved-pass shells: valid pass/student/course/teacher/ordinal/slot; `scheduled_at = null`; status `scheduled`.
- Activation **updates** existing rows via `finalize_pass_lesson_schedules`; never inserts a second lesson set.
- Null `scheduled_at` is valid only for reserved-pass shells; active/completed passes require non-null dates (deferred invariant).
- Ordinal-to-slot assignment at shell creation: round-robin by `slot_order`, weekday, `local_start_time`.

### Idempotency

- Completed payment + matching key → safe replay (`idempotent_replay = true`); no duplicate pass/lessons/SMS/audit
- Conflicting key, amount, or method → `REVE_IDEMPOTENCY_CONFLICT`

### Failure codes

`REVE_UNAUTHORIZED`, `REVE_STALE_STATE`, `REVE_IDEMPOTENCY_CONFLICT`, `REVE_PAYMENT_NOT_COMPLETABLE`, `REVE_PAYMENT_AMOUNT_MISMATCH`, `REVE_INVALID_PAYMENT_METHOD`, `REVE_RESERVED_EXISTS`, `REVE_NO_SCHEDULE`, `REVE_SCHEDULE_COLLISION`

---

### Provisional policies (OD-14 ~ OD-17) — **implemented as provisional; Owner UI review still required**

| OD | Policy |
|----|--------|
| OD-14 | Reserved pass: lesson shells at payment; `scheduled_at` finalized at activation on existing rows |
| OD-15 | Copy active slots to new pass as independent snapshot rows |
| OD-16 | Lesson order: chronological; tie-break `slot_order` |
| OD-17 | Collision: abort with `REVE_SCHEDULE_COLLISION`; no auto-reschedule |

---

## 5. `activate_reserved_pass`

| Aspect | Specification |
|--------|---------------|
| Purpose | Transition reserved → active when prior pass completes |
| Caller | Owner manual RPC; **automatic** from lesson-transition transaction |
| **Status** | **Implemented** — `public.reve_activate_reserved_pass` + auto hook in `synchronize_pass_after_lesson_change` (Phase 0B-3B-2B-2) |

### Input

- `p_reserved_pass_id uuid`
- `p_expected_pass_updated_at timestamptz`
- `p_reason text` (optional for manual; recorded in audit when provided)

### Output

`pass_id`, `pass_public_code`, `previous_status`, `new_status`, `pass_updated_at`, `activated_at`, `lessons_scheduled`, `first_lesson_at`, `last_lesson_at`, `previous_pass_id`, `idempotent_replay`

### Automatic activation

When the final deductible lesson completes the current active pass, reserved pass activation runs **in the same transaction**. Activation finalizes `scheduled_at` on existing lesson shells. Failure rolls back pass completion and lesson transition. `reserved_pass_activation_pending` is always `false` after success.

### Manual activation preconditions

Reserved status; no other active pass; previous pass completed; schedule slots present; stale token valid or pass already active (idempotent).

### Prohibited

Reactivating cancelled pass (OD-11)

---

## 6. `transition_lesson_status`

| Aspect | Specification |
|--------|---------------|
| Purpose | Ordinary lesson status change by teacher or owner |
| Caller | Teacher (assigned) or Owner via trusted |
| **Status** | **Implemented** — `public.reve_transition_lesson_status` (Phase 0B-3B-2B-1) |

### Allowed transitions

Per [state-transitions.md](./state-transitions.md) §1.4 matrix (excluding Owner-only correction from deductible states).

### Input

- `p_lesson_id uuid`
- `p_new_status text`
- `p_expected_updated_at timestamptz`
- `p_actual_started_at timestamptz` (default NULL)
- `p_actual_ended_at timestamptz` (default NULL)
- `p_reason text` (default NULL)

### Output (explicit contract; not base-table row type)

| Field | Type |
|-------|------|
| `lesson_id` | uuid |
| `previous_status` | text |
| `new_status` | text |
| `lesson_updated_at` | timestamptz |
| `pass_id` | uuid |
| `pass_status` | text |
| `registered_lesson_count` | integer |
| `used_lesson_count` | integer |
| `remaining_lesson_count` | integer |
| `next_lesson_at` | timestamptz |
| `sms_notification_status` | text |
| `reserved_pass_activation_pending` | boolean |

### Authorization

- Teacher: `reve_private.teacher_can_access_lesson(p_lesson_id)`; profile from `public.profiles` only (JWT metadata ignored)
- Owner: always
- Student / unassigned teacher / inactive profile: `REVE_UNAUTHORIZED` (`42501`)

### Lock order

1. Resolve authenticated profile and role
2. Lock target lesson `FOR UPDATE`
3. Lock referenced pass `FOR UPDATE`
4. Lock current pass SMS row when present `FOR UPDATE`
5. Validate authorization, stale token, transition, reason, actual times
6. Update lesson; recalc usage; sync pass lifecycle; next lesson; SMS; audit

### Concurrency

- Stale `p_expected_updated_at` → `REVE_STALE_STATE` (`22000`); no mutation; no audit

### Pass synchronization

- Usage derived from lesson statuses only (no count columns written on lessons)
- Active pass with remaining = 0 → `completed` + `completed_at`
- Returns `reserved_pass_activation_pending = true` when pass completes and a `reserved` pass exists for same student+course
- **Automatic** reserved-pass activation from lesson-transition transaction (same DB transaction; updates existing shells)

### SMS synchronization

- Recalculates unsent `renewal_reminder` row for pass; preserves `sent`
- Message body template: `회차권 갱신 안내: 잔여 N회`
- Asia/Seoul date for target window

### Audit

- Append-only `audit_logs` with shared `correlation_id` per RPC transaction
- Lesson transition always logged; pass/SMS logged when changed

### Failure codes

| Code | Message | When |
|------|---------|------|
| `42501` | `REVE_UNAUTHORIZED` | Missing/invalid profile or denied role |
| `22000` | `REVE_STALE_STATE` | Optimistic concurrency mismatch |
| `P0001` | `REVE_INVALID_TRANSITION` | Matrix violation |
| `P0001` | `REVE_REASON_REQUIRED` | Blank/whitespace reason |
| `P0001` | `REVE_ACTUAL_START_REQUIRED` | `completed` without actual start |
| `P0001` | `REVE_INVALID_ACTUAL_TIMES` | End before start |
| `P0001` | `REVE_USAGE_EXCEEDED` | Deductible count > registered |
| `P0001` | `REVE_PASS_CANCELLED` | Mutation on cancelled pass |

### Prohibited

Direct count updates; deductible→non-deductible (use correction op); dynamic SQL; exposing tuition/payment/audit internals in result

---

## 7. `correct_lesson_status`

| Aspect | Specification |
|--------|---------------|
| Purpose | Owner-only correction from deductible to non-deductible (OD-02) |
| Caller | Owner only |
| **Status** | **Implemented** — `public.reve_correct_lesson_status` (Phase 0B-3B-2B-1) |

### Input

- `p_lesson_id uuid`
- `p_new_status text`
- `p_expected_updated_at timestamptz`
- `p_reason text` (**mandatory**, non-empty after trim)
- `p_actual_started_at timestamptz` (default NULL)
- `p_actual_ended_at timestamptz` (default NULL)

### Output

Same explicit contract as §6.

### Preconditions

- From ∈ {`completed`, `same_day_cancelled`, `makeup_completed`}
- To ∈ non-deductible targets per ✓O matrix in [state-transitions.md](./state-transitions.md)

### Controlled correction reopening

- When correction restores remaining lessons on a `completed` pass → pass may return to `active`; `completed_at` cleared
- `cancelled` pass never reactivated
- Audit action `pass.reopened_by_correction` when pass status changes

### Security

- `SECURITY DEFINER`, `search_path = ''`, owner `postgres`
- `REVOKE` from `PUBLIC` and `anon`; `GRANT EXECUTE` to `authenticated`, `service_role`

### Prohibited

Lesson DELETE; silent SQL from client; teacher callers

---

## 8. Schedule change review — **Implemented (0B-3B-2B-3D-2A)**

`public.reve_owner_review_schedule_change_request` — migration `20260704120000_phase_0b3b2b3d2a_schedule_change_workflow.sql`.

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner only |
| Decisions | `approve` / `reject` on `submitted` requests only |
| Approve | Sets `approved_scheduled_at` (separate from `proposed_scheduled_at`); does **not** change lesson |
| Reject | Requires reason; no lesson schedule-change event |
| Idempotency | Exact replay → `no_change` without duplicate audit |

## 9. Schedule change rejection — **Implemented (0B-3B-2B-3D-2A)**

Merged into review RPC with `p_decision = 'reject'`.

## 10. Schedule change application — **Implemented (0B-3B-2B-3D-2A)**

`public.reve_owner_apply_schedule_change_request` — approved requests only.

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner only |
| Scope | **One lesson** only; `cascaded_lesson_count = 0` |
| Lesson | Updates `scheduled_at` only; `postponed` → `scheduled`; slot FK unchanged |
| History | One append-only `lesson_schedule_changes` row; `change_origin = direct_user` |
| Collision | `REVE_SCHEDULE_COLLISION` — request stays approved, lesson unchanged |
| Fixed timetable | `schedule_slots` not modified |

Legacy design reference (`apply_schedule_change_request`):

| Aspect | Specification |

## 11. `cascade_reschedule_lessons`

| Aspect | Specification |
|--------|---------------|
| Purpose | Owner-authorized cascade shift of future non-completed lessons |
| Caller | Owner trusted |
| Preconditions | Approved request or owner directive; exclude completed (OD-01) |
| Steps | Lock affected lessons → shift each → events with `change_origin = cascade_auto` → audit |
| Distinguish | direct_user vs cascade_auto in events |
| Failure | Full rollback of all shifts |

---

## 12. Pass schedule replacement — **Implemented (0B-3B-2B-3D-1)**

`public.reve_owner_replace_pass_schedule_slots` — migration `20260703120000_phase_0b3b2b3d1_pass_schedule_management.sql`.

| Aspect | Specification |
|--------|---------------|
| Caller | Active owner only |
| Purpose | Replace **fixed weekly timetable** on `active` or `reserved` pass |
| Inputs | `pass_id`, `expected_pass_updated_at`, `schedule_slots` JSON, `reason` |
| Separation | **Fixed timetable change ≠ lesson-date change** — no lesson row updates |
| Steps | Deactivate old active slots → insert new active slots |
| No-op | Fingerprint match → no deactivate/insert/audit/pass touch |
| Collision | Recurring teacher/weekday time-range overlap → `REVE_SCHEDULE_COLLISION`; reserved may overlap same student/course active predecessor |
| Immutable | `completed`/`cancelled` → `REVE_PASS_SCHEDULE_IMMUTABLE` |
| Result | `lesson_rows_changed = 0` always |

Legacy design reference (`replace_pass_schedule_slots`):

| Aspect | Specification |
|--------|---------------|
| Purpose | Replace active slot set for pass (deactivate old, insert new) |
| Caller | Owner trusted |
| Preconditions | Pass active or reserved; audit |
| Steps | Deactivate prior active slots → insert new → optional future lesson regen (future phase) |
| Prohibited | Silent rewrite of past lesson scheduled_at from slot row |

---

## 13. `process_payment_refund`

| Aspect | Specification |
|--------|---------------|
| Purpose | Active or reserved pass full refund (OD-12, OD-13) |
| Caller | Owner trusted |

### Ordered steps (OD-12)

1. Owner authorization
2. Lock payment + pass FOR UPDATE
3. Verify no existing payment_refunds row for payment
4. Validate amount = paid_amount_krw (full refund MVP)
5. Mandatory reason
6. INSERT single immutable payment_refunds row
7. Preserve deductible historical lessons unchanged
8. UPDATE future non-deducted lessons → advance_cancelled
9. SET pass status cancelled + cancelled_at
10. UPDATE payment status refunded
11. Recalculate SMS
12. Audit entries with one correlation_id
13. COMMIT atomically

### Failure

ROLLBACK — no refund row

### Idempotency

Second attempt after success → reject (refund row exists)

### Prohibited

Cancelled pass reactivation; partial refund MVP

---

## 14. `confirm_sms_sent`

| Aspect | Specification |
|--------|---------------|
| Purpose | Owner confirms manual SMS sent (MVP) |
| Caller | Owner |
| Input | sms_notification_id, optional message_body_snapshot update |
| Steps | SET status sent, sent_at, sent_confirmed_by_profile_id |
| Audit | Optional |
| Prohibited | Teacher confirm in MVP |

---

## 15. `correct_cancelled_pass`

| Aspect | Specification |
|--------|---------------|
| Purpose | Owner correction after mistaken cancel (OD-11) |
| Caller | Owner trusted |
| Steps | Preserve cancelled pass → create NEW pass with correction_source_pass_id → audit |
| Prohibited | Reactivating cancelled pass row |

---

## Internal helper operations (not client-callable)

| Helper | Purpose |
|--------|---------|
| `reve_generate_pass_code_and_sequence` | Lock student; next sequence; unique pass_code |
| `reve_generate_lessons_from_schedule_slots` | Chronological + slot_order sort; assign sequence (OD-16 provisional) |
| `reve_validate_lesson_pass_consistency` | Denormalized fields match pass |
| `reve_calculate_pass_usage` | Count deductible lessons |
| `reve_recalculate_sms_state` | Scoped SMS status for pass |
| `reve_detect_final_deductible_completion` | Last deductible → reserved activation |
| `reve_activate_one_reserved_pass` | Shared core for activation |
| `reve_append_audit_event` | Standardized audit insert |
| `reve_append_lesson_schedule_change` | Event row with origin |

All internal: `REVOKE EXECUTE FROM PUBLIC, authenticated`; callable only from other definer functions.

---

## Read-only client RPC contracts (Phase 0B-3B-2A)

These are **not** mutation operations. Wrong role or inactive profile → **empty result set** (no row-existence leak).

### `reve_get_my_pass_summary()`

| Aspect | Specification |
|--------|---------------|
| Purpose | Student operational pass usage summary for UI |
| Caller | Authenticated student (`profiles.role = student`, active) |
| Inputs | None (uses `auth.uid()`) |
| Output | One row per current `active`/`reserved` pass: pass/course ids and codes, status, registered/used/remaining counts, next scheduled lesson, dates, assigned teacher display name |
| Authorization | `reve_private.current_student_id()`; no caller-supplied ids |
| Sensitive exclusions | Tuition/discount snapshots, product pricing, payment/audit fields |
| Empty result | Non-student, inactive profile, or no qualifying passes |
| Failure | No detailed authorization exceptions |
| Provisional | OD-14: reserved pass may have null next lesson |

### `reve_get_my_assigned_student_summaries()`

| Aspect | Specification |
|--------|---------------|
| Purpose | Teacher operational view of currently assigned students |
| Caller | Authenticated teacher (active) |
| Inputs | None |
| Output | Student/course/pass identifiers, usage counts, next assigned lesson, slot weekday/time |
| Authorization | Active/reserved pass with current teacher slot or lesson assignment; historical-only pass does not qualify |
| Sensitive exclusions | Student contact, tuition, payments, SMS, notes, other teachers' data |
| Empty result | Non-teacher or no current assignments |

### `reve_get_my_payment_summary()`

| Aspect | Specification |
|--------|---------------|
| Purpose | Student payment-facing history |
| Caller | Authenticated student (active) |
| Inputs | None |
| Output | Payment id, related pass code, course display, paid amount, status, method, paid/created timestamps |
| Authorization | Own `student_id` only |
| Sensitive exclusions | Idempotency key, processed_at, created_by, refund base rows |
| Empty result | Non-student; no payments |

### `reve_get_my_teacher_display()`

| Aspect | Specification |
|--------|---------------|
| Purpose | Student-safe teacher list for current enrollment |
| Caller | Authenticated student (active) |
| Inputs | None |
| Output | Distinct teacher id/code/name per course from active/reserved passes, slots, future lessons |
| Sensitive exclusions | Phone, email, internal teacher account fields |
| Empty result | Non-student; no linked teachers |

### `reve_get_my_current_notice()`

| Aspect | Specification |
|--------|---------------|
| Purpose | Student current-pass payment/SMS notice (MVP) |
| Caller | Authenticated student (active) |
| Inputs | None |
| Output | Pass id/code, course name, message body snapshot, target date, sent timestamp |
| Authorization | Current active/reserved pass; non-empty message body only |
| Sensitive exclusions | SMS status calculation, actor ids, notification type, audit metadata |
| Empty result | Non-student; no user-facing message on current pass |
| Provisional | **OD-20** — subject to owner review; not hardened as irreversible policy |

---

## Related documents

- [postgresql-physical-design.md](./postgresql-physical-design.md)
- [rls-policy-design.md](./rls-policy-design.md)
- [open-decisions.md](./open-decisions.md)
- [database-test-plan.md](./database-test-plan.md)

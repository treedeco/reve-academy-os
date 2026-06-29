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

## 1. `provision_profile`

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

## 2. `set_profile_role`

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

---

## 3. `create_initial_pass`

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

- Active pass with **remaining > 0** → new pass `reserved`; lessons **deferred** (schema: `scheduled_at NOT NULL`)
- No active pass (or prior completed) → new pass `active`; lessons generated in same transaction

### Idempotency

- Completed payment + matching key → safe replay (`idempotent_replay = true`); no duplicate pass/lessons/SMS/audit
- Conflicting key, amount, or method → `REVE_IDEMPOTENCY_CONFLICT`

### Failure codes

`REVE_UNAUTHORIZED`, `REVE_STALE_STATE`, `REVE_IDEMPOTENCY_CONFLICT`, `REVE_PAYMENT_NOT_COMPLETABLE`, `REVE_PAYMENT_AMOUNT_MISMATCH`, `REVE_INVALID_PAYMENT_METHOD`, `REVE_RESERVED_EXISTS`, `REVE_NO_SCHEDULE`, `REVE_SCHEDULE_COLLISION`

---

### Provisional policies (OD-14 ~ OD-17) — **implemented as provisional; Owner UI review still required**

| OD | Policy |
|----|--------|
| OD-14 | Reserved pass: lessons generated at activation; first slot after prior pass completion boundary |
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

When the final deductible lesson completes the current active pass, reserved pass activation runs **in the same transaction**. Failure rolls back pass completion and lesson transition. `reserved_pass_activation_pending` is always `false` after success.

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
- **Does not** activate reserved pass (OD-14 provisional; deferred)

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

## 8. `approve_schedule_change_request`

| Aspect | Specification |
|--------|---------------|
| Purpose | Owner approves pending request (OD-01) |
| Caller | Owner |
| Input | request_id, decision_note, expected_updated_at |
| Preconditions | status ∈ {submitted, under_review} |
| Output | status = approved |
| Audit | Required |

---

## 9. `reject_schedule_change_request`

| Aspect | Specification |
|--------|---------------|
| Purpose | Owner rejects request |
| Caller | Owner |
| Input | request_id, decision_note |
| Output | status = rejected |
| Audit | Required |

---

## 10. `apply_schedule_change_request`

| Aspect | Specification |
|--------|---------------|
| Purpose | Apply approved schedule change to target lesson |
| Caller | Owner trusted |

### Steps

1. Request status = approved; not yet applied
2. Lock request + target lesson
3. Validate lesson not completed / not deductible terminal
4. Detect collision (OD-17 provisional) — abort with collision list if overlap
5. UPDATE lesson `scheduled_at` (direct change)
6. INSERT `lesson_schedule_changes` with `change_origin = direct_user`
7. SET request status applied, applied_at
8. Audit + correlation_id
9. ROLLBACK on any failure

### Prohibited

Modifying schedule_slots unless separate slot edit op

---

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

## 12. `replace_pass_schedule_slots`

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

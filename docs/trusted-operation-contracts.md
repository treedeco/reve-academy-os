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

### Input contract

- `payment_id uuid`
- `idempotency_key text` (must match payment row)
- `expected_payment_updated_at timestamptz`
- `payment_method text` (required at completion — OD-18 provisional: `cash`, `bank_transfer`, `card`, `other`)
- `payment_method_note text` (required when method = `other`)
- Optional schedule slot edits after copy (OD-15)

### Output contract

- `payment_id`, `renewed_pass_id`, `pass_code`, `pass_status` (active or reserved)
- Existing result if already processed

### Ordered steps

1. Authenticate and authorize owner
2. Validate payment status = `pending` (or completed for idempotent return)
3. `SELECT payment FOR UPDATE`; validate stale
4. Check idempotency: if `renewed_pass_id` set → return existing bundle
5. Load student, course, product, related_pass
6. `SELECT student FOR UPDATE` (race-safe sequence)
7. Compute next sequence + pass_code (internal helper)
8. Decide **active vs reserved** (existing active pass → reserved per OD-10)
9. Preserve all previous pass/lesson history (no deletes)
10. INSERT pass with immutable snapshots (OD-09)
11. **Copy active schedule slots** from current pass as independent rows (OD-15 provisional); Owner edits allowed before commit
12. **Reserved pass**: set placeholder `start_date`; **defer lesson generation** until activation (OD-14 provisional). **Active pass**: generate lessons now using chronological order / `slot_order` tie-break (OD-16 provisional)
13. Run **collision detection**; on conflict abort with collision list — no auto-move (OD-17 provisional)
14. UPDATE payment: status completed, renewed_pass_id, paid_at, processed_at, payment_method
15. INSERT sms_notifications row for new pass (reset lifecycle)
16. Append audit logs with shared `correlation_id`
17. COMMIT only if all succeed

### Locks

Payment row, student row, prior active pass row if status transition needed

### Idempotency

Same idempotency_key / payment already completed → return same renewed_pass_id

### SMS

New pass → new SMS row; prior pass SMS preserved

### Failure

Full ROLLBACK; payment stays pending; no pass, no lessons, no SMS

### Retry

Safe after failure; duplicate completion returns existing

---

### Provisional policies (OD-14 ~ OD-17) — subject to owner review before executable migration

| OD | Policy |
|----|--------|
| OD-14 | Reserved pass: no final lesson dates until activation; on activation first valid slot after prior pass completion |
| OD-15 | Copy active slots to new pass as independent snapshot rows; prior pass edits do not propagate |
| OD-16 | Lesson order: chronological, tie-break `slot_order`, then sequence_number |
| OD-17 | Collision: stop + return list; no arbitrary auto-reschedule |

---

## 5. `activate_reserved_pass`

| Aspect | Specification |
|--------|---------------|
| Purpose | Transition reserved → active when prior pass completes |
| Caller | Trusted (triggered from lesson completion or manual owner) |
| Preconditions | Exactly one reserved; prior active completed or cancelled; not cancelled terminal |
| Locks | Student, both passes FOR UPDATE |
| Steps | Validate → compute first lesson from first valid slot after completion (OD-14 provisional) → generate deferred lessons (OD-16) → collision check (OD-17) → UPDATE reserved status → set activated_at → audit |
| Idempotency | If already active → no-op success |
| Prohibited | Reactivating cancelled pass (OD-11) |

---

## 6. `transition_lesson_status`

| Aspect | Specification |
|--------|---------------|
| Purpose | Ordinary lesson status change by teacher or owner |
| Caller | Teacher (assigned) or Owner via trusted |

### Allowed transitions

Per [state-transitions.md](./state-transitions.md) §1.4 matrix (excluding Owner-only correction from deductible states).

### Input

- `lesson_id`, `new_status`, `reason`, `actual_start_at`, `actual_end_at`, `expected_updated_at`
- Optional makeup source for new makeup row path (separate insert)

### Authorization

- Teacher: `teacher_can_access_lesson`
- Owner: always

### Steps

1. Lock lesson FOR UPDATE
2. Stale check
3. Validate transition allowed
4. Validate reason / actual times per status rules
5. UPDATE lesson status (deduction implicit — no count columns)
6. Recalculate pass usage (read model / query)
7. Recalculate next lesson pointer (derived)
8. Recalculate SMS for pass (internal helper)
9. If last deductible on active pass → call `activate_reserved_pass`
10. Audit with previous/new JSON
11. COMMIT or full ROLLBACK

### Prohibited

Direct count updates; cascade from this op; deductible→non-deductible (use correction op)

---

## 7. `correct_lesson_status`

| Aspect | Specification |
|--------|---------------|
| Purpose | Owner-only correction from deductible to non-deductible (OD-02) |
| Caller | Owner only |
| Input | lesson_id, new_status, mandatory reason, expected_updated_at |
| Preconditions | From ∈ {completed, same_day_cancelled, makeup_completed}; to per ✓O matrix |
| Locks | Lesson, pass FOR UPDATE |
| Steps | Validate → update → usage recalc → SMS → audit |
| Prohibited | Lesson DELETE; silent SQL from client |

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

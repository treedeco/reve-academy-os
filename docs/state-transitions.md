# State Transitions — REVE ACADEMY OS

Phase 0A **상태 전이** 명세. Canonical identifier는 English code value. Korean는 display meaning.

**Confirmed 2026-06-26**: OD-01 ~ OD-12. Deduction source of truth: **lesson status only**.

---

## 1. Lesson statuses

### 1.1 Status reference

| Status | Korean (display) | Deductible | Scheduled time | Actual time | Reason required |
|--------|------------------|------------|----------------|-------------|-----------------|
| `scheduled` | 예정 | No | Required | Optional until completed | No (entry) |
| `completed` | 완료 | **Yes** | Required | Required | No (ordinary) |
| `same_day_cancelled` | 당일 취소 | **Yes** | Required | Optional | Yes |
| `makeup_completed` | 보강 완료 | **Yes** | Required | Required | Yes (link to source) |
| `postponed` | 연기 | No | Required (original) | Optional | Yes |
| `advance_cancelled` | 사전 취소 | No | Required | Optional | Yes |
| `teacher_cancelled` | 강사 취소 | No | Required | Optional | Yes |
| `academy_closed` | 학원 휴무 | No | Required | Optional | Yes |

### 1.2 Role authority summary

| Transition class | Enter | Leave |
|------------------|-------|-------|
| Ordinary operational | Owner, Teacher (assigned) | Owner, Teacher (assigned) per matrix |
| Owner-only correction | — | Deductible → non-deductible: **Owner only** via trusted function |
| Cascade auto-move | — | **Trusted only** after approved schedule request; **never** `completed` lessons |

### 1.3 Effects (conceptual)

| Status | Used/remaining | Next lesson | SMS | Cascade allowed | Pass activation |
|--------|----------------|-------------|-----|-----------------|-----------------|
| `scheduled` | No change | Included | Normal flow | Target may move if approved | No |
| `completed` | Used +1 | Recalc | May → target/exhausted | **No auto move** | May trigger reserved→active if last deductible |
| `same_day_cancelled` | Used +1 | Recalc | Same as completed | No | Same as completed |
| `makeup_completed` | Used +1 (makeup row only) | Recalc | Same | No | Same |
| `postponed` | No deduct | Recalc | Recalc | Optional later incomplete | No |
| `advance_cancelled` | No deduct | Recalc | Recalc | Reschedule workflow | No |
| `teacher_cancelled` | No deduct | Recalc | Recalc | Optional makeup path | No |
| `academy_closed` | No deduct | Recalc | Recalc | Optional shift | No |

### 1.4 Allowed transition matrix

Rows = **from**, columns = **to**. ✓ = allowed (with conditions). ✓O = Owner-only via trusted correction. — = prohibited.

| From \ To | scheduled | completed | same_day_cancelled | makeup_completed | postponed | advance_cancelled | teacher_cancelled | academy_closed |
|-----------|-----------|-----------|-------------------|------------------|-----------|-------------------|-------------------|----------------|
| **scheduled** | — | ✓ | ✓ | —* | ✓ | ✓ | ✓ | ✓ |
| **postponed** | ✓ | ✓ | ✓ | —* | — | ✓ | ✓ | ✓ |
| **advance_cancelled** | ✓** | ✓ | — | —* | — | — | — | — |
| **teacher_cancelled** | ✓** | — | — | ✓*** | — | — | — | — |
| **academy_closed** | ✓** | — | — | — | ✓ | — | — | — |
| **completed** | ✓O | — | — | — | ✓O | ✓O | ✓O | ✓O |
| **same_day_cancelled** | ✓O | — | — | — | ✓O | ✓O | ✓O | ✓O |
| **makeup_completed** | ✓O | — | — | — | ✓O | ✓O | ✓O | ✓O |

\* `makeup_completed` entered only as **new lesson row** linked to source, not direct transition from `scheduled` without makeup workflow.

\** `advance_cancelled` → `scheduled` only through **explicit rescheduling workflow** (Owner-approved schedule request or Owner direct reschedule).

\*** `teacher_cancelled` → `makeup_completed` only via **new makeup lesson** record; original stays `teacher_cancelled`.

### 1.5 Prohibited transitions

- Arbitrary jump between deductible statuses (e.g. `completed` → `same_day_cancelled`) without Owner correction workflow
- `completed` / deductible → another deductible status directly
- Teacher: any deductible → non-deductible (Owner only, OD-02)
- Automatic cascade movement **into or out of** `completed`, `same_day_cancelled`, `makeup_completed`

### 1.6 Owner-only correction (OD-02)

**From**: `completed`, `same_day_cancelled`, `makeup_completed`
**To**: non-deductible status per matrix (✓O cells)

Requirements:

- Owner only
- Mandatory correction reason
- `audit_logs`: previous and new values
- Single consistent operation updates: lesson, pass used/remaining, next lesson, SMS, dashboard counters
- Trusted function execution

### 1.7 Makeup lesson linkage (OD-05)

**Conceptual flow**:

1. Source lesson enters non-deductible cancelled/postponed state (e.g. `teacher_cancelled`, `advance_cancelled`) — **deductible = false**.
2. New lesson row created with status `makeup_completed`, **explicit link** to source lesson id.
3. **Double deduction prevention**:
   - Source remains non-deductible
   - Only makeup row counts as deductible (`makeup_completed`)
   - System rejects second makeup_completed for same source if one already deductible-completed
   - No hidden “deducted” flag — status is sole source of truth

**Original lesson**: preserved, never replaced or physically deleted.

---

## 2. Pass statuses

### 2.1 Status reference

| Status | Korean (display) | Meaning |
|--------|------------------|---------|
| `reserved` | 예약됨 | Created (often advance payment); not yet active |
| `active` | 진행 중 | Current operating pass |
| `completed` | 완료 | All lessons consumed or pass completion rules met |
| `expired` | 만료 | Expiration policy applied (optional date, OD-03) |
| `cancelled` | 취소됨 | **Terminal** — refund, owner cancel, correction (OD-11) |

### 2.2 Allowed transitions

| From | To | Authority | Entry / exit conditions | Audit |
|------|-----|-----------|-------------------------|-------|
| — | `reserved` | Trusted (payment renewal) | Advance payment; 0–1 reserved per (student,course) | ✓ |
| — | `active` | Trusted | First pass or immediate activation on payment | ✓ |
| `reserved` | `active` | Trusted | Prior pass last deductible completed; activation workflow | ✓ |
| `reserved` | `cancelled` | Owner + Trusted | Reserved refund (OD-06); owner cancel | ✓ |
| `active` | `completed` | Trusted / Owner | Pass completion conditions met | ✓ |
| `active` | `expired` | Owner / Trusted | Expiration **policy applies** (OD-03); optional date | ✓ |
| `active` | `cancelled` | Owner + Trusted | Active-pass refund (OD-12) or controlled owner cancel; **not** reactivatable | ✓ |
| `completed` | — | — | Terminal (normal) | — |
| `expired` | — | — | Terminal | — |
| `cancelled` | — | — | **Terminal** | — |

### 2.3 Prohibited transitions

- `cancelled` → `active` (**OD-11**)
- `cancelled` → `reserved` (**OD-11**)
- `cancelled` → any other state
- More than one `active` per (student, course)
- More than one `reserved` per (student, course)
- Reactivation of cancelled pass — use **new pass** + correction link instead

### 2.4 Reserved → active (trusted)

Triggered when:

- Current `active` pass for same (student, course) reaches completion (last **deductible** lesson completed), **and**
- A `reserved` pass exists (0 or 1)

Single transaction; audit required.

---

## 3. Payment statuses

### 3.1 Status reference

| Status | Korean (display) |
|--------|------------------|
| `pending` | 대기 |
| `completed` | 완료 |
| `cancelled` | 취소 |
| `refunded` | 환불 |

### 3.2 Allowed transitions

| From | To | Authority | Notes | Audit |
|------|-----|-----------|-------|-------|
| — | `pending` | Owner | Payment registered | ✓ |
| `pending` | `completed` | Owner + Trusted | **First valid** completion invokes pass renewal | ✓† |
| `pending` | `cancelled` | Owner | No pass created | ✓ |
| `completed` | `refunded` | Owner + Trusted | Preserves payment/pass/lessons; does not delete (OD-06, OD-12) | ✓† |
| `cancelled` | — | — | Terminal | — |
| `refunded` | — | — | Terminal | — |

### 3.3 Prohibited transitions

- `refunded` → `completed`
- `cancelled` → `completed` without new payment record
- Second `pending` → `completed` processing creating **second pass** for same idempotency key

### 3.4 Idempotency

- Only **first valid** `pending` → `completed` creates/connects renewed pass
- Repeated calls with same payment reference or idempotency key return **existing result**
- Snapshots immutable on pass/payment (OD-09)

### 3.5 Refund boundaries (OD-06, OD-12)

| Pass type at refund | Behavior |
|---------------------|----------|
| `reserved` | Pass → `cancelled`; history preserved; never activate |
| `active` | **OD-12 controlled refund** — see §3.6 |

Refund does **not** physically delete payment, pass, or lesson data. Refund does **not** directly overwrite used or remaining counts.

### 3.6 Active-pass controlled refund (OD-12) — trusted operation only

**Authority**: Owner initiates (mandatory refund amount + reason). **Teacher and Student prohibited.**

**Coordinated transitions** (single trusted transaction; all succeed or rollback):

| Entity | Transition |
|--------|------------|
| Payment | `completed` → `refunded` (refund record: amount, date, reason, actor) |
| Pass | `active` → `cancelled` (**terminal** — no reactivation) |
| Future non-deducted lessons | → `advance_cancelled` |
| SMS | Scoped recalculation for affected pass |
| Audit | Mandatory; original scheduled data for each affected future lesson preserved |

**Unchanged**:

- Completed and other **deductible historical** lessons — **no status change**
- Used/remaining counts — remain **derived** from lesson statuses + registered lesson count snapshot; **never manually edited**

**Prohibited**:

- Partial refund while pass remains `active` (MVP)
- Transfer remaining counts; credits; stored balances (MVP)
- Independent client updates to payment, pass, and lessons without trusted coordination
- `cancelled` → `active` or `cancelled` → `reserved` (OD-11)

**Mistaken refund**: new Owner-controlled pass correction workflow — **not** reactivation of cancelled pass.

---

## 4. Schedule change request statuses

### 4.1 Status reference

| Status | Korean (display) |
|--------|------------------|
| `submitted` | 제출됨 |
| `under_review` | 검토 중 |
| `approved` | 승인됨 |
| `rejected` | 거절됨 |
| `cancelled` | 취소됨 |
| `applied` | 적용됨 |

### 4.2 Allowed transitions

| From | To | Authority | Notes |
|------|-----|-----------|-------|
| — | `submitted` | Teacher (assigned), Student (own) | Reason + suggested replacement values |
| `submitted` | `under_review` | Owner | Optional explicit step |
| `submitted` | `approved` | **Owner only** | OD-01 |
| `submitted` | `rejected` | **Owner only** | OD-01 |
| `submitted` | `cancelled` | Submitter | Before apply |
| `under_review` | `approved` | **Owner only** | |
| `under_review` | `rejected` | **Owner only** | |
| `approved` | `applied` | **Trusted only** | Moves lessons; cascade rules |
| `approved` | `cancelled` | Owner | Before apply |
| `applied` | — | — | Immutable except documented Owner correction |
| `rejected` | — | — | Terminal |
| `cancelled` | — | — | Terminal |

### 4.3 Prohibited

- Teacher: `submitted` → `approved` / `rejected` / `applied`
- Apply without `approved`
- Cascade including `completed` lessons

---

## 5. SMS notification statuses

### 5.1 Status reference

| Status | Korean (display) | Derived / manual |
|--------|------------------|------------------|
| `normal` | 일반 | System-derived |
| `scheduled` | 발송 예정 | System-derived (remaining = 1, before notification date) |
| `target` | 발송 대상 | System-derived (from 1 day before final lesson) |
| `exhausted_unsent` | 소진·미발송 | System-derived (remaining = 0, not sent) |
| `sent` | 발송 완료 | **Manual** Owner confirm (MVP) |

### 5.2 Derived conditions

| Condition | State |
|-----------|-------|
| Default / no trigger | `normal` |
| remaining = 1, before notification date | `scheduled` |
| From 1 day before final lesson | `target` |
| remaining = 0, not sent | `exhausted_unsent` |
| Owner manual confirm | `sent` |

### 5.3 Transitions

| From | To | Notes |
|------|-----|-------|
| `normal` | `scheduled` / `target` / `exhausted_unsent` | System recalc on lesson/pass change |
| `scheduled` | `target` / `exhausted_unsent` / `sent` | Recalc or manual |
| `target` | `sent` / `exhausted_unsent` | Manual or recalc |
| `exhausted_unsent` | `sent` | Owner manual only |
| `sent` | other | **Default: no** — history preserved; new pass starts fresh SMS record |

### 5.4 New pass reset

- Payment renewal / new pass creation → **new** SMS notification record for that pass context; states reset to derived baseline (`normal` → rules apply)
- Prior pass sent history **preserved** on old pass record

### 5.5 Lesson correction (OD-02)

- Owner correction may recalculate SMS state for affected pass (scoped)
- Does not rewrite historical `sent` on prior pass periods

---

## 6. Phase 0B-3B-2B-1 implementation mapping

| Behavior | RPC / path | Notes |
|----------|------------|-------|
| Ordinary lesson transitions (§1.4 matrix, non-deductible sources) | `public.reve_transition_lesson_status` | Owner or assigned teacher |
| Owner correction (✓O cells) | `public.reve_correct_lesson_status` | Mandatory reason |
| Pass completion when remaining = 0 | Automatic inside both RPCs | Sets `completed_at`; no pass delete |
| Controlled pass reopen after correction | Inside `reve_correct_lesson_status` only | `completed` → `active` when remaining > 0 |
| Reserved pass activation | **Deferred** | Returns `reserved_pass_activation_pending`; OD-14 provisional |
| Usage / remaining counts | Derived in RPC result | Not persisted on `lessons` |
| SMS recalc | `reve_private.synchronize_sms_notification` | Preserves `sent` on same pass |

---

## Related documents

- [domain-rules.md](./domain-rules.md)
- [permissions-matrix.md](./permissions-matrix.md)
- [project-brief.md](./project-brief.md)
- [open-decisions.md](./open-decisions.md)

# Domain Rules — REVE ACADEMY OS

Phase 0A 권위 있는 **비즈니스 규칙** 문서입니다. SQL, migration, index, RLS policy는 포함하지 않습니다.

**Confirmed decisions (2026-06-26)**: OD-01 ~ OD-12. 상세는 [open-decisions.md](./open-decisions.md).

**Cross-cutting invariants** (모든 domain):

- PostgreSQL is the single source of truth
- Used count = count of lessons in **deductible** statuses (`completed`, `same_day_cancelled`, `makeup_completed`)
- Remaining count = registered lesson count − used count
- Used and remaining counts are **not user-editable**
- Deduction is derived from **lesson status** only (no second deduction source)
- Pass, lesson, and payment history is **not physically deleted**
- One **active** pass per (student, course)
- Zero or one **reserved** pass per (student, course)
- Pass IDs are unique
- Lesson sequence numbers are unique within a pass
- Product price changes do **not** alter pass or payment snapshots
- **Cancelled** passes cannot return to `active` or `reserved`
- Completed/deductible lessons cannot be corrected without **Owner**, **mandatory reason**, **transaction consistency**, and **audit_logs**
- Business date/time: **Asia/Seoul**

---

## 1. Profiles and roles

### Purpose

Supabase Auth 사용자와 애플리케이션 역할(Owner, Teacher, Student)을 연결합니다.

### Source-of-truth rules

- `profiles`는 Auth user id와 1:1
- Role은 `profiles` 및 server-side 검증의 authoritative source

### Invariants

- 한 Auth user는 하나의 primary operational role (MVP)
- Role 변경은 Owner만; audit 필수

### Allowed operations

- Owner: role assignment, profile read/update (non-destructive)
- Teacher/Student: own profile read; limited self-update (contact prefs 등 — 구현 Phase)

### Prohibited operations

- Teacher/Student: role elevation
- Any role: profile physical delete

### Related domains

students, teachers, permissions, audit_logs

### Audit requirements

Role change, permission change → `audit_logs`

### Relevant decisions

OD-01 (Teacher authority boundaries)

---

## 2. Students

### Purpose

재원 학생 마스터 및 operational context (배정 강사, course enrollment context).

### Source-of-truth rules

- Student identity and enrollment facts live in PostgreSQL
- Dashboard aggregates are derived, not stored as editable counters

### Invariants

- Student may have **multiple courses simultaneously** (OD-07)
- Pass rules are scoped per (student, course), not globally per student

### Allowed operations

- Owner: CRUD (no physical delete — deactivate/archive pattern in implementation)
- Teacher: read **assigned** students only
- Student: read **own** record only

### Prohibited operations

- Teacher: read unassigned students
- Student: edit pass, counts, payments, tuition
- Any role: physical delete of student with pass/lesson history

### Related domains

teachers, courses, passes, lessons, payments

### Audit requirements

Owner changes to student master affecting billing or assignment → audit

### Relevant decisions

OD-07

---

## 3. Teachers

### Purpose

강사 마스터 및 학생·수업 배정 관계.

### Source-of-truth rules

- Teacher assignment drives Teacher role data scope

### Invariants

- Teacher access is limited to assigned students and assigned lessons

### Allowed operations

- Owner: teacher CRUD, assignment management
- Teacher: read own teacher record; read assigned students/lessons

### Prohibited operations

- Teacher: view other teachers’ students; edit product prices; total revenue

### Related domains

students, lessons, schedule_slots, schedule_change_requests

### Audit requirements

Assignment changes → audit (Owner)

### Relevant decisions

OD-01

---

## 4. Courses

### Purpose

과목/커리큘럼 정의 (commercial packaging 아님).

### Source-of-truth rules

- `courses` = subject/curriculum metadata
- Tuition and lesson counts come from **`course_products`**, not course alone (OD-08)

### Invariants

- Course deletion (if ever allowed) must not destroy pass/lesson history — prefer inactive flag

### Allowed operations

- Owner: course CRUD (non-destructive)
- Teacher/Student: read courses relevant to their scope

### Prohibited operations

- Teacher: edit course commercial fields tied to products
- Storing default tuition on course as authoritative product price (use `course_products`)

### Related domains

course_products, passes, schedule_slots

### Audit requirements

Course deactivation → audit

### Relevant decisions

OD-08

---

## 5. Course products

### Purpose

**Commercial package** 정의: lesson count, frequency, default tuition, optional expiration policy.

### Source-of-truth rules

- Planned table: **`course_products`**
- Links to `courses`; drives pass creation defaults and snapshots
- **Document only in Phase 0A — no table/SQL yet**

### Invariants

- Product price change does **not** retroactively change existing pass/payment snapshots (OD-09)
- `active`/`inactive` product state; inactive products not used for new passes

### Fields (planned)

- Product name
- Course reference
- Default lesson count (e.g. 4, 8, 10, 12)
- Weekly frequency (e.g. 1, 2)
- Default tuition amount
- Optional expiration policy
- Active/inactive state

### Allowed operations

- Owner: product CRUD (implementation Phase)
- Others: read active products in scope

### Prohibited operations

- Editing snapshots on existing passes/payments via product update
- Teacher/Student: product price edit

### Related domains

courses, passes, payments

### Audit requirements

Product price or lesson count default change → audit

### Relevant decisions

OD-08, OD-09

---

## 6. Passes

### Purpose

회차권 lifecycle: registered lessons, financial/contract snapshots, status.

### Source-of-truth rules

- Pass record + its lessons = authoritative for used/remaining (derived from lesson status)
- Pass ID format e.g. `V-S006-001`, `V-S006-002` — unique globally

### Invariants

- One **active** pass per (student, course)
- **Zero or one reserved** per (student, course); reserved not mandatory (OD-10)
- Previous passes preserved; never overwritten or physically deleted
- **Cancelled is terminal** — no reactivation (OD-11)
- Snapshots at creation: product ref, product name, registered lesson count, weekly frequency, tuition amount (OD-09)
- Optional **expiration date** — absence does not invalidate pass (OD-03)

### Allowed operations

- Owner: create via payment renewal (trusted function); cancel; mark completed/expired; correction workflow for mistaken cancel (new pass, not reactivation)
- Trusted function: `reserved → active` when prior pass completion conditions met
- Teacher/Student: read pass in scope; no financial snapshot edit

### Prohibited operations

- Direct edit of used/remaining counts
- `cancelled → active` or `cancelled → reserved`
- More than one reserved per (student, course)
- Physical delete

### Related domains

course_products, lessons, schedule_slots, payments, sms_notifications

### Audit requirements

Status transitions (especially cancel, expired, correction-linked new pass) → audit

### Relevant decisions

OD-03, OD-07, OD-09, OD-10, OD-11

---

## 7. Fixed schedule slots

### Purpose

Pass에 연결된 **고정 요일·로컬 시간** 슬롯. Lesson generation 및 weekly schedule의 기준.

### Source-of-truth rules

- Slots configured on pass (or pass creation from product)
- **Not inferred** from first actual lesson, postponed date, or manual reschedule (OD-04)

### Invariants

- One pass may have **multiple slots** (OD-04)
- Weekly once → normally 1 slot; weekly twice → normally 2 slots
- Each slot: weekday, local start time, duration, teacher, active state
- Asia/Seoul for local time interpretation

### Allowed operations

- Owner: define/update slots at pass setup (implementation Phase)
- Owner: replace active/reserved pass timetable via `reve_owner_replace_pass_schedule_slots` (Phase 0B-3B-2B-3D-1) — **does not move lesson dates**
- Read within role scope

### Prohibited operations

- Deriving slot pattern from actual lesson dates
- Teacher: alter another teacher’s slot via schedule approval bypass

### Related domains

passes, lessons, schedule_change_requests

### Audit requirements

Slot changes affecting future lesson generation → audit

### Relevant decisions

OD-04

---

## 8. Lessons

### Purpose

Pass별 독립 수업 레코드. Status가 deduction의 **유일한** source.

### Source-of-truth rules

- Each lesson belongs to exactly one pass and student
- Sequence number unique within pass
- Status canonical values: `scheduled`, `completed`, `same_day_cancelled`, `makeup_completed`, `postponed`, `advance_cancelled`, `teacher_cancelled`, `academy_closed`

### Invariants

- Lesson cannot exist without valid student + pass
- **Completed lessons excluded from automatic cascading movement**
- User-initiated change vs cascade auto-move must be distinguishable
- Makeup lesson **must link** to source lesson (OD-05); original preserved

### Allowed operations

- Teacher: ordinary status transitions on **assigned** lessons (see state-transitions)
- Owner: all ordinary transitions + owner-only correction (deductible → non-deductible)
- Trusted function: cascade movement after approved schedule request

### Prohibited operations

- Student: status edit
- Teacher: owner-only correction; cascade execution
- Physical delete
- Arbitrary jump between completed-type statuses without rules

### Related domains

passes, lesson deduction, schedule_slots, schedule_change_requests, sms_notifications

### Audit requirements

Owner correction, cascade moves, makeup creation → audit

### Relevant decisions

OD-02, OD-05, OD-01

---

## 9. Lesson deduction

### Purpose

Used/remaining 계산 규칙. **Lesson status only.**

### Source-of-truth rules

```
used count = count(lessons where status ∈ deductible)
remaining count = registered_lesson_count − used count
```

### Deductible statuses

`completed`, `same_day_cancelled`, `makeup_completed`

### Non-deductible statuses

`scheduled`, `postponed`, `advance_cancelled`, `teacher_cancelled`, `academy_closed`

### Invariants

- Used and remaining are **derived**, never user-editable
- Impossible states rejected (used > total, remaining < 0, inconsistent triples)
- **Double deduction prevention** for makeup (OD-05): source lesson in non-deductible cancelled state; makeup bears `makeup_completed`; at most one deductible outcome per makeup event

### Allowed operations

- System/trusted function: recalculate pass aggregates after status change (scoped)

### Prohibited operations

- Client direct write to used/remaining fields
- Second hidden deduction flag as source of truth

### Related domains

lessons, passes, sms_notifications

### Audit requirements

Owner correction affecting deduction → audit (OD-02)

### Relevant decisions

OD-02, OD-05

---

## 10. Schedule change requests

### Purpose

일정 변경 요청 workflow. Owner 최종 승인.

### Source-of-truth rules

- Request record holds status, reason, suggested replacement datetime(s)
- Lesson movement happens only after **approved → applied** via trusted function

### Invariants

- Teacher: submit, reason, suggest replacements, view assigned-student requests (OD-01)
- Teacher: **no** final approve/reject, **no** cascade execution, **no** other teacher’s schedule
- Owner: final approve/reject; applied state immutable except documented correction
- Student: submit own requests (scope TBD in UI Phase)

### Allowed operations

- Teacher/Student: create `submitted` requests in scope
- Owner: review, approve, reject, trigger apply (trusted)

### Prohibited operations

- Teacher final approval or lesson record mutation via request
- Apply without `approved` status

### Related domains

lessons, schedule_slots, audit_logs

### Audit requirements

Approve, reject, apply → audit

### Relevant decisions

OD-01

---

## 11. Payments

### Purpose

입금 기록, pass renewal trigger, idempotency, financial snapshots.

### Source-of-truth rules

- Payment status: `pending`, `completed`, `cancelled`, `refunded`
- Snapshots: paid amount, date, method, status, related pass, idempotency reference (OD-09)

### Invariants

- **First valid `pending → completed`** may create/connect renewed pass (trusted transaction)
- Repeat same idempotency key → return existing result, no second pass
- Single PostgreSQL transaction for renewal (10-step flow in project-brief)
- Advance payment → **reserved** pass; activate after last deductible lesson of current pass

### Allowed operations

- Owner: register payment (implementation Phase)
- Trusted function: complete payment + renewal

### Prohibited operations

- Teacher/Student: payment create/complete
- Physical delete of payment records

### Related domains

passes, course_products, refunds, audit_logs

### Audit requirements

Payment complete, refund → audit

### Relevant decisions

OD-09, OD-10

---

## 12. Refunds

### Purpose

환불 처리. 이력 보존. MVP active-pass refund는 남은 서비스 종료 (OD-12).

### Source-of-truth rules

- `completed → refunded` preserves payment and pass records
- Used/remaining remain **derived** from lesson status — never directly edited on refund

### Invariants

**Reserved pass refund (OD-06)**:

- Cancel reserved pass → `cancelled`
- Preserve pass and payment history
- Do not activate later

**Active pass refund — MVP (OD-12)**:

- **Owner only**; refund **amount** and **reason** mandatory
- Completed and other **deductible historical lessons unchanged** and preserved
- **Future non-deducted** lessons on refunded pass → **`advance_cancelled`** in **one trusted transactional operation**
- Each affected future lesson: **original scheduled data** in audit history
- Active pass → **`cancelled`** (terminal; OD-11)
- Refund record: actual refunded amount, refund date, reason, actor
- Single trusted operation: pass change + future-lesson cancellation + refund record + SMS recalc + audit insertion
- Preserve original payment, pass, and all lesson records (no physical delete)

**MVP exclusions (OD-12)**:

- Partial refund while pass stays **active**
- Transfer remaining counts to another course, student, or pass
- Credits or stored balances

**Mistaken refund (OD-11 + OD-12)**:

- Do **not** reactivate cancelled pass
- Owner-controlled **new pass correction workflow** with audit

### Allowed operations

- Owner: initiate controlled refund workflow (implementation Phase)
- Trusted function: reserved refund path; active-pass refund coordinated update
- Teacher/Student: **none**

### Prohibited operations

- Teacher/Student: any refund processing
- Silent pass/lesson/payment deletion on refund
- Direct overwrite of used or remaining counts
- Partial active-pass refund (MVP)
- Credit, transfer, or stored balance creation (MVP)
- Cancelled pass reactivation

### Related domains

payments, passes, lessons, sms_notifications, audit_logs

### Audit requirements

All refunds mandatory audit; future-lesson scheduled data before `advance_cancelled` preserved in audit history

### Relevant decisions

OD-06, OD-11, OD-12

---

## 13. SMS notifications

### Purpose

잔여 회차 기반 알림 상태. MVP: copy text + manual sent confirmation.

### Source-of-truth rules

- States: `normal`, `scheduled`, `target`, `exhausted_unsent`, `sent`
- Derived from pass remaining count and schedule context; `sent` via Owner manual confirm (MVP)

### Invariants

- New pass resets SMS notification state for that pass context
- Lesson correction (OD-02) may recalculate SMS state — scoped, not full academy
- Prior sent history preserved (no physical delete)

### Allowed operations

- Owner: manual mark `sent`, copy message text
- System: derive `scheduled`, `target`, `exhausted_unsent`

### Prohibited operations

- Student: mark sent
- External SMS API in MVP

### Related domains

passes, lessons, lesson deduction

### Audit requirements

Manual `sent` confirmation → audit optional; state changes from owner correction → via lesson audit

### Relevant decisions

OD-02

---

## 14. Lesson notes

### Purpose

수업 메모, 상담 기록. Teacher write; Student visibility controlled.

### Source-of-truth rules

- Notes tied to lesson or student context
- Student-visible flag (implementation Phase) separates internal vs student-readable

### Invariants

- Teacher: notes for **assigned** lessons only
- Student: no edit; read only if marked student-visible

### Allowed operations

- Teacher: create/update notes on assigned lessons
- Owner: full read; moderate if needed

### Prohibited operations

- Student: write internal teacher notes
- Physical delete of notes with audit relevance — prefer append/correct with audit

### Related domains

lessons, students, audit_logs

### Audit requirements

Owner deletion or visibility change → audit

### Relevant decisions

OD-01 (Teacher scope)

---

## 15. Audit logs

### Purpose

중요 변경의 previous/new value, actor, timestamp.

### Source-of-truth rules

- Append-oriented; authoritative history of sensitive changes

### Invariants

- Owner correction (OD-02), refunds (OD-06, OD-12), pass cancel (OD-11), payment complete, role change, schedule apply → must log
- Clients do not forge audit entries

### Allowed operations

- Owner: read unrestricted audit logs
- Trusted function: insert audit rows
- Teacher/Student: **no** unrestricted read

### Prohibited operations

- Teacher/Student: read full audit log
- Physical delete or overwrite of audit rows

### Related domains

All sensitive domains

### Audit requirements

N/A (audit is the audit)

### Relevant decisions

OD-02, OD-06, OD-11, OD-12

---

## 16. Date and time handling

### Purpose

학원 업무 시간 기준 통일.

### Source-of-truth rules

- **Asia/Seoul** for business date boundaries, slot local times, “today’s lessons”, SMS timing

### Invariants

- Scheduled/actual datetimes stored with timezone clarity (implementation Phase)
- Fixed slot weekday/time is local Seoul context
- Do not use first actual lesson date for fixed placement

### Allowed operations

- Display and query in Seoul local context for operations

### Prohibited operations

- Mixing user device timezone as business authority without explicit rule

### Related domains

lessons, schedule_slots, sms_notifications

### Audit requirements

None specific

### Relevant decisions

OD-04

---

## Related documents

- [project-brief.md](./project-brief.md)
- [permissions-matrix.md](./permissions-matrix.md)
- [state-transitions.md](./state-transitions.md)
- [open-decisions.md](./open-decisions.md)

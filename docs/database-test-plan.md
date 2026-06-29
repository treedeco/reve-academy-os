# Database Test Plan — REVE ACADEMY OS

Phase **0B-2** database-level test specification. **pgTAP harness implemented** for Phase 0B-3A through 0B-3B-2B-3A (local Supabase). Remaining design cases from this document are deferred until their trusted operations exist.

Execution: `npx supabase test db` (transaction rollback per test file).

Each case: **Setup → Actor → Operation → Expected result → Expected DB state → Expected audit → Cleanup**.

---

## Test harness conventions

| Item | Convention |
|------|------------|
| Roles | Owner, Teacher, Student profiles with linked business rows |
| Timezone | Asia/Seoul for “today” tests |
| Cleanup | Transaction rollback in test harness or dedicated test schema truncate (dev only) |
| Trusted context | `SET ROLE service_role` or JWT simulation per Supabase test utils |

---

## 1. Constraint tests (CT-01 – CT-18)

| ID | Setup | Actor | Operation | Expected result | DB state | Audit | Cleanup |
|----|-------|-------|-----------|-----------------|----------|-------|---------|
| CT-01 | Student S1 exists | Owner | INSERT second student same `student_code` | ERROR unique violation | One row | None | Rollback |
| CT-02 | Teacher T1 | Owner | Duplicate `teacher_code` | ERROR | One row | — | Rollback |
| CT-03 | Course C1 | Owner | Duplicate `course_code` | ERROR | — | — | Rollback |
| CT-04 | Product P1 | Owner | Duplicate `product_code` | ERROR | — | — | Rollback |
| CT-05 | Pass exists code X | Trusted | Second pass same `pass_code` | ERROR | — | — | Rollback |
| CT-06 | Pass seq 1 for S+C | Trusted | Second pass seq 1 same pair | ERROR | — | — | Rollback |
| CT-07 | Active pass for S+C | Trusted | INSERT second active pass | ERROR partial unique | One active | — | Rollback |
| CT-08 | Reserved pass for S+C | Trusted | INSERT second reserved | ERROR partial unique | One reserved | — | Rollback |
| CT-09 | Lesson seq 2 on pass | Trusted | Duplicate seq 2 | ERROR | — | — | Rollback |
| CT-10 | Pass P for student A | Trusted | Lesson with P but student_id B | ERROR composite FK | — | — | Rollback |
| CT-11 | Payment pending | Owner | paid_amount_krw = -1 | ERROR CHECK | — | — | Rollback |
| CT-12 | Pass start 2026-01-01 | Owner | expires_on 2025-12-01 | ERROR CHECK | — | — | Rollback |
| CT-13 | Lesson | Teacher | actual_end < actual_start | ERROR CHECK | — | — | Rollback |
| CT-14 | Two pending payments | Owner | Same idempotency_key | ERROR unique | One payment | — | Rollback |
| CT-15 | Refund exists for payment | Owner | Second refund INSERT | ERROR unique payment_id | One refund | — | Rollback |
| CT-16 | Lesson L | Trusted | makeup_source = L.id | ERROR self ref | — | — | Rollback |
| CT-17 | Makeup completed for source S | Trusted | Second makeup_completed same source | ERROR partial unique | One makeup | — | Rollback |
| CT-18 | Pass status `foo` | Trusted | INSERT | ERROR CHECK | — | — | Rollback |
| CT-19 | Slot weekday 7 | Owner | INSERT | ERROR CHECK | — | — | Rollback |
| CT-20 | Slot duration 0 | Owner | INSERT | ERROR CHECK | — | — | Rollback |
| CT-21 | Active slot duplicate | Owner | Same pass/weekday/time/teacher active | ERROR partial unique | — | — | Rollback |

**Constraint subtotal: 21 cases**

---

## 2. RLS tests (RL-01 – RL-35)

### Owner

| ID | Operation | Expected |
|----|-----------|----------|
| RL-01 | SELECT all students | Allowed |
| RL-02 | SELECT all payments | Allowed |
| RL-03 | DELETE lesson | Denied (no policy) |
| RL-04 | INSERT audit_logs as client | Denied |

### Teacher

| ID | Setup | Operation | Expected |
|----|-------|-----------|----------|
| RL-05 | Teacher A, Student B unassigned | SELECT student B | Denied |
| RL-06 | Any | SELECT payments | Denied |
| RL-07 | Assigned pass | UPDATE pass snapshot column | Denied |
| RL-08 | Assigned lesson | Direct UPDATE lesson.status | Denied (use trusted) |
| RL-09 | Assigned lesson | SELECT lesson | Allowed |
| RL-10 | Other teacher's lesson | SELECT | Denied |

### Student

| ID | Setup | Operation | Expected |
|----|-------|-----------|----------|
| RL-11 | Student A | SELECT student B lessons | Denied |
| RL-12 | Own lesson | UPDATE status | Denied |
| RL-13 | Internal note on own lesson | SELECT | Denied |
| RL-14 | student_visible note | SELECT | Allowed |
| RL-15 | Own pass | SELECT | Allowed |
| RL-16 | Own payment | SELECT | Allowed |

### Anonymous

| ID | Operation | Expected |
|----|-----------|----------|
| RL-17 | SELECT students | Denied (0 rows) |
| RL-18 | SELECT courses | Denied |

### Trusted context

| ID | Operation | Expected |
|----|-----------|----------|
| RL-19 | complete_payment_and_renew_pass | Allowed coordinated effect |
| RL-20 | transition_lesson_status on assigned | Allowed |
| RL-21 | process_payment_refund | Allowed with audit |
| RL-22 | Student JWT call refund | Denied |

### Profiles / SMS / requests

| ID | Operation | Expected |
|----|-----------|----------|
| RL-23 | Student UPDATE own role | Denied |
| RL-24 | Teacher SELECT sms_notifications | Denied MVP |
| RL-25 | Student INSERT schedule_change own lesson | Allowed |
| RL-26 | Student INSERT request for other's lesson | Denied |
| RL-27 | Teacher approve request | Denied |
| RL-28 | Owner approve request | Allowed |
| RL-29 | INSERT lesson_schedule_changes as teacher | Denied |
| RL-30 | Owner SELECT audit_logs | Allowed |
| RL-31 | Teacher SELECT audit_logs | Denied |

### Additional matrix coverage

| ID | Operation | Expected |
|----|-----------|----------|
| RL-32 | Teacher SELECT own profile | Allowed |
| RL-33 | Student SELECT teacher name on own lesson | Allowed (limited) |
| RL-34 | Student SELECT teacher phone | Denied |
| RL-35 | Owner UPDATE payment to completed without trusted | Denied or no-op |

**RLS subtotal: 35 cases**

---

## 3. Transaction tests (TX-01 – TX-14)

| ID | Scenario | Expected result | Audit |
|----|----------|-----------------|-------|
| TX-01 | Payment renewal success | payment completed, pass created, lessons, SMS, linked | correlation_id present |
| TX-02 | Renewal fails mid-lesson insert | Full rollback; payment pending | No partial audit |
| TX-03 | Duplicate payment completion same key | Idempotent return; one pass | Single renewal audit |
| TX-04 | Concurrent duplicate renewal | One succeeds; other idempotent or unique error | One pass |
| TX-05 | Reserved pass activation after last deductible | reserved→active | activation audit |
| TX-06 | Lesson completion triggers activation | Same as TX-05 in one txn | bundled |
| TX-07 | Owner correct completed→postponed | Usage decreases; SMS recalc | correction audit |
| TX-08 | Cascade reschedule mid-failure | All lessons unchanged | no partial events |
| TX-09 | Active pass refund success | refund row, pass cancelled, futures advance_cancelled | correlated |
| TX-10 | Refund failure before insert | No refund row | none |
| TX-11 | Duplicate refund attempt | Rejected | one refund |
| TX-12 | Lesson status change SMS recalc | SMS status updated scoped | optional |
| TX-13 | Multi-table audit correlation | Same correlation_id across rows | verify count ≥2 |
| TX-14 | apply_schedule_change approved | lesson time changed, event row, request applied | yes |

**Transaction subtotal: 14 cases**

---

## 4. Race-condition tests (RC-01 – RC-06)

| ID | Scenario | Expected |
|----|----------|----------|
| RC-01 | Two concurrent pass-renewal for same payment | One pass; other idempotent |
| RC-02 | Two concurrent renewals different payments same student | Distinct sequence numbers |
| RC-03 | Two concurrent lesson status transitions same lesson | One wins; stale rejected |
| RC-04 | Stale optimistic updated_at | Error; no overwrite |
| RC-05 | Simultaneous refund and lesson completion | Serializable outcome; consistent pass state |
| RC-06 | Concurrent reserved-pass activation | At most one active |

**Race subtotal: 6 cases**

---

## 5. Historical integrity tests (HI-01 – HI-08)

| ID | Scenario | Expected |
|----|----------|----------|
| HI-01 | Product price change after pass create | Pass snapshot unchanged |
| HI-02 | Teacher deactivated | Lessons still reference teacher |
| HI-03 | Student operational inactive | Pass history readable |
| HI-04 | New pass created | Old SMS rows preserved |
| HI-05 | Refund processed | Payment + lessons remain |
| HI-06 | Cancelled pass | status cannot → active |
| HI-07 | audit_logs INSERT only | UPDATE/DELETE fail |
| HI-08 | lesson_schedule_changes | No UPDATE policy |

**Historical subtotal: 8 cases**

---

## 6. Derived-value tests (DV-01 – DV-12)

| ID | Setup | Expected derived |
|----|-------|------------------|
| DV-01 | registered 4, 0 deductible | used=0, remaining=4 |
| DV-02 | registered 4, 4 deductible | used=4, remaining=0 |
| DV-03 | registered 8, mixed statuses | used/remaining per formula |
| DV-04 | completed adds deduction | used +1 |
| DV-05 | advance_cancelled | no deduction |
| DV-06 | remaining never negative | remaining >= 0 |
| DV-07 | No is_deducted column | deduction only from status |
| DV-08 | Next lesson | earliest scheduled future lesson |
| DV-09 | Today lessons Seoul midnight boundary | Correct inclusion |
| DV-10 | One lesson remaining | SMS → target state |
| DV-11 | All used unsent | exhausted_unsent |
| DV-12 | Owner correction recalc | used/remaining/SMS consistent |

**Derived subtotal: 12 cases**

---

## 7. Provisional policy tests (PV-01 – PV-12)

> **Subject to revision** with corresponding OD when Owner confirms or changes provisional defaults.

| ID | OD | Setup | Actor | Operation | Expected | Revise when |
|----|-----|-------|-------|-----------|----------|-------------|
| PV-01 | OD-14 | Reserved pass on renewal | Trusted | complete_payment | Pass created; **no** lesson rows until activation | Pass-renewal UI review |
| PV-02 | OD-14 | Prior pass completes; reserved exists | Trusted | activate_reserved | First lesson = first valid slot after completion | Pass-renewal UI review |
| PV-03 | OD-15 | Active pass with 2 slots | Trusted | renew | New pass has **copied** slot rows; independent IDs | Schedule-slot UI review |
| PV-04 | OD-15 | Edit old pass slot after renewal | Owner | update old slot | New pass slots **unchanged** | Schedule-slot UI review |
| PV-05 | OD-16 | 2 slots same week | Trusted | generate lessons | sequence_number follows chronological + slot_order | Weekly schedule UI review |
| PV-06 | OD-17 | Overlapping scheduled_at | Trusted | apply schedule change | **Abort**; collision list returned | Schedule UI review |
| PV-07 | OD-18 | Pending payment | Owner | create payment | payment_method **NULL** allowed | Payment UI review |
| PV-08 | OD-18 | Complete with `other` no note | Owner | complete payment | **Reject** | Payment UI review |
| PV-09 | OD-18 | Complete with `card` | Owner | complete payment | Success | Payment UI review |
| PV-10 | OD-19 | Deactivate student | Owner | set inactive | No DELETE; history preserved | Account admin UI review |
| PV-11 | OD-20 | Student own SMS | Student | SELECT | message_body only on current pass; no status/actor | Student page UI review |
| PV-12 | OD-21 | Last active owner | Owner | demote self | **Reject** | Owner-management UI review |

**Provisional subtotal: 12 cases**

---

## Summary

| Category | Case IDs | Count |
|----------|----------|-------|
| Constraints | CT-01 – CT-21 | 21 |
| RLS | RL-01 – RL-35 | 35 |
| Transactions | TX-01 – TX-14 | 14 |
| Race conditions | RC-01 – RC-06 | 6 |
| Historical integrity | HI-01 – HI-08 | 8 |
| Derived values | DV-01 – DV-12 | 12 |
| Provisional (OD-14–21) | PV-01 – PV-12 | 12 |
| **Total** | | **108** |

---

## 8. Phase 0B-3B-2B-1 implemented coverage

| Area | pgTAP file | Tests | Status |
|------|------------|-------|--------|
| Core schema / constraints | `phase_0b3a_core_schema.test.sql` | 60 | **Pass** |
| Identity helpers + RLS | `phase_0b3b1_identity_rls.test.sql` | 111 | **Pass** |
| Safe read RPCs | `phase_0b3b2a_safe_read_projections.test.sql` | 47 | **Pass** |
| Lesson transitions + correction | `phase_0b3b2b1_lesson_transitions.test.sql` | 63 | **Pass** |
| Payment renewal + reserved activation | `phase_0b3b2b2_payment_renewal.test.sql` | 48 | **Pass** |
| Profile/people master data | `phase_0b3b2b3a_profile_people_master_data.test.sql` | 55 | **Pass** |
| Course/product master data | `phase_0b3b2b3b_course_product_management.test.sql` | 69 | **Pass** |
| Initial enrollment | `phase_0b3b2b3c_initial_enrollment.test.sql` | 85 | **Pass** |
| **Combined** | | **550** | **Pass** |

Lesson-transition tests cover: RPC existence/security, ordinary matrix transitions, owner correction, derived usage counts, optimistic concurrency (`REVE_STALE_STATE`), pass completion with automatic reserved activation (0B-3B-2B-2), SMS state sync, audit correlation, unauthorized roles.

## 9. Phase 0B-3B-2B-2 implemented coverage

Payment-renewal tests cover: RPC existence/security, payment completion, pass sequence and public code, active vs reserved creation, 4/8 lesson products, schedule snapshot copy, lesson scheduling (Asia/Seoul), reserved activation (manual and automatic), idempotency, optimistic concurrency, SMS initialization, audit correlation, scope isolation.

## 10. Phase 0B-3B-2B-2A implemented coverage

Reserved lesson-shell tests cover: nullable `scheduled_at`, deferred pass/lesson invariants, payment creates exact shell count, activation preserves lesson IDs, null-dated shells excluded from calendar projections, unscheduled shell transition denial.

## 11. Phase 0B-3B-2B-3A implemented coverage

Profile/people tests cover: bootstrap service_role security, owner provisioning, role/link validation, last-owner protection, student/teacher CRUD, deactivation without DELETE, audit correlation, direct table write denial.

## 12. Phase 0B-3B-2B-3B implemented coverage

Course/product tests cover: six owner RPCs security, course CRUD and lifecycle dependency checks, product CRUD (4/8 lesson counts), parent-child active consistency, pending-payment guards, pass/payment snapshot preservation, renewal integration (inactive course/product rejection, idempotent replay), lint regression for `reve_owner_create_student`.

## 13. Phase 0B-3B-2B-3C implemented coverage

Initial enrollment tests cover: `reve_owner_create_initial_enrollment` security, first pass sequence 001, 4/8 lesson generation, schedule JSON validation, Seoul start-boundary, teacher collision atomic rollback, idempotency replay/conflict, pass-history rejection (`REVE_NOT_INITIAL_ENROLLMENT`), payment-pass-slot-lesson-SMS atomicity, regression of prior phases.

**Still deferred**: general schedule editing, returning-student re-enrollment, refunds, schedule-change approval/cascade, external SMS, UI.

## Related documents

- [postgresql-physical-design.md](./postgresql-physical-design.md)
- [rls-policy-design.md](./rls-policy-design.md)
- [trusted-operation-contracts.md](./trusted-operation-contracts.md)
- [database-migration-plan.md](./database-migration-plan.md)

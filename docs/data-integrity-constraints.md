# Data Integrity Constraints — REVE ACADEMY OS

Phase **0B-1** future PostgreSQL integrity requirements. **No executable SQL.** Each entry names a constraint concept for migration Phase 0B-2+.

Legend — **Enforcement**:

| Code | Meaning |
|------|---------|
| **PG** | PostgreSQL constraint (PK, FK, UNIQUE, CHECK, partial unique index) |
| **TF** | Trusted function / application transaction required |
| **TR** | Trigger may be required later |
| **RLS** | RLS policy (Phase 0B-2) |

---

## 1. `students_student_code_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `students` |
| Purpose | Immutable business student identifier |
| Blocks | Two rows with `student_code = 'S006'` |
| Enforcement | **PG** |

---

## 2. `teachers_teacher_code_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `teachers` |
| Purpose | Immutable teacher business code |
| Blocks | Duplicate teacher codes |
| Enforcement | **PG** |

---

## 3. `courses_course_code_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `courses` |
| Purpose | Stable course identifier |
| Blocks | Duplicate course codes |
| Enforcement | **PG** |

---

## 4. `course_products_product_code_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `course_products` |
| Purpose | Product SKU uniqueness |
| Blocks | Duplicate product codes |
| Enforcement | **PG** |

---

## 5. `passes_pass_code_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `passes` |
| Purpose | Global human-readable pass id (OD) |
| Blocks | Two passes `V-S006-001` |
| Enforcement | **PG** |

---

## 6. `passes_student_course_sequence_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `passes` (`student_id`, `course_id`, `sequence_number`) |
| Purpose | Sequence integrity within student+course |
| Blocks | Two passes both sequence 1 for same student+course |
| Enforcement | **PG** |

---

## 7. `passes_one_active_per_student_course`

| Field | Value |
|-------|-------|
| Type | partial unique |
| Table | `passes` |
| Purpose | OD-07, OD-10 — one active pass |
| Blocks | Two `status = 'active'` for same (student_id, course_id) |
| Enforcement | **PG** partial unique index WHERE status = 'active' |

---

## 8. `passes_one_reserved_per_student_course`

| Field | Value |
|-------|-------|
| Type | partial unique |
| Table | `passes` |
| Purpose | OD-10 — zero or one reserved |
| Blocks | Two `status = 'reserved'` for same (student_id, course_id) |
| Enforcement | **PG** partial unique index WHERE status = 'reserved' |

---

## 9. `lessons_pass_sequence_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `lessons` (`pass_id`, `sequence_number`) |
| Purpose | Lesson order within pass |
| Blocks | Duplicate sequence 3 on same pass |
| Enforcement | **PG** |

---

## 10. `lessons_student_course_matches_pass`

| Field | Value |
|-------|-------|
| Type | check / composite FK |
| Tables | `lessons`, `passes` |
| Purpose | Denormalized student_id/course_id consistency |
| Blocks | Lesson pointing to pass of different student or course |
| Enforcement | **TR** or composite FK `(pass_id, student_id, course_id)` referencing passes; lesson creation **TF** only |

---

## 11. `passes_registered_lesson_count_positive`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `passes` |
| Purpose | Valid contract size |
| Blocks | `registered_lesson_count_snapshot <= 0` |
| Enforcement | **PG** |

---

## 12. `course_products_lesson_count_positive`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `course_products` |
| Purpose | Product definition validity |
| Blocks | default_lesson_count = 0 |
| Enforcement | **PG** |

---

## 13. `course_products_weekly_frequency_positive`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `course_products` |
| Purpose | At least one slot per week concept |
| Blocks | weekly_frequency = 0 |
| Enforcement | **PG** |

---

## 14. `monetary_krw_non_negative`

| Field | Value |
|-------|-------|
| Type | check |
| Tables | `course_products`, `passes`, `payments`, `payment_refunds` |
| Purpose | Integer KRW — no negative amounts where disallowed |
| Blocks | Negative tuition or paid amount |
| Enforcement | **PG** |

---

## 15. `passes_expires_on_after_start`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `passes` |
| Purpose | OD-03 optional expiration sanity |
| Blocks | expires_on < start_date when both set |
| Enforcement | **PG** |

---

## 16. `lessons_actual_end_after_start`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `lessons` |
| Purpose | Valid actual time range |
| Blocks | actual_end_at < actual_start_at |
| Enforcement | **PG** |

---

## 17. `schedule_slots_duration_positive`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `schedule_slots` |
| Purpose | Valid slot length |
| Blocks | duration_minutes <= 0 |
| Enforcement | **PG** |

---

## 18. `schedule_slots_weekday_range`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `schedule_slots` |
| Purpose | Valid weekday |
| Blocks | weekday not in 0..6 |
| Enforcement | **PG** |

---

## 19. `schedule_slots_no_duplicate_active`

| Field | Value |
|-------|-------|
| Type | partial unique |
| Table | `schedule_slots` |
| Purpose | OD-04 — no duplicate active slot definition |
| Blocks | Same pass + weekday + local_start_time + teacher active twice |
| Enforcement | **PG** partial unique WHERE is_active = true |

---

## 20. `payments_idempotency_key_unique`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `payments` |
| Purpose | Idempotent renewal |
| Blocks | Second payment row with same idempotency_key creating another pass |
| Enforcement | **PG** + **TF** (return existing on retry) |

---

## 21. `payments_renewed_pass_set_once`

| Field | Value |
|-------|-------|
| Type | immutable-field / TF |
| Table | `payments` |
| Purpose | One renewed pass link per completed payment |
| Blocks | Changing renewed_pass_id after set to different pass |
| Enforcement | **TF** + **TR** (immutable after completion) |

---

## 22. `payment_refunds_payment_id_unique_mvp`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `payment_refunds` (`payment_id`) |
| Purpose | OD-13 — zero or one completed refund per payment in MVP |
| Blocks | Two refund rows referencing the same `payment_id` |
| Enforcement | **PG** UNIQUE on `payment_id`; insert only via **TF** coordinated refund |

Failed refund transaction creates **no row**. Refund rows are **immutable** (no UPDATE/DELETE).

---

## 23. `payment_refunds_amount_valid`

| Field | Value |
|-------|-------|
| Type | check + TF |
| Table | `payment_refunds` |
| Purpose | Refund cannot exceed paid amount (full refund MVP path) |
| Blocks | refunded_amount_krw > payment.paid_amount_krw |
| Enforcement | **PG** check; **TF** on insert |

---

## 24. `payment_refunds_history_preserved`

| Field | Value |
|-------|-------|
| Type | append-only rule |
| Table | `payment_refunds` |
| Purpose | OD-06, OD-12 audit trail |
| Blocks | UPDATE/DELETE on refund rows |
| Enforcement | **RLS** + **TF** (insert only) |

---

## 25. `lessons_makeup_not_self`

| Field | Value |
|-------|-------|
| Type | check |
| Table | `lessons` |
| Purpose | Makeup FK sanity |
| Blocks | makeup_source_lesson_id = id |
| Enforcement | **PG** |

---

## 26. `lessons_one_makeup_completed_per_source`

| Field | Value |
|-------|-------|
| Type | partial unique |
| Table | `lessons` |
| Purpose | OD-05 duplicate deduction prevention |
| Blocks | Two `makeup_completed` lessons referencing same source |
| Enforcement | **PG** partial unique on (makeup_source_lesson_id) WHERE status = 'makeup_completed' |

---

## 27. `schedule_requests_applied_requires_approved`

| Field | Value |
|-------|-------|
| Type | trusted-operation rule |
| Table | `schedule_change_requests` |
| Purpose | OD-01 workflow |
| Blocks | status → applied without prior approved |
| Enforcement | **TF** only |

---

## 28. `cascade_excludes_completed_lessons`

| Field | Value |
|-------|-------|
| Type | trusted-operation rule |
| Tables | `lessons`, `lesson_schedule_changes` |
| Purpose | Phase 0A schedule rules |
| Blocks | cascade origin event on completed lesson |
| Enforcement | **TF** |

---

## 29. `passes_cancelled_terminal`

| Field | Value |
|-------|-------|
| Type | check + TF |
| Table | `passes` |
| Purpose | OD-11 |
| Blocks | status transition cancelled → active or reserved |
| Enforcement | **TF** + **TR** or state machine in trusted code |

---

## 30. `no_physical_delete_historical`

| Field | Value |
|-------|-------|
| Type | append-only / soft lifecycle |
| Tables | passes, lessons, payments, payment_refunds, sms_notifications, schedule_change_requests, lesson_schedule_changes, audit_logs |
| Purpose | History preservation |
| Blocks | DELETE via normal roles |
| Enforcement | **RLS** (no DELETE policy) + **TF** |

---

## 31. `audit_logs_append_only`

| Field | Value |
|-------|-------|
| Type | append-only |
| Table | `audit_logs` |
| Purpose | Tamper-evident audit |
| Blocks | UPDATE/DELETE on audit_logs |
| Enforcement | **RLS** + revoke UPDATE/DELETE |

---

## 32. `no_editable_used_remaining_columns`

| Field | Value |
|-------|-------|
| Type | schema design rule |
| Tables | passes (and globally) |
| Purpose | Single deduction source |
| Blocks | Client-writable used_count / remaining_count columns |
| Enforcement | **Schema** — columns absent; **RLS** if cache added later |

---

## 33. `no_editable_deduction_boolean`

| Field | Value |
|-------|-------|
| Type | schema design rule |
| Table | lessons |
| Purpose | Deduction from status only |
| Blocks | Independent `is_deducted` client-editable column |
| Enforcement | **Schema** — column absent |

---

## 34. `pass_snapshots_immutable_after_create`

| Field | Value |
|-------|-------|
| Type | immutable-field rule |
| Table | `passes` |
| Purpose | OD-09 financial snapshots |
| Blocks | Updating tuition_amount_krw_snapshot after creation |
| Enforcement | **TR** or **TF** (reject updates) |

---

## 35. `pass_sequence_generation_race_safe`

| Field | Value |
|-------|-------|
| Type | trusted-operation rule |
| Table | `passes` |
| Purpose | Concurrent renewal safety |
| Blocks | Two transactions assigning same sequence_number |
| Enforcement | **TF** with row lock on (student_id, course_id) or serializable transaction |

---

## 36. `payment_renewal_idempotent_transactional`

| Field | Value |
|-------|-------|
| Type | trusted-operation rule |
| Tables | payments, passes, lessons, schedule_slots, sms_notifications, audit_logs |
| Purpose | Phase 0A payment rules |
| Blocks | Partial renewal (payment completed without pass); duplicate pass on retry |
| Enforcement | **TF** single transaction + idempotency_key |

---

## 37. `active_pass_refund_coordinated`

| Field | Value |
|-------|-------|
| Type | trusted-operation rule |
| Tables | payments, payment_refunds, passes, lessons, sms_notifications, audit_logs |
| Purpose | OD-12 |
| Blocks | Refund without pass cancelled; future lessons not advance_cancelled; missing audit |
| Enforcement | **TF** single transaction |

---

## Status and enum checks (summary)

Apply **PG** `CHECK` on text status columns aligned with [state-transitions.md](./state-transitions.md):

- `passes.status`
- `lessons.status`
- `payments.status`
- `sms_notifications.status`
- `schedule_change_requests.status`
- `profiles.role`

---

## 38. `passes_composite_parent_key`

| Field | Value |
|-------|-------|
| Type | unique |
| Table | `passes` (`id`, `student_id`, `course_id`) |
| Purpose | Composite FK parent for lesson denormalized consistency |
| Blocks | Lesson referencing pass with mismatched student/course |
| Enforcement | **PG** UNIQUE + composite FK from `lessons` |

---

## 39. `profiles_id_equals_auth_user`

| Field | Value |
|-------|-------|
| Type | FK |
| Table | `profiles` (`id` → `auth.users(id)`) |
| Purpose | Single identity column; no separate auth_user_id |
| Blocks | Profile without auth user; duplicate auth mapping |
| Enforcement | **PG** PK/FK ON DELETE RESTRICT |

---

## 40. `payments_payment_method_provisional`

| Field | Value |
|-------|-------|
| Type | check + TF |
| Table | `payments` |
| Purpose | OD-18 provisional — NULL while pending; enum when set; required on completed |
| Blocks | Invalid method value; completed without method |
| Enforcement | **PG** CHECK (when not null); **TF** on completion |
| Status | **Provisional** — review before executable migration |

---

## Phase 0B-3B-2B-2 runtime protections (payment renewal)

| Protection | Mechanism |
|------------|-----------|
| One active pass per student/course | Partial unique index + TF validation before insert |
| At most one reserved pass | Partial unique index + `REVE_RESERVED_EXISTS` |
| Pass sequence and code uniqueness | `next_pass_sequence` under advisory lock + unique indexes |
| One payment → one pass | `payments.renewed_pass_id` partial unique + idempotency key |
| Exact registered lesson count | Product snapshot + lesson row count validation |
| Idempotent payment retry | `idempotency_key` unique partial on completed payments |
| No duplicate activation | Activation checks status; idempotent replay on success |
| No duplicate lesson ordinals | Unique `(pass_id, sequence_number)` + activation reuses shells when applicable |

Enforced in payment completion, activation, and deferred constraint triggers on `lessons` / `passes`.

| Invariant | Rule |
|-----------|------|
| Reserved shell row | `scheduled_at` null; status `scheduled`; no actual timestamps |
| Active pass | Exactly registered count; all lessons have non-null `scheduled_at` |
| Reserved pass | Exactly registered count; shells may have null `scheduled_at` |
| Activation | Updates existing lesson IDs; no second INSERT set |

---

## Related documents

- [data-model.md](./data-model.md)
- [schema-dictionary.md](./schema-dictionary.md)
- [erd.md](./erd.md)
- [state-transitions.md](./state-transitions.md)
- [postgresql-physical-design.md](./postgresql-physical-design.md) (Phase 0B-2)

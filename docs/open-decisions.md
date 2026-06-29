# Open Decisions — REVE ACADEMY OS

이 문서는 비즈니스 결정 이력과 **아직 확정되지 않은** 항목을 추적합니다.

## Status overview

| 범주 | 설명 |
|------|------|
| **Confirmed (2026-06-26)** | OD-01 ~ OD-13 — 아래 **Confirmed Decisions** 섹션. **권위 있는 요구사항**으로 취급 |
| **Provisional (2026-06-26)** | OD-14 ~ OD-21 — **임시 기본값**; executable migration 및 UI 검증 전 Owner 재검토 필수. **영구 확정 요구사항 아님** |

**Confirmed 결정은 `docs/project-brief.md`, `docs/domain-rules.md`, `docs/permissions-matrix.md`, `docs/state-transitions.md`에 반영되어야 합니다.**

**Provisional 결정 (OD-14 ~ OD-21)**:

- Phase 0B-2 아키텍처 계획용 **안전한 기본값**이며, 최종 Owner 승인 운영 정책이 **아님**.
- **Phase 0B-3** executable migration 생성 **전** 반드시 재검토.
- 관련 **UI phase**에서 사용자-facing 동작 재검토.
- production migration **전** schema-affecting 변경은 physical design, trusted-operation contracts, database tests, migrations에 반영 후 적용.
- Status: `Provisional — review before executable database implementation and again during UI workflow verification`

---

## Confirmed Decisions (2026-06-26)

다음 13개 결정은 Owner에 의해 **2026-06-26** 확정되었으며, 더 이상 open이 아닙니다.

---

### OD-01 — Teacher schedule-change authority

| Field | Content |
|-------|---------|
| **Original question** | Teacher가 schedule change request를 승인할 수 있는가, 제출만 가능한가? |
| **Confirmed decision** | Teacher는 **제출·사유 기록·대체 일시 제안·배정 학생 관련 요청 조회**만 가능. **최종 승인·거절·연쇄 수업 이동 실행·타 강사 일정 변경**은 **Owner만** 가능 |
| **Risk context** | Teacher 승인 허용 시 unauthorized cascade reschedule, 타 학생 일정 충돌 |
| **Affected** | `schedule_change_requests`, RLS, Teacher/Owner UI |

---

### OD-02 — Correcting completed lessons

| Field | Content |
|-------|---------|
| **Original question** | deductible/completed 수업을 non-deductible 상태로 되돌릴 수 있는가? |
| **Confirmed decision** | **Owner만** 가능. **수정 사유 필수**. `audit_logs`에 previous/new value 기록. lesson, pass 계산, next lesson, SMS, dashboard counter를 **하나의 일관된 operation**으로 갱신. Teacher·Student 불가 |
| **Risk context** | 무제한 revert 시 used count 조작, SMS 불일치 |
| **Affected** | `lessons`, `passes`, `audit_logs`, SMS, dashboard |

---

### OD-03 — Pass expiration date

| Field | Content |
|-------|---------|
| **Original question** | 모든 pass에 만료일이 필수인가? |
| **Confirmed decision** | **Optional**. 데이터 모델은 optional expiration date 지원. MVP는 모든 pass 자동 만료하지 않음. 만료 정책이 있는 product는 나중에 정의 가능. 만료일 없음 ≠ invalid pass |
| **Risk context** | 필수 시 입력 부담; optional 시 만료 미관리 pass 장기 active |
| **Affected** | `passes`, `course_products`, `expired` transition |

---

### OD-04 — Multiple fixed schedule slots

| Field | Content |
|-------|---------|
| **Original question** | 하나의 pass가 여러 fixed schedule slot을 가질 수 있는가? |
| **Confirmed decision** | **Yes**. 주 1회 보통 1 slot, 주 2회 보통 2 slot. 미래 product는 더 많은 slot 지원. 각 slot: weekday, local start time, duration, teacher, active state. **actual lesson date에서 slot 추론 금지** |
| **Risk context** | N slots 시 lesson generation·cascade 복잡도 |
| **Affected** | `schedule_slots`, lesson generation, weekly schedule UI |

---

### OD-05 — Makeup lesson relationship

| Field | Content |
|-------|---------|
| **Original question** | `makeup_completed`를 원본 수업과 어떻게 연결하는가? |
| **Confirmed decision** | makeup lesson은 **원인 lesson에 명시적 link** 필수. 원본 lesson 보존. makeup은 별도 lesson record. relationship queryable. **duplicate deduction 방지**. 원본 물리 대체·삭제 금지 |
| **Risk context** | FK 없으면 보강 추적 불가 |
| **Affected** | `lessons`, state-transitions, deduction rules |

---

### OD-06 — Refund effect

| Field | Content |
|-------|---------|
| **Original question** | 환불 시 active/reserved pass를 어떻게 처리하는가? |
| **Confirmed decision** | **Reserved pass refund**: reserved pass `cancelled`, pass·payment 이력 보존, 이후 activate 금지. **Active pass refund**: OD-12 controlled workflow — Owner only, mandatory amount/reason, future non-deducted lessons → `advance_cancelled`, pass → `cancelled`, trusted transactional operation, audit 필수. lesson/pass 이력 silent destroy 금지 |
| **Risk context** | partial refund, mid-pass refund 시 정책 미정이면 불일치 |
| **Affected** | `payments`, `passes`, refund workflow, `audit_logs` |

---

### OD-07 — Multiple simultaneous courses

| Field | Content |
|-------|---------|
| **Original question** | 한 학생이 동시에 여러 course 수강 가능한가? |
| **Confirmed decision** | **Yes**. (student, course)당 active pass **1개**, reserved pass **0 또는 1개**. 다른 course의 active pass와 충돌하지 않음 |
| **Risk context** | UI·dashboard aggregation 복잡 |
| **Affected** | `passes` uniqueness, student detail, dashboard |

---

### OD-08 — Tuition source (`course_products`)

| Field | Content |
|-------|---------|
| **Original question** | 수강료 기준 금액은 어디에 저장하는가? |
| **Confirmed decision** | **`course_products`** 테이블(계획) 도입. `courses` = 과목/커리큘럼. `course_products` = 상품(package): product name, course, default lesson count, weekly frequency, default tuition, optional expiration policy, active/inactive. **Phase 0A에서는 문서화만; table/SQL 미생성** |
| **Risk context** | course와 commercial package 혼동 방지 |
| **Affected** | `courses`, `course_products`, `passes`, payments |

---

### OD-09 — Tuition snapshots

| Field | Content |
|-------|---------|
| **Original question** | pass/payment 생성 시 금액 snapshot 저장하는가? |
| **Confirmed decision** | **Yes**. Pass snapshot: product reference, product name, registered lesson count, weekly frequency, tuition amount, (future) discount/adjustment. Payment snapshot: paid amount, payment date, method, status, related pass, idempotency reference. **Product 가격 변경이 historical pass/payment amount 변경하지 않음** |
| **Risk context** | No snapshot → historical revenue 부정확 |
| **Affected** | `passes`, `payments`, dashboard, audit |

---

### OD-10 — Reserved pass limit

| Field | Content |
|-------|---------|
| **Original question** | reserved pass를 exactly one vs at most one? |
| **Confirmed decision** | **Zero or one** reserved per (student, course). reserved는 **필수 아님**. 동일 (student, course)에 reserved **2개 이상 금지** |
| **Risk context** | 2+ reserved 시 activation 순서 충돌 |
| **Affected** | `passes` constraints, payment renewal |

---

### OD-11 — Cancelled pass reactivation

| Field | Content |
|-------|---------|
| **Original question** | `cancelled` pass를 다시 active로 전환할 수 있는가? |
| **Confirmed decision** | **No**. `cancelled`는 terminal. 오취소 시: cancelled pass 보존, Owner-controlled correction workflow로 **신규 pass** 생성, correction reason/source link, `audit_logs` 기록 |
| **Risk context** | reactivation 시 pass/lesson state 복구 복잡 |
| **Affected** | pass state machine, Owner admin tools, `audit_logs` |

---

## Decision Log

| ID | Topic | Status | Confirmed Date |
|----|-------|--------|----------------|
| OD-01 | Teacher schedule authority | **Confirmed** | 2026-06-26 |
| OD-02 | Completed lesson correction | **Confirmed** | 2026-06-26 |
| OD-03 | Pass expiration optional | **Confirmed** | 2026-06-26 |
| OD-04 | Multiple schedule slots | **Confirmed** | 2026-06-26 |
| OD-05 | Makeup lesson linkage | **Confirmed** | 2026-06-26 |
| OD-06 | Refund boundaries | **Confirmed** | 2026-06-26 |
| OD-07 | Multi-course per student | **Confirmed** | 2026-06-26 |
| OD-08 | `course_products` concept | **Confirmed** | 2026-06-26 |
| OD-09 | Pass/payment snapshots | **Confirmed** | 2026-06-26 |
| OD-10 | Zero or one reserved pass | **Confirmed** | 2026-06-26 |
| OD-11 | No cancelled reactivation | **Confirmed** | 2026-06-26 |
| OD-12 | Active-pass refund disposition | **Confirmed** | 2026-06-26 |
| OD-13 | Refund-record cardinality | **Confirmed** | 2026-06-26 |

---

### OD-12 — Active-pass refund disposition

| Field | Content |
|-------|---------|
| **Original question** | Active pass refund 시 remaining lessons 및 pass 후속 처리는? |
| **Confirmed decision** | MVP active-pass refund = **남은 서비스 종료**, 모든 이력 **보존**. **Owner only**. refund amount·reason **필수**. completed/deductible historical lessons **변경 없음**. refunded active pass의 **future non-deducted** lessons → **`advance_cancelled`** (trusted single transaction). 각 affected future lesson의 **original scheduled data** audit history 보존. active pass → **`cancelled`** (terminal). used/remaining **수동 편집 금지** — lesson status + registered count snapshot에서 derived. original payment, pass, lesson records 보존. refund record: refunded amount, date, reason, actor. pass change + future-lesson cancel + refund record + SMS recalc + audit → **trusted operation** 일관 처리 |
| **MVP exclusions** | Partial refund while pass stays active; remaining count transfer to other course/student/pass; credits or stored balances |
| **Mistaken refund correction** | cancelled pass **reactivate 금지**; Owner-controlled **new pass correction workflow** (OD-11) |
| **Risk context** | partial refund·credit·transfer 허용 시 financial/audit 복잡도 급증 |
| **Affected** | `payments`, `passes`, `lessons`, `sms_notifications`, `audit_logs`, trusted refund function |

---

### OD-13 — Refund-record cardinality per payment

| Field | Content |
|-------|---------|
| **Original question** | MVP에서 동일 payment에 refund 기록을 몇 건 허용할지 |
| **Confirmed decision** | MVP: payment당 **0 또는 1** completed refund record. 동일 payment에 **2건 이상 금지**. Partial refund **MVP 제외**. `payment_refunds` row existence = **성공적으로 완료된 refund**; 실패 시 trusted transaction **rollback**, refund row **미생성**. `payment_refunds.payment_id` **MVP unique**. Refund row **immutable**; 물리 삭제·silent edit **금지**. Mistaken refund → Owner correction workflow + audit; **원본 refund record 보존**. Multiple/partial refund → **future explicitly approved model extension** |
| **Risk context** | Multi-row 허용 시 partial refund·audit 복잡; single-row limit 시 correction workflow 필요 |
| **Affected** | `payment_refunds`, `payments`, trusted refund function, integrity constraints |

---

## Provisional Decisions (2026-06-26)

**Status for OD-14 ~ OD-21**: `Provisional — review before executable database implementation and again during UI workflow verification`

These are **safe defaults** selected to allow continued development. They are **not** final owner-approved operating policies.

**Review points** (all OD-14 ~ OD-21):

1. Before Phase 0B-3 creates executable migrations
2. During the related UI phase (see each OD)
3. Before production data migration

Any change must update [postgresql-physical-design.md](./postgresql-physical-design.md), [trusted-operation-contracts.md](./trusted-operation-contracts.md), [database-test-plan.md](./database-test-plan.md), and [database-migration-plan.md](./database-migration-plan.md) before production use.

---

### OD-14 — Reserved-pass start date calculation

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional default** | A **reserved** pass does **not** receive final lesson dates until activation. When the current pass finishes, the **first valid configured schedule slot after completion** becomes the new pass’s first lesson. |
| **UI review** | Pass-renewal UI design |
| **Affected** | `passes.start_date`, `complete_payment_and_renew_pass`, `activate_reserved_pass`, lesson generation |

**Phase 0B-3B-2B-2A implementation note (2026-06-29)**: Payment creates all lesson shells; activation finalizes `scheduled_at` on existing rows. **Status remains Provisional**.

---

### OD-15 — Schedule slot copy on renewal

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional default** | Active schedule slots from the **current pass** are **copied** into the new pass as **independent snapshot rows**. Owner may edit before activation. Later changes to the previous pass’s slots do **not** change the new pass. |
| **UI review** | Pass-renewal / schedule-slot editor UI |
| **Affected** | `schedule_slots`, `complete_payment_and_renew_pass`, `replace_pass_schedule_slots` |

**Phase 0B-3B-2B-2 implementation note (2026-06-29)**: Snapshot copy implemented in `reve_private.copy_schedule_slots_from_pass`. **Status remains Provisional**.

**Phase 0B-3B-2B-3D-1 implementation note**: Owner may replace active/reserved pass timetable; old slots deactivated (not deleted); lessons unchanged. Requires owner UI validation before confirmation. **Status remains Provisional**.

---

### OD-16 — Lesson generation order (multiple weekly slots)

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional default** | Generate lesson occurrences in **chronological order**. When timestamps are equal, use `slot_order`. Assign `sequence_number` from the sorted result. |
| **UI review** | Weekly schedule / lesson list UI |
| **Affected** | `reve_generate_lessons_from_schedule_slots`, `lessons.sequence_number` |

**Phase 0B-3B-2B-2 implementation note (2026-06-29)**: Chronological merge with `slot_order` tie-break implemented in `reve_private.generate_pass_lessons`. **Status remains Provisional**.

---

### OD-17 — Generated lesson collision handling

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional default** | Do **not** automatically move a lesson to an arbitrary alternative time. **Stop** the operation and return a **collision list**. Owner changes the schedule and retries. |
| **UI review** | Schedule change / collision presentation UI |
| **Affected** | `apply_schedule_change_request`, `cascade_reschedule_lessons`, lesson generation |

---

### OD-18 — Payment method allowed values

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional values** | `cash`, `bank_transfer`, `card`, `other` |
| **Provisional rules** | Pending payment may have **no** payment method (`NULL`). Completed payment **requires** a payment method. `other` requires a note (application/trusted validation). |
| **UI review** | Payment UI — labels and additional methods |
| **Affected** | `payments.payment_method`, CHECK constraint, `complete_payment_and_renew_pass` |

---

### OD-19 — Account deletion vs deactivation

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional default** | **No physical deletion** during MVP. Deactivate login and business records instead. Personal-data anonymization is a **future** owner-controlled workflow. Historical passes, lessons, payments, refunds, and audit history **remain preserved**. |
| **UI review** | Account / profile admin UI |
| **Affected** | `profiles`, `auth.users`, `students`, `teachers`, audit FKs |

**Phase 0B-3B-2B-3A implementation note (2026-06-30)**: Database uses deactivation (`account_state`, `operational_status`, `is_active`); no physical DELETE. **Status remains Provisional** — Owner UI validation required.

---

### OD-20 — Student visibility of SMS message content

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional default** | Student may read **only** the final message content (`message_body_snapshot`) related to **their own current pass** when the product UI exposes it. Internal SMS calculation state, audit information, actor information, and administrative metadata remain **hidden**. |
| **UI review** | Student page / payment notice UI |
| **Affected** | `sms_notifications` RLS, Student PWA |

---

### OD-21 — Owner profile count

| Field | Content |
|-------|---------|
| **Status** | **Provisional** (2026-06-26) |
| **Provisional default** | **Multiple** owner profiles allowed. At least **one active owner** must always remain. The **final active owner** cannot remove or deactivate their own owner access. |
| **UI review** | Owner-management UI before implementation |
| **Affected** | `profiles.role`, `provision_profile`, `set_profile_role`, `is_owner()` |

**Phase 0B-3B-2B-3A implementation note (2026-06-30)**: Multiple active owners allowed; `REVE_LAST_OWNER` protects final active owner from demotion/deactivation. **Status remains Provisional**.

---

## Remaining Open Decisions

**현재 Open status 항목 없음.** OD-14 ~ OD-21은 **Provisional** (위 섹션).

---

## Decision Log (updated)

| ID | Topic | Status |
|----|-------|--------|
| OD-01 – OD-13 | See Confirmed above | **Confirmed** 2026-06-26 |
| OD-14 | Reserved pass start date | **Provisional** 2026-06-26 |
| OD-15 | Schedule slot copy on renewal | **Provisional** 2026-06-26 |
| OD-16 | Multi-slot lesson generation order | **Provisional** 2026-06-26 |
| OD-17 | Lesson collision handling | **Provisional** 2026-06-26 |
| OD-18 | Payment method values | **Provisional** 2026-06-26 |
| OD-19 | Account deletion vs deactivation | **Provisional** 2026-06-26 |
| OD-20 | Student SMS content visibility | **Provisional** 2026-06-26 |
| OD-21 | Owner profile count | **Provisional** 2026-06-26 |

---

## How to Close a New Decision

1. Owner review
2. 이 파일에 Status → **Confirmed**, 날짜 기록
3. `project-brief.md` Confirmed 섹션 반영
4. `domain-rules.md`, `permissions-matrix.md`, `state-transitions.md` 동기화
5. Phase 0B ERD / test scenarios 갱신

**기록되지 않은 ambiguous behavior는 구현하지 않습니다.**

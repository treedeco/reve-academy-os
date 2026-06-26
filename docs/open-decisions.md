# Open Decisions — REVE ACADEMY OS

구현 전 Owner 또는 지정 decision maker의 결정이 필요한 비즈니스 항목입니다.  
**권장 default는 시작점일 뿐이며, 승인 전까지 확정 요구사항으로 취급하지 않습니다.**

---

## 1. Teacher schedule request approval

| Field | Content |
|-------|---------|
| **Decision required** | Teacher가 schedule change request를 **승인(approve)** 할 수 있는가, 아니면 **제출(submit)만** 가능한가? |
| **Recommended default** | Teacher는 **제출만**; Owner(또는 지정 admin)만 승인·거절 |
| **Reason** | 요구사항에 "Process schedule requests only if later approved as a business rule" 및 Teacher 권한 제한이 명시됨. 연쇄 일정 변경 위험을 Owner가 통제하는 것이 안전 |
| **Risk** | Teacher 승인 허용 시 unauthorized cascade reschedule, 타 학생 일정 충돌 가능 |
| **Affected** | `schedule_change_requests`, RLS policies, Teacher/Owner UI, notification flow |

---

## 2. Reverting completed lessons to non-deductible status

| Field | Content |
|-------|---------|
| **Decision required** | `completed`(또는 deductible) 수업을 `postponed` 등 **비차감 상태로 되돌릴** 수 있는가? |
| **Recommended default** | **Owner만** 제한적 허용; audit_log 필수; used/remaining 즉시 재계산 |
| **Reason** | 실무 오입력 수정 필요 vs 회차 조작·감사 추적 복잡성 trade-off |
| **Risk** | 무제한 revert 시 used count 조작, SMS 상태 불일치, pass completed 조기 전환 |
| **Affected** | `lessons.status` transitions, used/remaining function, `audit_logs`, SMS state |

---

## 3. Pass expiration date requirement

| Field | Content |
|-------|---------|
| **Decision required** | 모든 pass에 **만료일(expiration date)** 이 필수인가? |
| **Recommended default** | **Optional** — `expired` 상태는 만료일 또는 명시적 Owner action으로 전환 |
| **Reason** | vocal academy는 회차 소진 중심; 만료 정책이 학원마다 다름 |
| **Risk** | 필수 시 데이터 입력 부담; optional 시 만료 미관리 pass 장기 active |
| **Affected** | `passes.expires_at`, cron/job for auto-expire, dashboard filters |

---

## 4. Multiple fixed schedule slots per pass

| Field | Content |
|-------|---------|
| **Decision required** | 하나의 pass가 **여러 고정 schedule slot**(예: 화 15:00 + 목 15:00)을 가질 수 있는가? |
| **Recommended default** | **Yes** — `schedule_slots` 1:N to pass (or student+course); 주 2회 = 2 slots |
| **Reason** | 주 2회(8 lessons) 상품은 요일 2개가 자연스러움; 단일 slot이면 모델 왜곡 |
| **Risk** | N slots 시 lesson generation·cascade reschedule 복잡도 증가 |
| **Affected** | `schedule_slots`, lesson generation, weekly schedule UI |

---

## 5. Makeup lesson linkage

| Field | Content |
|-------|---------|
| **Decision required** | `makeup_completed` 수업을 **원본 취소 수업**과 어떻게 연결하는가? |
| **Recommended default** | Optional `lessons.makeup_for_lesson_id` FK → 원본 lesson; pass sequence는 별도 번호 유지 |
| **Reason** | 감사·통계에서 보강 vs 정규 구분; used count는 status로만 차감 |
| **Risk** | FK 없으면 보강 추적 불가; FK 필수 시 미연결 makeup 입력 거부 필요 |
| **Affected** | `lessons` schema, UI for makeup creation, reports |

---

## 6. Refund impact on active or reserved passes

| Field | Content |
|-------|---------|
| **Decision required** | 환불 시 **active** 또는 **reserved** pass를 어떻게 처리하는가? |
| **Recommended default** | Payment status `refunded`; linked pass → `cancelled`; unused lessons → non-deductible freeze; **no physical delete** |
| **Reason** | 이력 보존 원칙; financial audit 필요 |
| **Risk** | partial refund, mid-pass refund, reserved+active 동시 존재 시 정책 미정이면 데이터 불일치 |
| **Affected** | `payments`, `passes`, renewal transaction, Owner UI |

---

## 7. Multiple simultaneous courses per student

| Field | Content |
|-------|---------|
| **Decision required** | 한 학생이 **동시에 여러 course**(예: vocal + theory)를 수강할 수 있는가? |
| **Recommended default** | **Yes** — pass uniqueness = (student, course); not global per student |
| **Reason** | pass ID `V-S006-001`은 student scope; course별 active pass 규칙과 일치 |
| **Risk** | No 시 실제 운영 course 추가 불가; Yes 시 UI·dashboard aggregation 복잡 |
| **Affected** | `passes` unique constraints, student detail, dashboard counts |

---

## 8. Tuition base amount storage

| Field | Content |
|-------|---------|
| **Decision required** | 수강료 **기준 금액**은 어디에 저장하는가? |
| **Recommended default** | `courses` (or product catalog table)에 default tuition; per-student override on `students` optional |
| **Reason** | 과목별 상품 가격 + 개별 할인/약정 분리 |
| **Risk** | courses only → 개별 계약 반영 어려움; students only → 과목별 관리 혼란 |
| **Affected** | `courses`, `students`, dashboard "expected monthly tuition" |

---

## 9. Tuition snapshot on passes and payments

| Field | Content |
|-------|---------|
| **Decision required** | pass·payment 생성 시 **수강료 금액을 스냅샷** 저장하는가? |
| **Recommended default** | **Yes** — `passes.tuition_amount`, `payments.amount` at transaction time immutable |
| **Reason** | 기준가 변경 후에도 당시 계약·입금액 감사 가능 |
| **Risk** | No snapshot → historical revenue/reporting 부정확 |
| **Affected** | `passes`, `payments`, dashboard, audit |

---

## 10. Reserved pass limit (exactly one)

| Field | Content |
|-------|---------|
| **Decision required** | reserved pass를 **정확히 1개**로 제한할지, **최대 1개**로 할지 |
| **Recommended default** | **At most one** reserved per (student, course) — DB partial unique index |
| **Reason** | 요구사항 "At most one reserved next pass"; 선결제 중복 방지 |
| **Risk** | 0 reserved 허용은 정상; 2+ reserved 허용 시 activation 순서 충돌 |
| **Affected** | `passes` constraints, payment renewal idempotency |

---

## 11. Reactivating cancelled passes

| Field | Content |
|-------|---------|
| **Decision required** | `cancelled` pass를 **다시 active**로 전환할 수 있는가? |
| **Recommended default** | **No** — reactivation forbidden; issue new pass via new payment/Owner adjustment with audit |
| **Reason** | 상태 이력 단순화; cancelled → active는 감사·회차 혼란 유발 |
| **Risk** | Yes 시 lesson/pass state 복구 로직 복잡; No 시 Owner 실수 cancel 시 수동 보정 필요 |
| **Affected** | pass state machine, Owner admin tools, `audit_logs` |

---

## Decision Log

| ID | Topic | Status | Decided By | Date |
|----|-------|--------|------------|------|
| OD-01 | Teacher schedule approval | Open | — | — |
| OD-02 | Completed lesson revert | Open | — | — |
| OD-03 | Pass expiration required | Open | — | — |
| OD-04 | Multiple schedule slots | Open | — | — |
| OD-05 | Makeup lesson linkage | Open | — | — |
| OD-06 | Refund policy | Open | — | — |
| OD-07 | Multi-course per student | Open | — | — |
| OD-08 | Tuition base storage | Open | — | — |
| OD-09 | Tuition snapshot | Open | — | — |
| OD-10 | Reserved pass limit | Open | — | — |
| OD-11 | Cancelled pass reactivation | Open | — | — |

---

## How to Close a Decision

1. Owner review of recommended default vs alternatives  
2. Update this file: Status → **Decided**, record Decided By + Date  
3. Propagate to `project-brief.md` (Confirmed section)  
4. Update ERD / state diagrams in Phase 0  
5. Add test scenarios for the decided behavior  

**Do not implement ambiguous behavior until the decision is recorded.**

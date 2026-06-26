# REVE ACADEMY OS — Project Brief

레브보컬학원 사설 학원 관리 PWA의 권위 있는 요구사항 명세입니다.

**Phase 0A (2026-06-26)**: OD-01 ~ OD-12 확정. 상세 domain/permission/state 문서: [domain-rules.md](./domain-rules.md), [permissions-matrix.md](./permissions-matrix.md), [state-transitions.md](./state-transitions.md).

---

## 1. 프로젝트 개요

### Confirmed

- **이름**: REVE ACADEMY OS
- **목적**: Google Sheets + Apps Script 기반 학원 관리 시스템을 PostgreSQL 중심 PWA로 대체
- **대상 학원**: 레브보컬학원
- **현재 단계**: Planning & Architecture — **Phase 0A domain rules documented**; application implementation **not started**

### 기존 시스템 문제 (Confirmed — 대체 동기)

| 문제 | 설명 |
|------|------|
| 느린 재계산 | 소규모 변경 후 전체 시트 재계산 |
| UI·원본 불일치 | UI 값과 원본 수업 기록 불일치 |
| 회차 수 오류 | 사용·잔여 회차 부정확 |
| 이력 혼입 | 갱신된 pass에 이전 수업 기록 혼입 |
| 고정 일정 오류 | 첫 실제 수업일 기준으로 고정 일정 배치 |
| 연쇄 일정 위험 | 안전하지 않은 연쇄 일정 변경 |
| 중복 갱신 | pass 갱신 중복 위험 |

---

## 2. 기술 스택

### Confirmed

| 항목 | 선택 |
|------|------|
| Framework | Next.js, React |
| Language | TypeScript strict mode |
| Backend / DB | Supabase, PostgreSQL |
| Auth | Supabase Auth |
| Security | Row Level Security |
| Styling | Tailwind CSS |
| Distribution | PWA |
| Unit / Integration test | Vitest 또는 Jest |
| E2E test | Playwright |
| VCS | Git |

### 지원 환경 (Confirmed)

Windows, macOS, iPhone, Android

### MVP Exclusions

- App Store 배포
- Google Play 배포

---

## 3. 사용자 역할 및 권한

권한은 UI, 서버, PostgreSQL RLS에서 모두 강제해야 합니다. 매트릭스: [permissions-matrix.md](./permissions-matrix.md).

### Owner (Confirmed)

**관리 가능**: 전체 학생, 강사, 수업, 회차권, 결제, SMS, 수익, 통계, 권한, 감사 이력

**제한**: passes, lessons, payments **물리 삭제 불가**. 민감 correction은 **사유 필수** + audit. Payment renewal은 **trusted transactional function** 사용.

### Teacher (Confirmed)

**접근 범위**: 배정된 학생 및 수업만 (OD-01)

**허용**:

- 배정 학생 operational data 조회
- 배정 수업 일정 조회
- 허용된 ordinary lesson status 전환
- 배정 수업 lesson notes 작성
- 잔여 회차 조회
- schedule change request **제출**, 사유 기록, **대체 일시 제안**
- 배정 학생 관련 요청 조회

**금지** (OD-01):

- 일정 변경 **최종 승인·거절**
- **연쇄 수업 이동 실행**
- **타 강사** 일정 변경
- completed/deductible lesson **Owner correction**
- 학원 전체 수익 조회
- 다른 강사의 학생 조회
- product price / pass financial snapshot 편집
- payment renewal 완료
- 역할·권한 관리
- unrestricted audit log 조회

### Student (Confirmed)

**접근 범위**: 본인 데이터만

**조회 가능**: 다음 수업, 전체 일정, 사용·잔여 회차, 담당 강사, 결제 안내, 과거 수업·pass 이력, 일정 변경 요청 상태

**허용**: 본인 schedule change request 생성

**편집 금지**: 수업 상태, 사용·잔여 회차, pass, 결제, tuition, SMS sent 표시, schedule 최종 승인, internal teacher notes (student-visible 제외), audit logs

---

## 4. 회차권(Pass) 규칙

### Confirmed

- **ID 형식**: `V-S006-001` → 갱신 시 `V-S006-002` (학생·course별 시퀀스); pass ID **유일**
- **상태**: `reserved`, `active`, `completed`, `expired`, `cancelled`
- **이력 보존**: 이전 pass 덮어쓰기·**물리 삭제 금지**
- **단일 active**: (student, course)당 `active` pass **하나** (OD-07)
- **reserved**: (student, course)당 **0 또는 1**; reserved **필수 아님**; 2개 이상 **금지** (OD-10)
- **다과목**: 동일 student가 **여러 course** 동시 수강 가능; course별 pass 규칙 독립 (OD-07)
- **만료일**: **optional** (OD-03); 없어도 invalid 아님; MVP 자동 만료 전체 적용 안 함
- **cancelled**: **terminal** — `active`/`reserved` 재활성화 **금지** (OD-11). 오취소 시 cancelled pass 보존 + Owner correction workflow로 **신규 pass** + audit
- **UI**: 현재 active pass 최우선 표시
- **Snapshots** (OD-09): product reference, product name, registered lesson count, weekly frequency, tuition amount (+ future discount/adjustment)

### Planned (implementation Phase)

- pass 갱신 트랜잭션 및 idempotency (Phase 4)
- `reserved → active` trusted activation (마지막 deductible 수업 완료 시)

---

## 5. Course products (OD-08)

### Confirmed — planned concept

- **`courses`**: 과목/커리큘럼
- **`course_products`**: commercial package (테이블명 확정; **Phase 0A 문서만**, SQL/table 미생성)

**course_products 필드 방향**:

- Product name, course, default lesson count, weekly frequency, default tuition, optional expiration policy, active/inactive

주 1회 → 보통 4 lessons / 1 slot. 주 2회 → 보통 8 lessons / 2 slots.

---

## 6. 사용·잔여 회차 규칙

### Confirmed

**사용자 직접 입력·편집 불가.** 소스 오브 트루스는 **lesson status** (단일 source).

| 구분 | Status |
|------|--------|
| Deductible | `completed`, `same_day_cancelled`, `makeup_completed` |
| Non-deductible | `scheduled`, `postponed`, `advance_cancelled`, `teacher_cancelled`, `academy_closed` |

```
used count = deductible lesson count
remaining count = registered lesson count − used count
```

**거부**: used > total, remaining < 0, inconsistent totals

### Owner correction (OD-02)

Deductible/completed → non-deductible:

- **Owner only**, 사유 **필수**, `audit_logs` previous/new
- lesson, pass, next lesson, SMS, dashboard counters — **하나의 일관된 operation**
- Teacher/Student **불가**

---

## 7. 수업·일정 규칙

### Confirmed

- pass마다 **독립** lesson records
- **Asia/Seoul** business time
- Lesson sequence number: pass 내 **유일**
- Canonical status: English code values ([state-transitions.md](./state-transitions.md))

**고정 schedule slots** (OD-04):

- pass당 **복수 slot** 가능 (주 2회 → 보통 2 slots)
- 각 slot: weekday, local start time, duration, teacher, active state
- **actual lesson date에서 slot 추론 금지**

**고정 배치 금지 기준**: 첫 실제 수업일, 연기일, 수동 재배치일

**연쇄 재배치**: 미완료만 선택적 이동; **completed 제외**; Owner 승인 schedule apply + trusted function (OD-01)

### Makeup (OD-05)

- Makeup lesson **반드시** 원본 lesson에 explicit link
- 원본 record **보존**; makeup은 **별도** lesson; duplicate deduction **방지**
- 원본 물리 대체·삭제 **금지**

---

## 8. Schedule change requests (OD-01)

### Confirmed

- Teacher/Student: **submit**, reason, suggested replacement datetime
- **Owner only**: final approve/reject
- **Approved** → **applied** via trusted operation (lesson move / cascade)
- Teacher: approve/reject/cascade **금지**

상태: `submitted`, `under_review`, `approved`, `rejected`, `cancelled`, `applied` — [state-transitions.md](./state-transitions.md)

---

## 9. 결제·갱신·환불

### Confirmed — payment renewal

**단일 PostgreSQL 트랜잭션** (10-step, project-brief baseline):

1. 이전 pass 상태 갱신 → 2. 이력 보존 → 3. next sequence → 4. 신규 pass + **snapshots** → 5. N lessons → 6. used=0 → 7. remaining=total → 8. SMS reset → 9. payment link → 10. commit

- **Rollback** on any failure
- **Idempotent**: first valid `pending → completed` only; same idempotency key → existing result
- 선결제: `reserved` pass; last deductible complete → `active`

### Confirmed — payment snapshots (OD-09)

Payment preserves: paid amount, payment date, method, status, related pass, idempotency reference. **Product price change does not alter historical pass/payment amounts.**

Payment status: `pending`, `completed`, `cancelled`, `refunded`

### Confirmed — refunds (OD-06, OD-12)

#### Reserved pass refund

| Rule | Detail |
|------|--------|
| Pass | → `cancelled` |
| History | pass·payment 이력 보존 |
| Activation | 이후 activate **금지** |

#### Active pass refund — Confirmed MVP behavior (OD-12)

| Rule | Detail |
|------|--------|
| Authority | **Owner only** |
| Required input | Refund **amount** and **reason** (mandatory) |
| Historical lessons | completed 및 기타 **deductible** lessons **변경 없음**, 보존 |
| Future lessons | non-deducted future lessons → **`advance_cancelled`** via **one trusted transactional operation** |
| Audit | each affected future lesson **original scheduled data** preserved in audit history |
| Pass | `active` → **`cancelled`** (terminal; OD-11) |
| Counts | used/remaining **never manually edited**; derived from lesson status + registered lesson count snapshot |
| Records | original payment, pass, lesson records **preserved**; refund record preserves amount, date, reason, actor |
| Coordination | pass change, future-lesson cancellation, refund record, SMS recalc, audit insertion — **single trusted operation** |

#### Excluded from MVP (OD-12)

- Partial refund while keeping the same pass **active**
- Transferring remaining lesson counts to another course, student, or pass
- Creating credits or stored balances

#### Future controlled correction (not reactivation)

If refund was mistaken: **do not reactivate** the cancelled pass. Use Owner-controlled **new pass correction workflow** with audit (OD-11).

Teacher and Student **cannot** perform refunds.

---

## 10. SMS 알림 규칙

### Confirmed

States: `normal`, `scheduled`, `target`, `exhausted_unsent`, `sent`

| 조건 | State |
|------|-------|
| remaining = 1, 알림일 이전 | `scheduled` |
| 마지막 수업 1일 전부터 | `target` |
| remaining = 0, 미발송 | `exhausted_unsent` |
| Owner 수동 확인 | `sent` |

- New pass → SMS state reset (new record); prior sent history preserved
- Owner lesson correction → scoped SMS recalc

### MVP

- Include: message copy, manual sent
- Exclude: external SMS API

---

## 11. 주요 화면

### Confirmed — Planned screens

| 화면 | 주요 내용 |
|------|-----------|
| Owner dashboard | 재원 학생, active pass, 예상 월 수강료, 당월 입금, 미수금, 오늘 수업, SMS, 잔여 1회 |
| Today's lessons | 시간, 학생, course, 강사, status, memo |
| Weekly schedule | 고정 weekday/time, 필터, mobile list |
| Student detail | 프로필, active pass, 사용·잔여, slots, lessons, payments, passes history |
| Student page | 다음 수업, 잔여, 일정, 결제 안내, schedule request |

### Confirmed — 성능

단일 lesson status change → scoped update only (해당 lesson, pass, student, SMS, counters). **Full academy recalc 금지.**

---

## 12. 데이터 모델 방향

### Confirmed — tables (minimum + planned)

`profiles`, `students`, `teachers`, `courses`, **`course_products`** (planned), `passes`, `lessons`, `schedule_slots`, `payments`, `sms_notifications`, `schedule_change_requests`, `lesson_notes`, `audit_logs`

### Confirmed — principles

- PostgreSQL = **single source of truth**
- passes, lessons, payments: **no physical delete**
- used/remaining: **derived**, not editable
- service role key: browser **expose 금지**
- RLS on all app tables (implementation Phase)

### Planned (Phase 0B)

- ERD, columns, indexes, RLS SQL

---

## 13. 성능·개발 프로세스

### Confirmed

- Scoped updates; no full reload on single lesson change
- Development order: requirements → impact → data model → plan → minimal change → typecheck → lint → tests → browser → commit → report

---

## 14. 로드맵

[roadmap.md](./roadmap.md). Phase 0A deliverables (domain rules, permissions, state transitions) **documented**. Phase 0B (ERD, RLS design) **not started**.

---

## 15. MVP 범위

### In scope

Owner/Teacher/Student, pass lifecycle, status-based counts, transactional renewal (Phase 4+), SMS MVP, PWA

### Out of scope

App Store / Play, external SMS API, Sheets migration (Phase 6)

---

## 16. 미결정 사항

OD-01 ~ OD-12 **Confirmed 2026-06-26**. Phase 0B 설계 deliverable(ERD, RLS): [open-decisions.md](./open-decisions.md), [roadmap.md](./roadmap.md).

**누락 규칙을 임의로 발명하지 마세요.**

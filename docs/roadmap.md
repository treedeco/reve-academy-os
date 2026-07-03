# Development Roadmap — REVE ACADEMY OS

승인된 단계별 개발 로드맵입니다. **현재 Phase가 검증되기 전에 다음 Phase를 시작하지 않습니다.**

---

## Phase 0 — Requirements & Architecture

### Goal

데이터베이스·비즈니스 규칙 우선 설계를 완료하고, 구현 전 모든 핵심 결정과 테스트 시나리오를 문서화합니다.

### Entry Conditions

- 저장소 초기화 및 프로젝트 문서 존재 (README, AGENTS, docs/)
- 이 저장소 작업: **문서 초기화만 완료** — Phase 0 본격 산출물(ERD, RLS 등)은 **미시작**

### Deliverables

- [ ] 요구사항 명세 확정 (`docs/project-brief.md` 기반 보완)
- [ ] 권한 매트릭스 (Owner / Teacher / Student × 리소스 × CRUD)
- [ ] 데이터 모델 (테이블, 컬럼, 제약, 인덱스)
- [ ] ERD
- [ ] 상태 전이 다이어그램 (pass, lesson, SMS, schedule request)
- [ ] Pass renewal flow (트랜잭션 단계, reserved → active)
- [ ] Security & RLS 설계 (정책 초안)
- [ ] Development roadmap 검증 (`docs/roadmap.md` 유지)
- [ ] Test scenarios (회차 계산, 갱신, idempotency, 권한)

### Validation Requirements

- used/remaining이 editable source가 아님을 모델에 반영
- pass/lesson/payment soft-delete 또는 no-delete 정책 명시
- 결제·갱신 트랜잭션 및 idempotency 설계 검토
- **OD-01 ~ OD-12 confirmed (2026-06-26)** — authoritative business requirements documented in [open-decisions.md](./open-decisions.md)
- **Phase 0A** documentation (domain rules, permissions matrix, state transitions) validated and checkpointed **before Phase 0B begins**
- 이후 설계에서 **새로 발견된** unresolved business decision은 [open-decisions.md](./open-decisions.md)에 기록·승인 후 해당 구현 착수
- 문서 간 모순 없음

### Completion Conditions

- Phase 0 deliverables 전부 문서·다이어그램으로 존재
- Owner(또는 지정 decision maker) sign-off
- Phase 1 entry conditions 충족

### Explicitly Excluded

- Next.js 프로젝트 생성
- Supabase 프로젝트·migration 실행
- UI 구현
- Google Sheets 마이그레이션

---

## Phase 1 — Foundation

### Goal

Next.js + Supabase + Auth + 역할 + 기본 레이아웃 + PWA 기반을 구축합니다.

### Entry Conditions

- Phase 0 완료 및 sign-off
- RLS 설계 초안 존재
- Supabase 프로젝트 생성 (팀)

### Deliverables

- Next.js 프로젝트 (TypeScript strict)
- Supabase 연결 (환경 변수, server/client 분리)
- Supabase Auth (로그인·세션)
- Owner / Teacher / Student 역할 (profiles + RLS 기초)
- Base layout (역할별 네비게이션 골격)
- PWA manifest, service worker, installability
- CI: typecheck, lint, test scaffold

### Validation Requirements

- service role key가 클라이언트 번들에 없음
- 역할별 로그인·라우트 가드 동작
- PWA: Windows/macOS/iOS/Android 중 대표 기기 설치 테스트
- Vitest/Jest + Playwright smoke test

### Completion Conditions

- 인증된 사용자가 역할에 맞는 빈 shell 화면 접근
- Phase 2 entry conditions 충족

### Explicitly Excluded

- 학생·수업·결제 도메인 CRUD
- Dashboard 통계
- SMS
- Sheets 마이그레이션

---

## Phase 2 — Master Data & Student Detail

### Goal

학생, 강사, 과목, 고정 일정, 학생 상세 화면을 구현합니다.

### Entry Conditions

- Phase 1 완료
- Phase 0 데이터 모델·RLS 정책 확정

### Deliverables

- `students`, `teachers`, `courses`, `schedule_slots` CRUD (Owner)
- Teacher ↔ Student 배정
- Fixed schedule (요일·로컬 시간 기준; 첫 수업일 기준 금지)
- Student detail (Owner/Teacher): 프로필, active pass 표시, 고정 일정, 기본 목록
- RLS: Teacher는 배정 데이터만

### Validation Requirements

- 고정 일정이 pass/slot 설정 요일·시간을 따름
- Teacher가 타 강사 학생 접근 불가
- Student role은 Phase 2 범위 외 화면 미노출 또는 placeholder

### Completion Conditions

- Owner가 학생·강사·과목·고정 일정 관리 가능
- Student detail에서 active pass·일정 조회 (pass/lesson full lifecycle은 Phase 3–4)

### Explicitly Excluded

- Lesson status 변경 및 회차 계산
- 결제·pass 갱신
- SMS, dashboard 통계
- Schedule change request workflow

---

## Phase 3 — Lessons & Counts

### Goal

오늘의 수업, 수업 상태 변경, status 기반 used/remaining 계산, 수업 메모를 구현합니다.

### Entry Conditions

- Phase 2 완료
- Lesson status enum 및 deduction rules 확정

### Deliverables

- Today's lessons 화면
- Lesson status 변경 (scoped update only)
- used / remaining **derived** calculation (DB trigger 또는 server function)
- Impossible state rejection
- Lesson notes (`lesson_notes`)
- 연쇄 재배치 vs 수동 변경 구분 (설계대로)
- Postponed 시 미완료 수업 선택적 이동; completed 자동 이동 금지

### Validation Requirements

- 단일 status 변경이 full academy recalc를 유발하지 않음
- used/remaining UI에서 직접 편집 불가
- 차감/비차감 상태 매트릭스 unit test
- Teacher: 배정 수업만; Student: 편집 불가

### Completion Conditions

- Owner/Teacher가 오늘 수업 상태·메모 관리
- pass used/remaining이 lesson status와 일치

### Explicitly Excluded

- Payment, pass renewal (001→002)
- SMS automation beyond state stub
- Full dashboard
- Audit log UI (backend 기록은 Phase 5 가능)

---

## Phase 4 — Payments & Pass Renewal

### Goal

결제, pass 갱신, 시퀀스 증가, 선결제 reserved pass, 이력 pass를 트랜잭션·멱등으로 구현합니다.

### Entry Conditions

- Phase 3 완료
- Payment idempotency key 설계 확정
- OD-06, OD-12 refund rules confirmed ([open-decisions.md](./open-decisions.md))

### Deliverables

- `payments` CRUD (Owner)
- Renewal transaction (10-step, single commit)
- Pass ID sequence: `V-S006-001` → `V-S006-002`
- Advance payment → `reserved`; last deductible complete → `active`
- Historical passes read-only
- Idempotency: duplicate payment → no second pass
- Payment ↔ pass linkage

### Validation Requirements

- Integration test: full renewal rollback on failure
- Integration test: idempotent retry
- 이전 pass·lesson 물리 삭제 없음
- reserved + active 규칙 준수

### Completion Conditions

- Owner가 결제 등록 시 pass·lessons atomically 생성
- 선결제 reserved flow 동작

### Explicitly Excluded

- SMS copy/send UI (Phase 5)
- Dashboard revenue widgets
- Google Sheets import

---

## Phase 5 — SMS, Dashboard, Audit

### Goal

SMS 대상 관리(MVP: 복사·수동 확인), Owner dashboard, 통계, 감사 이력을 구현합니다.

### Entry Conditions

- Phase 4 완료
- SMS state transition rules 확정

### Deliverables

- SMS states: `normal`, `scheduled`, `target`, `exhausted_unsent`, `sent`
- SMS message text copy + manual sent confirmation
- Owner dashboard (scoped aggregates, not full recalc on each lesson change)
- Statistics (정의된 KPI)
- Audit log viewer (Owner)
- `schedule_change_requests` workflow (OD-01 confirmed approval rules)

### Validation Requirements

- Dashboard counter가 scoped lesson update로만 갱신
- SMS state transitions unit test
- 외부 SMS API **미연동** 확인

### Completion Conditions

- Owner dashboard operational
- SMS MVP workflow complete
- Audit history searchable (Owner)

### Explicitly Excluded

- External SMS provider integration
- Advanced analytics beyond defined MVP KPIs

---

## Phase 6 — Migration & Production Transition

### Goal

Google Sheets 데이터를 이전하고, 병행 운영·비교·오류 수정 후 프로덕션 전환합니다.

### Entry Conditions

- Phase 5 완료
- Production Supabase 환경
- Migration scripts + rollback/compensation plan

### Deliverables

- Sheets export/import tooling
- Parallel operation period
- Data comparison reports
- Error correction runbook
- Production cutover checklist

### Validation Requirements

- Sample student pass counts match Sheets (within agreed tolerance)
- No duplicate renewals from migrated payments
- Audit trail for migration fixes

### Completion Conditions

- Google Sheets 의존 종료
- Production on REVE ACADEMY OS

### Explicitly Excluded

- App Store / Google Play release
- New feature scope beyond parity + agreed fixes

---

## Phase Summary

| Phase | Focus | App Code |
|-------|-------|----------|
| 0 | Design & docs | No |
| 1 | Foundation | Yes |
| 2 | Master data | Yes |
| 3 | Lessons & counts | Yes |
| 4 | Payments & renewal | Yes |
| 5 | SMS & dashboard | Yes |
| 6 | Migration | Yes |

**Current status**: Phase **1A — Owner Alpha Core Operations** is **complete** (tag `phase-1a-owner-alpha-runtime-verified`). Phase 0B database trusted operations through **0B-3B-2B-3E** remain **authoritative** (tag `phase-0b3b2b3e-owner-payment-refund`).

---

## Phase 1A — Owner Alpha Core Operations (complete)

### Goal

Deliver the first browser-usable Owner application against the verified Supabase database. This is an operational vertical slice, **not** full product completion.

### Status

**Complete** — automated verification (H1), migration ordering audit (H2), and Owner manual browser verification (H3) passed on 2026-07-03. Checkpoint tag: `phase-1a-owner-alpha-runtime-verified`.

### Entry Conditions

- Phase 0B-3B-2B-3E database checkpoint verified locally
- Completed trusted operations remain authoritative (`reve_transition_lesson_status`, `reve_owner_get_pass_usage`, etc.)

### Deliverables

- Next.js + React + TypeScript (strict) + Tailwind + Supabase Auth
- Owner login/logout and protected routes
- Owner shell (responsive navigation, loading/empty/error states)
- `/dashboard`, `/lessons/today`, `/students`, `/students/[studentId]`
- Lesson status changes **only** via `reve_transition_lesson_status`
- Scoped refresh after mutations (lesson, pass summary, student summary, dashboard counts)
- Vitest unit/integration tests + Playwright browser tests
- Read-only migration `reve_owner_get_pass_usage` when required for derived counts

### Validation Requirements

- Owner can sign in, view today’s lessons, change lesson status, reload, and see persisted state in a real browser
- Failed mutations restore previous UI and show readable errors
- No service-role key in client code; RLS preserved
- Standard pgTAP baseline **882** + SMS concurrency **1** + refund concurrency **2** must not regress
- Phase 1A pgTAP assertions counted separately (**6** in `phase_1a_owner_read_projections.test.sql`)

### Explicitly Excluded (Phase 1A)

- `correct_cancelled_pass`, general re-enrollment, refund reversal UI
- Payment UI, refund UI, SMS management UI
- Teacher/Student login UI, schedule-change request UI
- Weekly schedule editing, advanced dashboard analytics

---

## Phase 1A-H1 — Owner Alpha Verification and Runtime Hardening (complete)

### Goal

Formalize verification gates and harden Owner Alpha runtime behavior without adding business features.

### Status

**Complete** — tag `phase-1a-h1-owner-alpha-verification-hardened`.

### Deliverables

- Deterministic db lint baseline verifier (`scripts/verify_db_lint_baseline.ps1`)
- Phase 1A aggregate verification script (`scripts/verify_phase_1a.ps1`)
- Scoped lesson-status UI refresh (no route-wide `router.refresh()`)
- Local-only demo seed safety checks
- Manual browser verification checklist (`docs/manual-verification-owner-alpha.md`)

---

## Phase 1A-H2 — Migration Ordering Audit (complete)

### Goal

Audit and normalize Phase 1A migration filenames without changing SQL behavior.

### Status

**Complete** — tag `phase-1a-h2-migration-order-audited`. Phase 1A migrations ordered immediately after `20260708120000_phase_0b3b2b3e_owner_payment_refund.sql` (`08130100`, `08130200`). Accepted ordering exception relative to project calendar date 2026-07-03.

---

## Phase 1A-H3 — Owner Manual Runtime Verification (complete)

### Goal

Owner performs all 15 manual browser checklist steps; record explicit sign-off.

### Status

**Complete** — Owner confirmed all steps PASS on 2026-07-03. Evidence: `docs/manual-verification-owner-alpha.md`. Final tag: `phase-1a-owner-alpha-runtime-verified`.

---

## Phase 1B-1 — Owner Weekly Schedule Read (active)

### Goal

Read-only Owner weekly fixed schedule view grouped by weekday and local time (Asia/Seoul).

### Deliverables

- Route `/schedule` with navigation **주간 시간표**
- Server-side `fetchWeeklySchedule` (2 DB queries, zero per-row N+1)
- Desktop column + mobile list layouts from one normalized model
- Extended local demo seed for multi-weekday coverage
- Unit, Playwright, and `scripts/verify_phase_1b1.ps1` verification

### Status

**Implementation complete — Owner manual verification pending** (`docs/manual-verification-owner-weekly-schedule.md`).

---

## Phase 0B-3B — Database trusted operations (implementation track)

Executable PostgreSQL migrations and pgTAP tests. **Baseline database checkpoint**: Phase 0B-3B-2B-3E (tag `phase-0b3b2b3e-owner-payment-refund`).

| Phase | Name | Status |
|-------|------|--------|
| 0B-3B-2B-3D-1 | Pass schedule slot replacement | **Implemented** |
| 0B-3B-2B-3D-2A | Schedule change review and direct apply | **Implemented** |
| 0B-3B-2B-3D-2B | Optional cascade rescheduling + SMS sync correction | **Implemented** |
| 0B-3B-2B-3D-3 | Owner manual SMS sent confirmation | **Implemented** |
| 0B-3B-2B-3D-3A | SMS sent confirmation specification (docs only) | **Implemented** |
| 0B-3B-2B-3D-3B | SMS sent confirmation database RPC + pgTAP | **Implemented** |
| 0B-3B-2B-3D-3B-H1 | SMS concurrency harness hygiene | **Implemented** |
| 0B-3B-2B-3E | Owner payment refund trusted operation | **Implemented** |
| 1A (read) | Owner pass usage read projection | **Implemented** |

### Phase 0B-3B-2B-3D-3 — Owner manual SMS sent confirmation

**Purpose**: Allow an authenticated Owner to record that an SMS notification was manually sent through an external SMS application. The application does **not** send SMS via an external API in this phase family.

**Subphases**:

- **3D-3A** — Canonical documentation: authorization, state transitions, audit, idempotency, concurrency, future test plan. **No migration or RPC.**
- **3D-3B-H1** — Forward migration removed production `reve_test` harness; concurrency verification isolated to scripts.
- **3E** — **Implemented**: `public.reve_process_payment_refund`; Owner-only full refund for active/reserved passes; duplicate rejection via `REVE_REFUND_ALREADY_EXISTS`; standard pgTAP **882** + dedicated concurrency pgTAP **2**. Verified via `scripts/verify_phase_0b3b2b3e.ps1`.

---

## Deferred after Owner Alpha (post-Alpha)

These database exception / correction workflows remain specified but **not scheduled** until Owner Alpha is operational in daily use:

- **`correct_cancelled_pass`** (formerly planned Phase 0B-3B-2B-3F)
- General **re-enrollment** workflows
- **Refund reversal** and related payment correction UI
- Owner UI for SMS copy/confirm workflow; external SMS API; sent-confirmation reversal
- Payment UI, schedule-change request UI, Teacher/Student portals
- Advanced dashboard statistics, accounting integration, multi-branch support

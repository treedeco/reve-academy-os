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
- [open-decisions.md](./open-decisions.md) 항목 Owner 승인 또는 default 채택
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
- [open-decisions.md](./open-decisions.md) 결제·환불 관련 결정

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
- `schedule_change_requests` workflow (승인 규칙은 open decision 반영)

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

**Current status**: Repository documentation initialized. **Phase 0 deliverables (ERD, RLS, etc.) not started.** Application implementation not started.

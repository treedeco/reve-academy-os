# REVE ACADEMY OS

레브보컬학원을 위한 사설 학원 관리 PWA(Progressive Web App)입니다.

## 프로젝트 목적

현재 Google Sheets 및 Apps Script로 운영 중인 학원 관리 시스템을 대체합니다. 학생, 강사, 수업, 회차권, 결제, SMS 알림, 일정 변경, 감사 로그, 대시보드 통계 등을 **데이터베이스와 비즈니스 규칙 우선**으로 재설계합니다.

기존 시스템에서 반복적으로 발생한 문제(전체 시트 재계산 지연, UI와 원본 수업 기록 불일치, 사용·잔여 회차 오류, 갱신 회차권에 이전 수업 혼입, 고정 일정 배치 오류, 연쇄 일정 변경 위험, 중복 갱신 위험 등)를 해결하는 것이 목표입니다.

## 현재 상태

**Phase 1A — Owner Alpha Core Operations** (active). Phase 0B-3B-2B-3E database checkpoint remains authoritative (tag `phase-0b3b2b3e-owner-payment-refund`). Owner Alpha Next.js application provides login, dashboard, today’s lessons, student list/detail, and lesson status changes via existing trusted RPCs.

Database exception workflows (`correct_cancelled_pass`, re-enrollment, refund reversal UI, etc.) are **deferred until after Owner Alpha** is operational.

## 계획된 기술 스택

| 영역 | 기술 |
|------|------|
| 프레임워크 | Next.js, React |
| 언어 | TypeScript (strict mode) |
| 백엔드 / DB | Supabase, PostgreSQL |
| 인증 | Supabase Auth |
| 보안 | Row Level Security (RLS) |
| 스타일 | Tailwind CSS |
| 배포 형태 | PWA |
| 테스트 | Vitest, Playwright |
| 버전 관리 | Git |

## 지원 환경

- Windows
- macOS
- iPhone
- Android

MVP는 PWA 설치 방식으로 제공하며, App Store / Google Play 배포는 계획하지 않습니다.

## 문서

| 문서 | 설명 |
|------|------|
| [AGENTS.md](./AGENTS.md) | Cursor 및 코딩 에이전트용 권위 있는 작업 지침 |
| [docs/project-brief.md](./docs/project-brief.md) | 프로젝트 요구사항 및 사양 |
| [docs/development-principles.md](./docs/development-principles.md) | 개발 원칙 (데이터 무결성, RLS, 성능, 트랜잭션 등) |
| [docs/roadmap.md](./docs/roadmap.md) | 단계별 개발 로드맵 |
| [docs/open-decisions.md](./docs/open-decisions.md) | 미결정 비즈니스 결정 사항 |
| [docs/data-model.md](./docs/data-model.md) | 논리 데이터 모델 및 aggregate 경계 |
| [docs/schema-dictionary.md](./docs/schema-dictionary.md) | 테이블별 컬럼 사전 (Phase 0B-1) |
| [docs/erd.md](./docs/erd.md) | ERD (Mermaid) 및 관계 설명 |
| [docs/data-integrity-constraints.md](./docs/data-integrity-constraints.md) | 무결성 제약 설계 (SQL 미포함) |
| [docs/postgresql-physical-design.md](./docs/postgresql-physical-design.md) | PostgreSQL 물리 스키마 설계 (Phase 0B-2) |
| [docs/rls-policy-design.md](./docs/rls-policy-design.md) | RLS 정책 아키텍처 (Phase 0B-2) |
| [docs/trusted-operation-contracts.md](./docs/trusted-operation-contracts.md) | Trusted operation 계약 (Phase 0B-2) |
| [docs/production-deployment-runbook.md](./docs/production-deployment-runbook.md) | 프로덕션 배포 (Vercel + hosted Supabase) 운영 가이드 |
| [docs/database-migration-plan.md](./docs/database-migration-plan.md) | 마이그레이션 순서 및 롤백 전략 (Phase 0B-2) |
| [docs/database-test-plan.md](./docs/database-test-plan.md) | 데이터베이스 테스트 계획 (Phase 0B-2) |

## 로컬 개발 (Phase 1A Owner Alpha)

**요구 사항**: Docker Desktop, Node.js, Supabase CLI (`npx supabase`).

```powershell
npx supabase start
npx supabase db reset
npm run db:seed:alpha
cp .env.local.example .env.local   # local anon key from `npx supabase status`
npm install
npm run dev
```

Owner local login (`/login`):

- Username: `reve`
- Password: set in gitignored `.env.local` as `OWNER_PASSWORD` (used by `npm run db:seed:alpha` to store a bcrypt hash in Supabase Auth — never commit plaintext passwords)

Manual browser checklist: [docs/manual-verification-owner-alpha.md](./docs/manual-verification-owner-alpha.md)

**Note**: `supabase/seed.sql` is intentionally empty so pgTAP bootstrap tests are not polluted. Use `npm run db:seed:alpha` for app dev and Playwright.

`scripts/seed-owner-alpha.sql` is **local demo/E2E only**. It mutates auth users and domain rows with fixed UUIDs. Do **not** run it against hosted/production Supabase. Demo credentials must never be reused in production.

## 프로덕션 배포 (Vercel + hosted Supabase)

애플리케이션 런타임에는 `NEXT_PUBLIC_SUPABASE_URL`과 `NEXT_PUBLIC_SUPABASE_ANON_KEY`만 필요합니다. 로컬 alpha 시드(`npm run db:seed:alpha`)와 integration cleanup은 **프로덕션에서 실행하지 마세요**.

- 환경 변수 템플릿: [`.env.production.example`](./.env.production.example)
- 운영 절차: [docs/production-deployment-runbook.md](./docs/production-deployment-runbook.md)
- Owner 일회성 부트스트랩: `npm run bootstrap:production-owner` (호스팅 Supabase + `SUPABASE_SERVICE_ROLE_KEY` + `OWNER_BOOTSTRAP_PASSWORD`; 비밀번호는 로그에 출력되지 않음)

## 로컬 데이터베이스 (Phase 0B-3A ~ 0B-3B-2B-3E + 1A read)

**요구 사항**: **Docker Desktop**(엔진 실행 중), Node.js, Supabase CLI (`npx supabase`).

Phase 0B-3B-2B-3E까지 trusted database operations가 적용되어 있습니다. Phase 1A adds read-only `reve_owner_get_pass_usage`. Owner **UI** for payment/refund/SMS, `correct_cancelled_pass`, re-enrollment는 deferred.

**로컬 런타임 검증**: `db reset` 18개 마이그레이션 적용. 표준 pgTAP **882** + Phase 1A **6** = **888**. SMS concurrency pgTAP **1** + refund concurrency pgTAP **2** (별도 스크립트).

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_phase_0b3b2b3e.ps1
```

SMS-only regression:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_phase_0b3b2b3d3b.ps1
```

## Phase 1A — Owner Alpha Core Operations

**Routes**: `/login`, `/dashboard`, `/lessons/today`, `/students`, `/students/[studentId]`

**Lesson status mutation**: `public.reve_transition_lesson_status` (client never writes lesson rows directly)

**Pass usage reads**: `public.reve_owner_get_pass_usage`

**Validation**:

```powershell
npm run typecheck
npm run lint
npm run db:seed:alpha
npm run test
npm run build
npx playwright test
powershell -ExecutionPolicy Bypass -File scripts/verify_phase_0b3b2b3e.ps1
```

## Phase 0B-3B-2B-3E — Owner payment refund (database)

**RPC**: `public.reve_process_payment_refund(p_payment_id uuid, p_refunded_amount_krw integer, p_reason text)` — Owner-only; active/reserved pass full refund; duplicate attempt → `REVE_REFUND_ALREADY_EXISTS`. **Migration**: `20260708120000_phase_0b3b2b3e_owner_payment_refund.sql`.

## Phase 0B-3B-2B-3D-3B — Owner SMS sent confirmation (database)

**RPC**: `public.reve_owner_confirm_sms_sent(p_sms_notification_id uuid)` — Owner-only; `scheduled` / `target` / `exhausted_unsent` → `sent`; idempotent when already `sent`. **Audit**: `sms_notification.sent_confirmed`. **Migration**: `20260706120000_phase_0b3b2b3d3b_owner_sms_sent_confirmation.sql`. Owner UI 및 외부 SMS 발송은 deferred.

OD-14 ~ OD-21은 **Provisional** — executable migration 전 Owner 재검토 필요.

## 사용자 역할 (개요)

- **Owner** — 학원 전체 관리, 수익·통계·권한·감사 이력
- **Teacher** — 배정된 학생·수업만 접근, 수업 상태·메모·일정 변경 요청
- **Student** — 본인 데이터만 조회 (수업, 잔여 회차, 결제 안내 등)

자세한 권한은 [docs/project-brief.md](./docs/project-brief.md)를 참조하세요.

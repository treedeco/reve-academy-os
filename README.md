# REVE ACADEMY OS

레브보컬학원을 위한 사설 학원 관리 PWA(Progressive Web App)입니다.

## 프로젝트 목적

현재 Google Sheets 및 Apps Script로 운영 중인 학원 관리 시스템을 대체합니다. 학생, 강사, 수업, 회차권, 결제, SMS 알림, 일정 변경, 감사 로그, 대시보드 통계 등을 **데이터베이스와 비즈니스 규칙 우선**으로 재설계합니다.

기존 시스템에서 반복적으로 발생한 문제(전체 시트 재계산 지연, UI와 원본 수업 기록 불일치, 사용·잔여 회차 오류, 갱신 회차권에 이전 수업 혼입, 고정 일정 배치 오류, 연쇄 일정 변경 위험, 중복 갱신 위험 등)를 해결하는 것이 목표입니다.

## 현재 상태

**Planning & Architecture** — Phase 0A complete; Phase 0B-1 logical data model; **Phase 0B-2 complete** (physical schema, RLS, trusted operations, migration and test design). OD-14 ~ OD-21: **Provisional** — review before Phase 0B-3 migrations.

애플리케이션 구현은 **아직 시작하지 않았습니다.**

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
| 테스트 | Vitest 또는 Jest, Playwright |
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
| [docs/database-migration-plan.md](./docs/database-migration-plan.md) | 마이그레이션 순서 및 롤백 전략 (Phase 0B-2) |
| [docs/database-test-plan.md](./docs/database-test-plan.md) | 데이터베이스 테스트 계획 (Phase 0B-2) |

## 사용자 역할 (개요)

- **Owner** — 학원 전체 관리, 수익·통계·권한·감사 이력
- **Teacher** — 배정된 학생·수업만 접근, 수업 상태·메모·일정 변경 요청
- **Student** — 본인 데이터만 조회 (수업, 잔여 회차, 결제 안내 등)

자세한 권한은 [docs/project-brief.md](./docs/project-brief.md)를 참조하세요.

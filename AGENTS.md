# AGENTS.md — REVE ACADEMY OS

Cursor 및 기타 코딩 에이전트를 위한 **권위 있는** 작업 지침입니다. 이 문서와 충돌하는 임의 판단을 하지 마세요.

## 최우선 원칙

1. **데이터 정확성이 최우선**입니다. 화면에 보이는 숫자를 고치기 위해 근본 데이터 흐름을 건너뛰지 마세요.
2. **PostgreSQL이 단일 진실 공급원(Single Source of Truth)**입니다.
3. **한 레코드 변경으로 전체 시스템 재계산을 수행하지 마세요.** (전체 학생 재로드, 전체 회차권 재계산, 전체 일정 재생성, 전체 대시보드 재생성, 전체 페이지 새로고침, 동일 데이터 중복 요청 금지)
4. **과거 회차권(passes), 수업(lessons), 결제(payments)를 덮어쓰거나 물리 삭제하지 마세요.**
5. **사용 회차(used count)와 잔여 회차(remaining count)를 사용자가 직접 입력·편집 가능한 소스 데이터로 설계하지 마세요.** 차감은 **수업 상태(lesson status)**에서 파생됩니다.
6. **권한은 UI뿐 아니라 RLS와 서버 로직에서 강제**해야 합니다.
7. **결제 및 회차권 갱신은 PostgreSQL 트랜잭션**으로 처리해야 합니다.
8. **결제 처리는 멱등(idempotent)**이어야 합니다. 동일 결제로 두 개의 회차권이 생성되어서는 안 됩니다.
9. **Supabase service role key를 클라이언트(브라우저)에 노출하지 마세요.**
10. **학원 업무 시간·날짜 규칙은 Asia/Seoul**을 사용합니다.

## 기술 요구사항

- TypeScript **strict mode** 사용
- 승인된 스택: Next.js, React, Supabase, PostgreSQL, Tailwind CSS, PWA
- 테스트: Vitest 또는 Jest, Playwright
- 모든 애플리케이션 테이블에 RLS 적용 (Phase 1 이후)

## 개발 프로세스

모든 기능은 다음 순서를 따릅니다:

1. 요구사항 분석
2. 영향 분석
3. 데이터 모델 검토
4. 구현 계획
5. 최소 범위 수정
6. 타입 체크
7. Lint
8. 단위 테스트
9. 통합 테스트
10. 브라우저 검증
11. Git commit
12. 완료 보고

## 금지 사항

- **관련 없는 대규모 리팩터링** 금지
- **현재 Phase가 검증되기 전에 이후 Phase 시작** 금지
- **검증되지 않은 작업을 완료로 보고** 금지
- **누락된 비즈니스 규칙을 임의로 발명** 금지 — 미결정 사항은 [docs/open-decisions.md](./docs/open-decisions.md)에 기록

## 핵심 도메인 규칙 (요약)

### 회차권(Pass)

- ID 형식 예: `V-S006-001`, `V-S006-002`, `V-S006-003`
- 상태: `reserved`, `active`, `completed`, `expired`, `cancelled` (최소)
- 동일 학생·과목에 **active 회차권은 하나만**
- **reserved 다음 회차권은 최대 하나** (비즈니스 규칙; [open-decisions.md](./docs/open-decisions.md) 참조)
- 갱신 시 이전 회차권은 이력으로 보존

### 사용·잔여 회차

- **차감 대상 상태**: `completed`, `same_day_cancelled`, `makeup_completed`
- **비차감 상태**: `scheduled`, `postponed`, `advance_cancelled`, `teacher_cancelled`, `academy_closed`
- `used = 차감 대상 수업 수`, `remaining = 총 등록 수업 수 - used`
- 불가능한 상태(예: total 4 / used 0 / remaining 0, used > total, 음수 remaining)는 **거부**

### 수업·일정

- 고정 일정 배치는 **회차권 또는 schedule slot에 설정된 요일·로컬 시간** 사용
- **첫 실제 수업일, 연기된 수업일, 수동 재배치일을 기준으로 고정 일정을 잡지 않음**
- 완료된 수업은 자동 이동 금지
- 사용자 직접 변경 vs 연쇄 재배치 자동 이동을 구분

### 결제·갱신

- 결제 완료 시 단일 트랜잭션: 이전 pass 상태 갱신 → 이력 보존 → 다음 시퀀스 생성 → 신규 pass → 수업 N개 생성 → used=0, remaining=설정값 → SMS 상태 리셋 → 결제 연결 → commit
- 실패 시 전체 rollback
- 선결제 시 **reserved** pass 생성, 현재 pass의 마지막 차감 수업 완료 후 **active** 전환
- **고유 payment reference 또는 idempotency key** 필수

### SMS (MVP)

- 상태: `normal`, `scheduled`, `target`, `exhausted_unsent`, `sent`
- MVP: 메시지 텍스트 복사, 수동 발송 확인
- MVP 제외: 외부 SMS API 연동

## 완료 보고 형식

작업 완료 시 다음을 포함합니다:

- **원인/목적** — 왜 이 변경이 필요했는지
- **변경 파일** — 수정·추가된 파일 목록
- **데이터베이스 변경** — migration, RLS, 함수 등
- **테스트** — 실행한 테스트 및 결과
- **남은 위험** — 알려진 제한사항
- **사용자 검증 항목** — 수동 확인이 필요한 항목
- **commit hash** — (commit 수행 시)

## 참조 문서

- [docs/project-brief.md](./docs/project-brief.md) — 전체 요구사항
- [docs/development-principles.md](./docs/development-principles.md) — 개발 원칙
- [docs/roadmap.md](./docs/roadmap.md) — Phase별 로드맵
- [docs/open-decisions.md](./docs/open-decisions.md) — 미결정 사항

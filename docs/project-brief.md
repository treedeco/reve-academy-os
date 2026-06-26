# REVE ACADEMY OS — Project Brief

레브보컬학원 사설 학원 관리 PWA의 권위 있는 요구사항 명세입니다.

---

## 1. 프로젝트 개요

### Confirmed

- **이름**: REVE ACADEMY OS
- **목적**: Google Sheets + Apps Script 기반 학원 관리 시스템을 PostgreSQL 중심 PWA로 대체
- **대상 학원**: 레브보컬학원
- **현재 단계**: Planning & Architecture (구현 미시작)

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

권한은 UI, 서버, PostgreSQL RLS에서 모두 강제해야 합니다.

### Owner (Confirmed)

**관리 가능**: 전체 학생, 강사, 수업, 회차권, 결제, SMS, 수익, 통계, 권한, 감사 이력

### Teacher (Confirmed)

**접근 범위**: 배정된 학생 및 수업만

**허용**:

- 오늘의 수업 조회
- 배정 학생 조회
- 수업 상태 변경
- 수업 메모 작성
- 잔여 회차 조회
- 일정 변경 요청 제출
- 일정 요청 처리 — *비즈니스 규칙상 승인 후에만* ([open-decisions.md](./open-decisions.md) 참조)

**금지**:

- 학원 전체 수익 조회
- 다른 강사의 학생 조회
- 수강료 편집
- pass 강제 갱신
- 역할·권한 관리

### Student (Confirmed)

**접근 범위**: 본인 데이터만

**조회 가능**: 다음 수업, 전체 일정, 사용·잔여 회차, 담당 강사, 결제 안내, 과거 수업·pass 이력, 일정 변경 요청 상태

**편집 금지**: 수업 상태, 사용·잔여 회차, 수강료, pass, 결제 상태

---

## 4. 회차권(Pass) 규칙

### Confirmed

- **ID 형식**: `V-S006-001` → 갱신 시 `V-S006-002` (학생·과목별 시퀀스)
- **상태**: `reserved`, `active`, `completed`, `expired`, `cancelled` (최소)
- **이력 보존**: 이전 pass는 덮어쓰기·물리 삭제 금지
- **단일 active**: 동일 학생·과목에 active pass는 하나만
- **reserved**: 동일 학생·과목에 reserved 다음 pass는 **최대 하나** (exactly one vs at most one 세부는 [open-decisions.md](./open-decisions.md) OD-10)
- **UI**: 현재 active pass를 관리 UI에서 최우선 표시
- **수업 수**: 주 1회 상품 기본 4회, 주 2회 기본 8회; 10·12회 등 확장 가능

### Planned

- pass 갱신 트랜잭션 및 idempotency 구현 (Phase 4)
- reserved → active 자동 전환 (마지막 차감 수업 완료 시)

### Unresolved

- pass 만료일 필수 여부
- cancelled pass 재활성화 가능 여부
- reserved pass를 정확히 1개로 제한할지 ([open-decisions.md](./open-decisions.md))

---

## 5. 사용·잔여 회차 규칙

### Confirmed

**사용자 직접 입력·편집 불가.** 소스 오브 트루스는 **수업 상태**입니다.

| 구분 | 상태 |
|------|------|
| 차감 대상 (deductible) | `completed`, `same_day_cancelled`, `makeup_completed` |
| 비차감 (non-deductible) | `scheduled`, `postponed`, `advance_cancelled`, `teacher_cancelled`, `academy_closed` |

**계산**:

```
used count = deductible 상태 수업 수
remaining count = 총 등록 수업 수 - used count
```

**거부해야 하는 불가능 상태**:

- total 4 / used 0 / remaining 0
- total 4 / used 5
- remaining count < 0

### Unresolved

- completed 수업을 비차감 상태로 되돌릴 수 있는지 ([open-decisions.md](./open-decisions.md))

---

## 6. 수업·일정 규칙

### Confirmed

- **pass마다 독립적인 수업 레코드**
- **업무 시간대**: Asia/Seoul

**수업 필수 필드**:

| 필드 | 설명 |
|------|------|
| pass | 소속 회차권 |
| student | 학생 |
| course | 과목 |
| assigned teacher | 담당 강사 |
| lesson sequence number | pass 내 순번 (pass 내 유일) |
| scheduled date/time | 예정 일시 |
| actual date/time | 실제 일시 |
| status | 수업 상태 |
| deduction result | 상태에서 파생 |
| change reason | 변경 사유 |
| lesson memo | 수업 메모 |
| created_at, updated_at | 타임스탬프 |

**고정 일정 배치 기준 (사용)**:

- pass 또는 schedule slot에 설정된 **요일·로컬 시간**

**고정 일정 배치 기준 (사용 금지)**:

- 첫 실제 수업일
- 연기된 수업일
- 수동 재배치된 수업일

**연쇄 재배치**:

- 연기 시 이후 미완료 수업을 선택적으로 순서 이동 가능
- **완료된 수업은 자동 이동 금지**
- 사용자 직접 변경 vs 연쇄 자동 이동 구분 필수

### Unresolved

- pass당 고정 schedule slot 복수 허용 여부
- 보강 수업과 원본 취소 수업 연결 방식 ([open-decisions.md](./open-decisions.md))

---

## 7. 결제·갱신 규칙

### Confirmed

**결제 완료 시 단일 PostgreSQL 트랜잭션** (모두 성공 시에만 commit):

1. 이전 pass 상태 갱신
2. 이전 pass·수업 이력 보존
3. 다음 pass 시퀀스 생성
4. 신규 pass 생성
5. 4·8·또는 설정된 수만큼 수업 생성
6. used count = 0
7. remaining count = 설정된 총 수
8. SMS 알림 상태 리셋
9. 결제를 신규 pass에 연결
10. commit

- **실패 시 전체 rollback**
- **멱등성**: 동일 결제로 두 pass 생성 금지; 고유 payment reference 또는 idempotency key 사용

**선결제 (현재 pass 미완료)**:

- 다음 pass를 `reserved`로 생성
- 현재 pass의 **마지막 deductible 수업** 완료 후 `active` 전환

### Unresolved

- 환불 시 active/reserved pass 처리 ([open-decisions.md](./open-decisions.md))
- 수강료 기준 금액 저장 위치 및 pass/payment 스냅샷 여부 ([open-decisions.md](./open-decisions.md))

---

## 8. SMS 알림 규칙

### Confirmed — 상태

`normal`, `scheduled`, `target`, `exhausted_unsent`, `sent`

### Confirmed — 전환 규칙

| 조건 | 상태 |
|------|------|
| remaining = 1, 알림일 이전 | `scheduled` |
| 마지막 수업 하루 전부터 | `target` |
| remaining = 0, 미발송 | `exhausted_unsent` |
| 사용자 수동 발송 확인 | `sent` |

### MVP Inclusions

- SMS 메시지 텍스트 복사
- 수동 발송 확인

### MVP Exclusions

- 외부 SMS API 연동

---

## 9. 주요 화면

### Confirmed — Planned screens

| 화면 | 주요 내용 |
|------|-----------|
| Owner dashboard | 재원 학생, active pass, 예상 월 수강료, 당월 입금, 미수금, 오늘 수업, SMS 대상·예약·미발송, 잔여 1회 학생 |
| Today's lessons | 시간, 학생, 과목, 강사, 상태, 메모 |
| Weekly schedule | 고정 요일·시간 기준, 강사·과목 필터, 학생 검색, 모바일 리스트 |
| Student detail (Owner/Teacher) | 프로필, 담당 강사, active pass, 사용·잔여, 다음 수업, 고정 일정, 수업·결제·SMS·이전 pass, 상담·수업 메모 |
| Student page (Student) | 다음 수업, 잔여 회차, 전체 일정, 강사, 결제 안내, 일정 변경 요청 |

### Confirmed — 성능 (Today's lessons 상태 변경)

한 수업 상태 변경은 **다음만** 갱신:

- 해당 수업
- 해당 pass 계산
- 해당 학생 데이터
- 필요 SMS 상태
- 필요 대시보드 카운터

**금지**: 전체 학원 재로드·재계산

---

## 10. 데이터 모델 방향

### Confirmed — 최소 테이블

`profiles`, `students`, `teachers`, `courses`, `passes`, `lessons`, `schedule_slots`, `payments`, `sms_notifications`, `schedule_change_requests`, `lesson_notes`, `audit_logs`

### Confirmed — 원칙

- PostgreSQL = 단일 진실 공급원
- pass ID 유일
- pass 내 lesson sequence number 유일
- 수업은 유효한 student + pass 없이 존재 불가
- passes, lessons, payments **물리 삭제 금지**
- 중요 변경은 audit_logs에 이전·신규 값 기록
- service role key 브라우저 노출 금지
- 모든 애플리케이션 테이블 RLS 적용 (구현 Phase)

### Unresolved

- ERD 상세, 컬럼 타입, 인덱스 (Phase 0)
- RLS 정책 상세 (Phase 0)

---

## 11. 성능 원칙

### Confirmed

단일 수업 상태 변경이 다음을 유발하면 안 됨:

- 전체 학생 재로드
- 전체 pass 재계산
- 전체 일정 재생성
- 전체 대시보드 재생성
- 전체 페이지 새로고침
- 동일 데이터 중복 요청

**Optimistic UI**: 실패 시 즉시 이전 상태 복원 + 오류 표시할 때만 허용

---

## 12. 개발 프로세스

### Confirmed

1. 요구사항 분석 → 2. 영향 분석 → 3. 데이터 모델 검토 → 4. 구현 계획 → 5. 최소 범위 수정 → 6. Type check → 7. Lint → 8. Unit tests → 9. Integration tests → 10. Browser verification → 11. Git commit → 12. Completion report

**금지**: 대규모 무관 리팩터링, 근본 데이터 흐름 없이 표시 숫자만 변경, 미검증 완료 보고

---

## 13. 로드맵 개요

상세는 [roadmap.md](./roadmap.md) 참조.

| Phase | 초점 |
|-------|------|
| 0 | 요구사항, 권한, 데이터 모델, ERD, 상태 전이, 갱신 흐름, RLS, 테스트 시나리오 |
| 1 | Next.js, Supabase, Auth, 역할, 레이아웃, PWA |
| 2 | 학생, 강사, 과목, 고정 일정, 학생 상세 |
| 3 | 오늘 수업, 상태 변경, 회차 계산, 수업 메모 |
| 4 | 결제, pass 갱신, reserved pass, 이력 |
| 5 | SMS, 대시보드, 통계, 감사 |
| 6 | Google Sheets 마이그레이션, 병행 운영, 전환 |

---

## 14. MVP 범위 요약

### In scope (Confirmed direction)

- Owner / Teacher / Student 역할
- Pass lifecycle 및 이력
- Lesson status 기반 회차 계산
- 결제·갱신 트랜잭션 (Phase 4)
- SMS 텍스트 복사 + 수동 확인 (Phase 5)
- PWA

### Out of scope for MVP

- App Store / Google Play
- 외부 SMS API
- (기타 Phase 6 이전 마이그레이션)

---

## 15. 미결정 사항

[open-decisions.md](./open-decisions.md)에 상세 목록. **누락 규칙을 임의로 발명하지 마세요.**

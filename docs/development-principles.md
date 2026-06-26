# Development Principles — REVE ACADEMY OS

모든 구현·리뷰·에이전트 작업이 따를 개발 원칙입니다.

---

## 1. Data Integrity (데이터 무결성)

### Single Source of Truth

- **PostgreSQL**이 모든 비즈니스 데이터의 단일 진실 공급원입니다.
- UI 상태, 클라이언트 캐시, Google Sheets 잔재는 authoritative source가 될 수 없습니다.

### Derived, Not Edited

- **used count**, **remaining count**, **deduction result**는 사용자 입력 필드가 아닙니다.
- **lesson status**에서 파생·계산합니다.
- 차감 대상: `completed`, `same_day_cancelled`, `makeup_completed`
- 비차감: `scheduled`, `postponed`, `advance_cancelled`, `teacher_cancelled`, `academy_closed`

### Immutability of History

- **passes**, **lessons**, **payments**는 물리 삭제(硬删除)하지 않습니다.
- pass 갱신 시 이전 pass·수업은 이력으로 보존합니다.
- 상태 전이(예: `active` → `completed`)는 허용; 레코드 소멸은 금지.

### Impossible States

다음과 같은 상태는 애플리케이션·DB 제약으로 **거부**합니다:

- `remaining`과 `used`/`total` 불일치 (예: total 4, used 0, remaining 0)
- `used > total`
- `remaining < 0`

### Business Time

- 날짜·시간 비즈니스 규칙은 **Asia/Seoul** 기준입니다.

---

## 2. Authorization and RLS

### Defense in Depth

권한은 다음 **세 계층** 모두에서 강제합니다:

1. **PostgreSQL RLS** — 최종 방어선
2. **서버/API 로직** — 비즈니스 규칙과 함께 검증
3. **UI** — UX 및 오류 방지 (UI만으로는 불충분)

### Role Boundaries

| Role | 원칙 |
|------|------|
| Owner | 전체 데이터 |
| Teacher | 배정 학생·수업만 |
| Student | 본인 데이터만 |

- Teacher는 학원 수익, 타 강사 학생, 수강료·pass 강제 갱신, 권한 관리 불가
- Student는 상태·회차·수강료·pass·결제 편집 불가

### Secrets

- **Supabase service role key**는 서버 전용; 브라우저·클라이언트 번들에 포함 금지
- 모든 애플리케이션 테이블에 RLS 정책 적용 (구현 시)

---

## 3. Performance

### Scoped Updates

**한 레코드 변경** (예: 수업 상태)은 다음 범위만 갱신합니다:

- 해당 lesson
- 해당 pass (used/remaining 재계산)
- 해당 student 관련 파생 데이터
- 영향받는 SMS 상태
- 필요한 dashboard counter

### Prohibited Patterns

다음은 **금지**합니다:

- 전체 학생 목록 재로드
- 전체 pass 일괄 재계산
- 전체 schedule 재생성
- 전체 dashboard 재생성
- 불필요한 full page refresh
- 동일 데이터에 대한 중복 concurrent request

### Optimistic UI

- 사용 가능 조건: 실패 시 **즉시** 이전 상태 rollback + 사용자에게 오류 표시
- 실패를 무시하거나 stale optimistic state를 유지하지 않음

---

## 4. Transactions

### Payment and Pass Renewal

결제 완료 → pass 갱신은 **단일 PostgreSQL 트랜잭션**으로 처리:

1. 이전 pass 상태 갱신
2. 이력 보존 (데이터 삭제 없음)
3. 다음 pass ID 시퀀스
4. 신규 pass 생성
5. N개 lesson 생성 (4, 8, 또는 설정값)
6. used = 0, remaining = total
7. SMS 상태 리셋
8. payment ↔ new pass 연결
9. commit

**어느 단계든 실패 시 전체 rollback.**

### Reserved Pass Activation

- 선결제 시 `reserved` pass 생성
- 현재 pass의 마지막 **deductible** lesson 완료 후 `active` 전환
- 해당 전환도 트랜잭션·상태 전이 규칙을 따름

---

## 5. Idempotency

### Payment Processing

- 동일 결제가 **두 번째 pass를 생성하면 안 됩니다.**
- **고유 payment reference** 또는 **idempotency key** 필수
- 재시도·네트워크 중복 시에도 안전해야 함

### Implementation Guidance

- DB unique constraint + upsert/no-op 패턴 검토
- API layer에서 idempotency key 검증
- audit_logs에 중복 시도 기록 고려

---

## 6. Audit Logs

### When to Audit

중요 변경은 `audit_logs`에 기록:

- **previous value**와 **new value**
- 변경 주체, 타임스탬프, 대상 엔티티

### Examples

- pass 상태 전이
- lesson status 변경
- 결제·갱신
- 권한 변경
- 수강료 관련 변경 (Owner)

---

## 7. Testing

### Required Layers

| Layer | Tool | Focus |
|-------|------|-------|
| Unit | Vitest 또는 Jest | 회차 계산, 상태 전이, idempotency logic |
| Integration | Vitest/Jest + DB | 트랜잭션, RLS, renewal flow |
| E2E | Playwright | 역할별 화면, critical paths |

### Test Scenarios (Phase 0 deliverable)

- pass 갱신 001 → 002
- 선결제 reserved → active
- lesson status → used/remaining
- impossible state rejection
- idempotent payment
- role boundary (Teacher/Student)

### Policy

- **검증되지 않은 작업을 complete로 보고하지 않음**
- Type check + lint + tests + browser verification 후 commit

---

## 8. Minimum-Change Policy

### Scope Discipline

- 요청된 기능·버그에 **최소 범위**로만 수정
- 대규모 무관 리팩터링 금지
- 표시 숫자만 패치하지 말고 **데이터 흐름** 수정

### Feature Development Order

1. Requirements analysis
2. Impact analysis
3. Data model review
4. Implementation plan
5. Minimum-scope modification
6. Type check → Lint → Unit → Integration → Browser
7. Git commit
8. Completion report

---

## 9. Git Checkpoints

### Commits

- 논리적 단위로 commit (사용자 요청 시)
- commit message는 **why** 중심
- Phase 완료 또는 검증된 milestone마다 checkpoint

### Branches

- main/master 보호 정책은 팀 합의 후 적용 (Phase 1+)

### Tags

- 릴리스·마일스톤 tag는 명시적 요청 시에만

---

## 10. Rollback Policy

### Application Rollback

- DB migration과 함께 배포된 변경은 **forward-fix** 우선 검토
- destructive migration rollback script는 Phase 0 설계 시 명시

### Transaction Rollback

- 결제·갱신 실패 → PostgreSQL transaction rollback (자동)
- partial success 상태를 허용하지 않음

### Data Rollback

- pass/lesson/payment **물리 삭제로 rollback하지 않음**
- compensating transaction (상태 `cancelled`, audit log) 사용

### Deployment Rollback

- PWA: 이전 빌드 재배포 가능하도록 versioning 유지 (Phase 1+)

---

## Related Documents

- [project-brief.md](./project-brief.md)
- [roadmap.md](./roadmap.md)
- [open-decisions.md](./open-decisions.md)
- [../AGENTS.md](../AGENTS.md)

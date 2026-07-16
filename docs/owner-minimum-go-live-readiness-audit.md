# Minimum Owner Go-Live Readiness Audit (Phase 2B-2A)

Status: **audit complete — not go-live ready**

This document records a read-only operational readiness audit of REVE Academy OS at the Phase 2B-1 runtime-verified checkpoint. It does **not** substitute for production cutover. No application behavior was changed during this audit except documentation.

---

## 1. Starting branch, HEAD, tag, and working-tree status

| Item | Value |
|------|-------|
| Branch | `main` |
| HEAD | `0ee3cad6b8f57586e922ee95c66e9f5616f56747` |
| Runtime tag | `phase-2b1-owner-teachers-master-data-runtime-verified` → `0ee3cad...` |
| Implementation tag (teachers) | `phase-2b1-owner-teachers-master-data-implemented` → `08987f2...` |
| Working tree at audit start | clean |
| `origin/main` | matches local `main` at `0ee3cad...` |
| Audit date | 2026-07-16 |

---

## 2. Existing feature inventory

### Owner routes and navigation

| Route | Nav label | Capability |
|-------|-----------|------------|
| `/login` | — | Owner email/password login |
| `/dashboard` | 대시보드 | Today-scoped read summary |
| `/lessons/today` | 오늘의 수업 | Read + lesson status mutation |
| `/schedule` | 주간 시간표 | Read-only weekly fixed schedule |
| `/schedule-requests` | 일정 변경 요청 | Review / apply / cascade schedule changes |
| `/sms` | SMS 발송 확인 | Read + copy message + confirm sent |
| `/refunds` | 환불 처리 | Read eligible payments + full refund |
| `/students` | 학생 | Read-only list/search |
| `/students/[studentId]` | (detail link) | Read-only profile, pass usage, schedule, lessons, operational history |
| `/teachers` | 강사 | Create / update / activate / deactivate teachers |

**Implementation update (Phase 2B-2B1):** Owner UI now includes student create/edit/status and initial enrollment. See [manual-verification-owner-student-initial-enrollment.md](./manual-verification-owner-student-initial-enrollment.md). Payment record UI and pass renewal UI remain open (Phase 2B-2B2).

### Application RPC wiring (`lib/data`)

| Wired to Owner UI | RPC |
|-------------------|-----|
| Yes | `reve_owner_get_pass_usage`, `reve_transition_lesson_status`, `reve_owner_confirm_sms_sent`, `reve_process_payment_refund`, `reve_owner_review_schedule_change_request`, `reve_owner_apply_schedule_change_request`, `reve_owner_cascade_schedule_change_request`, `reve_owner_create_teacher`, `reve_owner_update_teacher`, `reve_owner_set_teacher_active` |
| **No UI** | `reve_owner_create_student`, `reve_owner_update_student`, `reve_owner_set_student_active`, `reve_owner_create_initial_enrollment`, `reve_complete_payment_and_renew_pass`, `reve_activate_reserved_pass`, `reve_owner_replace_pass_schedule_slots`, `reve_owner_create_course`, `reve_owner_create_course_product`, `reve_correct_lesson_status` |

### Automated test coverage (baseline at audit)

| Layer | Coverage |
|-------|----------|
| Vitest unit | Today lessons, students list, pass summary, SMS, refunds, schedule change, teachers, weekly schedule, login |
| Vitest integration | Owner queries (lessons, pass usage, SMS, refunds, schedule requests); owner teachers |
| pgTAP | 888 standard assertions across trusted RPC contracts |
| Concurrency | SMS sent (1), payment refund (2) |
| Playwright | 41 tests across Owner Alpha, weekly schedule, SMS, refunds, schedule requests, student detail, teachers |
| Manual runtime | Phase 1A, 1B-1–1B-6, 2B-1 signed off (2026-07-03 through 2026-07-14) |

---

## 3. End-to-end workflow results (24 steps)

Legend: **Auto** = verified automated test; **Manual** = prior Owner browser sign-off; **Inspect** = source/migration review only; **Gap** = not executable through current Owner UI.

| # | Step | Result | Evidence |
|---|------|--------|----------|
| 1 | Owner signs in | **Pass** | Manual 1A; E2E `owner-alpha.spec.ts`; unit `login-form.test.tsx` |
| 2 | Create/select teacher | **Pass** | Manual 2B-1; E2E `owner-teachers.spec.ts`; integration `owner-teachers.test.ts` |
| 3 | Create/select student | **Gap (P0)** | Select: `/students` read (E2E mobile). **Create: no UI** — RPC `reve_owner_create_student` pgTAP only |
| 4 | Assign student to teacher and course | **Gap (P0)** | RPC `reve_owner_create_initial_enrollment` pgTAP only; no Owner UI |
| 5 | Create/activate 4-lesson weekly pass | **Gap (P0)** | Enrollment / payment RPCs only; seed creates Alpha 4-lesson pass |
| 6 | Four independent lessons created | **Partial** | pgTAP `phase_0b3b2b3c_initial_enrollment.test.sql`; not browser-created |
| 7 | Fixed weekly schedule position | **Pass (read)** | E2E `owner-weekly-schedule.spec.ts`; **edit UI gap** — `reve_owner_replace_pass_schedule_slots` unwired |
| 8 | Today Lessons page | **Pass** | Manual 1A; E2E `owner-alpha.spec.ts` |
| 9 | Change lesson to completed/normal | **Pass** | Manual 1A; E2E status change; pgTAP `phase_0b3b2b1_lesson_transitions.test.sql` |
| 10 | Only affected lesson/pass updated | **Pass** | E2E failed-mutation rollback; scoped panel update (no full refresh) |
| 11 | Used/remaining counts | **Pass** | E2E Alpha used=1 remaining=3; pgTAP `phase_1a_owner_read_projections.test.sql` |
| 12 | Student detail reflects change | **Pass** | Manual 1A; E2E `owner-alpha.spec.ts`, `owner-student-detail.spec.ts` |
| 13 | Move/cancel future lesson; verify deduction | **Partial** | pgTAP deduction matrix; **no dedicated E2E/manual for cancel/postpone** |
| 14 | Complete final deductible lesson | **Partial** | pgTAP reserved-pass activation; **no E2E** |
| 15 | SMS status and message | **Pass** | Manual 1B-2; E2E `owner-sms.spec.ts`; pgTAP SMS confirmation |
| 16 | Record payment | **Gap (P0)** | RPC `reve_complete_payment_and_renew_pass` pgTAP only; **no Owner UI** |
| 17 | Old pass/lessons preserved | **Pass (DB)** | pgTAP payment renewal; student detail read shows prior pass |
| 18 | Next pass number generated | **Pass (DB)** | pgTAP `build_pass_public_code` assertions |
| 19 | New pass 4 or 8 lessons | **Pass (DB)** | pgTAP initial enrollment + payment renewal |
| 20 | Duplicate payment → no duplicate passes | **Partial** | pgTAP idempotency replay; **no app/integration/E2E test** |
| 21 | Audit log entries | **Partial** | pgTAP across RPCs; integration teacher audit rows; **no audit viewer UI** |
| 22 | Reload persistence | **Pass (scoped)** | E2E reload for lessons, teachers; **not for payment/enrollment** |
| 23 | ~390px mobile layouts | **Pass (operational pages)** | E2E 390px: alpha, teachers, weekly schedule, SMS, refunds, schedule requests, student detail |
| 24 | No blocking console/network errors | **Partial** | Manual checklists; teachers empty-state E2E asserts console/page/network; **no global Playwright gate** |

**Verdict:** Steps 1–2, 7–12, 15, 17–19, 22–23 are **operationally usable on existing seeded data**. Steps 3–6 and 16–20 require **SQL/RPC or seed** today and **block real academy onboarding** through the UI alone.

---

## 4. Four-lesson pass results

| Aspect | Status | Evidence |
|--------|--------|----------|
| DB: 4 lessons from enrollment | **Pass** | `phase_0b3b2b3c_initial_enrollment.test.sql` |
| DB: weekly frequency 1 schedule slot | **Pass** | Same + `phase_0b3b2b3d1_pass_schedule_management.test.sql` |
| DB: payment renewal creates next 4-lesson pass | **Pass** | `phase_0b3b2b2_payment_renewal.test.sql` |
| Seed fixture | **Pass** | `scripts/seed-owner-alpha.sql` — Alpha Student, 4-lesson product, 1 slot, 4 lessons |
| Owner UI: create 4-lesson pass | **Gap** | No enrollment/payment UI |
| Browser E2E: full 4-lesson lifecycle | **Partial** | Alpha E2E covers lesson 1 completion + counts on **seeded** pass only |

---

## 5. Eight-lesson pass results

| Aspect | Status | Evidence |
|--------|--------|----------|
| DB: 8 lessons, 2 schedule slots, weekly_frequency=2 | **Pass** | `phase_0b3b2b3c_initial_enrollment.test.sql` (`PIANO-8`) |
| DB: twice-weekly cascade rescheduling | **Pass** | `phase_0b3b2b3d2b_lesson_cascade_rescheduling.test.sql` |
| DB: 8-lesson product catalog | **Pass** | `phase_0b3b2b3b_course_product_management.test.sql` |
| Seed fixture | **Gap** | Alpha seed is 4-lesson / once-weekly only |
| Owner UI | **Gap** | No enrollment UI |
| Browser E2E | **Gap** | No end-to-end 8-lesson / twice-weekly test |

---

## 6. Payment and renewal results

| Aspect | Status | Evidence |
|--------|--------|----------|
| Record payment + renew pass (RPC) | **Pass (DB)** | `reve_complete_payment_and_renew_pass`; pgTAP payment renewal |
| Idempotent replay | **Pass (DB)** | pgTAP: no duplicate pass/lessons/SMS on replay |
| Owner refund UI | **Pass** | `/refunds`; E2E + integration |
| Owner payment **record** UI | **Gap (P0)** | Not wired |
| App-layer idempotency test | **Gap (P1)** | No integration/E2E for duplicate payment submission |
| Student payment history (read) | **Pass** | `/students/[studentId]` operational history |

---

## 7. SMS status results

| Aspect | Status | Evidence |
|--------|--------|----------|
| List eligible notifications | **Pass** | `/sms`; integration + E2E |
| Copy message body | **Pass** | E2E `owner-sms.spec.ts` |
| Confirm sent (manual external send) | **Pass** | RPC `reve_owner_confirm_sms_sent`; concurrency pgTAP |
| Automatic SMS API | **Deferred** | MVP design: Owner copies and sends externally |
| Exhausted → target transition | **Pass (DB)** | pgTAP; not re-verified in this audit browser session |

---

## 8. Audit-log results

| Aspect | Status | Evidence |
|--------|--------|----------|
| RPC-internal append on trusted mutations | **Pass (DB)** | pgTAP: lesson transitions, enrollment, payment renewal, refund, schedule change, teacher CRUD |
| Integration: teacher mutations | **Pass** | `tests/integration/owner-teachers.test.ts` |
| Owner audit log viewer | **Gap (P1 visibility)** | No UI route |
| Operator can verify audit without SQL | **Gap** | Requires DB access or pgTAP |

---

## 9. RLS and security findings

| Finding | Severity | Notes |
|---------|----------|-------|
| App uses anon key only; no service role in client bundle | **Pass** | `lib/supabase/client.ts`, `server.ts` |
| Owner layout enforces `role=owner` | **Pass** | `lib/auth/owner-session.ts`, `(owner)/layout.tsx` |
| Mutations via `SECURITY DEFINER` Owner RPCs | **Pass** | Trusted operation pattern |
| `reve_bootstrap_first_owner` service_role only | **Pass** | pgTAP + migration grants |
| Teacher/Student auth users in seed only; no alternate portals | **Pass (scope)** | Reduces attack surface for minimum go-live |
| Production RLS enforcement | **Inspect** | Policies exist in migrations; **not validated on hosted Supabase** (no production env connected) |
| Physical DELETE blocked on lessons/passes | **Pass (DB)** | Historical protection triggers |

---

## 10. Production deployment readiness

| Item | Status | Finding |
|------|--------|---------|
| Deployment config (Vercel/Docker/CI) | **Gap (P0)** | Only `next.config.ts`; no `vercel.json`, Dockerfile, deploy workflow |
| Production env template | **Gap (P0)** | `.env.local.example` local-only; no `.env.production.example` |
| Hosted Supabase assumptions | **Gap (P0)** | Documented for local dev only; no production project runbook |
| Owner bootstrap in production | **Gap (P0)** | `reve_bootstrap_first_owner` documented in migrations; **no operator runbook** |
| HTTPS / cookie domain | **Gap (P0)** | Middleware redirect pattern exists; production cookie settings not configured |
| Error logging / monitoring | **Gap (P1)** | UI `mapDatabaseError` only; no Sentry/Datadog/log drain |
| Migration procedure | **Pass (local)** | `supabase/migrations/` + `docs/database-migration-plan.md` + verify scripts |

---

## 11. Backup and recovery readiness

| Item | Status | Finding |
|------|--------|---------|
| Backup policy mention | **Partial** | `docs/database-migration-plan.md` references backup before destructive changes |
| Dedicated backup/restore runbook | **Gap (P0)** | No documented RPO/RTO, Supabase backup steps, or restore drill |
| Point-in-time recovery procedure | **Gap (P0)** | Not documented in repository |

---

## 12. PWA and mobile readiness

| Item | Status | Finding |
|------|--------|---------|
| `manifest.webmanifest` | **Present** | `public/manifest.webmanifest`; linked in `app/layout.tsx` |
| Service worker / offline | **Gap (P2)** | Phase 1 deliverable incomplete; installability limited |
| Asia/Seoul timezone in app | **Pass** | `lib/domain/format.ts` — `getSeoulDayBounds`, `formatDateTimeSeoul` |
| Operational pages ~390px | **Pass (automated)** | Playwright 390px on audited Owner routes |
| Dashboard 390px dedicated E2E | **Gap (P2)** | Covered indirectly via alpha mobile test on `/students` |

---

## 13. P0 issues (blocks real use)

| ID | Issue |
|----|-------|
| P0-1 | **No Owner UI to create students** — cannot onboard new students without SQL/RPC (`reve_owner_create_student`). |
| P0-2 | **No Owner UI for initial enrollment** — cannot assign teacher + course product + weekly schedule and create first pass/lessons (`reve_owner_create_initial_enrollment`). |
| P0-3 | **No Owner UI to record payment and renew pass** — cannot complete the renewal loop in browser (`reve_complete_payment_and_renew_pass`). |
| P0-4 | **No production deployment configuration or runbook** — repository cannot be cut over to a hosted environment from documented steps alone. |
| P0-5 | **No production Owner bootstrap procedure** — first Owner must be created via service_role RPC without documented operator steps. |
| P0-6 | **No backup/restore runbook** — operational recovery after failure is undefined. |

---

## 14. P1 issues (incorrect or unrecoverable operational data risk)

| ID | Issue |
|----|-------|
| P1-1 | Payment idempotency enforced in DB but **not tested at application layer** — duplicate UI submission risk untested. |
| P1-2 | Course/product catalog manageable only via RPC/SQL — enrollment without UI risks wrong product/schedule JSON. |
| P1-3 | Pass fixed schedule changes require schedule-change workflow or RPC — no direct slot replacement UI; operational error path unclear for staff. |
| P1-4 | **No audit log viewer** — operators cannot confirm mutations without database access. |
| P1-5 | Lesson cancel/postpone deduction and final-lesson reserved activation **not browser-verified** end-to-end. |
| P1-6 | No centralized production error logging — incidents may go unnoticed. |

---

## 15. P2 issues (usability; does not block minimum use on seeded data)

| ID | Issue |
|----|-------|
| P2-1 | PWA service worker missing — limited install/offline experience. |
| P2-2 | No repository-wide Playwright console/network error gate. |
| P2-3 | 8-lesson twice-weekly pass not covered by seed or browser E2E. |
| P2-4 | README still describes “Phase 1A active” — documentation drift. |
| P2-5 | Roadmap “Deferred after Owner Alpha” section stale (SMS/refund/schedule UI now implemented). |

---

## 16. Deferred features (unnecessary for minimum go-live scope)

Explicitly out of minimum go-live scope per audit charter:

- Teacher login and Teacher-facing pages
- Student login and Student-facing pages
- Schedule change request **submission** UI (Owner **review** exists; defer for minimum scope)
- Automatic SMS sending / external SMS API integration
- Card payment integration
- Accounting integration
- Advanced analytics / revenue KPIs
- Multi-branch support
- App-store distribution
- AI features
- Nonessential UI redesign
- Bulk import (unless manual entry proven impossible)
- `reve_correct_lesson_status` correction UI
- `correct_cancelled_pass`, re-enrollment, refund reversal workflows
- Audit log viewer (recommended before production, but deferrable for alpha ops with SQL access)

---

## 17. Exact recommendation for the next implementation phase

### Recommended single phase: **Phase 2B-2B — Owner Student Enrollment and Payment Operations**

Implement the **smallest coherent Owner UI slice** that removes **all P0 application blockers (P0-1, P0-2, P0-3)** and the most serious **P1 data-risk gaps (P1-1, P1-2)** by wiring existing trusted RPCs only:

1. **Student master data UI** (`/students` create/update/deactivate) — mirror Phase 2B-1 teachers pattern using `reve_owner_create_student`, `reve_owner_update_student`, `reve_owner_set_student_active`.
2. **Initial enrollment UI** — form for teacher + course product selection + weekly schedule JSON + start date calling `reve_owner_create_initial_enrollment` (supports 4-lesson weekly and 8-lesson twice-weekly products).
3. **Payment record UI** — record completed payment with idempotency key calling `reve_complete_payment_and_renew_pass`.
4. **Read-only course/product pickers** for enrollment (SELECT lists; no new catalog CRUD required in this slice).
5. **Integration + Playwright** coverage for enrollment, payment idempotency replay, and 4/8-lesson lesson counts.
6. **Verification script** `scripts/verify_phase_2b2b.ps1`.

**Parallel operational prerequisite (not a second app phase):** document production deployment, Owner bootstrap, env separation, and backup/restore in a dedicated ops runbook to address P0-4 through P0-6 before hosted cutover.

Do **not** start Teacher portal, Student portal, automatic SMS, or analytics in this phase.

---

## 18. Proposed real-use acceptance checklist

Use after Phase 2B-2B implementation and production ops runbook exist:

| # | Action | Expected result |
|---|--------|-----------------|
| 1 | Production-like env: hosted Supabase + deployed app + HTTPS login | Owner session established |
| 2 | Bootstrap first Owner (documented procedure) | Single active Owner profile |
| 3 | Create teacher via `/teachers` | Teacher appears; audit row |
| 4 | Create student via `/students` | Student appears; audit row |
| 5 | Enroll student: 4-lesson weekly product + 1 schedule slot | Pass active; 4 lessons; slot visible on `/schedule` |
| 6 | Enroll second student: 8-lesson twice-weekly + 2 slots | 8 lessons; 2 slots |
| 7 | Complete lessons on `/lessons/today` | Used/remaining correct on student detail |
| 8 | Cancel/postpone future lesson | Deduction rules match domain spec |
| 9 | Complete final lesson on pass | Reserved pass activation / SMS target state |
| 10 | Confirm SMS on `/sms` | Status `sent`; message matched snapshot |
| 11 | Record payment with idempotency key | New pass; old pass preserved; correct sequence number |
| 12 | Replay same payment idempotency key | No duplicate pass |
| 13 | Process refund on `/refunds` if needed | Refund row; pass state correct |
| 14 | Reload all touched pages | Persistence confirmed |
| 15 | 390px check on enrollment, today, students, schedule, SMS | No horizontal overflow |
| 16 | Console/network | No blocking errors |
| 17 | Backup restore drill (documented) | Restored DB accepts login and shows data |

---

## Audit verification run (2026-07-16)

Baseline unchanged-application verification via `scripts/verify_phase_2b1.ps1` — **exit 0**:

| Step | Result |
|------|--------|
| `npm run typecheck` | Pass |
| `npm run lint` | Pass |
| Vitest | **90/90** |
| Production build | Pass |
| pgTAP standard | **888** |
| SMS concurrency | **1** |
| Refund concurrency | **2** |
| db lint baseline | 74 findings, delta 0 |
| Playwright full | **41/41** |
| Playwright owner-teachers | **12/12** |
| Phase 1A + 1B-1–1B-6 regressions | Pass |

**Not re-run in this audit:** Operator manual browser session for the full 24-step workflow on 2026-07-16 (prior phase sign-offs through 2026-07-14 remain authoritative for implemented surfaces).

---

## Overall go-live readiness verdict

**Not ready for real academy operations without SQL/RPC assistance.**

The database layer is production-grade and extensively tested. The Owner UI supports **daily operations on pre-seeded or externally created data** (today’s lessons, SMS confirm, refunds, schedule-change review, teacher CRUD, read views). The **onboarding and renewal chain** (student create → enrollment → payment → next pass) is **not available in the browser** and **production cutover procedures are undocumented**.

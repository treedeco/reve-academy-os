# Owner Schedule Change Requests — Manual Browser Verification Checklist

Status: **passed — Owner runtime verification complete**

Automated Playwright tests do **not** substitute for this checklist. This record reflects **Owner-provided** browser verification on commit `33aca1e39d9d43a45312ddfc5d54a1e0fc263dd8` (tag `phase-1b4-owner-schedule-change-request-review-implemented`).

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| Schedule requests route | `http://127.0.0.1:3000/schedule-requests` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | `owner-alpha@test.local` / `OwnerAlphaTest123!` |

## Verification environment

| Item | Value |
|------|-------|
| Supabase | Local (`npx supabase start`, `db reset`, `npm run db:seed:alpha`) |
| App | `npm run dev` → `http://127.0.0.1:3000` |
| Tested commit | `33aca1e39d9d43a45312ddfc5d54a1e0fc263dd8` |
| Implementation tag | `phase-1b4-owner-schedule-change-request-review-implemented` |
| Runtime verification date | **2026-07-08** |

---

## 12-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Start Supabase local | Services healthy | `npx supabase status` OK | ☑ |
| 2 | Reset DB | Clean schema | `npx supabase db reset` | ☑ |
| 3 | Seed alpha data | Seed script completes | `npm run db:seed:alpha` | ☑ |
| 4 | Start app | Login page loads | `npm run dev` | ☑ |
| 5 | Login as `owner-alpha@test.local` | Redirect to dashboard | Owner session active | ☑ |
| 6 | Open **일정 변경 요청** (`/schedule-requests`) | Page title and nav item visible | Owner-only route | ☑ |
| 7 | Verify actionable requests | Beta (submitted) and Delta (approved) visible | `fetchOwnerScheduleChangeRequests` filter | ☑ |
| 8 | Verify excluded requests | Rejected and applied not listed | No client-side request update | ☑ |
| 9 | Approve submitted request | Approved time + note required; row becomes approved | `reve_owner_review_schedule_change_request` | ☑ |
| 10 | Apply approved request | Confirmation dialog; row removed on success | `reve_owner_apply_schedule_change_request` | ☑ |
| 11 | Reload page | Applied request stays absent; approved/submitted state persisted | Lesson `scheduled_at` updated | ☑ |
| 12 | Console / network | No blocking errors | No 401/403/500 on read/review/apply | ☑ |

**Checklist: 12/12 PASS**

---

## Sign-off

- Verifier: **Owner (REVE)**
- Date: **2026-07-08**
- Browser / device: **Desktop browser; mobile/responsive layout**
- Result: **passed**
- Notes: Owner confirmed PASS for `/schedule-requests` using local Supabase, alpha seed data, and `owner-alpha@test.local`. Verified submitted and approved actionable queues, rejected/applied exclusion, student/course/pass/lesson context display, approve flow with approved time and reason, reject flow with required reason, apply flow with confirmation, scoped UI updates after approve/reject/apply, reload persistence, `/schedule` still loads after apply, and no blocking browser console or server runtime errors.

## Non-blocking observations

- Cascade schedule change UI is out of scope for Phase 1B-4.
- Fixed weekly timetable (`schedule_slots`) is not modified by apply; only lesson `scheduled_at` changes.
- Schedule collision leaves request approved but unapplied (`REVE_SCHEDULE_COLLISION`).

## Remaining risks

- Cascade UI and fixed schedule slot editing remain deferred.
- Append-only `lesson_schedule_changes` history accumulates on repeated apply during local testing; alpha seed uses UPDATE-only reset.

# Owner Student Operational History — Manual Browser Verification Checklist

Status: **passed — Owner runtime verification complete**

Automated Playwright tests do **not** substitute for this checklist. This record reflects **Owner-provided** browser verification on commit `3650eb0e8ce7ab372f6a3be8343f5bdd228bc57e` (tag `phase-1b6-owner-student-operational-history-implemented`).

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| Students route | `http://127.0.0.1:3000/students` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | `owner-alpha@test.local` / `OwnerAlphaTest123!` |

## Verification environment

| Item | Value |
|------|-------|
| Supabase | Local (`npx supabase start`, `db reset`, `npm run db:seed:alpha`) |
| App | `npm run dev` → `http://127.0.0.1:3000` |
| Tested commit | `3650eb0e8ce7ab372f6a3be8343f5bdd228bc57e` |
| Implementation tag | `phase-1b6-owner-student-operational-history-implemented` |
| Runtime verification date | **2026-07-09** |

---

## 12-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Start Supabase local | Services healthy | `npx supabase status` OK | ☑ |
| 2 | Reset DB | Clean schema | `npx supabase db reset` | ☑ |
| 3 | Seed alpha data | Seed script completes | `npm run db:seed:alpha` | ☑ |
| 4 | Start app | Login page loads | `npm run dev` | ☑ |
| 5 | Login as `owner-alpha@test.local` | Redirect to dashboard | Owner session active | ☑ |
| 6 | Open `/students` | Student list loads without errors | Owner-only route | ☑ |
| 7 | Open student detail with operational history | Delta detail page loads | `/students/[studentId]` | ☑ |
| 8 | Verify payment history section | **결제 이력** visible; status, amount, pass, course; no payment buttons | `fetchStudentOperationalHistory.payments` | ☑ |
| 9 | Verify refund history section | Delta empty state; Zeta refund row; no refund buttons | `fetchStudentOperationalHistory.refunds` | ☑ |
| 10 | Verify schedule change request history section | Status, sequence, times, cascade label, reason; no review/apply/cascade buttons | `fetchStudentOperationalHistory.schedule_requests` | ☑ |
| 11 | Verify existing student detail sections | **현재 회차권**, **고정 일정**, **수업 이력** still render; no new write actions | Existing `fetchStudentDetail` unchanged | ☑ |
| 12 | Mobile/responsive layout and runtime errors | Sections readable; no blocking console/network/server errors | `/schedule`, `/sms`, `/refunds`, `/schedule-requests` still accessible | ☑ |

**Checklist: 12/12 PASS**

---

## Expected seed fixtures

| Student | Payments | Refunds | Schedule requests |
|---------|----------|---------|-------------------|
| Delta   | 1 completed | 0 | multiple statuses |
| Beta    | 1 completed | 0 | submitted + rejected |
| Zeta    | 1 refunded | 1 | 0 |
| Gamma   | 0 | 0 | 0 (empty states) |

---

## Sign-off

- Verifier: **Owner**
- Date: **2026-07-09**
- Browser / device: **Desktop browser; mobile/responsive layout**
- Result: **passed**
- Notes: Owner confirmed PASS for student operational history using local Supabase, alpha seed (`npm run db:seed:alpha`), and `owner-alpha@test.local`. Verified student list navigation, student detail rendering, payment history, refund history, schedule change request history, empty states, existing student detail sections, no write actions in history sections, responsive layout, and no blocking console/network/server errors.

## Non-blocking observations

- Operational history sections are read-only; payment creation, refund processing, and schedule request review/apply/cascade remain on their dedicated routes.
- Gamma Student provides empty-state coverage when payment, refund, and schedule request history are all absent.

## Remaining risks

- Owner Alpha login requires `npm run db:seed:alpha` after every `db reset`; credentials are not in migration seed alone.
- Supabase auth may be transiently unavailable immediately after `db reset`; retry after seed if login fails.

# Owner Schedule Change Requests — Manual Browser Verification Checklist

Status: **PENDING — Owner runtime verification not complete**

Automated Playwright tests do **not** substitute for this checklist. Complete each step in a local browser before marking Phase 1B-4 runtime verification.

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
| Implementation tag | `phase-1b4-owner-schedule-change-request-review-implemented` |

---

## 12-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Start Supabase local | Services healthy | `npx supabase status` OK | ☐ |
| 2 | Reset DB | Clean schema | `npx supabase db reset` | ☐ |
| 3 | Seed alpha data | Seed script completes | `npm run db:seed:alpha` | ☐ |
| 4 | Start app | Login page loads | `npm run dev` | ☐ |
| 5 | Login as `owner-alpha@test.local` | Redirect to dashboard | Owner session active | ☐ |
| 6 | Open **일정 변경 요청** (`/schedule-requests`) | Page title and nav item visible | Owner-only route | ☐ |
| 7 | Verify actionable requests | Beta (submitted) and Delta (approved) visible | `fetchOwnerScheduleChangeRequests` filter | ☐ |
| 8 | Verify excluded requests | Rejected and applied not listed | No client-side request update | ☐ |
| 9 | Approve submitted request | Approved time + note required; row becomes approved | `reve_owner_review_schedule_change_request` | ☐ |
| 10 | Apply approved request | Confirmation dialog; row removed on success | `reve_owner_apply_schedule_change_request` | ☐ |
| 11 | Reload page | Applied request stays absent; approved/submitted state persisted | Lesson `scheduled_at` updated | ☐ |
| 12 | Console / network | No blocking errors | No 401/403/500 on read/review/apply | ☐ |

---

## Sign-off

- Verifier: **Owner (REVE)**
- Date: _pending_
- Browser / device: _pending_
- Result: **pending**
- Notes: _Record any deviations or UX feedback here._

## Remaining risks

- Cascade schedule change UI is out of scope for Phase 1B-4.
- Fixed weekly timetable (`schedule_slots`) is not modified by apply; only lesson `scheduled_at` changes.
- Schedule collision leaves request approved but unapplied (`REVE_SCHEDULE_COLLISION`).

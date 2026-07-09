# Owner Schedule Change Cascade — Manual Browser Verification Checklist

Status: **pending — awaiting Owner runtime verification**

Automated Playwright tests do **not** substitute for this checklist.

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
| Implementation tag | `phase-1b5-owner-schedule-change-cascade-implemented` |

---

## 12-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Start Supabase local | Services healthy | `npx supabase status` OK | ☐ |
| 2 | Reset DB | Clean schema | `npx supabase db reset` | ☐ |
| 3 | Seed alpha data | Seed script completes | `npm run db:seed:alpha` | ☐ |
| 4 | Start app | Login page loads | `npm run dev` | ☐ |
| 5 | Login as `owner-alpha@test.local` | Redirect to dashboard | Owner session active | ☐ |
| 6 | Open **일정 변경 요청** | Review + cascade sections visible | Owner-only route | ☐ |
| 7 | Verify review queue | Beta (submitted) and Delta (approved) in review section | `fetchOwnerScheduleChangeQueue.reviewRequests` | ☐ |
| 8 | Verify cascade queue | Delta cascade-pending fixture visible; completed cascade excluded | `cascade_completed_at IS NULL` filter | ☐ |
| 9 | Apply approved request | Row moves to cascade section | `reve_owner_apply_schedule_change_request` | ☐ |
| 10 | Execute cascade | Reason required; confirm dialog; row removed on success | `reve_owner_cascade_schedule_change_request` | ☐ |
| 11 | Reload page | Completed cascade stays absent; review/apply behavior unchanged | Later lessons rescheduled | ☐ |
| 12 | Console / network | No blocking errors | No 401/403/500 on read/review/apply/cascade | ☐ |

**Checklist: pending Owner sign-off**

---

## Sign-off

| Role | Name | Date | Result |
|------|------|------|--------|
| Owner | | | |
| Engineer | | | |

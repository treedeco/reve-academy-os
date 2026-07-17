# Owner Schedule Change Cascade — Manual Browser Verification Checklist

Status: **passed — Owner runtime verification complete**

Automated Playwright tests do **not** substitute for this checklist. This record reflects **Owner-provided** browser verification on commit `c25fb0ac167ea4b56ee36e3dd0d06e9c09a9e775` (tag `phase-1b5-owner-schedule-change-cascade-implemented`).

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| Schedule requests route | `http://127.0.0.1:3000/schedule-requests` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | Username `reve`; password from `OWNER_PASSWORD` in `.env.local` (local only) |

## Verification environment

| Item | Value |
|------|-------|
| Supabase | Local (`npx supabase start`, `db reset`, `npm run db:seed:alpha`) |
| App | `npm run dev` → `http://127.0.0.1:3000` |
| Tested commit | `c25fb0ac167ea4b56ee36e3dd0d06e9c09a9e775` |
| Implementation tag | `phase-1b5-owner-schedule-change-cascade-implemented` |
| Runtime verification date | **2026-07-09** |

---

## 12-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Start Supabase local | Services healthy | `npx supabase status` OK | ☑ |
| 2 | Reset DB | Clean schema | `npx supabase db reset` | ☑ |
| 3 | Seed alpha data | Seed script completes | `npm run db:seed:alpha` | ☑ |
| 4 | Start app | Login page loads | `npm run dev` | ☑ |
| 5 | Login as Owner username `reve` (password from `.env.local`) | Redirect to dashboard | Owner session active | ☑ |
| 6 | Open **일정 변경 요청** | Review + cascade sections visible | Owner-only route | ☑ |
| 7 | Verify review queue | Beta (submitted) and Delta (approved) in review section | `fetchOwnerScheduleChangeQueue.reviewRequests` | ☑ |
| 8 | Verify cascade queue | Delta cascade-pending fixture visible; completed cascade excluded | `cascade_completed_at IS NULL` filter | ☑ |
| 9 | Apply approved request | Row moves to cascade section | `reve_owner_apply_schedule_change_request` | ☑ |
| 10 | Execute cascade | Reason required; confirm dialog; row removed on success | `reve_owner_cascade_schedule_change_request` | ☑ |
| 11 | Reload page | Completed cascade stays absent; review/apply behavior unchanged | Later lessons rescheduled | ☑ |
| 12 | Console / network | No blocking errors | No 401/403/500 on read/review/apply/cascade | ☑ |

**Checklist: 12/12 PASS**

---

## Sign-off

- Verifier: **Owner**
- Date: **2026-07-09**
- Browser / device: **Desktop browser; mobile/responsive layout**
- Result: **passed**
- Notes: Owner confirmed PASS for `/schedule-requests` cascade section using local Supabase, alpha seed (`npm run db:seed:alpha`), with username `reve`. Verified review/apply queues unchanged, cascade-pending section, cascade-completed exclusion, apply to cascade handoff, cascade reason plus confirm plus scoped row removal, reload persistence, and no blocking console/network/server errors on read/review/apply/cascade.

## Non-blocking observations

- Fixed weekly timetable (`schedule_slots`) is not modified by cascade; only later eligible lesson `scheduled_at` values move.
- Cascade collision or immutable-lesson barriers leave the request applied but cascade incomplete with readable errors.

## Remaining risks

- Owner Alpha login requires `npm run db:seed:alpha` after every `db reset`; credentials are not in migration seed alone.
- Supabase auth may be transiently unavailable immediately after `db reset`; retry after seed if login fails.

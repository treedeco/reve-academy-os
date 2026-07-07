# Owner Weekly Schedule — Manual Browser Verification Checklist

Status: **passed — Owner runtime verification complete**

Automated Playwright tests do **not** substitute for this checklist. This record reflects **Owner-provided** browser verification on commit `04f886950f618d9f26d053608a72b4bd043c62f8` (tag `phase-1b1-owner-weekly-schedule-implemented`).

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| Weekly schedule route | `http://127.0.0.1:3000/schedule` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | `owner-alpha@test.local` / `OwnerAlphaTest123!` |

## Verification environment

| Item | Value |
|------|-------|
| Supabase | Local (`npx supabase start`, `db reset`, `npm run db:seed:alpha`) |
| App | `npm run dev` → `http://127.0.0.1:3000` |
| Tested commit | `04f886950f618d9f26d053608a72b4bd043c62f8` |
| Runtime verification date | **2026-07-07** |

---

## 10-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Navigate to **주간 시간표** | `/schedule` loads with page title | Fixed slots from `schedule_slots` | ☑ |
| 2 | Desktop weekday grouping | Columns/sections 월→일 order | Slots grouped by `weekday` not lesson date | ☑ |
| 3 | Time ordering within weekday | Earlier local times first | `local_start_time` sort | ☑ |
| 4 | Student, teacher, course values | Match seeded Alpha/Beta/Delta | Joined names correct | ☑ |
| 5 | Fixed schedule time | Monday Alpha 10:00, Wed Beta 10:00/15:00 | Slot times unchanged | ☑ |
| 6 | Postponed lesson | Alpha fixed row still Monday 10:00 | `schedule_slots.weekday` unchanged; lesson occurrence postponed separately | ☑ |
| 7 | Inactive/historical passes hidden | Gamma Student not listed | Completed pass excluded | ☑ |
| 8 | Mobile layout | List grouped by weekday, readable | Same data as desktop | ☑ |
| 9 | Browser reload | Same entries after F5 | No data loss | ☑ |
| 10 | Console/network | No failed schedule request | No 401/403/500 on schedule read | ☑ |

---

## Sign-off

- Verifier: **Owner (REVE)**
- Date: **2026-07-07**
- Browser / device: **Desktop weekly grid; mobile list layout**
- Result: **passed**
- Notes: Owner confirmed PASS for `/schedule` using local Supabase, seeded alpha data, and `owner-alpha@test.local`. Verified fixed schedule slot position, postponed lesson occurrence display, active/reserved/completed pass inclusion rules, and no blocking runtime errors.

## Remaining risks

- Reserved pass with active slot but no concurrent active pass for the same (student, course) is not covered by current demo seed; inclusion rule is unit-tested.
- `fetchStudentList` N+1 pattern remains unchanged (pre-existing, out of Phase 1B-1 scope).

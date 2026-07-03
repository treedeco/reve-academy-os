# Owner Weekly Schedule — Manual Browser Verification Checklist

Status: **pending Owner verification**

Automated Playwright tests do **not** substitute for this checklist.

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| Weekly schedule route | `http://127.0.0.1:3000/schedule` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | `owner-alpha@test.local` / `OwnerAlphaTest123!` |

---

## 10-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Navigate to **주간 시간표** | `/schedule` loads with page title | Fixed slots from `schedule_slots` | ☐ |
| 2 | Desktop weekday grouping | Columns/sections 월→일 order | Slots grouped by `weekday` not lesson date | ☐ |
| 3 | Time ordering within weekday | Earlier local times first | `local_start_time` sort | ☐ |
| 4 | Student, teacher, course values | Match seeded Alpha/Beta/Delta | Joined names correct | ☐ |
| 5 | Fixed schedule time | Monday Alpha 10:00, Wed Beta 10:00/15:00 | Slot times unchanged | ☐ |
| 6 | Postponed lesson | Alpha fixed row still Monday 10:00 | `schedule_slots.weekday` unchanged; lesson occurrence postponed separately | ☐ |
| 7 | Inactive/historical passes hidden | Gamma Student not listed | Completed pass excluded | ☐ |
| 8 | Mobile layout | List grouped by weekday, readable | Same data as desktop | ☐ |
| 9 | Browser reload | Same entries after F5 | No data loss | ☐ |
| 10 | Console/network | No failed schedule request | No 401/403/500 on schedule read | ☐ |

## Sign-off

- Verifier:
- Date:
- Browser / device:
- Result: **pending** / passed / failed
- Notes:

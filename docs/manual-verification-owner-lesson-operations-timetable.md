# Manual verification — Owner lesson operations and weekly timetable

Phase **2B-2B1-R1**. Run after automated verification passes on a local stack seeded with `scripts/seed-owner-alpha.ps1`.

**Status:** Not verified — operator sign-off pending.

## Prerequisites

- Local Supabase running (`npx supabase start`)
- Owner Alpha demo seed applied
- App at `http://localhost:3000`
- Logged in as Owner (username `reve`)

---

## Lesson status correction

| # | Check | Expected | Pass |
|---|--------|----------|------|
| 1 | On `/lessons/today`, change a scheduled lesson to **완료** | Status persists; used count increases | ☐ |
| 2 | Click **상태 정정** on the completed lesson; set target **예정** | Confirmation dialog shows current vs proposed status and deduction impact | ☐ |
| 3 | Confirm correction | Used count decreases; remaining count increases | ☐ |
| 4 | Reload student detail | Counts remain restored | ☐ |
| 5 | Attempt correction without reason | Error shown; no mutation | ☐ |
| 6 | Complete correction with reason | Success feedback; dialog closes | ☐ |
| 7 | Reload `/lessons/today` and student detail | Corrected status persisted | ☐ |
| 8 | Inspect audit log (SQL) for correction | Previous/new status, deduction impact, reason, actor, timestamp recorded | ☐ |

## Lesson rescheduling

| # | Check | Expected | Pass |
|---|--------|----------|------|
| 9 | From student detail, open **일시 변경**; change date only | Only selected lesson moves | ☐ |
| 10 | Change time only | Lesson time updates; sequence unchanged | ☐ |
| 11 | Change both date and time | Combined change persists after reload | ☐ |
| 12 | Reschedule with cascade **disabled** | Later lessons unchanged | ☐ |
| 13 | Reschedule with cascade **enabled** | Later incomplete lessons shift; completed lessons unmoved | ☐ |
| 14 | Confirm a completed later lesson date | Unchanged after cascade on earlier lesson | ☐ |
| 15 | Compare fixed schedule slots (student/pass view or SQL) | Recurring weekly pattern unchanged after one-off move | ☐ |
| 16 | Reload `/schedule` and student detail | Moved datetimes persisted | ☐ |
| 17 | From `/lessons/today`, open correction on completed lesson | Entry point works without visiting student detail | ☐ |
| 18 | From `/lessons/today`, open rescheduling on scheduled lesson | Entry point works | ☐ |

## Academy operating hours

| # | Check | Expected | Pass |
|---|--------|----------|------|
| 19 | Reschedule to start **12:30** | Rejected with hours message | ☐ |
| 20 | Reschedule to start **22:00** | Rejected | ☐ |
| 21 | Reschedule to **21:00** (60 min) | Accepted; ends at 22:00 | ☐ |

## Weekly timetable (desktop)

| # | Check | Expected | Pass |
|---|--------|----------|------|
| 22 | Open `/schedule` on desktop width | Monday–Sunday columns visible | ☐ |
| 23 | Time axis | Range label **13:00–22:00**; no 22:00 lesson-start row | ☐ |
| 24 | Grid alignment | 30-minute rows; same times align across weekdays | ☐ |
| 25 | Horizontal alignment | 15:00 Wednesday lesson aligns with 15:00 axis label | ☐ |
| 26 | Overlapping lessons (Beta Wed) | Both cards visible; names readable | ☐ |
| 27 | Progress notation | **4-1** (or equivalent) on 4-lesson pass first lesson | ☐ |
| 28 | Progress notation | **8-*** on 8-lesson pass lessons where applicable | ☐ |
| 29 | Card content | No **주 N회** text in desktop cards | ☐ |
| 30 | Card content | No redundant weekday name inside column cards | ☐ |

## Weekly timetable (mobile ~390px)

| # | Check | Expected | Pass |
|---|--------|----------|------|
| 31 | Viewport ~390px on `/schedule` | Weekday-grouped list; no seven-column grid | ☐ |
| 32 | Chronological order within weekday sections | Earlier times first | ☐ |

## Regression

| # | Check | Expected | Pass |
|---|--------|----------|------|
| 33 | Smoke `/students`, `/teachers`, `/lessons/today`, `/sms`, `/refunds` | Pages load; no blocking errors | ☐ |
| 34 | Browser console and network tab | No blocking errors during above flows | ☐ |

---

## Sign-off

| Field | Value |
|-------|-------|
| Operator | |
| Date | |
| Environment | |
| Result | Pass / Fail |
| Notes | |

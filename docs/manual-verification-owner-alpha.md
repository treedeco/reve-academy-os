# Owner Alpha — Manual Browser Verification Checklist

Status: **pending Owner verification**

Automated Playwright tests do not substitute for this checklist. Record pass/fail and defects after completing each step in a real browser.

## Prerequisites

1. Start local Supabase: `npx supabase start`
2. Reset database: `npx supabase db reset`
3. Apply demo seed **local only**: `npm run db:seed:alpha`
4. Copy `.env.local.example` to `.env.local` and set the local anon key from `npx supabase status`
5. Start the app: `npm run dev`

Demo credentials (`scripts/seed-owner-alpha.sql`):

- Email: `owner-alpha@test.local`
- Password: `OwnerAlphaTest123!`

Never reuse these credentials or run the demo seed against hosted/production Supabase.

## Checklist

| # | Step | Pass | Notes |
|---|------|------|-------|
| 1 | Open `/login` while signed out | ☐ | |
| 2 | Log in with the local demo Owner account | ☐ | |
| 3 | Confirm redirect to `/dashboard` | ☐ | |
| 4 | Open `/lessons/today` | ☐ | |
| 5 | Confirm today’s lesson list renders (student, course, teacher, status) | ☐ | |
| 6 | Change one lesson status to **완료** | ☐ | |
| 7 | Confirm submit control disables and a pending/loading state appears | ☐ | |
| 8 | Reload the browser tab | ☐ | |
| 9 | Confirm the changed status persisted | ☐ | |
| 10 | Open the related student detail from the lesson card | ☐ | |
| 11 | Confirm used and remaining counts reflect the saved lesson state | ☐ | |
| 12 | Log out and confirm protected routes redirect to `/login` | ☐ | |
| 13 | Desktop Chrome: repeat login + today lesson view | ☐ | Browser/version: |
| 14 | Mobile browser or phone on local network (if configured): layout remains usable | ☐ | Device/viewport: |

## Defect log

| Step | Expected | Actual | Severity |
|------|----------|--------|----------|
| | | | |

## Sign-off

- Verifier:
- Date:
- Result: pending / passed / failed

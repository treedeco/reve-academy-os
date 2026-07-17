# Owner Alpha — Manual Browser Verification Checklist

Status: **passed — Owner runtime verification complete**

Automated Playwright tests do **not** substitute for this checklist. This record reflects **Owner-provided** browser verification on commit `1240aea179778dfc4045831b138ba17ccc8ef6f3` (tag `phase-1a-h2-migration-order-audited`).

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` (default `npm run dev`) |
| Login URL | `http://127.0.0.1:3000/login` |
| Demo seed command | `npm run db:seed:alpha` (**local only**) |
| Checklist file | `docs/manual-verification-owner-alpha.md` |
| Demo username | `reve` |
| Demo password | Set locally in `.env.local` as `OWNER_PASSWORD` (never commit plaintext) |

Never reuse demo credentials or run the demo seed against hosted/production Supabase.

---

## 15-step verification checklist

| # | Action | Expected UI result | Expected persisted DB result | Failure evidence to capture | Pass |
|---|--------|-------------------|------------------------------|----------------------------|------|
| 1 | Start local Supabase: `npx supabase start` | CLI reports API and DB running; `npx supabase status` shows local URLs | Local Docker containers healthy; no hosted project touched | CLI error output, `docker ps` showing missing `supabase_db_*` | ☑ |
| 2 | Reset and apply demo seed locally: `npx supabase db reset` then `npm run db:seed:alpha` | Seed script prints local container name and completes without “Refusing to continue” | Demo Owner user and today’s lessons exist in **local** DB only | Seed refusal message, SQL error, hosted URL in env vars | ☑ |
| 3 | Copy `.env.local.example` → `.env.local`, set local anon key from `npx supabase status`, then `npm run dev` | Next.js dev server starts; browser can reach `http://127.0.0.1:3000` | N/A (app config only) | Build/start error, wrong Supabase URL in `.env.local` | ☑ |
| 4 | Open `/login` and sign in with username `reve` and the password from `.env.local` (`OWNER_PASSWORD`) | Login succeeds; redirect to `/dashboard` | Session established for demo Owner profile | Login error banner, stay on `/login`, network 401/403 | ☑ |
| 5 | Open `/lessons/today` | Today’s lesson list renders with student name, course, teacher, and current status for seeded lessons | `lessons` rows for today unchanged since seed | Empty list when seed expected rows, missing columns, layout broken | ☑ |
| 6 | Change **one** lesson status (e.g. **완료** / `completed`) via the status control | Selected lesson shows new status in the card after save | `lessons.status` updated for that `lesson_id`; `lessons.updated_at` advanced | Wrong lesson changed, status reverts without error, duplicate RPC in network tab | ☑ |
| 7 | Repeat a status change and observe the in-flight state | Submit control disabled; “저장 중…” (or equivalent pending text) visible during request | N/A during request | Control stays enabled, no pending indicator, double-submit possible | ☑ |
| 8 | Hard-reload the browser tab on `/lessons/today` | Page reloads; changed lesson still shows the saved status | Same `lessons.status` as step 6 after reload | Status reverts to pre-change value | ☑ |
| 9 | Confirm persisted status matches step 6 | UI status equals the value chosen in step 6 | DB row for target lesson matches UI (`status`, `updated_at`) | UI/DB mismatch; screenshot + `docker exec … psql -c "SELECT id, status, updated_at FROM lessons WHERE …"` | ☑ |
| 10 | From the same lesson card, open **학생 상세 보기** | Student detail page loads (`/students/[studentId]`) with correct student name | N/A for navigation | 404, wrong student, broken link | ☑ |
| 11 | On student detail, confirm **used** and **remaining** lesson counts | Counts reflect the saved lesson state from step 6 (e.g. completed increases used) | Pass usage via `reve_owner_get_pass_usage` consistent with lesson status | Stale counts, zero/blank summary, mismatch after reload | ☑ |
| 12 | Log out (or clear session) and visit `/dashboard` or `/lessons/today` | Redirect to `/login`; protected routes inaccessible | Session cleared | Still authenticated, protected route visible while logged out | ☑ |
| 13 | Desktop **Chrome**: repeat login and open `/lessons/today` | Layout readable; lesson list and status control usable | Same seeded data visible | Layout overlap, unreadable text, console errors — note Chrome version | ☑ |
| 14 | **Mobile browser or phone** on local network (if configured): login and open `/lessons/today` | Layout remains usable; controls reachable without horizontal scroll breaking primary actions | Same functional data as desktop | Unusable controls, obscured status select — note device/viewport | ☑ |
| 15 | Record overall pass/fail and any visible defect in **Sign-off** below | All prior steps reviewed; defects logged in Defect log | N/A | Missing notes, unchecked failures, Playwright output substituted for human observation | ☑ |

---

## Defect log

| Step | Expected | Actual | Severity |
|------|----------|--------|----------|
| — | — | No blocking defects | — |

**Accepted behavior (not a defect):** After a lesson reaches **완료** (`completed`), the status control is disabled because Phase 1A allows only ordinary transitions via `reve_transition_lesson_status`. Post-completion correction requires `reve_correct_lesson_status`, which is **deferred** beyond Phase 1A UI scope. Owner acknowledged this behavior.

---

## Sign-off

- Verifier: **Owner (REVE)**
- Date: **2026-07-03**
- Tested commit: **`1240aea179778dfc4045831b138ba17ccc8ef6f3`**
- Browser / device (steps 13–14): **Desktop Google Chrome; Chrome DevTools mobile device emulation**
- Result: **passed**
- Notes: Owner confirmed all 15 steps pass in local browser (“다 잘돼”). Completed lessons cannot be re-edited via ordinary transition — expected Phase 1A domain behavior.

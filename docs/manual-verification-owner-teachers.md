# Manual verification — Owner teacher master data (Phase 2B-1)

Status: **implementation-ready — Owner runtime verification not yet signed off**

Automated Playwright tests do **not** substitute for this checklist. Browser-level empty-state coverage exists in `e2e/owner-teachers.spec.ts` (isolated SQL fixture); manual runtime verification is still pending.

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| Teachers route | `http://127.0.0.1:3000/teachers` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | `owner-alpha@test.local` / `OwnerAlphaTest123!` |

## Verification environment

| Item | Value |
|------|-------|
| Supabase | Local (`npx supabase start`, `db reset`, `npm run db:seed:alpha`) |
| App | `npm run dev` → `http://127.0.0.1:3000` |
| Implementation tag | `phase-2b1-owner-teachers-master-data-implemented` (after implementation commit) |

---

## Checklist

| # | Action | Expected result | Pass |
|---|--------|-----------------|------|
| 1 | Start Supabase local and reset DB | Services healthy; schema reset | ☐ |
| 2 | Seed alpha data | `npm run db:seed:alpha` completes | ☐ |
| 3 | Start app and login as Owner | Redirect to dashboard | ☐ |
| 4 | Open `/teachers` | Page loads; **강사** nav item visible | ☐ |
| 5 | Verify teacher list | Existing seed teachers (e.g. T-A1, T-A2) listed with active badges | ☐ |
| 6 | Create a teacher | Required fields validated; new row appears without full-page reload | ☐ |
| 7 | Reload after create | Created teacher persists | ☐ |
| 8 | Edit teacher contact fields | Save succeeds; updated values visible | ☐ |
| 9 | Reload after edit | Edited values persist | ☐ |
| 10 | Deactivate unassigned teacher | Confirmation required; status becomes **비활성** | ☐ |
| 11 | Attempt deactivate assigned teacher (e.g. T-A1) | Korean error about active assignments; teacher stays active | ☐ |
| 12 | Reactivate previously deactivated teacher | Status returns to **활성** when contract allows | ☐ |
| 13 | Empty state (optional) | Automated Playwright empty-state test passes; manual browser confirmation still pending | ☐ |
| 14 | Responsive layout (~390px width) | No horizontal overflow; forms usable | ☐ |
| 15 | Console/network/server | No blocking errors during create/edit/deactivate flows | ☐ |
| 16 | No physical delete | No delete button; teacher rows remain in database when deactivated | ☐ |
| 17 | Existing Owner pages | `/students`, `/schedule`, `/sms`, `/refunds`, `/schedule-requests` still open | ☐ |

---

## Sign-off

- Verifier: _pending_
- Date: _pending_
- Browser / device: _pending_
- Result: _pending_
- Notes: _pending_

Do not mark runtime verification as passed until all checklist items are confirmed in a real browser by the Owner operator.

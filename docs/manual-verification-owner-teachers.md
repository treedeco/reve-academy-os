# Manual verification — Owner teacher master data (Phase 2B-1)

Status: **passed — Owner runtime verification complete**

Automated Playwright tests do **not** substitute for this checklist. Browser-level empty-state coverage exists in `e2e/owner-teachers.spec.ts` (isolated SQL fixture). This record reflects **Owner-provided** browser verification on commit `08987f20b8b08f508a96da55b3051aafaba6d25f` (tag `phase-2b1-owner-teachers-master-data-implemented`).

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
| Tested commit | `08987f20b8b08f508a96da55b3051aafaba6d25f` |
| Implementation tag | `phase-2b1-owner-teachers-master-data-implemented` |
| Runtime verification date | **2026-07-14** |

## Automated verification status

| Suite | Result |
|-------|--------|
| Vitest | 90/90 passed |
| Integration (`owner-teachers`) | 5/5 passed |
| pgTAP standard suite | 888 passed |
| SMS concurrency pgTAP | 1 passed |
| Refund concurrency pgTAP | 2 passed |
| Focused Playwright (`e2e/owner-teachers.spec.ts`) | 12/12 passed |
| Full Playwright suite | 41/41 passed |
| Phase 1A regression | passed |
| Phase 1B-1 through 1B-6 regressions | passed |

---

## Checklist

| # | Action | Expected result | Pass |
|---|--------|-----------------|------|
| 1 | Start Supabase local and reset DB | Services healthy; schema reset | ☑ |
| 2 | Seed alpha data | `npm run db:seed:alpha` completes | ☑ |
| 3 | Start app and login as Owner | Redirect to dashboard | ☑ |
| 4 | Open `/teachers` | Page loads; **강사** nav item visible | ☑ |
| 5 | Verify teacher list | Existing seed teachers (e.g. T-A1, T-A2) listed with active badges | ☑ |
| 6 | Create a teacher | Required fields validated; new row appears without full-page reload | ☑ |
| 7 | Reload after create | Created teacher persists | ☑ |
| 8 | Edit teacher contact fields | Save succeeds; updated values visible | ☑ |
| 9 | Reload after edit | Edited values persist | ☑ |
| 10 | Deactivate unassigned teacher | Confirmation required; status becomes **비활성** | ☑ |
| 11 | Attempt deactivate assigned teacher (e.g. T-A1) | Korean error about active assignments; teacher stays active | ☑ |
| 12 | Reactivate previously deactivated teacher | Status returns to **활성** when contract allows | ☑ |
| 13 | Empty state (optional) | Automated Playwright empty-state test passes | ☑ |
| 14 | Responsive layout (~390px width) | No horizontal overflow; forms usable | ☑ |
| 15 | Console/network/server | No blocking errors during create/edit/deactivate flows | ☑ |
| 16 | No physical delete | No delete button; teacher rows remain in database when deactivated | ☑ |
| 17 | Existing Owner pages | `/students`, `/schedule`, `/sms`, `/refunds`, `/schedule-requests` still open | ☑ |

**Checklist: 17/17 PASS**

---

## Operator-confirmed runtime results (2026-07-14)

1. `/teachers` page load — **PASS**
2. Teacher list display — **PASS**
3. Teacher creation and persistence after reload — **PASS**
4. Teacher update and persistence after reload — **PASS**
5. Unassigned teacher deactivation — **PASS**
6. Teacher reactivation — **PASS**
7. `T-A1` assigned-teacher deactivation blocking — **PASS**
8. No physical-delete button — **PASS**
9. Responsive layout at approximately 390px — **PASS**
10. Existing Owner page regression checks — **PASS**
11. No blocking Console errors — **PASS**
12. No blocking Network errors — **PASS**

No physical teacher deletion occurred. No remaining manual browser issue reported by the operator.

---

## Sign-off

- Verifier: **Owner**
- Date: **2026-07-14**
- Browser / device: **Desktop browser; mobile/responsive layout (~390px)**
- Result: **passed**
- Notes: Owner confirmed PASS for teacher master data using local Supabase, alpha seed (`npm run db:seed:alpha`), and `owner-alpha@test.local`. Verified `/teachers` page load, teacher list, create/update persistence after reload, unassigned deactivation, reactivation, `T-A1` deactivation blocking, no delete button, responsive layout, existing Owner page regression, and no blocking console or network errors.

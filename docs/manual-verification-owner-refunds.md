# Owner Payment Refund — Manual Browser Verification Checklist

Status: **PENDING — Owner runtime verification not complete**

Automated Playwright tests do **not** substitute for this checklist. Complete each step in a local browser before marking Phase 1B-3 runtime verification.

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| Refund route | `http://127.0.0.1:3000/refunds` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | `owner-alpha@test.local` / `OwnerAlphaTest123!` |

## Verification environment

| Item | Value |
|------|-------|
| Supabase | Local (`npx supabase start`, `db reset`, `npm run db:seed:alpha`) |
| App | `npm run dev` → `http://127.0.0.1:3000` |
| Implementation tag | `phase-1b3-owner-payment-refund-implemented` |

---

## 12-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Start Supabase local | Services healthy | `npx supabase status` OK | ☐ |
| 2 | Reset DB | Clean schema | `npx supabase db reset` | ☐ |
| 3 | Seed alpha data | Seed script completes | `npm run db:seed:alpha` | ☐ |
| 4 | Start app | Login page loads | `npm run dev` | ☐ |
| 5 | Login as `owner-alpha@test.local` | Redirect to dashboard | Owner session active | ☐ |
| 6 | Open **환불 처리** (`/refunds`) | Page title and nav item visible | Owner-only route | ☐ |
| 7 | Verify eligible payments | Delta/Beta/Epsilon (reserved) visible; Alpha pending and Zeta refunded hidden | `fetchOwnerRefundablePayments` filter | ☐ |
| 8 | Verify excluded payments | Pending and already-refunded not listed | No client-side payment update | ☐ |
| 9 | Enter refund reason | Confirm button enabled only with non-empty reason | No DB write yet | ☐ |
| 10 | Confirm full refund | Confirmation dialog; row removed on success | `reve_process_payment_refund` RPC | ☐ |
| 11 | Reload page | Refunded payment stays absent; pass cancelled persisted | `payments.status = refunded` | ☐ |
| 12 | Console / network | No blocking errors | No 401/403/500 on refund read/process | ☐ |

---

## Sign-off

- Verifier: **Owner (REVE)**
- Date: _pending_
- Browser / device: _pending_
- Result: **pending**
- Notes: _Record any deviations or UX feedback here._

## Remaining risks

- Full refund only; partial refund and reversal are out of scope.
- Duplicate refund attempts show error (non-idempotent RPC contract).
- Integration tests may refund Beta payment before Playwright; Delta remains Playwright target after seed reset.

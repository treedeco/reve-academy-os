# Owner SMS Sent Confirmation — Manual Browser Verification Checklist

Status: **PENDING — Owner runtime verification not complete**

Automated Playwright tests do **not** substitute for this checklist. Complete each step in a local browser before marking Phase 1B-2 runtime verification.

## Owner quick reference

| Item | Value |
|------|-------|
| Local app URL | `http://127.0.0.1:3000` |
| SMS confirmation route | `http://127.0.0.1:3000/sms` |
| Demo seed | `npm run db:seed:alpha` (**local only**) |
| Demo login | `owner-alpha@test.local` / `OwnerAlphaTest123!` |

## Verification environment

| Item | Value |
|------|-------|
| Supabase | Local (`npx supabase start`, `db reset`, `npm run db:seed:alpha`) |
| App | `npm run dev` → `http://127.0.0.1:3000` |
| Implementation tag | `phase-1b2-owner-sms-sent-confirmation-implemented` |

---

## 12-step verification checklist

| # | Action | Expected UI | Expected DB / behavior | Pass |
|---|--------|-------------|------------------------|------|
| 1 | Start Supabase local | Services healthy | `npx supabase status` OK | ☐ |
| 2 | Reset DB | Clean schema | `npx supabase db reset` | ☐ |
| 3 | Seed alpha data | Seed script completes | `npm run db:seed:alpha` | ☐ |
| 4 | Start app | Login page loads | `npm run dev` | ☐ |
| 5 | Login as `owner-alpha@test.local` | Redirect to dashboard | Owner session active | ☐ |
| 6 | Open **SMS 발송 확인** (`/sms`) | Page title and nav item visible | Owner-only route | ☐ |
| 7 | Verify eligible entries | Beta (scheduled), Delta (target), Gamma (exhausted_unsent) visible; Alpha (normal) and sent rows hidden | `fetchOwnerSmsNotifications` eligible filter | ☐ |
| 8 | Copy message | **메시지 복사** shows **복사됨**; clipboard has `message_body_snapshot` | No DB write | ☐ |
| 9 | Confirm sent for one item | Row disappears or shows success; button disabled while pending | `reve_owner_confirm_sms_sent` RPC | ☐ |
| 10 | Verify UI update | Confirmed row no longer in eligible list | Scoped client update (no full refresh required) | ☐ |
| 11 | Reload page | Confirmed item stays absent | `status = sent` persisted | ☐ |
| 12 | Console / network | No blocking errors | No 401/403/500 on SMS read or confirm | ☐ |

---

## Sign-off

- Verifier: **Owner (REVE)**
- Date: _pending_
- Browser / device: _pending_
- Result: **pending**
- Notes: _Record any deviations or UX feedback here._

## Remaining risks

- Clipboard copy behavior varies by browser permissions on mobile devices.
- Integration tests may confirm Delta SMS before Playwright; render tests tolerate absent Delta row.
- External SMS sending is manual; this UI only records confirmation.

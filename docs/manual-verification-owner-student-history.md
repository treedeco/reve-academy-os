# Manual verification — Owner student operational history (Phase 1B-6)

Use this checklist after automated verification passes locally.

## Prerequisites

- Supabase local running
- `.env.local` configured for local Supabase
- Node.js dependencies installed (`npm ci`)

## Checklist

1. **Start Supabase local**
   - Run `npx supabase start` if not already running.

2. **Reset DB**
   - Run `npx supabase db reset`.

3. **Seed alpha data**
   - Run `npm run db:seed:alpha`.

4. **Start app**
   - Run `npm run dev` and open the local app URL (typically `http://localhost:3000`).

5. **Login as Owner**
   - Email: `owner-alpha@test.local`
   - Password: `OwnerAlphaTest123!`

6. **Open `/students`**
   - Confirm the student list loads without errors.

7. **Open a student detail page with operational history**
   - Open **Delta Student** (`/students/44444444-4444-4444-4444-444444444104`).
   - Optional: also spot-check **Zeta Student** for refund history and **Gamma Student** for empty states.

8. **Verify payment history section**
   - Section heading **결제 이력** is visible.
   - At least one completed payment row shows status, amount, pass code, and course context.
   - No payment creation or renewal buttons appear.

9. **Verify refund history section**
   - On Delta: empty state **환불 이력이 없습니다.** is shown.
   - On Zeta: one refund row shows amount, reason, and linked pass/course context.
   - No refund processing buttons appear.

10. **Verify schedule change request history section**
    - Section heading **일정 변경 요청 이력** is visible on Delta.
    - Rows show request status, target lesson sequence, time summary, cascade status, and reason.
    - No review/apply/cascade action buttons appear in this section.

11. **Verify existing student detail sections still work**
    - **현재 회차권**, **고정 일정**, **수업 이력** (and other existing sections) still render.
    - Confirm no new write actions were added to operational history sections.

12. **Verify mobile/responsive layout and runtime errors**
    - Resize to mobile width (~390px) or use device emulation.
    - Operational history sections remain readable (horizontal scroll acceptable for tables).
    - No blocking browser console or server runtime errors during navigation.

## Expected seed fixtures

| Student | Payments | Refunds | Schedule requests |
|---------|----------|---------|-------------------|
| Delta   | 1 completed | 0 | multiple statuses |
| Beta    | 1 completed | 0 | submitted + rejected |
| Zeta    | 1 refunded | 1 | 0 |
| Gamma   | 0 | 0 | 0 (empty states) |

## Notes

- This phase is **read-only**; mutations remain on `/refunds` and `/schedule-requests`.
- Do not create the runtime-verified tag until manual browser verification is complete.

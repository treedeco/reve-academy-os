# Manual Browser Verification — Owner Student Master and Initial Enrollment

Phase **2B-2B1** manual checklist. Run against **local** Supabase after `npx supabase db reset` and `npm run db:seed:alpha`, with `npm run dev` (or Playwright’s dev server) on port 3000.

Login: `owner-alpha@test.local` / `OwnerAlphaTest123!`

**Automated prerequisite:** `scripts/verify_phase_2b2b1.ps1` must exit 0 before operator manual verification begins.

**Automated coverage (H1 stabilization):** 54 Playwright tests with `--retries=0`; Owner Alpha today-lesson rows reset via `scripts/fixture-reset-owner-alpha-today-lesson.sql`; Owner Teachers empty-state uses `scripts/fixture-owner-teachers-empty.sql` (no mid-run `supabase db reset` during Playwright).

**Status legend:** `[ ]` not yet verified by operator · `[x]` verified · `[!]` failed

Do **not** mark items passed unless an operator actually performs them in a browser.

---

## 1. Student creation

- [ ] Open `/students`.
- [ ] Fill 학생 코드, 이름, and optional phone/email in **학생 등록**.
- [ ] Click **학생 등록**.
- [ ] Expect navigation to the new student detail page without full-page reload flicker beyond route change.
- [ ] Expect persisted name and code on detail.

## 2. Reload persistence (create)

- [ ] Reload the student detail page.
- [ ] Expect the same student record.

## 3. Student editing

- [ ] On student detail, click **수정**, change 이름 (and optional contact fields), click **저장**.
- [ ] Expect updated values in **학생 정보** without leaving the page.

## 4. Reload persistence (edit)

- [ ] Reload student detail.
- [ ] Expect edited values.

## 5. Eligible deactivation

- [ ] Create or use a student **without** a linked active profile (no portal login).
- [ ] Enter 상태 변경 사유, confirm **비활성화**.
- [ ] Expect badge **비활성** and no physical delete control.

## 6. Reactivation

- [ ] Enter 사유, click **활성화**.
- [ ] Expect badge **활성**.

## 7. Four-lesson weekly enrollment

- [ ] Use an **active** student with **no current pass**.
- [ ] In **초기 등록**, select Alpha Vocal Course, Alpha 4 Lessons, start date, one teacher, one weekly slot.
- [ ] Submit **초기 등록 실행**.
- [ ] Expect success message with pass code.

## 8. Four generated lessons

- [ ] On student detail **수업 이력**, expect exactly **4** rows with sequence 1–4.

## 9. Used 0 / remaining 4

- [ ] In **현재 회차권**, expect 사용 **0**, 잔여 **4**.

## 10. Weekly schedule placement

- [ ] In **고정 일정**, expect **1** slot matching the submitted weekday/time/teacher.

## 11. Eight-lesson twice-weekly enrollment

- [ ] Create another active student without a pass.
- [ ] Select Alpha Piano Course, Alpha 8 Lessons, **two** schedule slots (different weekdays/times as needed).
- [ ] Submit and expect success.

## 12. Eight generated lessons

- [ ] Expect **8** lesson rows with sequence 1–8.

## 13. Used 0 / remaining 8

- [ ] Expect 사용 **0**, 잔여 **8**.

## 14. Two weekly schedule positions

- [ ] Expect **2** entries under **고정 일정**.

## 15. Student-detail persistence

- [ ] Reload student detail after each enrollment.
- [ ] Expect pass, lessons, counts, and schedule unchanged.

## 16. Duplicate-submit prevention

- [ ] Start a new student enrollment; double-click **초기 등록 실행** quickly.
- [ ] Expect at most **one** pass and no duplicate lesson sets.

## 17. Validation failure without partial records

- [ ] Attempt enrollment with missing required slot fields or wrong slot count for the product.
- [ ] Expect inline error; **no** new pass, lessons, or schedule rows.

## 18. Approximately 390px responsive layout

- [ ] Set viewport ~390px width on `/students` and a student detail page.
- [ ] Expect forms readable, no horizontal overflow, primary actions reachable.

## 19. Existing Owner page regression

- [ ] From `/students`, open Dashboard, 학생, 강사, weekly schedule, SMS, refunds, schedule requests.
- [ ] Expect prior Phase 1A–2B-1 pages still load.

## 20. Blocking console errors

- [ ] With DevTools open, repeat create → edit → enroll flows.
- [ ] Expect **no** uncaught exceptions or error-level console noise blocking use.

## 21. Blocking network errors

- [ ] Monitor Network tab during the same flows.
- [ ] Expect **no** failing RPC or page requests (4xx/5xx) except deliberate validation failures.

---

## Operator sign-off

| Field | Value |
|-------|-------|
| Operator | |
| Date (Asia/Seoul) | |
| Browser / OS | |
| Commit under test | |
| Overall result | Pass / Fail |
| Notes | |

**Automated verification alone does not satisfy this checklist.**

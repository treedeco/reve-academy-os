# Manual verification — Owner deletion workflows (Phase 2B-2B5)

Local Supabase + Owner Alpha seed only. **Do not use Production credentials or real student data.**

## Prerequisites

```powershell
npx supabase start
npx supabase db reset
npm run db:seed:alpha
npm run dev
```

Owner login: username `reve`, password from `.env.local` (`OWNER_PASSWORD`).

## 1. Fixed schedule removal

1. Open `/students` and select a student with an active pass and fixed schedule (e.g. Alpha seed student).
2. On student detail, locate **고정 일정 관리 → 고정 스케줄 삭제**.
3. Confirm the button is visually distinct from **학생 영구 삭제** (amber vs red danger zone).
4. Open the dialog; verify impact preview shows student, pass code, weekday/time, future lesson count.
5. Set **적용 시작일** to today; enter a reason.
6. Enter confirmation phrase `{pass_code} 스케줄삭제` (e.g. `V-S001-001 스케줄삭제`).
7. Submit; verify success message and refreshed student detail shows **등록된 고정 일정이 없습니다.**
8. Open `/weekly-schedule`; confirm future lessons from removed schedule no longer appear.
9. Confirm past/completed lessons remain on student detail lesson history.

## 2. Student permanent deletion

1. Create a disposable test student via **학생 등록** (or use a dedicated fixture student in local only).
2. Scroll to **위험 작업** section at bottom of student detail.
3. Open **학생 영구 삭제**; verify preflight counts (passes, lessons, payments).
4. Enter reason and confirmation `{student_code} 영구삭제`.
5. Submit; verify redirect to `/students` and student no longer listed.
6. Navigate directly to `/students/{id}`; expect not-found or error state.
7. Confirm other students unchanged.

## 3. Teacher permanent deletion (reassign mode)

1. Open `/teachers`.
2. On a teacher with assigned lessons, open **강사 영구 삭제** in danger section.
3. Select **다른 강사에게 재배정** and pick an active replacement teacher.
4. Enter reason and confirmation `{teacher_code} 영구삭제`.
5. Submit; verify teacher removed from list.
6. Confirm assigned students still exist; future lessons show replacement teacher on timetable.

## 4. Accessibility and safety

- [ ] Dialog traps focus; Escape or Cancel closes without mutation.
- [ ] Submit disabled until confirmation phrase matches exactly.
- [ ] Submit disabled while request pending (no double submit).
- [ ] Error messages readable in Korean; no raw UUIDs on screen.
- [ ] Mobile layout: impact summary readable without horizontal scroll.

## 5. Regression smoke

- [ ] Student create / edit / deactivate still works.
- [ ] Initial enrollment still works.
- [ ] Weekly timetable loads.
- [ ] Fixed schedule change dialog still works.

## Record

| Field | Value |
|-------|-------|
| Date | |
| Verifier | |
| Git SHA | |
| Local migration count | 26 (includes `20260728120000`) |
| Result | PASS / FAIL |
| Notes | |

# Manual verification — Owner deletion workflows (Phase 2B-2B5)

Production runtime verification against commit **`e6a9ba6`** (`fix: simplify deletion confirm and allow multi-course enrollment`).

**Do not use real student, teacher, schedule, lesson, profile, payment, or Auth records.** Use disposable records prefixed `PHASE2B2B5-20260729-{random}` only.

## Current confirmation contracts (commit `e6a9ba6`)

| Workflow | User-facing confirmation | Value sent to RPC (`p_confirmation_code`) | Validation layers |
|----------|--------------------------|---------------------------------------------|-------------------|
| Fixed schedule removal | Checkbox: **위 내용을 확인했으며, 정말 삭제합니다.** | `{pass_code} 스케줄삭제` (client auto-generated) | Client: checkbox + reason + preflight; Server: exact phrase + fingerprint + stale-state |
| Student permanent deletion | Same checkbox | `{student_code} 영구삭제` (client auto-generated) | Same |
| Teacher permanent deletion | Same checkbox | `{teacher_code} 영구삭제` or `{teacher_name} 영구삭제` if code empty (client auto-generated) | Same + link mode / replacement teacher |

Migration `20260728120000` is unchanged between `f38b89a` and `e6a9ba6`. UI/RPC contract is consistent: the checkbox gates submission; the client always passes the server-required exact phrase derived from the preview target.

## Safety classification (pre-runtime)

**`SAFE_MODIFIED`** — confirmation UX simplified from typed phrase to checkbox, but server-side exact-phrase validation, preflight fingerprint, target display, reason requirement, and duplicate-submit prevention remain intact.

## Local checklist (reference)

```powershell
npx supabase start
npx supabase db reset
npm run db:seed:alpha
npm run dev
```

Owner login: username `reve`, password from `.env.local` (`OWNER_PASSWORD`).

### 1. Fixed schedule removal

1. Open `/students` and select a student with an active pass and fixed schedule.
2. On student detail, locate **고정 일정 관리 → 고정 스케줄 삭제**.
3. Confirm the button is visually distinct from **학생 영구 삭제** (amber vs red danger zone).
4. Open the dialog; verify impact preview shows student, pass code, weekday/time, future lesson count.
5. Set **적용 시작일** to today; enter a reason.
6. Check **위 내용을 확인했으며, 정말 삭제합니다.**
7. Submit; verify success message and refreshed student detail shows **등록된 고정 일정이 없습니다.**
8. Open `/weekly-schedule`; confirm future lessons from removed schedule no longer appear.
9. Confirm past/completed lessons remain on student detail lesson history.

### 2. Student permanent deletion

1. Create a disposable test student via **학생 등록**.
2. Scroll to **위험 작업** section at bottom of student detail.
3. Open **학생 영구 삭제**; verify preflight counts (passes, lessons, payments).
4. Enter reason and check **정말 삭제** confirmation.
5. Submit; verify redirect to `/students` and student no longer listed.
6. Navigate directly to `/students/{id}`; expect not-found or error state.
7. Confirm other students unchanged.

### 3. Teacher permanent deletion (reassign mode)

1. Open `/teachers`.
2. On a teacher with assigned lessons, open **강사 영구 삭제** in danger section.
3. Select **다른 강사에게 재배정** and pick an active replacement teacher.
4. Enter reason and check **정말 삭제** confirmation.
5. Submit; verify teacher removed from list.
6. Confirm assigned students still exist; future lessons show replacement teacher on timetable.

### 4. Teacher permanent deletion (remove future schedule mode)

1. Open `/teachers` on a disposable teacher with future assignments.
2. Open **강사 영구 삭제**; select **미래 고정 일정·수업 제거**.
3. Enter reason and check **정말 삭제** confirmation.
4. Submit; verify teacher removed, future schedules disabled/removed, historical lessons readable.

### 5. Accessibility and safety

- [ ] Dialog traps focus; Escape or Cancel closes without mutation.
- [ ] Submit disabled until **정말 삭제** is checked and reason is entered.
- [ ] Submit disabled while request pending (no double submit).
- [ ] Error messages readable in Korean; no raw UUIDs on screen.
- [ ] Mobile layout: impact summary readable without horizontal scroll.

## Production runtime record

| Field | Value |
|-------|-------|
| Date (KST) | **2026-07-30 17:08–17:10** |
| Verifier | Operator (production Owner login + disposable-record workflows) |
| Production URL | `https://reve-academy-os.vercel.app` |
| Production deployment ID | `dpl_GQD11F8RcmAUXtbNsPcP6RZcd4Gm` |
| Production commit verified | **`e6a9ba6`** (`e6a9ba69dafb633c7aa745c61bc220015c850af4`) |
| Tested production commit | **`e6a9ba6`** (not `f38b89a`) |
| Migration state | **26/26** local = remote (`20260728120000` applied) |
| Ancestry audit | `f38b89a` is ancestor of `e6a9ba6` — classification **`SAFE_MODIFIED`** |
| Safety verdict | **`SAFE_MODIFIED`** |
| Runtime run ID | `PHASE2B2B5-20260729-ON8T7N` |
| Evidence file | `backups/phase-2b2b5-production-runtime-evidence.json` |
| Verification script | `scripts/run_phase_2b2b5_production_runtime.ps1` (`-ConfirmProduction -AllowSecurePrompt`) |
| Owner production login | **PASS** (Stage 1; auth user `2e4716e5-6ad4-4e2e-bc39-7c5a435602e4`) |
| Fixed schedule removal | **PASS** (pass `V-S0009-001`; checkbox gating verified; active slots 1→0; future scheduled 4→`advance_cancelled` 4) |
| Student permanent deletion | **PASS** (disposable `S0010` / `2473d534-59e2-4f83-ba61-1cbf58845a4d`; student row count 0; detail not-found-like) |
| Teacher reassignment deletion | **PASS** (`TP25ON8T7NB` → replacement `TP25ON8T7NC`; future lessons 4 retained on replacement) |
| Teacher future-schedule removal | **PASS** (`TP25ON8T7ND`; active slots 1→0; 4 `advance_cancelled` lessons) |
| Tombstone audit evidence | **PASS** (`student.permanently_deleted` audit row present) |
| Unrelated row control | **PASS** (4 non-disposable students unchanged) |
| Duplicate-submit safety (production) | **PASS** (submit disabled until checkbox + reason; UI gating observed in dialogs) |
| Cleanup result | Disposable delete student + 2 teachers removed; retained disposable rows documented in evidence `cleanup.retainedRecords` |
| Automated regression (`e6a9ba6` tree) | typecheck ✓, lint ✓, vitest **231/231** ✓, build ✓, pgTAP **1038** ✓, `verify_phase_2b2b5.ps1` ✓, owner-deletion E2E **5/5** ✓, owner-student-enrollment E2E **13/13** ✓ |
| **Result** | **PASS — production runtime verification complete** |

### Disposable production records (run `PHASE2B2B5-20260729-ON8T7N`)

Prefix rule: **`PHASE2B2B5-20260729-*`** — not real academy data.

| Kind | Identifier | Status after run |
|------|------------|------------------|
| Teacher (enroll helper) | `TP25ON8T7NA` | Retained |
| Teacher (reassign target) | `TP25ON8T7NB` | **Deleted** |
| Teacher (replacement) | `TP25ON8T7NC` | Retained |
| Teacher (remove-sched target) | `TP25ON8T7ND` | **Deleted** |
| Student (schedule removal) | `79a7228a-037a-407d-9cb6-57060c50da9e` | Retained (no active fixed schedule) |
| Student (permanent delete) | `2473d534-59e2-4f83-ba61-1cbf58845a4d` (`S0010`) | **Deleted** |
| Student (reassign helper) | `134b658b-8477-4a5b-ac31-c289e00cf000` | Retained |
| Student (remove-sched helper) | `5ebb5df6-676d-4803-9920-ca9b58301d25` | Retained |

Prior partial runs may have left additional `PHASE2B2B5-20260729-*` rows in production; they are likewise disposable and may be cleaned up operator-side when convenient.

### Tag policy

| Tag | Target | Status |
|-----|--------|--------|
| `phase-2b2b5-owner-deletion-implemented` | `f38b89a` | preserved |
| `phase-2b2b5-owner-deletion-rollback` | `98d8c21` | preserved |
| `phase-2b2b5-owner-deletion-runtime-verified` | closure commit after PASS | **created on closure commit** |

## Sign-off

- Verifier: **Operator**
- Date: **2026-07-30**
- Environment: **Production** (`reve-academy-os.vercel.app`, Supabase `bfhptqhgxignyggyxxkx`)
- Result: **passed**
- Notes: All four Owner deletion / schedule-removal workflows verified against commit **`e6a9ba6`** using disposable records only. Confirmation checkbox gates submission; client auto-passes server exact phrase. No real production student/teacher master rows were mutated except documented disposable test rows.

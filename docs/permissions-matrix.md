# Permissions Matrix — REVE ACADEMY OS

Phase 0A **권한 매트릭스**. RLS SQL은 Phase 0B. **Confirmed 2026-06-26**: OD-01 ~ OD-12.

**Legend**

| Symbol | Meaning |
|--------|---------|
| ✓ | Allowed (with conditions) |
| — | Not allowed |
| ✓* | Allowed via **server-only trusted function** only |
| ✓† | Allowed with **mandatory audit** |
| Own | Own record only |
| Assigned | Assigned student/lesson only |
| All | Owner full scope |

**Roles**: Owner | Teacher | Student | **Trusted** (server-only database function)

---

## profiles

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Own | Own | — | Teacher/Student: own profile |
| Create | ✓† | — | — | ✓* | Auth signup + trusted bootstrap |
| Update | ✓† | Own (limited) | Own (limited) | — | Role change Owner only |
| Delete | — | — | — | — | Physical delete prohibited |
| Special | ✓† role assign | — | — | — | |
| Server-only | — | — | — | ✓* role bootstrap | |
| Audit | ✓† role changes | — | — | inserts via trusted | |

---

## students

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Assigned | Own | — | OD-07 multi-course |
| Create | ✓ | — | — | — | |
| Update | ✓† | — | — | — | |
| Delete | — | — | — | — | Physical delete prohibited |
| Special | — | — | — | — | |
| Server-only | — | — | — | — | |
| Audit | ✓† material changes | — | — | — | |

---

## teachers

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Own | Assigned only | — | Student sees own teacher(s) |
| Create | ✓ | — | — | — | |
| Update | ✓† | Own (limited) | — | — | |
| Delete | — | — | — | — | Physical delete prohibited |
| Special | ✓ assignment mgmt | — | — | — | |
| Server-only | — | — | — | — | |
| Audit | ✓† assignment | — | — | — | |

---

## courses

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | ✓ | ✓ (enrolled) | — | Curriculum metadata |
| Create | ✓ | — | — | — | |
| Update | ✓† | — | — | — | |
| Delete | — | — | — | — | Prefer inactive |
| Special | — | — | — | — | |
| Server-only | — | — | — | — | |
| Audit | ✓† deactivate | — | — | — | |

---

## course_products

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | ✓ (active) | — | ✓* | OD-08; planned table |
| Create | ✓† | — | — | — | |
| Update | ✓† | — | — | — | Does not alter pass snapshots |
| Delete | — | — | — | — | Prefer inactive |
| Special | — | — | — | ✓* snapshot on pass create | |
| Server-only | — | — | — | ✓* financial snapshot | OD-09 |
| Audit | ✓† price/count change | — | — | — | |

---

## passes

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Assigned | Own | — | Active first in UI |
| Create | — | — | — | ✓*† | Payment renewal only |
| Update | ✓† (limited) | — | — | ✓*† | No used/remaining direct edit; active refund → `cancelled` via trusted only (OD-12) |
| Delete | — | — | — | — | Physical delete prohibited |
| Special | ✓† cancel/correct | — | — | ✓* reserved→active | OD-10, OD-11 |
| Server-only | — | — | — | ✓* renewal, activation | |
| Audit | ✓† status change | — | — | ✓† | |

**Restrictions**

- Owner: historical passes not physically deleted; mistaken cancel → new pass (OD-11), not reactivation
- Teacher: read assigned; no financial snapshot edit; no forced renewal
- Student: read own; no edit

---

## lessons

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Assigned | Own schedule | — | |
| Create | — | — | — | ✓*† | Pass renewal / generation |
| Update | ✓† | ✓ (ordinary) | — | ✓*† | Teacher: assigned only; no owner correction |
| Delete | — | — | — | — | Physical delete prohibited |
| Special | ✓† deductible→non-deductible | — | — | ✓* cascade apply | OD-02, OD-01 |
| Server-only | — | — | — | ✓* correction, cascade | |
| Audit | ✓† owner correction | ✓ (optional memo) | — | ✓† | |

**Restrictions**

- Teacher: ordinary transitions per state-transitions; **not** owner correction; **not** cascade
- Student: no status edit

---

## schedule_slots

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Assigned | Own | — | OD-04 multiple slots |
| Create | ✓† | — | — | ✓* | Pass setup |
| Update | ✓† | — | — | — | Not from actual lesson dates |
| Delete | — | — | — | — | Prefer deactivate slot |
| Special | — | — | — | — | |
| Server-only | — | — | — | ✓* lesson gen from slots | |
| Audit | ✓† | — | — | — | |

---

## payments

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | — | Own notice | — | Teacher: no total revenue |
| Create | ✓ | — | — | — | |
| Update | — | — | — | ✓*† | Owner **initiates**; normal clients **must not** independently update payment, pass, or affected lessons for refund. Complete/refund execution **trusted only** |
| Delete | — | — | — | — | Physical delete prohibited |
| Special | — | — | — | ✓*† renewal idempotent | OD-09 |
| Server-only | — | — | — | ✓* complete, refund | |
| Audit | ✓† | — | — | ✓† | |

**Restrictions**

- Owner: **initiates** controlled refund workflow; coordinated update via **trusted operation only** — not independent client writes to payment + pass + lessons
- Teacher: **no** refund; **no** payment CRUD or academy revenue
- Student: read own payment notice only; **no** refund

---

## sms_notifications

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Assigned (limited) | — | — | MVP targets |
| Create | — | — | — | ✓* | Derived on pass/lesson change |
| Update | ✓† manual sent | — | — | ✓* | Recalc on correction |
| Delete | — | — | — | — | History preserved |
| Special | ✓ copy text, mark sent | — | — | — | MVP |
| Server-only | — | — | — | ✓* derive states | |
| Audit | ✓† manual sent | — | — | — | |

**Restrictions**

- Student: cannot mark `sent`
- Teacher: read-only operational view if needed; no mark sent

---

## schedule_change_requests

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Assigned students | Own | — | OD-01 |
| Create | ✓ | ✓ (assigned) | ✓ (own) | — | Reason + suggested times |
| Update | ✓† approve/reject | ✓ (own draft/submitted) | ✓ (own cancel) | ✓*† apply | |
| Delete | — | — | — | — | Use cancelled status |
| Special | ✓† final approve/reject | — submit only | — submit only | ✓* apply lessons | OD-01 |
| Server-only | — | — | — | ✓* apply cascade | |
| Audit | ✓† | — | — | ✓† | |

**Teacher prohibitions (OD-01)**

- — final approve/reject
- — execute cascading lesson movement
- — alter another teacher’s schedule

---

## lesson_notes

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | Assigned | Own if student-visible | — | Internal notes hidden from student |
| Create | ✓ | ✓ (assigned) | — | — | |
| Update | ✓ | ✓ (assigned) | — | — | |
| Delete | — | — | — | — | Prefer append + audit |
| Special | — | — | — | — | |
| Server-only | — | — | — | — | |
| Audit | ✓† if removed | optional | — | — | |

---

## audit_logs

| Action | Owner | Teacher | Student | Trusted | Conditions / notes |
|--------|-------|---------|---------|---------|-------------------|
| Read | All | — | — | — | Unrestricted Owner only |
| Create | — | — | — | ✓*† | Clients cannot insert directly |
| Update | — | — | — | — | Append-only |
| Delete | — | — | — | — | Prohibited |
| Special | — | — | — | ✓* all sensitive ops | |
| Server-only | — | — | — | ✓* insert | |
| Audit | N/A | — | — | — | |

---

## Trusted function catalog (planned)

Operations **must not** be directly writable by normal client roles:

| Operation | Trigger role | Audit |
|-----------|--------------|-------|
| Payment complete + pass renewal | Owner initiates; Trusted executes | ✓† |
| Idempotent payment retry | Trusted | ✓ |
| Reserved pass activation | Trusted (on last deductible complete) | ✓† |
| Owner completed-lesson correction | Owner initiates; Trusted executes | ✓† |
| Cascading schedule movement | Owner approved request; Trusted applies | ✓† |
| Financial snapshot creation | Trusted on pass/payment create | ✓ |
| Controlled refund (reserved path) | Owner initiates; Trusted executes | ✓† |
| Controlled refund (active pass — OD-12) | Owner initiates (amount + reason required); Trusted executes coordinated update: payment → `refunded`, pass → `cancelled`, future non-deducted lessons → `advance_cancelled`, SMS recalc, audit | ✓† |
| Audit log insertion | Trusted | — |

---

## Summary restrictions by role

### Owner

- Broad management access
- **Cannot** physically delete passes, lessons, payments
- Sensitive corrections **require reason** + audit
- Payment renewal **must** use trusted transactional function
- Refunds **must** use trusted coordinated operation; **cannot** physically delete historical records

### Teacher

- Assigned students and lessons only
- Ordinary lesson status transitions; lesson notes; schedule request **submit** + suggest replacements
- **Cannot**: final schedule approve/reject; cascade; owner correction; **refunds**; revenue; other teachers’ students; product/pass financial edit; payment renewal; roles; unrestricted audit

### Student

- Read own allowed data; create own schedule change requests
- **Cannot**: edit lesson status, pass, counts, payments, tuition, **refunds**; mark SMS sent; approve schedules; read internal teacher notes (unless student-visible); read audit logs

---

## Related documents

- [domain-rules.md](./domain-rules.md)
- [state-transitions.md](./state-transitions.md)
- [project-brief.md](./project-brief.md)
- [open-decisions.md](./open-decisions.md)

**Next step (Phase 0B)**: Translate this matrix into RLS policies and API route guards.

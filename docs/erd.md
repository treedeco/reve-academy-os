# Entity Relationship Diagram — REVE ACADEMY OS

Phase **0B-1** logical ERD. Mermaid for rendering; plain-language summary follows.

---

## Mermaid `erDiagram`

```mermaid
erDiagram
  profiles {
    uuid id PK
    uuid auth_user_id UK
    text role
    text display_name
    text account_state
  }

  students {
    uuid id PK
    text student_code UK
    uuid profile_id FK
    text operational_status
  }

  teachers {
    uuid id PK
    text teacher_code UK
    uuid profile_id FK
    boolean is_active
  }

  courses {
    uuid id PK
    text course_code UK
    text name
    boolean is_active
  }

  course_products {
    uuid id PK
    uuid course_id FK
    text product_code UK
    integer default_lesson_count
    integer weekly_frequency
    integer default_tuition_krw
  }

  passes {
    uuid id PK
    text pass_code UK
    uuid student_id FK
    uuid course_id FK
    uuid course_product_id FK
    integer sequence_number
    text status
    uuid previous_pass_id FK
    uuid correction_source_pass_id FK
  }

  schedule_slots {
    uuid id PK
    uuid pass_id FK
    uuid teacher_id FK
    smallint weekday
    time local_start_time
    integer duration_minutes
  }

  lessons {
    uuid id PK
    uuid pass_id FK
    uuid student_id FK
    uuid course_id FK
    uuid assigned_teacher_id FK
    uuid schedule_slot_id FK
    integer sequence_number
    text status
    uuid makeup_source_lesson_id FK
  }

  payments {
    uuid id PK
    uuid student_id FK
    uuid course_id FK
    uuid course_product_id FK
    uuid related_pass_id FK
    uuid renewed_pass_id FK
    text idempotency_key UK
    text status
    integer paid_amount_krw
  }

  payment_refunds {
    uuid id PK
    uuid payment_id FK
    integer refunded_amount_krw
    text pass_disposition
    uuid actor_profile_id FK
  }

  sms_notifications {
    uuid id PK
    uuid student_id FK
    uuid pass_id FK
    text status
    text notification_type
  }

  schedule_change_requests {
    uuid id PK
    uuid student_id FK
    uuid target_lesson_id FK
    uuid requesting_profile_id FK
    text status
  }

  lesson_schedule_changes {
    uuid id PK
    uuid lesson_id FK
    uuid schedule_change_request_id FK
    text change_origin
    timestamptz previous_scheduled_at
    timestamptz new_scheduled_at
  }

  lesson_notes {
    uuid id PK
    uuid lesson_id FK
    uuid author_profile_id FK
    text visibility
  }

  audit_logs {
    uuid id PK
    uuid actor_profile_id FK
    text resource_table
    uuid resource_id
    jsonb previous_value
    jsonb new_value
    uuid correlation_id
  }

  profiles ||--o| students : "optional profile_id"
  profiles ||--o| teachers : "optional profile_id"
  profiles ||--o{ lesson_notes : authors
  profiles ||--o{ schedule_change_requests : requests
  profiles ||--o{ payment_refunds : actor
  profiles ||--o{ audit_logs : actor

  courses ||--|{ course_products : offers
  courses ||--o{ passes : context
  course_products ||--o{ passes : product_snapshot
  course_products ||--o{ payments : purchased

  students ||--|{ passes : owns
  students ||--o{ lessons : denorm
  students ||--o{ payments : pays
  students ||--o{ sms_notifications : notifies
  students ||--o{ schedule_change_requests : subject

  teachers ||--o{ schedule_slots : fixed_slot
  teachers ||--o{ lessons : assigned

  passes ||--|{ schedule_slots : has
  passes ||--|{ lessons : contains
  passes ||--o{ sms_notifications : lifecycle
  passes ||--o| passes : previous_pass_id
  passes ||--o| passes : correction_source_pass_id
  passes ||--o{ payments : related_pass
  passes ||--o| payments : renewed_pass

  lessons ||--o| lessons : makeup_source_lesson_id
  lessons ||--o{ schedule_change_requests : target
  lessons ||--|{ lesson_schedule_changes : history
  lessons ||--o{ lesson_notes : notes

  schedule_change_requests ||--o{ lesson_schedule_changes : may_produce

  payments ||--o| payment_refunds : refund_at_most_one
```

---

## Plain-language relationship summary

### Authentication and people

- Each **profile** links to at most one Supabase Auth user and carries a single application **role**.
- A **student** business record may optionally link to one profile (login). A student without a profile is still a valid enrolled student.
- A **teacher** business record may optionally link to one profile. Teaching staff can exist before login activation.

### Curriculum and products

- Each **course** is a subject or curriculum (e.g. vocal).
- Each **course_product** belongs to one course and defines the commercial package (lesson count, weekly frequency, default tuition). Multiple products may exist per course.

### Pass aggregate

- Each **pass** belongs to one student and one course, references the product used at creation, and stores **immutable snapshots** of product name, lesson count, frequency, and tuition.
- Passes are sequenced per (student, course) via `sequence_number` and exposed as immutable `pass_code` (e.g. `V-S006-001`).
- A pass may reference a **previous pass** (renewal chain) and optionally a **correction source pass** (mistaken cancel/refund correction per OD-11).
- At most **one active** and **zero or one reserved** pass exist per (student, course) at any time.

### Fixed schedule and lessons

- Each **schedule_slot** belongs to one pass and defines weekday + local start time + duration + teacher. A pass may have multiple slots (weekly twice → usually two).
- Each **lesson** belongs to one pass and copies `student_id` and `course_id` for RLS performance; these must stay consistent with the pass.
- Lessons have a sequence number unique within the pass. Status is the **only** deduction source of truth.
- A **makeup** lesson may reference a **source lesson** via self-FK; duplicate completed makeup for the same source is blocked.

### Payments and refunds

- Each **payment** belongs to a student, course, and product context. It carries a unique **idempotency key**.
- On trusted completion, payment links to at most one **renewed pass** and may reference a **related (prior) pass**.
- **payment_refunds**: **zero or one** row per payment (MVP, OD-13). Row existence means refund completed successfully. Separate historical record (OD-12). Refunds do not delete payments or passes.

### SMS

- **sms_notifications** rows tie to a student and pass. MVP uses **one primary lifecycle row per pass**; creating a new pass creates a new notification row; old pass notification history remains.

### Schedule changes

- **schedule_change_requests** target a lesson; teachers or students submit; owner approves or rejects.
- **lesson_schedule_changes** append each schedule move with previous/new timestamps and **change_origin** (direct, cascade, trusted, correction).

### Notes and audit

- **lesson_notes** attach to lessons with visibility internal vs student-visible.
- **audit_logs** append-only; optional **correlation_id** groups trusted multi-table operations.

---

## Related documents

- [data-model.md](./data-model.md)
- [schema-dictionary.md](./schema-dictionary.md)
- [data-integrity-constraints.md](./data-integrity-constraints.md)

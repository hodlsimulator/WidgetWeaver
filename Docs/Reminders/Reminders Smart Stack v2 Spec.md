# Reminders Smart Stack v2 — Behaviour Spec (pages, dedupe, ordering)

Date: 2026-01-28  
Scope: Reminders-only (Smart Stack widget pages). Spec only; no implementation details required.

## Deliverable and acceptance criteria

This document defines the Smart Stack v2 behaviour as a pure partitioning of one widget snapshot of reminders into exactly six pages.

Acceptance criteria:

1. Smart Stack v2 contains exactly six pages, with fixed order and user-facing names:
   1) Overdue  
   2) Today  
   3) Upcoming  
   4) High priority  
   5) Anytime  
   6) Lists
2. For a single widget refresh/snapshot, no reminder row (by stable reminder ID) appears in more than one Smart Stack page.
3. “Upcoming” never includes “Today”. (The upcoming window starts at tomorrow’s local day boundary.)
4. “Lists” never repeats any item already visible on pages 1–5. It is the true remainder.
5. Ordering is deterministic for every page, with a stable final tie-break using reminder ID to avoid refresh reordering.

## Goals

1. Make the six pages and their rules unambiguous.
2. Remove overlaps present in v1:
   - “Soon” vs “Today”: “Upcoming” must exclude “Today”.
   - “Priority” vs “Focus”: consolidate into a single “High priority” concept.
   - “Lists” vs everything: “Lists” must only show items not already shown elsewhere.
3. Ensure a clear day-boundary contract in local time.

## Terminology

Snapshot
- The single set of reminder items available to the widget at one refresh.
- Smart Stack v2 does not change which reminders are eligible; it only partitions the snapshot.

Eligible reminder
- Any reminder item in the snapshot input set (after any existing kit/design baseline filtering such as list selection and “incomplete only”).

Reminder ID
- A stable identifier used for deduplication and deterministic tie-breaking.
- Deduplication is by ID, not by title.

Local calendar day
- All day-level comparisons are done using the user’s current Calendar and Time Zone at the time the snapshot is built.
- “Day boundary” means the start of a local day as defined by the Calendar (not “now minus 24 hours”). This matters around daylight saving changes.

Day-boundary anchors (conceptual)
- `now`: the time at which the snapshot is evaluated.
- `startOfToday`: start of the local calendar day containing `now`.
- `startOfTomorrow`: start of the local calendar day after `startOfToday`.
- `startOfDayPlus8`: start of the local day 8 days after `startOfToday`.

Due date vs due day
- If a reminder has a due date (date-only or timed), it has a due day: the local calendar day that contains that due date.
- If a reminder has no due date, it has no due day.
- If due date components are missing/invalid such that a local due day cannot be derived, treat it as “no due date” for classification.

Upcoming window definition
- “Upcoming” is tomorrow through the next 7 days (inclusive at day granularity).
- Formally, a reminder is “Upcoming” if it has a due date and:
  - dueDate ∈ [startOfTomorrow, startOfDayPlus8)
  - i.e. any due day from tomorrow (day +1) through day +7 inclusive.

Priority definition
- A reminder is considered “high priority” if its priority value is in 1–4 inclusive.
- Lower numbers indicate higher priority (1 is highest).
- Missing/0 priority is treated as “not high priority”.

## Smart Stack pages (fixed order)

The Smart Stack consists of exactly these six pages, in this order:

1) Overdue  
2) Today  
3) Upcoming  
4) High priority  
5) Anytime  
6) Lists

## Partitioning and deduplication rule

Smart Stack v2 is a non-overlapping partition of the snapshot, using first-match precedence in the page order above.

Conceptual algorithm:

- Start with `unassigned = all eligible reminders in the snapshot`.
- For each page in order (Overdue → Today → Upcoming → High priority → Anytime → Lists):
  - Select from `unassigned` the reminders matching that page’s inclusion rule.
  - Assign them to that page.
  - Remove them from `unassigned` by reminder ID.

Result:
- Each reminder ID appears in at most one page for that snapshot.
- Overlaps are resolved by construction (earliest page wins).

Known overlap resolutions (required):
- Due today + high priority → Today only.
- No due date + high priority → High priority only.
- Due tomorrow + high priority → Upcoming only.
- Anything captured in pages 1–5 → never appears again in Lists.

## Deterministic ordering contract

For each page, ordering must be deterministic and must not depend on the source array order.

- Each page defines an explicit sort key.
- The final tie-break for any sort must be reminder ID (ascending) to prevent refresh reordering.

## Page definitions

### 1) Overdue

User-facing name: Overdue

Inclusion rule:
- Reminder has a due day AND the due day is strictly before today’s day.
- Classification is day-based: any reminder due on a prior local calendar day is overdue, regardless of time-of-day.

Exclusion rule:
- None (this page has highest precedence).

Ordering (within Overdue):
1. Earlier due date/time first (older/more overdue first).
2. Higher priority first (numerically lower priority value).
3. Stable alphabetical by title (locale-aware).
4. Final tie-break: reminder ID.

Empty state:
- Heading: Overdue
- Message: Nothing overdue

### 2) Today

User-facing name: Today

Inclusion rule:
- Reminder has a due day AND the due day is today’s day.

Exclusion rule:
- Excludes anything already assigned to Overdue.

Ordering (within Today):
1. Timed reminders (explicit due time) before date-only reminders.
2. Among timed reminders: earlier due time first.
3. Among date-only reminders: higher priority first, then alphabetical by title.
4. Final tie-break: reminder ID.

Empty state:
- Heading: Today
- Message: Nothing due today

### 3) Upcoming

User-facing name: Upcoming

Inclusion rule:
- Reminder has a due date AND due date is within the upcoming window:
  - dueDate ∈ [startOfTomorrow, startOfDayPlus8)

Exclusion rule:
- Excludes anything already assigned to Overdue or Today.

Ordering (within Upcoming):
1. Earlier due date/time first.
2. Higher priority first (numerically lower value).
3. Alphabetical by title.
4. Final tie-break: reminder ID.

Empty state:
- Heading: Upcoming
- Message: Nothing upcoming

Notes:
- This definition deliberately eliminates the “Upcoming vs Today” overlap by starting at tomorrow’s day boundary.

### 4) High priority

User-facing name: High priority

Inclusion rule:
- Reminder priority is in 1–4 inclusive AND it is not already assigned to Overdue/Today/Upcoming.

What this page represents:
- High priority reminders that are not already time-urgent in the first three pages.

Ordering (within High priority):
1. Priority value ascending (1 before 2 before 3 before 4).
2. If a due date exists (e.g. due beyond the upcoming window): earlier due date/time first; reminders with no due date sort after reminders with a due date.
3. Alphabetical by title.
4. Final tie-break: reminder ID.

Empty state:
- Heading: High priority
- Message: No high priority reminders

### 5) Anytime

User-facing name: Anytime

Inclusion rule:
- Reminder has no due date (no due day) AND is not already assigned to any prior page.

Exclusion rule:
- Excludes high priority no-due reminders, because those are captured by “High priority” via precedence.

Ordering (within Anytime):
1. Higher priority first (numerically lower; reminders with missing/0 priority sort after explicit priorities).
2. Alphabetical by title.
3. Final tie-break: reminder ID.

Empty state:
- Heading: Anytime
- Message: No anytime reminders

### 6) Lists

User-facing name: Lists

Inclusion rule:
- Any remaining unassigned reminder, regardless of due date or priority, after applying pages 1–5.

Primary purpose:
- A true remainder/catch-all page. It must not repeat items already visible elsewhere in the Smart Stack.

Presentation rule (logical, not layout):
- Reminders are grouped by their originating Reminders list/calendar.
- Only lists with at least one remaining reminder appear.

Ordering (lists/sections):
1. Use the user’s existing list ordering if available from the Reminders source.
2. Otherwise, sort list names alphabetically (locale-aware).
3. Final tie-break: list ID.

Ordering (within each list section):
1. If due date/time exists: earlier due date/time first.
2. Higher priority first.
3. Alphabetical by title.
4. Final tie-break: reminder ID.

Empty state:
- Heading: Lists
- Message: No other reminders

## Additional clarifications and edge cases

1. Completed reminders
- Completed items are expected to be excluded by existing v1 baseline filtering.
- Smart Stack v2 does not add completion filtering; it partitions whatever the snapshot contains.

2. Missing/invalid due components
- If due date components cannot be interpreted into a local calendar day, treat as “no due date” for classification.
  - Therefore: High priority if priority is 1–4, otherwise Anytime, otherwise Lists by remainder.

3. Snapshot time at day rollover
- Classification uses the local calendar day containing `now` at the time the snapshot is evaluated.
- If a refresh occurs around midnight, reminders may move between “Today” and “Overdue/Upcoming” on the next snapshot; this is expected.

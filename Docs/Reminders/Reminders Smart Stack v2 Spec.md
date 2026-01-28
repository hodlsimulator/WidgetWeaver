# Reminders Smart Stack v2 — Page Definitions and Non-Overlapping Rules

Date: 2026-01-28  
Scope: Reminders-only (Smart Stack widget pages). Spec only; no implementation details required here.

## Goals

1. Clarify the six Smart Stack pages with unambiguous, user-facing names and rules.
2. Resolve v1 overlaps:
   - “Soon” vs “Today”: “Upcoming” must exclude “Today”.
   - “Priority” vs “Focus”: consolidate semantics into a single “High priority” page.
   - “Lists” vs everything: “Lists” must only show items not already shown elsewhere.
3. Acceptance criterion: For a single widget refresh/snapshot, no reminder row appears in more than one Smart Stack page.

## Terminology

Snapshot: The single set of reminder items available to the widget at one refresh (after any existing v1 baseline filters such as list selection and “incomplete only”). Smart Stack v2 operates purely on this snapshot.

Eligible reminder: Any reminder item included in the snapshot input set. Smart Stack v2 does not expand or shrink the snapshot; it only partitions it.

Reminder ID: A stable identifier for deduplication within the snapshot (for example, EventKit calendarItemIdentifier or an app-level stable ID). Deduplication is by ID, not by title.

Local day boundaries:
- `startOfToday`: start of the current day in the user’s current calendar/time zone.
- `startOfTomorrow`: start of the next day.
- All day-level comparisons use the user’s local calendar day.

Due day:
- If a reminder has a due date/time, it has a due day (local calendar day).
- If a reminder has no due date, it has no due day.

Upcoming window:
- “Upcoming” includes reminders due from tomorrow up to 7 days ahead.
- Formally: dueDate ∈ [startOfTomorrow, startOfToday + 8 days), i.e. tomorrow through the end of the 7th day after today (inclusive at day granularity).

Priority mapping:
- A reminder is considered “high priority” if it has an explicit priority value in the high band.
- Recommended definition for determinism: `priority` in 1...4 is “high”, where lower numbers indicate higher priority (consistent with common Reminders/EventKit conventions). If priority is missing/0, it is not high priority.

## Smart Stack v2 page order and names

The Smart Stack consists of exactly these six pages, in this order:

1) Overdue  
2) Today  
3) Upcoming  
4) High priority  
5) Anytime  
6) Lists

## Partitioning rule (non-overlapping guarantee)

Each eligible reminder must be assigned to at most one page, determined by first-match precedence in the page order above.

Algorithm definition (conceptual):
- Start with `unassigned = all eligible reminders in snapshot`.
- For each page in order (Overdue → … → Lists), select from `unassigned` the reminders matching that page’s inclusion rule, assign them to that page, and remove them from `unassigned`.
- Result: each reminder ID can appear in only one page for that snapshot.

This precedence is the contract that prevents duplicates and resolves the known overlaps.

## Page definitions

### 1) Overdue
User-facing name: “Overdue”

Inclusion rule:
- Reminder has a due day AND due day is strictly before today’s day.
- (Time of day does not change classification: any due date on a prior calendar day is overdue.)

Exclusion rule:
- Anything already assigned by precedence (none, since this is first).

Ordering (within Overdue):
1. Earliest due date/time first (most overdue at the top).
2. If due date/time ties, higher priority first (numerically lower priority value).
3. If still tied, stable alphabetical by title (locale-aware).
4. Final tiebreak: reminder ID (ascending) to keep deterministic output.

Empty state:
- Title: “Overdue”
- Message: “Nothing overdue”

### 2) Today
User-facing name: “Today”

Inclusion rule:
- Reminder has a due day AND due day is today’s day.

Exclusion rule:
- Excludes any reminder already assigned to Overdue.

Ordering (within Today):
1. Timed reminders (with an explicit due time) before all-day/date-only reminders.
2. Among timed reminders: earliest due time first.
3. Among date-only reminders: higher priority first, then alphabetical by title.
4. Final tiebreak: reminder ID.

Empty state:
- Title: “Today”
- Message: “Nothing due today”

### 3) Upcoming
User-facing name: “Upcoming”

Inclusion rule:
- Reminder has a due date/time AND due date/time falls within the upcoming window:
  - Due is tomorrow or later, but within the next 7 days (as defined above).

Exclusion rule:
- Excludes any reminder already assigned to Overdue or Today.

Ordering (within Upcoming):
1. Earliest due date/time first.
2. Higher priority first (numerically lower value).
3. Alphabetical by title.
4. Final tiebreak: reminder ID.

Empty state:
- Title: “Upcoming”
- Message: “Nothing upcoming”

Notes:
- This definition deliberately eliminates the v1 “Soon vs Today” overlap by excluding today entirely.

### 4) High priority
User-facing name: “High priority”

Inclusion rule:
- Reminder is high priority (priority in 1...4) AND is not already assigned to Overdue/Today/Upcoming.

What this page represents:
- A “catch high priority that is not already time-urgent in the first three pages”.
- This resolves “Priority vs Focus” by making the concept singular and explicit: “High priority”.

Ordering (within High priority):
1. Priority value ascending (1 before 2 before 3 before 4).
2. If due date/time exists (e.g., due beyond the upcoming window), earlier due date/time first; if no due date, sort after any dated items.
3. Alphabetical by title.
4. Final tiebreak: reminder ID.

Empty state:
- Title: “High priority”
- Message: “No high priority reminders”

### 5) Anytime
User-facing name: “Anytime”

Inclusion rule:
- Reminder has no due date (no due day) AND is not already assigned to any prior page.

Exclusion rule:
- Excludes high priority no-due reminders, because those are captured by “High priority” via precedence.

Ordering (within Anytime):
1. Higher priority first (numerically lower; reminders with missing/0 priority sort after explicit priorities).
2. Alphabetical by title.
3. Final tiebreak: reminder ID.

Empty state:
- Title: “Anytime”
- Message: “No anytime reminders”

### 6) Lists
User-facing name: “Lists”

Inclusion rule:
- Any remaining unassigned reminder, regardless of due date, priority, or list, after applying the first five pages.

Primary purpose:
- A true remainder/catch-all page to resolve the “Lists vs everything” overlap. It must not repeat items already visible elsewhere in the Smart Stack.

Presentation rule (logical, not layout):
- Reminders are grouped by their originating Reminders list/calendar.
- Only lists with at least one remaining reminder appear.

Ordering (lists/sections):
1. Use the user’s existing list ordering if available from the Reminders source.
2. Otherwise, sort list names alphabetically (locale-aware).
3. Final tiebreak: list ID.

Ordering (within each list section):
1. If due date/time exists: earliest due date/time first.
2. Higher priority first.
3. Alphabetical by title.
4. Final tiebreak: reminder ID.

Empty state:
- Title: “Lists”
- Message: “No other reminders”

## Additional clarifications / edge cases

1. Completed reminders
- Completed items are not eligible if the v1 baseline already excludes them (expected).
- Smart Stack v2 does not add any new completion filtering; it partitions whatever the snapshot contains.

2. Missing/invalid due components
- If due date components cannot be interpreted into a local calendar day, treat the reminder as “no due date” for classification purposes (therefore it will land in High priority if high priority, otherwise Anytime, otherwise Lists by remainder).

3. Time zone and calendar determinism
- All day boundary comparisons use the user’s current calendar and time zone at snapshot time.
- This keeps classification stable and prevents “Today”/“Overdue” flicker across pages within the same snapshot.

4. Deterministic output
- Sorting must be stable and include a final ID tiebreak so that two identical titles do not reorder across refreshes.

## Non-goals (explicitly out of scope for Step 1)

- No layout or density changes (handled later).
- No changes to the baseline reminder query (permissions, list selection, limits).
- No changes outside Reminders + related kit catalogue/guide copy.

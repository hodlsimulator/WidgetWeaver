# WidgetWeaver

WidgetWeaver is an **iOS 26-only** prototype app that turns a typed “widget design spec” into real WidgetKit widgets.

The project is a playground for exploring:

- A simple typed JSON-ish design spec (`WidgetSpec`)
- Deterministic SwiftUI rendering in a WidgetKit extension (`WidgetWeaverSpecView`)
- A lightweight template catalogue (the **Explore** tab) for seeding designs
- Pro features (matched sets + variables + interactive buttons)
- Optional on-device AI for spec generation and patch edits

The app and widget extension communicate via an App Group (UserDefaults + shared files) so widgets can render offline.

---

## App structure

WidgetWeaver has three tabs:

- **Explore**: featured widgets + templates + setup entry points (Weather / Calendar / Steps)
- **Library**: saved designs (set Default, duplicate, delete)
- **Editor**: edits the currently selected design; **Save** pushes changes to widgets

Widgets refresh when a design is saved. If something looks stale, the in-app refresh action can be used (Editor → … → Refresh Widgets).

---

## Featured — Weather

WidgetWeaver includes a built-in **WeatherKit-powered Weather layout template** (`LayoutTemplateToken.weather`):

- Rain-first “next hour” nowcast chart (Dark Sky-ish)
- Hourly strip + daily highs/lows (when data is available)
- Glass container + glow styling
- Adaptive Small / Medium / Large layouts
- Exposes `__weather_*` **built-in variables** usable in any text field (no Pro required)
- Includes a Lock Screen companion widget: **Rain (WidgetWeaver)** (accessory rectangular)

### Weather setup checklist

- Explore → Weather: location selected (Current Location or search)
- Weather snapshot cached (Update now)
- Weather template added into the Library (optionally “Add & Make Default”)
- Widgets added:
  - Home Screen: **WidgetWeaver** (select a Weather design), and/or
  - Lock Screen: **Rain (WidgetWeaver)**

Notes:

- Widgets refresh on a schedule, but **WidgetKit may throttle updates**.
- Weather UI provides “Update now” to refresh the cached snapshot used by widgets.

---

## Featured — Next Up (Calendar)

WidgetWeaver includes a built-in **Next Up (Calendar) layout template** (`LayoutTemplateToken.nextUpCalendar`):

- Next calendar event with a live countdown
- Medium/Large can also show a “Then” line (second upcoming event)
- Cached calendar snapshot stored in the App Group (offline-friendly widgets)
- Looks ahead until upcoming events are found (not limited to “next 24 hours”)
- Includes a Lock Screen companion widget: **Next Up (WidgetWeaver)** (inline / circular / rectangular)

### Next Up (Calendar) setup checklist

- Explore → Templates: **Next Up (Calendar)** added into the Library
- Calendar permission granted
- Calendar snapshot cached (Next Up refresh action)
- Widgets added:
  - Home Screen: **WidgetWeaver** (select a Next Up design), and/or
  - Lock Screen: **Next Up (WidgetWeaver)**

Notes:

- Calendar widgets render from a cache.

If the widget looks stale:

- refresh the Calendar snapshot (Next Up refresh action), then
- refresh widget timelines (Editor → … → Refresh Widgets).

---

## Featured — Steps (Pedometer)

WidgetWeaver includes a built-in **HealthKit-powered Steps mini-app** plus widgets:

- Today’s step count snapshot (offline-friendly for widgets)
- **Goal schedule** (weekday / weekend goals, with optional rest days)
- **Streak rules** designed to feel fair:
  - “Fair” rule avoids showing the streak as broken early in the day
  - Rest days (goal = 0) can be skipped without breaking
- **Full-history timeline in-app**: loads daily step totals back to the earliest available step sample
- **Monthly calendar view** with goal-hit dots (tap a day → jump to that day in the timeline)
- **Year heatmap view** (GitHub-style grid) with year picker + “best week / most consistent month”
- “Pin this day” action from history (creates a saved design highlight for that day)
- **Steps built-in variables** (`__steps_*`) usable in any design text field once Steps is set up
- Lock Screen companion widget: **Steps (WidgetWeaver)** (inline / circular / rectangular)
- Home Screen companion widget: **Steps (Home)** (Small / Medium / Large)

### Steps setup checklist

- Health permission granted for Step Count
- Steps refreshed in-app to cache:
  - Today’s steps snapshot (for widgets and `__steps_today`), and
  - Full history (for streak / averages / heatmap / calendar)
- Optional: weekday/weekend goals configured and a streak rule selected
- Widgets added:
  - Lock Screen: **Steps (WidgetWeaver)**
  - Home Screen: **Steps (Home)**
  - Or: `__steps_*` variables used inside any normal **WidgetWeaver** design

Notes:

- If “0 steps” appears unexpectedly, Fitness Tracking may be disabled or no step samples may be recorded.
- Health access can be inspected via the Steps settings screen.

---

## Featured — Clock (Home Screen)

WidgetWeaver includes a Small Home Screen clock widget (`WidgetWeaverHomeScreenClockWidget`) with a configurable colour scheme and an Apple-style second hand.

### Why the clock is tricky

WidgetKit budgets timeline reloads. High-frequency widget timelines (for example: 1–2 second timeline entries) can look great briefly, then get coalesced or throttled.

On iOS 26 Home Screen, some hosting paths also freeze `TimelineView` schedules and can ignore long-running SwiftUI animations.

### Clock animation strategies (history + trade-offs)

1) **Timeline-driven redraws + short linear sweeps** (most reliable when budgets allow)

- Provider emits frequent timeline entries (`tickSeconds` around 2–15s, capped `maxEntries`, policy `.atEnd`).
- The view wraps rendering in `WidgetWeaverRenderClock.withNow(entry.date)` and computes monotonic hand angles from `entry.date` so interpolation never runs backwards at wrap boundaries.
- The sweeping effect comes from `.animation(.linear(duration: tickSeconds), value: secondDegrees)` between entries.

Notes:

- The update cadence can eventually be throttled by WidgetKit.
- Alignment to whole seconds (base = `ceil(timeIntervalSinceReferenceDate)`) keeps the sweep phase-locked.

2) **Widgy-style CoreAnimation sweeps** (no timeline spam, but host-dependent)

- Keep the provider sparse (hourly or less) and start CoreAnimation-backed `repeatForever` sweeps on appearance.
- Uses three phase values (seconds / minutes / hours) and resyncs to `Date()` on appearance to catch up after suspension.

Status: not reliably animated on Home Screen; the hosting view can be paused/frozen.

3) **Heartbeat driver** (in-view periodic invalidation)

- Keep the provider sparse (hourly) but drive an in-view periodic tick (for example: `TimelineView(.periodic(...))`) so the view re-evaluates.

Status: can render but has been unreliable; the clock can stop even after a widget kind bump.

4) **Long single sweep per interval** (previous attempt)

- Provider emits an immediate “now” entry plus hour-boundary entries; each entry carries `intervalStart` and `intervalEnd`.
- The view snaps hands to real current time on appear, then attempts a single long `.linear` animation towards `intervalEnd` using monotonic (unbounded) angle maths.

Status: snaps correctly but often remains stopped (no ongoing animation).

5) **Minute-boundary timelines + stable tree + second-hand experiments** (current strategy)

- Provider emits **minute-boundary** timeline entries (for example: 60–120 entries ≈ 1–2 hours), policy `.atEnd`.
- Goal: the minute hand updates reliably while avoiding whole-widget “blink”.
- Key behavioural win: avoiding subtree replacement (for example: `.id(minuteAnchor)`) keeps the minute tick smooth (no fade-out/fade-in).
- Second-hand goal: tick all day without 1 Hz WidgetKit timeline entries.
- Current approach: keep the timeline minute-boundary and attempt to drive the second hand from a host-animated primitive (`ProgressView(timerInterval: minuteAnchor...minuteAnchor+60)`), not from SwiftUI timers.
- Findings so far:
  - The host will animate `ProgressView(timerInterval: ...)` in some real device contexts (Release-signed), but `ProgressViewStyle.Configuration.fractionCompleted` is often not updated for date-range progress. Any custom seconds hand that derives its angle from `fractionCompleted` can stick at 12 even while the ProgressView animates.
  - In some debug builds the widget can remain in placeholder/privacy redaction on Home Screen; when that happens WidgetKit may not advance minute-boundary entries, so `minuteAnchor` doesn’t change and “reset each minute” tests are misleading.
- Status: minute stepping is reliable and does not blink; second hand is currently stuck at 12 in the latest sweep attempts and still needs a host-driven solution that doesn’t depend on `fractionCompleted`.

### Files

- `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift` — minute-boundary timeline generation (entry cap, policy `.atEnd`)
- `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift` — stable-tree clock rendering + second-hand experiments
- `WidgetWeaverWidget/Clock/WidgetWeaverClockLiveView.swift` — experimental Widgy-style `repeatForever` driver
- `Shared/WidgetWeaverRenderClock.swift` — helpers for injecting a deterministic “now” into rendering

### Sweeping second hand (time maths)

The core time maths is:

- `local = now.timeIntervalSince1970 + TimeZone.autoupdatingCurrent.secondsFromGMT(for: now)`
- `secondDeg = local * 6.0`
- `minuteDeg = local * (360.0 / 3600.0)`
- `hourDeg = local * (360.0 / 43200.0)`

Using monotonic degrees avoids reverse interpolation if any implicit animation is introduced elsewhere.

### Archived snapshots during iteration

WidgetKit can hold onto an archived snapshot from a failed render; during iteration a widget can appear partially rendered or stuck until a clean archive occurs.

If a clock widget remains stuck after code changes, bump the clock widget kind string (`WidgetWeaverWidgetKinds.homeScreenClock`) to force a clean archive.

### RenderClock recursion pitfall

`WidgetWeaverRenderClockScope.body` must not call `WidgetWeaverRenderClock.withNow(...)` from inside the scope.

Overload resolution can re-wrap a new scope repeatedly, causing infinite SwiftUI view recursion and a black Home Screen widget.

---

## Current status (0.9.4 (15))

### App

- ✅ Explore tab: featured widgets + template catalogue (adds templates into the Library)
- ✅ Library of saved specs + Default selection
- ✅ Editor for `WidgetSpec`
- ✅ Free tier: up to `WidgetWeaverEntitlements.maxFreeDesigns` saved designs
- ✅ Pro: unlimited saved designs
- ✅ Pro: matched sets (S/M/L) share style tokens
- ✅ Share/export/import JSON (optionally embedding images)
- ✅ Optional on-device AI (generate + patch)
- ✅ Weather setup + cached snapshot + attribution
- ✅ Calendar snapshot engine for Next Up (permission + cached “next/second” events)
- ✅ Steps setup (HealthKit access + cached today snapshot + goal schedule + streak rules)
- ✅ Steps History (timeline + monthly calendar + year heatmap) + insights + “Pin this day”
- ✅ Inspector sheet (resolved spec + JSON + quick checks)
- ✅ In-app preview dock (preview vs live, Small/Medium/Large)

### Widgets

- ✅ **Home Screen widget (“WidgetWeaver”)** renders a saved design (Small / Medium / Large)
- ✅ **Lock Screen widget (“Rain (WidgetWeaver)”)** next hour precipitation + temperature + nowcast (accessory rectangular)
- ✅ **Lock Screen widget (“Next Up (WidgetWeaver)”)** next calendar event + countdown (inline / circular / rectangular)
- ✅ **Lock Screen widget (“Steps (WidgetWeaver)”)** today’s step count + optional goal gauge (inline / circular / rectangular)
- ✅ **Home Screen widget (“Steps (Home)”)** today’s step count + goal ring (Small / Medium / Large)
- **Home Screen widget (“Clock (Icon)”)** analogue clock face (Small); sweeping second hand is experimental (see Clock section)
- ✅ Per-widget configuration (Home Screen “WidgetWeaver” widget): Default (App) or pick a specific saved design
- ✅ Optional interactive action bar (Pro) with up to 2 buttons that run App Intents and update Pro variables (no Shortcuts setup required)
- ✅ Weather + Calendar templates render from cached snapshots stored in the App Group
- ✅ Steps widgets render from a cached “today” snapshot stored in the App Group
- ✅ `__weather_*` built-in variables available in any design (free)
- ✅ `__steps_*` built-in variables available in any design once Steps is set up (free)
- ✅ Time-sensitive designs can attempt minute-level timelines (still subject to WidgetKit throttling)

### Layout + style

- ✅ Layout templates: Classic / Hero / Poster / Weather / Next Up (Calendar) (includes a starter Steps design via `__steps_*` keys)
- ✅ Axis: vertical/horizontal; alignment; spacing; line limits
- ✅ Accent bar toggle
- ✅ Style tokens: padding, corner radius, background token, overlay, glow, accent
- ✅ Optional SF Symbol spec (name/size/weight/rendering/tint/placement)
- ✅ Optional banner image (stored in App Group container)

### Components

- ✅ Built-in typed models: `WidgetSpec`, `LayoutSpec`, `StyleSpec`, `SymbolSpec`, `ImageSpec`
- ✅ Rendering path: `WidgetWeaverSpecView` (SwiftUI)
- ✅ Variable template engine: `WidgetWeaverVariableTemplate` (stored vars are Pro-only)
- ✅ WeatherKit integration: `WidgetWeaverWeatherEngine`, `WidgetWeaverWeatherStore`, Weather template renderer
- ✅ Calendar integration: `WidgetWeaverCalendarEngine`, `WidgetWeaverCalendarStore`, Next Up template renderer
- ✅ HealthKit steps integration: `WidgetWeaverStepsEngine`, `WidgetWeaverStepsStore`, Steps settings + history + widgets + built-in vars
- ✅ App Group store: `WidgetSpecStore`, `WidgetWeaverVariableStore`, `AppGroup`

---

## Project setup checklist

- Xcode project opened
- Team + bundle identifiers configured for app + widget targets
- App Groups configured:
  - Both targets have the App Group capability enabled
  - Default identifier: `group.com.conornolan.widgetweaver` (see `Shared/AppGroup.swift`)
  - If the identifier changes, updates are required in:
    - `Shared/AppGroup.swift` (`AppGroup.identifier`)
    - `WidgetWeaver/WidgetWeaver.entitlements`
    - `WidgetWeaverWidgetExtension.entitlements`
- First run: templates added from **Explore** into the Library
- Designs edited in **Editor**, then saved to push updates to widgets
- Weather / Calendar / Steps setup performed (for templates that depend on cached snapshots)

Widgets can be added from the Home Screen / Lock Screen widget galleries and configured to select a specific saved design when relevant.

Pro features require a Pro unlock; Variables and Actions become available in the editor after unlock.

---

## Editor features

### Layout templates

- **Classic**: stacked header + text, optional symbol, optional accent bar
- **Hero**: text left, big symbol right (when present), optional accent bar
- **Poster**: photo-first with a gradient overlay for text
- **Weather**: WeatherKit-powered, rain-first nowcast layout with glass panels and adaptive S/M/L layouts
- **Next Up (Calendar)**: next event + countdown (optionally “Then” on Medium/Large)

### Built-in variables (free)

Built-in variables are available in any text field via `{{...}}` templating.

Weather:

- `__weather_location_name`
- `__weather_temperature`
- `__weather_temperature_feels_like`
- `__weather_condition`
- `__weather_condition_symbol`
- `__weather_rain_next_hour_mm`
- `__weather_rain_next_hour_max_mm_hr`
- `__weather_rain_next_hour_summary`
- `__weather_hourly_strip`
- `__weather_daily_high`
- `__weather_daily_low`

Steps:

- `__steps_today`
- `__steps_goal_today`
- `__steps_progress_today`
- `__steps_streak`
- `__steps_avg_7`, `__steps_avg_7_exact`
- `__steps_avg_30`, `__steps_avg_30_exact`
- `__steps_best_day`
- `__steps_best_day_date`
- `__steps_best_day_date_iso`

Access/debug:

- `__steps_access`

Example:

- `Steps: {{__steps_today|--}} • Streak {{__steps_streak|0}}d`

### Stored variables (Pro)

The shared variable store is Pro-only and can be updated in-app or via widget buttons (App Intents).

---

## AI (Optional)

AI features are designed to run on-device to generate or patch the design spec. Images are never generated.

---

## Licence / notes

This is a prototype playground; it is not intended as a production app yet.

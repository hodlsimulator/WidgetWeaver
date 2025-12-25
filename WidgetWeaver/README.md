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

- Calendar widgets render from a cache. If the widget looks stale:
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

WidgetWeaver includes a Small Home Screen clock widget (`WidgetWeaverHomeScreenClockWidget`) with a configurable colour scheme and an Apple-style sweeping second hand.

Current dev builds can snap to the correct time and then freeze; see **Public per-second ticking plan (WIP)** below.

### Sweeping second hand (implementation notes)

WidgetKit doesn’t guarantee 1 Hz redraws for non-text content on the Home Screen. On iOS 26 (iPhone 16 Pro), updates often coalesce to ~2 seconds even if a 1-second timeline is provided. To get a smooth sweep without whole-widget blinking or frozen renders, the clock previously used:

1. A modest timeline cadence (2 seconds) in `WidgetWeaverHomeScreenClockProvider` (for example: `tickSeconds = 2`, `maxEntries ≈ 180`).
2. Monotonic angles derived from time (no `mod 360`), using local-time seconds:
   - `localT = date.timeIntervalSinceReferenceDate + TimeZone.current.secondsFromGMT(for: date)`
   - `secondDegrees = localT * (360.0 / 60.0)` (and similar for minute/hour).
3. Explicit linear animations across the full tick interval so the hands move continuously between timeline entries:

        let tz = TimeInterval(TimeZone.current.secondsFromGMT(for: date))
        let localT = date.timeIntervalSinceReferenceDate + tz

        let secondDegrees = localT * (360.0 / 60.0)
        SecondHand()
            .rotationEffect(.degrees(secondDegrees))
            .animation(.linear(duration: tickSeconds), value: secondDegrees)

4. No root identity churn (no `.id(entry.date)` or similar) to prevent “entire widget flashes each tick”.

Hard “ticks” (instead of a sweep) are produced by quantising `localT` to whole seconds before computing degrees.

WidgetKit may hold onto an archived snapshot from a failed render; during iteration a widget can appear partially rendered or stuck until a clean archive occurs.

### Public per-second ticking plan (WIP)

Goal: restore a reliably ticking clock using **public APIs only** (App Review-safe) without relying on high-frequency WidgetKit timelines (which trigger throttling). Private API/backdoor approaches (for example anything like `_clockHandRotationEffect`) are intentionally avoided.

High-level approach:

- Keep `WidgetWeaverHomeScreenClockProvider` timelines sparse (one entry, refresh every few hours).
- Drive the hands from a SwiftUI “time-aware” view that iOS updates internally on the Home Screen (so the system can re-render without consuming the WidgetKit refresh budget).

Attempted drivers and outcomes:

1. `ProgressView(timerInterval:)` with a custom `ProgressViewStyle` reading `configuration.fractionCompleted` to derive the current time.
   - Observed outcome: `fractionCompleted` did not advance for the timer-interval progress view in that configuration, leaving hands static.
2. Hidden timer text driver using `Text(entry.date, style: .timer)` (transparent) and rendering the clock in an attached `background` driven from `Date()`.
   - Observed outcome: the timer text can update, but the host appears to update only the text layer; the clock subtree can still freeze (snaps once, then stops). This is the current behaviour.

Next iteration (public-only):

- Render the clock drawing within the same subtree as the dynamic timer text (overlaying the timer text itself rather than using sibling/background), to force the host to re-evaluate the same view subtree each tick.
- Add a DEBUG-only on-face seconds counter to confirm whether the host is actually re-evaluating the view hierarchy at 1 Hz.
- Keep timeline reloads low-frequency and avoid `WidgetCenter.shared.reloadAllTimelines()` loops while iterating; reload only the clock widget kind when its configuration changes.

Once reliable ticking returns, smooth sweeping can be reintroduced by interpolating within each second (hands-only), keeping the dial static.

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
- ✅ **Home Screen widget (“Clock (Icon)”)** analogue clock face with a sweeping second hand (Small)
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
- **Steps (Starter)**: a ready-made Steps design using built-in `__steps_*` keys

The layout is controlled via `LayoutSpec` (template + axis + alignment + spacing + line limits).

### Preview dock

The editor includes a collapsible preview dock:

- Size: Small / Medium / Large
- Mode: Preview vs Live (mimics widget rendering constraints)

### Photo theme extraction

A simple “image theme” can be extracted from a chosen photo to guide accent/background choices. Images are always chosen manually.

### Remix

Remix generates deterministic variants of a design by perturbing layout/style tokens, intended for rapid exploration without losing the original.

### Interactive actions (Pro)

Designs can include an action bar with up to 2 buttons:

- Buttons run App Intents directly from the widget
- Designed for quick “tap to update” workflows (increment a counter, set a timestamp)
- No Shortcuts app setup required for end users

### Templates

Templates live in **Explore**:

- Starter templates are free
- Pro templates can include matched sets, variables, and interactive buttons
- Templates are designed to be offline-friendly (shared App Group storage)
- Weather and Next Up (Calendar) use cached snapshots (widgets do not fetch directly)

### Sharing

Designs can be exported as JSON, optionally embedding images. Imports duplicate designs with new IDs to avoid overwriting existing ones.

### Inspector

Inspector shows the current spec JSON and allows quick checks while tuning the renderer.

---

## Variables + App Intents

WidgetWeaver supports template variables in text fields:

- `{{key}}`
- `{{key|fallback}}`
- `{{amount|0|number:0}}`
- `{{last_done|Never|relative}}`
- Inline maths: `{{=done/total*100|0|number:0}}`

### Built-in keys (available to everyone)

- `__now`, `__now_unix`
- `__today`
- `__time`
- `__weekday`

### Weather built-in keys (available to everyone)

Once a Weather location is set (and a snapshot is cached), these are available in any text field:

- `__weather_location`
- `__weather_condition`
- `__weather_symbol`
- `__weather_updated_iso`
- `__weather_temp`, `__weather_temp_c`, `__weather_temp_f`
- `__weather_feels`, `__weather_feels_c`, `__weather_feels_f` (when available)
- `__weather_high`, `__weather_low` (when available)
- `__weather_precip`, `__weather_precip_fraction` (when available)
- `__weather_humidity`, `__weather_humidity_fraction` (when available)

When a location is set but a snapshot hasn’t been cached yet, these can still be present:

- `__weather_lat`
- `__weather_lon`

Example:

- `Weather: {{__weather_temp|--}}° • {{__weather_condition|Updating…}}`

### Steps built-in keys (available to everyone)

Once Steps access is granted and the app has cached steps, these become available in any text field:

Today snapshot keys:

- `__steps_today`
- `__steps_goal_today`
- `__steps_today_percent`
- `__steps_today_fraction`
- `__steps_goal_hit_today`
- `__steps_updated_iso`

Goal schedule + behaviour:

- `__steps_goal_weekday`
- `__steps_goal_weekend`
- `__steps_streak_rule`

History-derived keys (require history cache):

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

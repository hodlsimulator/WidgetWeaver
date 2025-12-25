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
- If the widget looks stale:
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

### Per-second ticking without WidgetKit throttling (Widgy-style)

Goal: a second hand that **ticks every second** (ideally a smooth sweep) without using high-frequency WidgetKit timelines (which get throttled).

Chosen approach (public APIs only, App Review-safe):
- Keep `WidgetWeaverHomeScreenClockProvider` timelines **sparse** (single entry; refresh every few hours).
- Drive motion using a **view-local SwiftUI animation loop**:
  - Animate a `secPhase` from `0 → 1` over `60s` with `.linear(duration: 60).repeatForever`.
  - Do the same for minutes (`3600s`) and hours (`43200s`).
  - Compute the base angles from the current time at sync, then add `phase * 360` for each hand.
- When the widget is not visible, iOS may pause animations.
  - When it becomes visible again, the view re-appears and **re-syncs** to the current time.

Implementation:
- `WidgetWeaverWidget/Clock/WidgetWeaverClockLiveView.swift` contains the repeat-forever sweep driver.
- `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift` uses a sparse WidgetKit timeline and renders `WidgetWeaverClockLiveView`.

Notes:
- This avoids burning the WidgetKit refresh budget because the widget is not requesting per-second timeline entries.
- If WidgetKit holds onto an archived snapshot from a failed render, a widget can appear partially rendered or stuck until a clean archive occurs.

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

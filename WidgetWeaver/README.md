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

Widgets refresh when a design is saved. If something looks stale, use the in-app refresh action (Editor → … → Refresh Widgets).

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
  - Lock Screen: **Rain (WidgetWeaver)** (accessory rectangular)

Notes:

- Widgets refresh on a schedule, but the exact cadence is best‑effort (WidgetKit can delay or coalesce updates).
- Weather UI provides “Update now” to refresh the cached snapshot used by widgets.

### Nowcast rain surface chart rendering

The Weather template’s 0–60 minute nowcast chart uses a dedicated, widget-safe rendering pipeline.

**Used (current path)**

- `Shared/WidgetWeaverWeatherTemplateNowcastChart.swift` — builds a `RainForecastSurfaceConfiguration` tuned for the nowcast chart and renders `RainForecastSurfaceView`.
- `Shared/RainForecastSurfaceView.swift` — `Canvas` wrapper that fills a pure black background, applies WidgetKit budget guardrails, then calls the renderer.
- `Shared/RainForecastSurfaceRenderer.swift` — procedural core mound + **asset-driven subtractive dissipation** (the body “evaporates” into grain on the slopes); deterministic and budget-clamped.
- `Shared/RainSurfacePRNG.swift` — deterministic PRNG used for stable jitter/offsets.

**Not used for the Weather nowcast chart (legacy / experiments)**

- `Shared/RainSurfaceDrawing.swift`
- `Shared/RainSurfaceDrawing+Core.swift`
- `Shared/RainSurfaceDrawing+Fuzz.swift`
- `Shared/RainSurfaceDrawing+Rim.swift`
- `Shared/RainSurfaceGeometry.swift`
- `Shared/RainSurfaceMath.swift`
- `Shared/RainSurfaceStyleHarness.swift`

#### Technique (current): asset-driven subtractive dissipation

We changed approach because “adding fuzz” kept reading like an outline/halo and was hard to push without triggering WidgetKit placeholders.

The current technique is:

- Draw the **core body** normally (a filled mound with a vertical gradient).
- Then make the body **dissipate** by **subtracting opacity** near the contour:
  - A wide, soft erosion band establishes the fade into the slope.
  - A narrower erosion band is masked by a tiled speckle texture so the fade breaks into grain.
- Optional: a very faint continuation outside the body (“outer dust”) can be used, but it is treated as a budget risk in widgets and may be disabled or heavily clamped.

Key property:
- This technique does **not** add a coloured fuzz layer. It primarily removes alpha from the body, so the surface looks like it is dissolving into black.
- The goal is: **the body dissipates** (not a cyan halo, not a sharp outline).

#### Noise assets (required for the new look)

The dissipation grain comes from small tileable alpha textures derived from the mockup:

- `RainFuzzNoise` (normal)
- `RainFuzzNoise_Sparse`
- `RainFuzzNoise_Dense`

Important:
- The widget extension is a separate bundle. These image sets must exist in the **widget extension’s** asset catalogue (and in the app’s if the app preview uses them).
- If the assets do not load in the widget bundle, the erosion still happens but the “grain” component becomes subtle, and the chart can look very close to the previous commit.

Notes:

- `RainForecastSurfaceConfiguration` still contains several legacy knobs (for compatibility). The renderer uses a subset of fuzz/dissipation knobs and ignores unrelated legacy settings.
- If the chart appearance needs tuning, start with the config values in `Shared/WidgetWeaverWeatherTemplateNowcastChart.swift`, then adjust dissipation behaviour in `Shared/RainForecastSurfaceRenderer.swift`. Avoid editing the legacy `RainSurfaceDrawing*` files for this chart.

#### Current status of visual fidelity (and what to expect)

The current output is still not matching the mockup, and it can look “nearly unchanged” if the erosion is too conservative or if the noise assets are not being loaded by the widget bundle.

Can this technique reach mockup fidelity?
- **Yes, this is the correct foundation** for the mockup look, because the mockup’s slopes are primarily an **alpha structure** problem (solid → grain → nothing), not a “draw more fuzz” problem.
- The remaining gap is mostly:
  - tuning the erosion width/strength so the dissipation reaches into the slope (not just the edge), and
  - ensuring the tile textures have the right character (fine grain, sparse, no seams) and are consistently loaded.

What may remain constrained by WidgetKit budgets:
- Very large “outer dust clouds” can be risky in widgets. The primary requirement is **body dissipation**, which is achievable with bounded erosion passes.

#### Troubleshooting: “no visible difference” and “wrong colour”

If the chart looks almost identical to the older path:

- Confirm `RainFuzzNoise*` image sets exist in the **widget extension** asset catalogue (not just the app).
- Ensure names match exactly (case-sensitive).
- Ensure the tile textures are truly sparse (mostly transparent). If the tile is too opaque, the effect reads as a smooth fade instead of grain.
- Increase erosion width/strength in the nowcast configuration. A narrow band reads like a softened outline, not dissipation.

If you see cyan/halo-like colour:
- That indicates an additive blend (for example “screen”) or a haze stroke that is too strong, or the dissipation colour being sourced incorrectly.
- The intended look is a blue body that dissolves; the dissipation should not introduce a new hue.

### Regression A — WidgetKit placeholder (crash/budget blow) for rainy locations

This is the most important pitfall for the nowcast chart.

When the nowcast chart is “heavy” (lots of rain + expensive rendering), WidgetKit can decide the widget render exceeded its time/memory budget (or crashed) and it will fall back to a **placeholder snapshot**. That can appear as a skeleton-like widget or a generic placeholder look where the rain chart never appears correctly for rainy locations.

#### Symptoms

- Weather widget shows a placeholder-style UI only when rain is present (dry locations render fine).
- The nowcast chart area becomes blank/grey/skeleton-like, or the entire widget looks like a placeholder.
- The placeholder persists even after waiting, until a fresh snapshot is produced.

#### Root causes (what to avoid)

Avoid any rendering approach that can trigger expensive rasterisation or too many draw calls:

- Large offscreen bitmaps (for example, trying to render into big images for compositing)
- Repeated big blurs (especially `GraphicsContext.Filter.blur` or large `shadow`/`blur` chains)
- Per-pixel loops or CPU “image processing” in the widget render path
- Unbounded work tied to area (for example work ∝ width * height)
- Thousands of individual shape fills/strokes per frame (draw-call explosion)
- Any accidental “budget scaling” that increases work when rain is heavier (worst-case input)

#### Guardrails (what the current path enforces)

The nowcast renderer is designed to stay inside WidgetKit budgets by construction:

- The silhouette is **O(n)** in samples.
- Dissipation is a **bounded number of passes** (small constant number of clipped fills).
- Grain uses small **asset-backed tile textures**, not per-speckle procedural loops.
- Blur is avoided; any “coherence” should be a cheap stroke haze (and is best kept off in widgets).
- In WidgetKit placeholder/preview contexts, the chart should **degrade** by removing extras first:
  - disable gloss/glint
  - disable haze/blur
  - reduce dense samples
  - reduce dissipation passes / disable “outer dust”
  - if needed: disable dissipation entirely (core-only render is better than placeholder)

Implementation notes:

- `RainForecastSurfaceView` detects placeholder/preview contexts (including `.redactionReasons`) and applies widget budget guardrails.
  It does this via `RainForecastSurfaceConfiguration.applyWidgetPlaceholderBudgetGuardrails(...)`.
- `WidgetWeaverWidget.swift` treats `snapshot(...)` renders as low-budget.
  This ensures WidgetKit snapshots cannot trigger expensive rain rendering.

#### How to fix it (when you see a placeholder)

If the placeholder shows up during development, follow this order:

1) **Force a fresh widget render**

- In the app: Editor → … → **Refresh Widgets** (reload timelines).
- Remove the widget from the Home Screen and add it again (forces a new snapshot path).

2) **Flush archived WidgetKit snapshots**

- Bump the relevant widget kind string so WidgetKit treats it as a “new” widget and re-archives cleanly:
  - For the main widget: `Shared/WidgetWeaverWidgetKinds.swift` (the `main` kind).
  - For the lock screen weather widget: the lock screen weather kind.
- Rebuild and run on a physical device.

3) **Reduce nowcast cost (stay inside the guardrails)**

- Lower the tuned values in `Shared/WidgetWeaverWeatherTemplateNowcastChart.swift`:
  - `maxDenseSamples`
  - dissipation width/strength (erosion band width, number of passes)
  - disable “outer dust” in widgets

---

## Featured — Calendar (Next Up)

WidgetWeaver includes a built-in Next Up calendar template (`LayoutTemplateToken.nextUp`) and a Lock Screen widget for quick access.

The Calendar engine caches a lightweight snapshot of:

- next event (title, start/end, all-day, location),
- optional second event (“Then”),
- and a countdown-friendly start date.

The snapshot is stored in the App Group for offline widget rendering.

### Calendar setup checklist

- Explore → Calendar: permission granted
- Snapshot cached (Update now)
- Next Up template added into the Library (optionally “Add & Make Default”)
- Widgets added:
  - Lock Screen: **Next Up (WidgetWeaver)** (inline / circular / rectangular)

Notes:

- If calendar widgets show “—”, confirm permission is granted and a snapshot exists.
- The lock screen widget is designed to be fast and stable; the Home Screen uses the normal “WidgetWeaver” design renderer.

---

## Featured — Steps

WidgetWeaver includes a Steps engine and a built-in Steps design template. Steps are available as built-in variables (`__steps_*`) in any normal design once steps setup is completed.

### Steps setup checklist

- Explore → Steps: Health permission granted
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

WidgetWeaver includes a Small Home Screen clock widget (`WidgetWeaverHomeScreenClockWidget`) with a configurable colour scheme and an Apple-style seconds hand.

### Goal: “throttle-proof” seconds

The clock is intended to keep time without relying on high-frequency WidgetKit timelines. In practice there are two separate update mechanisms:

- **WidgetKit timeline entries** (from the provider): used for hour/minute hands. Current code schedules minute-boundary entries for ~2 hours at a time.
- **In-view ticking/animation** (inside the SwiftUI view): used for the seconds hand. This is where iOS 26 Home Screen hosting has been inconsistent.

Important: the current bug is **not** provider timeline “throttling”. The minute hand continues to tick on schedule. The failure mode is that the **in-view seconds driver stops firing**, and configuration edits can make WidgetKit fall back to an archived snapshot where the seconds hand is missing.

### Current implementation (minute-proof, seconds experimental)

**Minute hand (fixed):**

- The timeline starts with an entry at `now`, then the next entry lands on the next true minute boundary (`:00`) and continues every minute.
- This avoids a subtle drift where WidgetKit can effectively “phase lock” minute updates to the second the timeline started, making the minute tick a couple of seconds late.

**Dial overlay artefact (fixed):**

- An intermittent rectangular band across the dial was caused by a multiply-blended lower-half gradient.
- That layer was removed from `WidgetWeaverClockDialFaceView`.

**Seconds hand (current experiment):**

- A vector seconds hand is drawn in an overlay.
- It is driven by `TimelineView(.periodic(from: minuteAnchor, by: 1.0))` (1 Hz) so only the seconds hand redraws, not the whole widget tree.

Observed on device:

- The seconds hand can **render once** (becoming visible), but then **stays frozen** (the `TimelineView` schedule appears paused on the Home Screen host).
- After editing the widget configuration (changing the clock’s colour scheme), the seconds hand can **disappear** even though the minute hand continues to tick.

Working hypothesis:

- On iOS 26 Home Screen, some widget hosting paths treat the view as a mostly-static snapshot and can pause/stop periodic SwiftUI schedules (`TimelineView`) and long-running SwiftUI animations.
- This is distinct from provider timeline coalescing/throttling.

### Clock animation strategies tried (history)

1) **High-frequency provider timeline (2–15s entries) + linear sweep**
   - Looks great when it runs.
   - Rejected for “throttle-proof” work: it relies on frequent timeline entries, which the system can delay/coalesce in real usage.

2) **Widgy-style CoreAnimation sweeps (`repeatForever`)**
   - Minimal provider work.
   - Not reliable on Home Screen: animations can be paused/frozen by the host.

3) **Ligature font seconds hand (`Text(..., style: .timer)` / `timerInterval`)**
   - Idea: use system-updating timer text glyphs, and a font where `0:SS` becomes a needle.
   - Not reliable: OpenType `liga` substitution and/or timer formatting differs between hosts; if ligatures do not apply the font renders “blank digits” → invisible seconds.

4) **`ProgressView(timerInterval:)` driven masks**
   - Can animate visually, but `ProgressViewStyle.Configuration.fractionCompleted` is not updated for date-range progress, so it cannot drive a custom seconds hand.

### Files

- `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
  - Minute-boundary timeline generation (first entry at `now`, then minute boundaries).
- `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`
  - Stable-tree rendering + seconds overlay experiment (`TimelineView(.periodic(..., by: 1))`).
- `WidgetWeaverWidget/Clock/WidgetWeaverClockDialFaceView.swift`
  - Dial gradients; removal of the lower-half multiply overlay that produced a rectangular seam.
- `WidgetWeaverWidget/Clock/WidgetWeaverClockLiveView.swift`
  - Experimental Widgy-style `repeatForever` driver.
- `Shared/WidgetWeaverRenderClock.swift`
  - Helpers for injecting a deterministic “now” into rendering.

### Hand angle maths

The clock uses simple degrees:

- seconds: `second * 6`
- minutes: `minute * 6`
- hours: `(hour12 + minute/60) * 30`

For smooth sweeps (if a reliable driver is found), monotonic “unbounded” degrees are preferred to avoid reverse interpolation at wrap boundaries.

### Archived snapshots during iteration

WidgetKit can keep an archived snapshot from a previous render. During development this can look like “code changes did nothing”, or like only part of the view updated.

Notes from clock iteration:

- Editing widget configuration (colour scheme) can trigger a fresh snapshot path, and that snapshot can omit the seconds hand if the seconds driver is paused.
- If a clock widget looks stuck after code changes:
  - Remove the widget and add it again.
  - Bump `WidgetWeaverWidgetKinds.homeScreenClock` to force a clean archive.

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
- ✅ Steps History (timeline + monthly calendar + year heatmap / calendar) + insights + “Pin this day”
- ✅ Inspector sheet (resolved spec + JSON + quick checks)
- ✅ In-app preview dock (preview vs live, Small/Medium/Large)

### Widgets

- ✅ **Home Screen widget (“WidgetWeaver”)** renders a saved design (Small / Medium / Large)
- ✅ **Lock Screen widget (“Rain (WidgetWeaver)”)** next hour precipitation + temperature + nowcast (accessory rectangular)
- ✅ **Lock Screen widget (“Next Up (WidgetWeaver)”)** next calendar event + countdown (inline / circular / rectangular)
- ✅ **Lock Screen widget (“Steps (WidgetWeaver)”)** today’s step count + optional goal gauge (inline / circular / rectangular)
- ✅ **Home Screen widget (“Steps (Home)”)** today’s step count + goal ring (Small / Medium / Large)
- **Home Screen widget (“Clock (Icon)”)** analogue clock face (Small); minute hand ticks on time; seconds hand is experimental (currently can freeze / disappear after config edits; see Clock section)
- ✅ Per-widget configuration (Home Screen “WidgetWeaver” widget): Default (App) or pick a specific saved design
- ✅ Optional interactive action bar (Pro) with up to 2 buttons that run App Intents and update Pro variables (no Shortcuts setup required)
- ✅ Weather + Calendar templates render from cached snapshots stored in the App Group
- ✅ Steps widgets render from a cached “today” snapshot stored in the App Group
- ✅ `__weather_*` built-in variables available in any design (free)
- ✅ `__steps_*` built-in variables available in any design once Steps is set up (free)
- ✅ Time-sensitive designs can attempt minute-level timelines (delivery is best‑effort; WidgetKit can delay or coalesce updates)

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

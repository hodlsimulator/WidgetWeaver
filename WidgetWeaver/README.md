# WidgetWeaver

WidgetWeaver builds and previews real WidgetKit widgets from saved designs.

It runs on **iOS 26** and ships with: 

- A template catalogue (Explore) with multiple remixes per template
- A searchable design Library (set Default, duplicate, delete)
- An Editor that pushes updates to widgets on Save
- Share/export/import JSON design packages (with embedded images) with an Import Review step (preview + selective import)
- Robust widget previews across sizes and contexts (Home Screen + Lock Screen)
- Weather, Calendar, and Steps setups that cache snapshots for offline widget rendering
- A small Home Screen clock widget (seconds hand work is still in progress)

WidgetWeaver uses an App Group so the app and widget extension share designs, snapshots, and images.

---

## App structure

WidgetWeaver has three tabs:

- **Explore**: featured widgets + templates + setup entry points (Weather / Calendar / Steps) + remixes
- **Library**: saved designs (search, set Default, duplicate, delete)
- **Editor**: edits the currently selected design; **Save** pushes changes to widgets

Widgets refresh when a design is saved. If something looks stale, use the in-app refresh action (Editor → … → Refresh Widgets).

### Previews (Home + Lock Screen)

WidgetWeaver includes a preview dock designed for day-to-day iteration:

- Small / Medium / Large previews for Home Screen designs
- Lock Screen previews for accessory widgets where relevant
- Snapshot-style previews for catching WidgetKit quirks early (including “budget guardrail” paths)
- Quick switching between preview modes without leaving the editor

### Sharing and importing designs (JSON)

WidgetWeaver can export a single design or your entire library as a JSON package (optionally embedding image files). You can import these packages back into the app to clone designs onto another device or share them with someone else.

Where to find it:

- **Editor → Sharing**: “Share This Design”, “Share All Designs”, and “Import designs…”
- **Editor → … menu**: “Import Designs…”

#### Import Review (preview + selective import)

When you pick a JSON file to import, WidgetWeaver shows a review sheet before it writes anything to the library:

- Shows the file name.
- Lists each contained design: name, template, last updated date, and whether it references an embedded image.
- Lets you tick which designs to import, with “Select all” and “Select none”.
- Imports only the selected designs and skips the rest.
- Shows a summary after import (for example: “Imported X designs. Skipped Y (not selected).”).

#### Free tier behaviour

The free tier is capped at `WidgetWeaverEntitlements.maxFreeDesigns` saved designs.

- **Pro unlocked**: default selection is “select all”.
- **Free tier**: default selection picks up to the available slots (newest designs first).
- If your selection exceeds the available slots, the sheet shows a warning and **Import** is disabled. An “Unlock Pro” shortcut is provided.

Notes:

- Imported designs are duplicated with new IDs to avoid overwriting existing designs.
- When selectively importing, only images referenced by the selected designs are included in the subset package (keeps imports lean).

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
- `Shared/RainForecastSurfaceRenderer.swift` — procedural core ribbon (robust scaling + dense resampling) split into wet segments with tapered ends measured in points (no cliffs).
- `Shared/RainForecastSurfaceRenderer+Dissipation.swift` — dissipation/mist layering using seamless tiled noise (constant-cost passes, widget-safe).
- `Shared/RainSurfaceSeamlessNoiseTile.swift` — generates periodic (wrap-around) fine/coarse noise tiles used by dissipation (cached and small to reduce cold-start cost).
- `Shared/RainSurfacePRNG.swift` — deterministic PRNG used for stable jitter/offsets.

**Not used for the Weather nowcast chart (legacy / experiments)**

- `Shared/RainSurfaceDrawing.swift`
- `Shared/RainSurfaceDrawing+Core.swift`
- `Shared/RainSurfaceDrawing+Fuzz.swift`
- `Shared/RainSurfaceDrawing+Rim.swift`
- `Shared/RainSurfaceGeometry.swift`
- `Shared/RainSurfaceMath.swift`
- `Shared/RainSurfaceStyleHarness.swift`

#### Technique (current): seamless‑tile additive dissipation (grain + mist)

The current nowcast look is built from a solid core plus layered texture. The goal is the same behaviour as the mockup:

- solid body at the ridge,
- texture present *through the body* once fuzz starts (not just a thin outline),
- stronger turbulence at the surface,
- and a soft mist above the surface.

The current technique is:

- Draw the **core body** normally (a filled ribbon with a vertical gradient).
- Add an **interior grain layer** inside the body:
  - seamless **fine noise tile** filled additively (`.plusLighter`) to create subtle white micro‑highlights,
  - depth-faded (strong near the surface, weaker towards the baseline),
  - modulated horizontally by a certainty mask derived from chance/height.
- Add a **surface band layer** near the contour:
  - a stroked contour band (`innerBandPath`) clipped to the body,
  - layered coarse + coarse‑detail + fine‑detail fills to produce visible turbulence without dots.
- Add an **above‑surface mist layer** outside the body:
  - outside-of-core region via even‑odd (`clipRect − corePath`) and `outerBandPath`,
  - blue haze base (normal blend) + subtle white lift (additive),
  - additional variation applied additively (no hard noise masking),
  - then faded vertically above the ridge and modulated by the same horizontal mask.

Key property:
- This technique adds *texture* and *white highlight grain* while keeping the core colour stable.
- It avoids the “cyan halo” failure mode by keeping above-surface lift subtle and by not relying on thick outline strokes.

#### 0–60 minute series and “Ends in Xm” alignment

The chart must not “stretch” shorter WeatherKit minute forecasts across a full 60 minutes.

The current pipeline keeps the text and the graphic aligned:

- Build `intensityByMinute[0..<60]` and `chanceByMinute[0..<60]`.
- Bucket each minute point using **floor minute indexing** from `forecastStart`:
  - `idx = Int((point.date - forecastStart) / 60)`
- Plot **expected intensity**:
  - `expected = precipitationIntensityMMPerHour × precipitationChance01`
- Clamp sub-wet values to 0 using `WeatherNowcast.wetIntensityThresholdMMPerHour`.
- Pass the chance series as `certainties` into the renderer so uncertainty controls dissipation.

This prevents “Ends in 34m” while the ribbon still looks wet beyond the forecast window.

#### Core shape, segmenting, and tapered ends (no cliffs)

The renderer draws wet runs as segments so each burst can taper cleanly:

- Robust intensity scaling (percentile-based reference max) + `intensityGamma`.
- Dense resampling (`maxDenseSamples`) for a smooth ridge at widget sizes.
- Wet runs are split into segments.
- Each segment is extended left/right by a target taper width measured in **points**, bounded by dry space, with intermediate taper points (e.g. ~0.22 and ~0.68 of edge height). This removes vertical end caps.

Pitfall: when sampling is very dense, one sample can be < 1pt, so tapering must be measured in points, not indices.

#### Seamless noise tiles (how repetition is kept under control)

The dissipation grain comes from two procedural tiles:

- `fine` — micro grain (small, sparse highlights)
- `coarse` — wispier clumps for surface turbulence

These are generated in code and cached:

- Tiles wrap in both axes (periodic), so tiling cannot introduce a seam line.
- Tile size is kept small to reduce WidgetKit cold-start cost.
- Rendering jitters tile origins deterministically (PRNG) so the texture does not “lock” to edges.

#### Avoiding visible tile edges along the surface

When tile edges appear, the cause is usually clip boundaries, not the tile itself:

- The dissipation `clipRect` must be derived from the **actual curvePoints x-range**. Segment tapering introduces non‑uniform x spacing; any index→x assumption can place a hard clip edge inside the visible ribbon.
- Above-surface mist should remain continuous. Using noise as a hard alpha mask (`destinationIn` with noisy shading) creates blocky cut-outs that can read as tiled edges. Current code applies noise variation additively and then applies smooth fades/masks.

#### Troubleshooting: “no visible difference”, “tile edges”, and “wrong colour”

If the chart looks almost identical to the older path:

- Confirm fuzz is not being disabled by budget guardrails (`canEnableFuzz` can be turned off in low‑budget snapshot/placeholder contexts).
- Confirm `GraphicsContext.Shading.tiledImage` usage: `sourceRect` is in unit space (0–1). Passing pixel-sized source rects collapses sampling and can make the tile look like it does nothing.
- Increase config multipliers (opacity + band multipliers) before adding extra passes.

If you still see tile edges along the surface:

- The most common cause is the dissipation `clipRect` ending inside the visible segment. Ensure `clipRect` is based on `curvePoints.x` and padded enough to include above-surface fades.

If you see cyan/halo-like colour:

- Above-surface lift is too strong or mist colour is drifting away from the core body colour.
- The intended look is a blue body that dissolves; dissipation should not introduce a new hue.

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
- Grain uses small **seamless tile textures** (procedural + cached), not per-speckle CPU loops.
- Blur is avoided; any “coherence” should be a cheap stroke haze (and is best kept off in widgets).
- In WidgetKit placeholder/preview contexts, the chart should **degrade** by removing extras first:
  - disable gloss/glint
  - disable haze/blur
  - reduce dense samples
  - reduce dissipation passes / disable outside mist
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
  - dissipation band multipliers / opacity multipliers
  - disable outside mist in widgets

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

## Current status (0.9.4 (16))

### App

- ✅ Explore tab: featured widgets + template catalogue (adds templates into the Library)
- ✅ More remixes across built-in templates (faster iteration without starting from scratch)
- ✅ Library of saved designs + Default selection
- ✅ Library search (find designs by name quickly)
- ✅ Editor for `WidgetSpec`
- ✅ More robust widget previews (multi-size + snapshot-style preview paths)
- ✅ Free tier: up to `WidgetWeaverEntitlements.maxFreeDesigns` saved designs
- ✅ Pro: unlimited saved designs
- ✅ Pro: matched sets (S/M/L) share style tokens
- ✅ Share/export/import JSON (optionally embedding images) with Import Review (preview + selective import)
- ✅ On-device AI (generate + patch)
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
- ✅ More remixes for templates (Explore)
- ✅ Axis: vertical/horizontal; alignment; spacing; line limits
- ✅ Accent bar toggle
- ✅ Style tokens: padding, corner radius, background token, overlay, glow, accent
- ✅ Improved image theme extraction (better palette/contrast derived from images for poster-style designs)
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

## AI

AI features run on-device to generate or patch the design spec. Images are never generated.

---

## Licence / notes

This repo changes quickly and prioritises iteration speed. Expect breaking changes while features are being consolidated.

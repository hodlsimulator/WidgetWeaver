# WidgetWeaver

WidgetWeaver builds and previews real WidgetKit widgets from saved designs.

It runs on **iOS 26** and ships with: 

- A template catalogue (Explore) with multiple remixes per template
- A searchable design Library (set Default, duplicate, delete)
- An Editor that pushes updates to widgets on Save
- Share/export/import JSON design packages (with embedded images) with an Import Review step (preview + selective import)
- Robust widget previews across sizes and contexts (Home Screen + Lock Screen)
- Weather, Calendar, and Steps setups that cache snapshots for offline widget rendering
- A small Home Screen clock widget (ticking seconds hand via the glyphs method)
- A Sleep Machine-style Noise Machine (4-layer procedural noise) with instant resume + Home Screen controller widget

WidgetWeaver uses an App Group so the app and widget extension share designs, snapshots, and images.

---

## App structure

WidgetWeaver has three tabs:

- **Explore**: featured templates + remixes (Weather / Calendar / Steps / Clock) + Noise Machine
- **Library**: saved designs (search, set Default, duplicate, delete)
- **Editor**: edit a design and Save to push updates to widgets

Pro features (matched sets, variables, actions) are unlocked via an in-app purchase.

---

## Key files

### Widget rendering

- `Shared/WidgetSpec.swift` — the design model used by the app and widget extension
- `Shared/WidgetWeaverSpecView.swift` — deterministic SwiftUI renderer for a spec
- `WidgetWeaverWidget/WidgetWeaverWidget.swift` — widget entry points (Home Screen + Lock Screen families)
- `WidgetWeaverWidget/WidgetWeaverTimelineProviders.swift` — provider timelines (mostly conservative; time-sensitive templates are best-effort)

### Previews / thumbnails (app)

- `WidgetWeaver/WidgetPreview.swift` — live preview renderer (app)
- `WidgetWeaver/WidgetPreviewDock.swift` — preview container (size + live toggle)
- `WidgetWeaver/WidgetPreviewThumbnail.swift` — library thumbnails (crisp, size-correct)

### Theme extraction / remixes

- `WidgetWeaver/WidgetThemeExtractor.swift` — image palette extraction (robust, widget-safe)
- `WidgetWeaver/WidgetWeaverRemixEngine.swift` + `WidgetWeaver/WidgetWeaverRemixEngine+Looks.swift` — remix generation

### Import / export

- `WidgetWeaver/WidgetSharePackage.swift` — export format + image embedding
- `WidgetWeaver/WidgetImportReviewSheet.swift` — Import Review (preview + selective import)


### Noise Machine

- `Shared/NoiseMachine/NoiseMixState.swift` — Codable model for the last mix (4 slots)
- `Shared/NoiseMachine/NoiseMixStore.swift` — App Group persistence (debounced writes + safe defaults)
- `Shared/NoiseMachine/NoiseMachineController.swift` — AVAudioEngine graph + procedural noise (white/pink/brown) + smoothing
- `Shared/NoiseMachine/NoiseMachineIntents.swift` — App Intents used by the widget (AudioPlaybackIntent)
- `Shared/NoiseMachine/NoiseMachineView.swift` + `Shared/NoiseMachine/NoiseMachineViewModel.swift` — in-app controls
- `WidgetWeaverWidget/WidgetWeaverNoiseMachineWidget.swift` — Home Screen controller widget (play/pause/stop + layer toggles)
### Weather nowcast chart (current)

The nowcast surface is a procedural renderer used by the Lock Screen Weather template. It is deterministic, widget-safe, and designed to avoid cliffs and seams.

- `Shared/RainForecastSurfaceRenderer.swift` — procedural surface renderer (builds the rain “body” from segments, adds tapered ends, glint, and shading)
- `Shared/RainForecastSurfaceRenderer+Dissipation.swift` — dissipation shading using seamless tiled noise (constant-cost passes, widget-safe)
- `Shared/RainSurfaceSeamlessNoiseTile.swift` — generates periodic noise tiles used by dissipation (cached and small to reduce cold-start cost)
- `Shared/RainSurfacePRNG.swift` — deterministic PRNG used for stable jitter/offsets

**Not used for the Weather nowcast chart (legacy / experiments)**

- `Shared/RainSurfaceDrawing.swift`
- `Shared/RainSurfaceDrawing+Core.swift`
- `Shared/RainSurfaceDrawing+Fuzz.swift`
- `Shared/RainSurfaceDrawing+Rim.swift`
- `Shared/RainSurfaceGeometry.swift`
- `Shared/RainSurfaceMath.swift`
- `Shared/RainSurfaceStyleHarness.swift`

---

## Featured — Weather

WidgetWeaver includes a Next Hour precipitation template and a Lock Screen Weather widget powered by a cached “nowcast snapshot” stored in the App Group.

The snapshot includes:

- next-hour precipitation intensity timeline (minutes 0–60),
- current temperature and feels-like,
- location name + attribution fields,
- derived flags for “rain soon”, “rain ending”, and uncertainty.

Weather templates render from this cached snapshot so they can work offline and avoid calling network APIs inside widgets.

### Weather setup checklist

1) Open **Weather** settings inside the app.
2) Select a location and provider.
3) Confirm the “nowcast snapshot” is updating.
4) Add the Weather widget.

---

## Featured — Calendar (Next Up)

WidgetWeaver includes a “Next Up” calendar template that can render in Lock Screen families and on the Home Screen.

A cached “Next Up snapshot” is built in the app using EventKit and contains:

- next event (title, start/end, all-day, location),
- optional second event (“Then”),
- and a countdown-friendly start date.

The snapshot is stored in the App Group for offline widget rendering.

### Calendar setup checklist

1) Open **Calendar** settings inside the app.
2) Grant calendar access.
3) Select calendars to include.
4) Confirm the “Next Up snapshot” is updating.

---

## Featured — Steps

WidgetWeaver includes Steps templates for both Lock Screen and Home Screen.

Steps widgets render from a cached “today snapshot” stored in the App Group:

- current day step count
- goal and progress fraction (if configured)
- derived streak / milestone values (if enabled)

Health access can be inspected via the Steps settings screen.

### Steps setup checklist

1) Open **Steps** settings inside the app.
2) Grant Health access.
3) Set a goal (optional).
4) Confirm the “today snapshot” is updating.

---

## Featured — Clock (Home Screen)

WidgetWeaver includes a Small Home Screen clock widget (`WidgetWeaverHomeScreenClockWidget...`) with a configurable colour scheme, minute ticks, and a ticking seconds hand.

### Current approach

- **Minutes / hours:** driven by minute-boundary WidgetKit timeline entries from the provider (low refresh cost).
- **Seconds (ticking, no sweep):** rendered using the **glyphs method**:
  - A custom font (`WWClockSecondHand-Regular.ttf`) contains a pre-drawn seconds hand glyph at the corresponding angle.
  - The widget view uses `Text(timerInterval: timerRange, countsDown: false)` updating once per second and the font turns it into the correct hand.

This keeps the seconds hand moving without scheduling high-frequency WidgetKit timelines. The ligature-glyph approach is the current “throttle-proof” path.

### Notes

- A small spillover past `:59` is allowed to avoid a brief blank hand if the next minute entry arrives slightly late.
- During iteration, WidgetKit can keep an archived snapshot; remove/re-add the widget or bump `WidgetWeaverWidgetKinds.homeScreenClock`.

---

## Featured — Noise Machine

WidgetWeaver includes a Sleep Machine-style Noise Machine that mixes **4 simultaneous layers** of procedural noise.

Each layer has:

- enabled toggle
- volume
- colour (white → pink → brown continuum)
- low cut / high cut filters
- simple 3-band EQ

The full mix is stored as a single **Last Mix** record in the App Group so:

- the widget can reflect the current state instantly
- the app can **resume immediately on relaunch** (optional)

### Noise Machine setup checklist

1) In Xcode, enable **Background Modes → Audio** on the **WidgetWeaver** app target (required for playback with the screen off).
2) Open **Explore → Noise Machine** and press **Play**.
3) Optional: enable **Resume on launch** so force-quit → relaunch restarts audio automatically.
4) Add the **Noise Machine** widget to the Home Screen and test Play/Pause + layer toggles.

The widget is a controller only: buttons run App Intents (AudioPlaybackIntent) that update the stored state and drive playback in the app process.

---

## Current status (0.9.5 (2))

### App

- ✅ Explore templates + remixes
- ✅ Library (search, set Default, duplicate, delete)
- ✅ Editor (save → widgets update)
- ✅ Robust previews (Home Screen + Lock Screen)
- ✅ Import Review (preview + selective import)
- ✅ Theme extraction + more remixes
- ✅ Noise Machine (4-layer procedural mixer + instant resume + widget controls)
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
- ✅ **Home Screen widget (“Clock (Icon)”)** analogue clock face with minute ticks and a ticking seconds hand (glyphs method)
- ✅ **Home Screen widget (“Noise Machine (WidgetWeaver)”)** controller widget (play/pause/stop + 4 layer toggles)
- ✅ Per-widget configuration (Home Screen “WidgetWeaver” widget): Default (App) or pick a specific saved design
- ✅ Optional interactive action bar (Pro) with up to 2 buttons that can trigger App Intents and update Pro variables (no Shortcuts setup required)
- ✅ Weather + Calendar templates render from cached snapshots stored in the App Group
- ✅ Steps widgets render from a cached “today” snapshot stored in the App Group
- ✅ `__weather_*` built-in variables available in any design (free)
- ✅ `__steps_*` built-in variables available in any design once Steps is set up (free)
- ✅ Time-sensitive designs can attempt minute-level timeline updates (delivery is best-effort; WidgetKit can delay or coalesce updates)

### Layout + style

- ✅ Layout templates: Classic / Hero / Poster / Weather / Next Up / Steps / Gallery / Banner / Chip (Calendar) (includes a starter Steps design via `__steps_*` keys)
- ✅ More remixes for templates (Explore)
- ✅ Image themes (palette extraction + background/foreground harmonisation)
- ✅ Inline validation (spec clamps + safe defaults)

---

## Project setup checklist

1) Open `WidgetWeaver.xcodeproj`
2) Select an iOS 26 device/simulator
3) Run the app target
4) Confirm App Group is configured and accessible
5) Add widgets from the Home Screen / Lock Screen widget gallery
6) If using Noise Machine: enable **Background Modes → Audio** on the WidgetWeaver app target

First run expectations:

- First run: templates added from **Explore** into the Library
- Designs edited in **Editor**, then saved to push updates to widgets
- Weather / Calendar / Steps setup performed (for templates that depend on cached snapshots)

Widgets can be added from the Home Screen / Lock Screen widget gallery and configured to select a specific saved design when relevant.

Pro features require a Pro unlock; Variables and Actions become available in the editor after unlock.

---

## Editor features

### Layout templates

WidgetWeaver ships with multiple “starter” layout templates and remixes, including:

- **Weather**: nowcast surface + decision text + temperature
- **Next Up**: next event with countdown + then line
- **Steps**: step count + goal + streak
- **Actions**: compact action bar (buttons)
- **Gallery**: tiled images with captions
- **Banner**: single-line compact template
- **Chip (Calendar)**: Lock Screen-friendly chip with event + countdown

### Action bars (Pro)

- Optional action bar with up to 2 buttons
- Buttons can trigger App Intents
- Buttons can update Pro variables
- No Shortcuts setup required

### Variables (Pro)

- Variables are stored in the App Group and can be referenced in any spec
- Variable values can be updated by App Intents (buttons) and reflected in widgets
- Variables unlock additional “dynamic” templates and remixes

---

## AI

WidgetWeaver includes optional on-device AI for:

- generating a starter spec from a prompt
- patch-editing an existing spec (“more minimal”, “bigger title”, etc.)

AI is additive and not required to use the app.

---

## Licence / notes

This repository is an active app project, not a polished library. Expect breaking changes while features are being consolidated.

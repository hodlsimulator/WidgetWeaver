# WidgetWeaver

WidgetWeaver builds and previews real WidgetKit widgets from saved designs.

It runs on **iOS 26** and ships with: 

- A template catalogue (Explore) with multiple remixes per template
- A searchable design Library (set Default, duplicate, delete)
- An Editor that pushes updates to widgets on Save
- Share/export/import JSON design packages (with embedded images) with an Import Review step (preview + selective import)
- Smart Photos for Poster images (app-only Vision prep + per-family renders; widget loads a single size-appropriate file)
- Robust widget previews across sizes and contexts (Home Screen + Lock Screen)
- Weather, Calendar, Steps, and Activity setups that cache snapshots for offline widget rendering
- A small Home Screen clock widget (ticking seconds hand via the glyphs method)
- A Sleep Machine-style Noise Machine (4-layer procedural noise) with instant resume + Home Screen controller widget
- Shareable Noise Machine diagnostics log (Dump status / Rebuild engine / Share log)

WidgetWeaver uses an App Group so the app and widget extension share designs, snapshots, and images.

---

## App structure

WidgetWeaver has three tabs:

- **Explore**: featured templates + remixes (Weather / Calendar / Steps / Activity / Clock) + Noise Machine
- **Library**: saved designs (search, set Default, duplicate, delete)
- **Editor**: edit a design and Save to push updates to widgets

Pro features (matched sets, variables, actions) are unlocked via an in-app purchase.

---

## Key files

### Widget rendering

- `Shared/WidgetSpec.swift` — the design model used by the app and widget extension
- `Shared/WidgetWeaverSpecView.swift` — deterministic SwiftUI renderer for a spec
- `WidgetWeaverWidget/WidgetWeaverWidget.swift` — widget entry points (Home Screen + Lock Screen families)

### Data snapshots (Weather / Calendar / Steps)

Widgets do not fetch heavy data directly. Instead the app builds and caches small snapshots in the App Group:

- `Shared/WidgetWeaverWeatherEngine.swift` — location + weather snapshot
- `Shared/WidgetWeaverCalendarEngine.swift` — Next Up snapshot via EventKit
- `Shared/WidgetWeaverStepsEngine.swift` — Steps + Activity snapshots via HealthKit
- `Shared/AppGroup.swift` — shared file + UserDefaults access

---

## Featured — Weather

WidgetWeaver includes a rain-first Weather template for Lock Screen and Home Screen.

Weather templates render from a cached Weather snapshot built in the app.

### Weather setup checklist

1) Open **Weather** settings inside the app.
2) Pick a location.
3) Confirm attribution is shown.
4) Confirm widgets update when you Refresh.

---

## Featured — Next Up (Calendar)

WidgetWeaver includes Next Up templates for Lock Screen and Home Screen.

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
- optional goal + ring
- last updated timestamp

### Steps setup checklist

1) Open **Steps** settings inside the app.
2) Grant Health access.
3) Set a goal (optional).
4) Confirm the “today snapshot” is updating.

---

## Featured — Activity

WidgetWeaver includes Activity templates for both Lock Screen and Home Screen.

Activity widgets render from a cached “today snapshot” stored in the App Group:

- steps today
- flights climbed
- walking/running distance
- active energy
- last updated timestamp

The **Steps** screen in the app includes an **Activity (steps + more)** section so the same snapshot that powers Activity widgets (and `__activity_*` keys) is visible in-app.

### Activity setup checklist

1) Open **Steps** settings inside the app.
2) Scroll to **Activity (steps + more)**.
3) Tap **Request Activity Access**.
4) Confirm the “today snapshot” is updating.
5) Add an Activity widget and confirm it renders offline (Airplane Mode).

---

## Featured — Smart Photos (Poster)

WidgetWeaver can prepare photos in the app so widgets always show a good crop per size, without doing heavy work in the widget extension.

### Current implementation (Phase 0)

- The app runs a one-time “photo prep” step when importing a photo:
  - Vision analysis in the app (faces/pets/saliency fallback)
  - writes a **master** image plus **Small/Medium/Large** pre-rendered crops into the App Group
- `ImageSpec` stores:
  - `fileName` (currently set to the Medium render for backwards compatibility)
  - optional `smartPhoto` metadata with `masterFileName` and the per-family render filenames
- The widget extension:
  - does **not** import Vision
  - loads exactly **one** already-cropped image file for the current widget family (Poster background path is family-aware)
  - uses a smaller, cost-limited in-memory image cache to reduce jetsam risk
- Import/export and cleanup treat Smart Photo images as first-class:
  - export embeds the master + all render files used by a design
  - import rewrites embedded filenames consistently
  - cleanup removes unreferenced masters/renders

### Why Vision stays out of the widget

Widgets have tight CPU/memory budgets and timeline generation can be terminated; all Vision work is done in the app so widget rendering stays deterministic and fast.

**Note:** per-family loading is currently wired into the Poster template’s background image path. Other templates that reference `ImageSpec.fileName` will show the Medium render until they adopt family-aware loading.

---

## Featured — Clock (Home Screen)

WidgetWeaver includes a Small Home Screen clock widget (`WidgetWeaverHomeScreenClockWidgetV116`) with a configurable colour scheme, minute ticks, and a ticking seconds hand.

### Current approach

- **Minutes / hours:** driven by minute-boundary WidgetKit timeline entries from the provider (low refresh cost).
- **Seconds (ticking, no sweep):** rendered using the **glyphs method**:
  - A custom font (`WWClockSecondHand-Regular.ttf`) contains a pre-drawn seconds hand glyph at the corresponding angle.
  - The widget view uses `Text(timerInterval: timerRange, countsDown: false)` updating once per second and the font turns it into the correct hand.

### Notes

- The clock attempts frequent updates; WidgetKit delivery is best-effort.
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


Noise Machine generates audio procedurally (no bundled audio files) and runs on `AVAudioEngine`.
It requests `AVAudioSession` category `.playback` with `.mixWithOthers` and falls back to plain `.playback` if needed.

### Diagnostics

If playback is flaky (won’t start, won’t resume after Pause, or stops unexpectedly), use the built-in diagnostics:

- **Diagnostics → Dump status** writes a one-shot engine/session snapshot to the log.
- **Diagnostics → Rebuild engine** tears down and recreates the audio graph, then re-applies the saved mix.
- **Diagnostics → Share log** exports the last ~250 log entries (app + widget intents) as plain text.

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
- ✅ Smart Photos (app-only prep pipeline: Vision analysis + per-family renders stored in the App Group)
- ✅ Noise Machine (4-layer procedural mixer + instant resume + widget controls)
- ✅ Noise Machine diagnostics (shareable log + audio status dump + engine rebuild)
- ✅ Pro: matched sets (S/M/L) share style tokens
- ✅ Share/export/import JSON (optionally embedding images) with Import Review (preview + selective import)
- ✅ On-device AI (generate + patch)
- ✅ Weather setup + cached snapshot + attribution
- ✅ Calendar snapshot engine for Next Up (permission + cached “next/second” events)
- ✅ Steps setup (HealthKit access + cached today snapshot + goal schedule + streak rules)
- ✅ Activity setup (HealthKit access + cached today snapshot: steps + distance + flights + active energy; surfaced in Steps → Activity (steps + more))
- ✅ Steps History (timeline + monthly calendar + year heatmap / calendar) + insights + “Pin this day”
- ✅ Inspector sheet (resolved spec + JSON + quick checks)
- ✅ In-app preview dock (preview vs live, Small/Medium/Large)

### Widgets

- ✅ **Home Screen widget (“WidgetWeaver”)** renders a saved design (Small / Medium / Large)
- ✅ Poster templates can load per-family Smart Photo crops (no Vision in widget; single-file render per size)
- ✅ **Lock Screen widget (“Rain (WidgetWeaver)”)** next hour precipitation + temperature + nowcast (accessory rectangular)
- ✅ **Lock Screen widget (“Next Up (WidgetWeaver)”)** next calendar event + countdown (inline / circular / rectangular)
- ✅ **Lock Screen widget (“Steps (WidgetWeaver)”)** today’s step count + optional goal gauge (inline / circular / rectangular)
- ✅ **Home Screen widget (“Steps (Home)”)** today’s step count + goal ring (Small / Medium / Large)
- ✅ **Lock Screen widget (“Activity (WidgetWeaver)”)** multi-metric activity snapshot (steps / distance / flights / energy)
- ✅ **Home Screen widget (“Activity (Home)”)** multi-metric activity snapshot (Small / Medium / Large)
- ✅ **Home Screen widget (“Clock (Icon)”)** analogue clock face with minute ticks and a ticking seconds hand (glyphs method)
- ✅ **Home Screen widget (“Noise Machine (WidgetWeaver)”)** controller widget (play/pause/stop + 4 layer toggles)
- ✅ Per-widget configuration (Home Screen “WidgetWeaver” widget): Default (App) or pick a specific saved design
- ✅ Optional interactive action bar (Pro) with up to 2 buttons that can trigger App Intents and update Pro variables (no Shortcuts setup required)
- ✅ Weather + Calendar templates render from cached snapshots stored in the App Group
- ✅ Steps widgets render from a cached “today” snapshot stored in the App Group
- ✅ `__weather_*` built-in variables available in any design (free)
- ✅ `__steps_*` built-in variables available in any design once Steps is set up (free)
- ✅ `__activity_*` built-in variables available in any design once Activity is set up (free)
- ✅ Time-sensitive designs can attempt minute-level timeline updates (delivery is best-effort; WidgetKit can delay or coalesce updates)

### Layout + style

- ✅ Layout templates: Classic / Hero / Poster / Weather / Next Up / Steps / Activity / Gallery / Banner / Chip (Calendar) (includes starter designs via `__steps_*` and `__activity_*` keys)
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
- Weather / Calendar / Steps / Activity setup performed (for templates that depend on cached snapshots)

Widgets can be added from the Home Screen / Lock Screen widget gallery and configured to select a specific saved design when relevant.

Pro features require a Pro unlock; Variables and Actions become available in the editor after unlock.

---

## Editor features

### Layout templates

Widget specs are built from a small set of layout templates and style tokens.

### Action bars (Pro)

Action Bars can add up to 2 interactive buttons that can trigger App Intents (no Shortcuts required).

### Variables (Pro)

Variables can be referenced inside text fields and updated via App Intents.

---

## AI

AI features are optional and are built around structured generation into the WidgetSpec schema.

---

## Licence / notes

WidgetWeaver is a personal project. All assets and code are for the repo owner.

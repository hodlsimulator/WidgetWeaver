# WidgetWeaver

WidgetWeaver builds and previews real WidgetKit widgets in a fast “template catalogue (Explore) + editor” workflow.

The core idea:

- widgets are composed from **capability-driven tools** (layout, text, symbols, images, Smart Photos, clock, weather, etc.)
- the editor is **context-aware**, so only tools relevant to the current focus/selection are visible
- heavy work (Vision, ranking, rendering prep) happens in the **app**, while widgets stay deterministic and budget-safe

Minimum OS: **iOS 26**

---

## Status

WidgetWeaver is in active development. The codebase is structured so new tools can be added incrementally while keeping widget rendering safe and deterministic.

---

## High-level architecture

WidgetWeaver is split into three layers:

1) **Model + persistence (App Group shared)**
- All widget state that the widget needs is stored in the App Group.
- Widgets read shared state and render deterministically.

2) **Editor (App)**
- The editor builds and edits widget drafts.
- The editor can perform heavy work (Vision, ranking, asset prep) that cannot run in widgets.

3) **Widgets (Widget extension)**
- Widgets render based on shared state and timeline entries.
- Widgets must stay budget-safe and avoid expensive work at render time.

---

## Context-aware editor

The editor is context-aware: the visible tool suite is derived from what is currently being edited (selection/focus/mode), so irrelevant tools are hidden.

Key ideas:

- Tools declare required capabilities and selection constraints.
- Content types (e.g. Smart Photos, Clock) declare what they support.
- A single source of truth produces an `EditorToolContext` (focus, selection descriptor, capabilities, mode).
- The tool suite is computed from that context and is stable/deterministic.
- Tool teardown actions prevent “dangling state” when focus changes (e.g. leaving a crop editor, exiting a modal flow).

This keeps the editor predictable even as more tools are added.

---

## Project structure

- `WidgetWeaver/` — app (editor)
- `WidgetWeaverWidget/` — widget extension
- `Shared/` — shared code used by both app and widget extension
- `Resources/` — assets, localisation, fonts, etc.

Shared code uses the App Group for persistence and cross-process signalling.

---

## Storage & App Group

WidgetWeaver stores shared state in the App Group so:

- widget rendering is deterministic
- the widget can update quickly after edits
- the app and widget can communicate without network dependencies

App Group helper: `Shared/AppGroup.swift`

---

## Widget catalogue (Explore)

Explore presents widget templates that can be remixed.

A template can be:

- a static preset
- a preset plus tool defaults
- a preset with optional dynamic behaviour (e.g. Smart Photos rotation)

Explore is designed to keep the “edit loop” fast: find a template, remix, preview, save.

---

## Draft model

Widget drafts are designed around:

- typed capability sets (what a draft can support)
- explicit selection descriptors (what is selected, how many, homogeneous/heterogeneous)
- predictable focus boundaries (widget vs Smart Photos vs Clock, etc.)

The editor uses this to derive tool availability.

---

## Smart Photos

Smart Photos are “widget-safe photo experiences” that can be prepared in-app and rendered deterministically in widgets.

### Current shape

- Smart Photos are prepared and ranked in the app (Vision allowed).
- Widgets only render from the prepared artifacts.
- Prep includes:
  - thumbnail + per-family renders (Small/Medium/Large)
  - crop metadata
  - ranking/quality info (debuggable)
  - shuffle/rotation manifests (budget-safe)

### Key implementation files

- Smart Photo pipeline: `WidgetWeaver/SmartPhotoPipeline/*`
- Crop editor: `WidgetWeaver/SmartPhotoCropEditorView.swift`
- Shuffle manifest store: `WidgetWeaver/SmartPhotoShuffleManifestStore.swift`
- Widget render: `WidgetWeaverWidget/SmartPhoto/*`

### Why Vision stays out of the widget

Widgets have tight CPU/memory budgets and timeline generation limits. Vision and asset prep must be done in the app so widget rendering stays deterministic and fast.

**Note:** per-family loading is currently wired into the pipeline but not fully adopted everywhere. Some hosts will show the Medium render until they adopt family-aware loading.

---

## Featured — Clock (Home Screen)

WidgetWeaver includes a Small Home Screen clock widget (`WidgetWeaverHomeScreenClockWidgetV156`) with a configurable colour scheme, minute ticks, and a ticking seconds hand.

Key implementation files:

- Provider + widget entry point: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Live view (hands rendering): `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`

### Current approach

- **Minutes / hours:** the provider publishes minute-boundary WidgetKit timeline entries (budget-safe; ~120 minutes precomputed per timeline). The live view snaps the hour/minute hands to the current minute boundary.
- **Live vs pre-render:** when the widget is actually live on the Home Screen, hour/minute are derived from the wall clock (`Date()`). When WidgetKit is pre-rendering future entries (timeline caching), hour/minute are derived from the pinned entry date for deterministic snapshots.
- **Seconds (ticking, no sweep):** rendered using the **glyphs method**:
  - A custom font (`WWClockSecondHand-Regular.ttf`) contains a pre-drawn seconds hand glyph at the corresponding angle.
  - The widget view uses `Text(timerInterval: timerRange, countsDown: false)` updating once per second and the font turns it into the correct hand.

### Clock logs (budget-safe)

Clock diagnostics are written via `WWClockDebugLog` and must never be able to delay rendering:

- **Storage:** file-backed in the App Group container (`WidgetWeaverClockDebugLog.txt`), not a giant `[String]` in `UserDefaults`.
- **Hard cap:** pruned to a small fixed size (currently 256 KB) and only the most recent lines are shown in the in-app viewer.
- **Write path:** best-effort and asynchronous; never call `UserDefaults.synchronize()` from a widget and never do “log every frame” in the extension. Under Swift 6, avoid capturing a mutable `var` into `DispatchQueue.async` closures (build a `let` line first).

If the minute tick ever “goes slow again”, the first sanity check is: clear the clock log and confirm logging isn’t accidentally spamming writes from the widget.

### 🚨 Do not break these invariants (easy to regress)

If the clock looks fine in the widget gallery preview but is wrong on the Home Screen, these are the repeat offenders.

#### 1) Minute hand can look “slow” if hour/minute render from the entry date (or render is delayed)

WidgetKit delivery of minute-boundary entries is best-effort. A `:16:00` entry can arrive a few seconds late on the Home Screen. If hour/minute angles are computed from the timeline entry’s date, the minute hand visibly lags behind real time.

Separately: expensive work inside the widget render path (most often debug logging) can delay the render enough that the minute tick appears late.

Fix / rule:

- When the widget is actually on-screen (“live”), compute hour/minute from `Date()` (wall clock) and snap to the minute boundary.
- When WidgetKit is pre-rendering future entries (timeline caching), compute from the entry date for deterministic snapshots.
- Keep widget diagnostics cheap (see “Clock logs” above).

The shipped implementation uses `WidgetWeaverRenderClock.withNow(entryDate)` plus a pre-render check:

    let sysNow = Date()
    let ctxNow = WidgetWeaverRenderClock.now   // pinned to the timeline entry date

    let sysMinuteAnchor = floorToMinute(sysNow)
    let ctxMinuteAnchor = floorToMinute(ctxNow)

    // If ctxNow is far ahead of sysNow (or has already rolled into the next minute), WidgetKit is pre-rendering.
    let isPrerender = (ctxNow.timeIntervalSince(sysNow) > 5.0) || (ctxMinuteAnchor > sysMinuteAnchor)

    // Hour/minute angles MUST use renderNow (live = wall clock, pre-render = entry date).
    let renderNow = isPrerender ? ctxNow : sysNow

If the minute hand is ever “slow again”, confirm this logic still exists and that hour/minute angles are derived from `renderNow` (not from `entryDate` directly), and confirm the clock log hasn’t grown huge again.

Do NOT “fix” minute accuracy by switching to 1-second WidgetKit timeline entries or adding timers. The design is intentionally budget-safe.

#### 2) Home Screen can cache a stale snapshot unless the widget tree is entry-keyed

During iteration (especially after many edits / reinstalls), WidgetKit can keep an archived snapshot and stop applying timeline advances to the rendered view.

Typical symptoms:

- minute hand appears frozen,
- the widget tile can go black for a while after adding to the Home Screen,
- preview looks fine but Home Screen is wrong.

Fix / rule:

- Keep the Home Screen clock widget keyed by the timeline entry date in the widget configuration closure:

    AppIntentConfiguration(...) { entry in
        WidgetWeaverHomeScreenClockView(entry: entry)
            .id(entry.date)
    }

Removing this has repeatedly caused “black tile + frozen minute hand” regressions.

#### 3) Proving minute accuracy (debug)

In DEBUG builds, the widget emits a `minuteTick` line once per live minute:

- `lagMs`: milliseconds between the exact minute boundary and when the view ticked.
- `ok=1`: within tolerance (currently ±250 ms).

Example:

    2026-01-14T02:05:00.012Z [clock] [com.conornolan.WidgetWeaver.WidgetWeaverWidget] minuteTick hm=2:05 handsRef=... lagMs=12 ok=1 ...

If only `render ... live=0` lines appear, those are from WidgetKit pre-rendering future entries (expected) and won’t prove live ticking.

### Notes

- The clock attempts frequent updates; WidgetKit delivery is best-effort.
- A small spillover past `:59` is allowed to avoid a brief blank seconds hand if the next minute entry arrives slightly late.
- If you’re fiddling with the clock, always do a 2-minute Home Screen test after changes:
  - minute boundary tick is on time (not slow),
  - no black tile on add,
  - minute hand actually advances on Home Screen,
  - seconds hand behaviour unchanged.

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

Noise Machine includes diagnostics in debug builds:

- audio graph stability
- session state
- engine reconfiguration paths
- layer state snapshots

### Implementation files

- Controller: `Shared/NoiseMachine/NoiseMachineController.swift`
- Engine + DSP: `Shared/NoiseMachine/NoiseMachineController+Engine.swift`
- Graph: `Shared/NoiseMachine/NoiseMachineController+Graph.swift`
- State: `Shared/NoiseMachine/NoiseMachineController+State.swift`
- View: `Shared/NoiseMachine/NoiseMachineView.swift`
- Widget: `WidgetWeaverWidget/NoiseMachine/*`

---

## Widgets

WidgetWeaver widgets are built as real WidgetKit widgets with:

- widget-safe rendering
- App Group state reads
- budget-safe timelines

Widget work is split into:

- providers (timeline entries)
- views (rendering)
- shared state stores (App Group)

---

## Build & run

- Open `WidgetWeaver.xcodeproj`
- Build the app target and widget extension target
- Run the app on a device or simulator
- Add widgets from the Home Screen

---

## Debugging tips

- Widget rendering can be cached; use `.id(entry.date)` to force refresh across entries where needed.
- If a widget looks stuck, remove and re-add the widget.
- In DEBUG builds, prefer logging through `WWClockDebugLog` and keep logs small.

---

## Principles / guardrails

- Widgets must remain deterministic and budget-safe.
- Vision and heavy ranking work is app-only.
- Avoid frequent widget reloads; prefer short precomputed timelines.
- Context-aware editor must remain stable and predictable.

---

## Roadmap (high level)

- Continue adding tools incrementally while keeping widget rendering stable.
- Expand template catalogue and remix options.
- Improve Smart Photos adoption and family-aware loading.
- Expand Weather / time-critical widgets.
- Harden editor teardown and selection stability as tool count grows.

---

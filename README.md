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

## Photo widgets (Poster templates)

Poster templates are photo-backed widgets. They render a prepared image as a full-bleed background, optionally with an overlay.

### Variants

1) **Single photo**
- Full-bleed photo with no text overlay.
- Intended for a “photo frame” style widget.
- Backed by the poster template with `posterOverlayMode = .none`.

2) **Photo + caption**
- Photo background with a caption block at the bottom (with a gradient fade for legibility).
- Caption text comes from `WidgetSpec.name`, `primaryText`, and optional `secondaryText`.

3) **Photo Clock**
- Uses the same caption overlay, but the caption contains time variables (for example `{{__time}}`).
- Needs minute-accurate updates on the Home Screen.

### How photos are sourced (widget-safe)

A poster can render:

- a single chosen photo (`spec.image.fileName`), or
- a Smart Photos shuffle manifest (`spec.image.smartPhoto.shuffleManifestFileName`) for rotation.

Widgets must never run Vision, ranking, or asset preparation. They only load prepared artefacts from the App Group and render deterministically.

Key implementation files:

- Background render: `Shared/WidgetWeaverSpecView+Background.swift` (`posterBackdrop`)
- Overlay render: `Shared/WidgetWeaverSpecView.swift` (`posterTemplate`, `WidgetWeaverPosterCaptionOverlayView`)
- Smart Photo widget render helpers: `WidgetWeaverWidget/SmartPhoto/*`
- Shuffle manifest + scheduling: `WidgetWeaver/SmartPhotoPipeline/*` + `WidgetWeaver/SmartPhotoShuffleManifestStore.swift`

### Timeline behaviour (rotation vs time)

- Posters that only rotate photos (no time-dependent variables) schedule timeline entries at rotation boundaries (plus a small horizon), then ask WidgetKit to reload again soon.
- Posters that include time-dependent variables (Photo Clock) must update at minute boundaries.

### Known issue: Photo Clock minutes frozen / wrong time on the Home Screen

Symptoms:

- Works in the in-app widget preview but the Home Screen widget shows the wrong time.
- Launching from Xcode (or opening the app) makes it jump to the correct time once, then it stops again.

Root cause:

- Time variables were being resolved using a wall-clock `Date()` (or other non-entry clock) during render rather than the WidgetKit `TimelineEntry.date`, and/or the view relied on a view-level timer that the Home Screen host can suppress.
- With WidgetKit pre-rendering/caching, future timeline entries can end up with “baked” time strings.

Fix (keep these in place):

1) **Drive time-dependent posters via the WidgetKit timeline**

If `spec.usesTimeDependentRendering()` is true (e.g. Photo Clock), generate a timeline with minute entries.

2) **Align to minute boundaries**

Avoid minute schedules like `21:26:37 → 21:27:37`. Use a minute-aligned base for the repeating schedule.

3) **Resolve variables using the timeline entry date**

Pass the timeline entry’s date down into the shared render tree and resolve variables against that date.

- `WidgetWeaverSpecView` carries a `renderDate` and resolves variables using:

        let resolved = familySpec.resolvingVariables(now: renderDate)

- The widget configuration passes `entry.date` as that `renderDate`:

        WidgetWeaverSpecView(spec: liveSpec, family: entry.family, context: .widget, now: entry.date)

4) **Key the widget view by the entry date**

This reduces the odds of WidgetKit keeping a stale cached snapshot on the Home Screen:

        .id(entry.date)

Recovery when testing:

- Remove and re-add the widget to drop cached renders.
- If it still looks stuck, rebuild + reinstall to ensure the widget extension has been updated.

---

## Featured — Clock (Home Screen)

WidgetWeaver includes a Small Home Screen clock widget (`WidgetWeaverHomeScreenClockWidgetV156`) with a configurable colour scheme, minute ticks, and a ticking seconds hand.

Key implementation files:

- Provider + widget entry point: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Live view (hands rendering): `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`

### Current approach

- **Provider timeline (budget-safe):** the provider publishes minute-boundary WidgetKit timeline entries with a deliberately short horizon (now + next minute boundary). This bounds provider work, avoids colour scheme changes getting “stuck” behind a long cached timeline on iOS 26, and ensures the widget updates even if the view-level heartbeat is suppressed.
- **Minute-accurate hands (view-level heartbeat):** the live view does not rely on WidgetKit delivering the *next* minute entry exactly on time. Instead it uses an invisible, time-aware `ProgressView(timerInterval:)` as a lightweight heartbeat so SwiftUI re-evaluates the view frequently while still avoiding high-frequency WidgetKit reloads.
- **Heartbeat interval:** the heartbeat is a **60-second** interval anchored to the **current minute** and keyed by that minute anchor. Long timer intervals (e.g. multi-hour ranges) can be updated too infrequently by iOS, which reintroduces “late” minute ticks.
- **Live vs pre-render:** when the widget is live on the Home Screen, hour/minute are derived from the wall clock (`Date()`). When WidgetKit is pre-rendering future entries (timeline caching), hour/minute are derived from the pinned entry date (`WidgetWeaverRenderClock.now`) for deterministic snapshots.
- **Hours / minutes (tick-style):** the hour and minute hands are snapped to the minute boundary (`floorToMinute(renderNow)`) to avoid drift between updates.
- **Seconds (ticking, no sweep):** rendered using the **glyphs method**:
  - A custom font (`WWClockSecondHand-Regular.ttf`) contains a pre-drawn seconds hand glyph at the corresponding angle.
  - The widget view uses `Text(timerInterval: timerRange, countsDown: false)` updating once per second and the font turns it into the correct hand.
  - A small spillover window past `:59` avoids a brief freeze if the next minute entry arrives slightly late.

### Clock logs (budget-safe)

Clock diagnostics are written via `WWClockDebugLog` and must never be able to delay rendering:

- **Storage:** file-backed in the App Group container (`WidgetWeaverClockDebugLog.txt`), not a giant `[String]` in `UserDefaults`.
- **Hard cap:** pruned to a small fixed size (currently 256 KB) and only the most recent lines are shown in the in-app viewer.
- **Write path:** best-effort and asynchronous; never call `UserDefaults.synchronize()` from a widget and never do “log every frame” in the extension. Under Swift 6, avoid capturing a mutable `var` into `DispatchQueue.async` closures (build a `let` line first).
- **Clearing logs:** `clear()` deletes the file and drops any legacy `UserDefaults` key (no migration), so an old oversized log cannot reintroduce timing issues.

If the minute tick ever “goes slow again”, the first sanity check is: clear the clock log and confirm logging isn’t accidentally spamming writes from the widget.


### Troubleshooting (iOS 26): colour scheme + black tile regressions

#### Clock colour scheme does not change on the Home Screen (but previews look correct)

Symptoms:

- Changing the clock widget’s colour scheme updates the in-app preview / widget gallery preview.
- The live Home Screen widget keeps the previous scheme (sometimes indefinitely).

Why this happens:

- On iOS 26, WidgetKit can keep rendering from an already-generated clock timeline and not request a fresh timeline immediately after a configuration edit.
- The Edit Widget UI can drive updates via `snapshot(for:)` without forcing `timeline(for:)` to be re-run, so the preview looks right while the Home Screen instance stays on the old timeline.

Fix (safe, does not require WidgetCenter reload calls):

- Keep the clock timeline intentionally short so WidgetKit is forced to re-request it frequently.
- In `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`, reduce the clock timeline horizon to “now + next minute boundary”, for example:
  - `WWClockTimelineConfig.maxEntriesPerTimeline = 2`
  - produce entries for `now` and `nextMinuteBoundary`
  - return the timeline with `.policy = .atEnd`

Expected behaviour:

- After editing the scheme on the Home Screen, the live widget should pick up the new scheme by the next minute boundary (worst-case just under 60 seconds).

Do not “fix” this by calling `WidgetCenter.shared.reloadTimelines(...)` / `reloadAllTimelines()` from inside the widget provider. On iOS 26 this can easily reintroduce the black tile issue described below.

#### Clock widget renders as a solid black tile on the Home Screen

Symptoms:

- The clock widget appears as a black tile on the Home Screen.
- Previews may still render correctly.

Common causes in this codebase:

- Doing heavy or blocking work during widget rendering or timeline generation (especially debug logging that writes synchronously, or ballooning logs in `UserDefaults`).
- Triggering WidgetKit reload loops by calling `WidgetCenter.shared.reloadTimelines(...)` / `reloadAllTimelines()` from within the widget extension/provider.
- App Group access failing inside the widget extension due to entitlements/suite/container issues.
- Snapshot/identity regressions (removing `.id(entry.date)` from the widget configuration closure).

Fix checklist:

- Avoid WidgetCenter reload calls from inside widget providers. Reloads should be triggered from the app after a user edit, not from `snapshot(for:)` / `timeline(for:)`.
- Keep `WWClockDebugLog` budget-safe: file-backed, capped, and best-effort/asynchronous. Never store huge logs in `UserDefaults`, and never call `UserDefaults.synchronize()` from the widget.
- Verify App Group entitlements are present for both the app target and the widget extension (same group identifier), and make App Group access non-fatal inside the extension.
- Keep the widget tree keyed by the entry date:

        .id(entry.date)

Recovery while testing:

- Remove the widget from the Home Screen, rebuild/reinstall, then add the widget again.
- If the tile remains black, check the device logs for widget extension crashes (Console.app on macOS, filter for the widget bundle identifier).


### 🚨 Do not break these invariants (easy to regress)

If the clock looks fine in the widget gallery preview but is wrong on the Home Screen, these are the repeat offenders.

#### 1) Minute hand can look “slow” if the view only advances when WidgetKit applies the next entry (or render work blocks)

WidgetKit delivery of minute-boundary entries is best-effort. A `:16:00` entry can arrive a few seconds late on the Home Screen. If hour/minute only change when the next entry is applied, the minute tick visibly lags behind real time.

Separately: expensive work inside the widget render path (most often debug logging) can delay the render enough that the minute tick appears late.

Fix / rule:

- Keep the **view-level heartbeat** via an invisible `ProgressView(timerInterval:)` anchored to the current minute:

        let minuteAnchor = floorToMinute(Date())
        ProgressView(timerInterval: minuteAnchor...minuteAnchor.addingTimeInterval(60), countsDown: false)
            .id(minuteAnchor)
            .opacity(0.001)

- Keep the **pre-render check** so live renders use the wall clock and pre-rendered renders stay deterministic:

        let sysNow = Date()
        let ctxNow = WidgetWeaverRenderClock.now   // pinned to the timeline entry date

        let sysMinuteAnchor = floorToMinute(sysNow)
        let ctxMinuteAnchor = floorToMinute(ctxNow)

        // If ctxNow is far ahead of sysNow (or has already rolled into the next minute), WidgetKit is pre-rendering.
        let isPrerender = (ctxNow.timeIntervalSince(sysNow) > 5.0) || (ctxMinuteAnchor > sysMinuteAnchor)

        // Hour/minute angles MUST use renderNow (live = wall clock, pre-render = entry date).
        let renderNow = isPrerender ? ctxNow : sysNow

- Keep widget diagnostics cheap (see “Clock logs” above).

Do NOT “fix” minute accuracy by switching to 1-second WidgetKit timeline entries. The design is intentionally budget-safe.

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

- Inside the live view, keep minute-keyed identity for the hands (`.id(handsNow)`) and minute-keyed identity for the heartbeat (`.id(minuteAnchor)`), so Home Screen caching has fewer ways to “stick”.

#### 3) Proving minute accuracy (debug)

In DEBUG builds, the widget emits a `minuteTick` line once per live minute:

- `lagMs`: milliseconds between the exact minute boundary and when the view ticked.
- `ok=1`: within tolerance (currently ±250 ms).

Example:

    2026-01-14T02:05:00.012Z [clock] [com.conornolan.WidgetWeaver.WidgetWeaverWidget] minuteTick hm=2:05 handsRef=... lagMs=12 ok=1 ...

If only pre-render output appears (large `ctx-sys` lead, or `live=0` in older log formats), those entries are from WidgetKit timeline caching and won’t prove live ticking.

### Notes

- The clock attempts frequent updates; WidgetKit delivery is best-effort.
- A small spillover past `:59` is allowed to avoid a brief blank seconds hand if the next minute entry arrives slightly late.
- When changing clock code, a short Home Screen test is required:
  - minute boundary tick is on time (not slow),
  - no black tile on add,
  - minute hand advances on Home Screen,
  - seconds hand behaviour unchanged.

---

## Featured — Reminders

WidgetWeaver includes a Reminders template that can render a widget-safe snapshot of Apple Reminders.

Design goals:

- **budget-safe widgets:** widgets never talk to EventKit; they render from cached snapshots only
- **fast updates:** the host app refreshes the snapshot and signals WidgetKit to reload timelines
- **optional interactivity:** in widget context, tapping a row can complete a reminder via an App Intent (gated when access/snapshot state is not safe)

### Architecture (budget-safe)

- Reminders engine (EventKit, app-only): `Shared/WidgetWeaverRemindersEngine.swift`
- Snapshot store (App Group): `Shared/WidgetWeaverRemindersStore.swift`
- Widget render view: `Shared/WidgetWeaverRemindersTemplateView.swift`
- Schema/config: `Shared/WidgetWeaverRemindersConfig.swift`

Widgets render from `WidgetWeaverRemindersStore` only. If no snapshot exists yet, the template shows a placeholder and asks the user to open the app to refresh.

### Configuration

Per-widget configuration lives in `WidgetSpec.remindersConfig` and currently supports:

- modes: Today / Overdue / Soon / Priority / Focus / List
- presentation: Dense / Focus / Sectioned
- list filtering via `EKCalendar.calendarIdentifier` values (empty means "all lists")
- display toggles (hide completed, show due times, progress badge)

### Permissions + refresh

Reminders access requires EventKit **Full Access**. Snapshot refresh is throttled and backs off after repeated failures (`WidgetWeaverRemindersRefreshPolicy`) so the app does not spam EventKit or widget reloads.

### Widget interactivity (complete)

In widget context, rows can be tappable to complete a reminder via `WidgetWeaverCompleteReminderWidgetIntent(reminderID:)`.

Interactivity is disabled when:

- Reminders permission is missing / write-only / restricted
- there is no snapshot yet (open the app to refresh)
- the snapshot is considered stale, or the last refresh ended in a generic error

### Notes / limitations

- EventKit does not currently expose the Reminders app "Flagged" state. The "Priority" mode approximates this by treating high-priority reminders (priority 1–4) as flagged.

### Template visibility (feature flag)

The Reminders template and its editor settings menu entry are gated by a shared feature flag:

- `WidgetWeaverFeatureFlags.remindersTemplateEnabled`
- App Group key: `widgetweaver.feature.template.reminders.enabled`

The flag defaults to enabled when unset, but can be overridden per-device via the App Group store (DEBUG builds include a toolbar toggle).

If the template/settings show on one device but not another, check for an explicit override on the missing device (reset/remove the key).

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

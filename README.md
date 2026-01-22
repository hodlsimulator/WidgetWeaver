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

Widgets have tight CPU/memory/time budgets and can be killed aggressively. Running Vision in widgets is a reliability and performance risk.

The correct approach is:

- do heavy work in the app
- persist results in the App Group
- render deterministically in the widget

---

## Photo widgets (Poster templates)

Photo templates are “simple photo-backed widgets” that can either use:

- a single chosen photo
- a Smart Photos source (shuffle / rotate / curated)

### Variants

Poster templates include multiple variants in the catalogue:

- “Poster” (basic)
- “Poster + Caption”
- “Poster + Glass Caption”
- “Poster + Top Caption”
- “Poster + Glass Top Caption”

The variants differ in presentation and defaults, but share the same underlying rendering system.

### How photos are sourced (widget-safe)

Photo widgets never do heavy work in the widget process.

- The app prepares images and writes them to the App Group images directory.
- The widget reads the pre-rendered files and renders them.
- For Smart Photos, the app writes a manifest describing which image is “current” for the widget at a given time.

### Timeline behaviour (rotation vs time)

Photo widgets rely on WidgetKit timelines for the “current” entry date, but do not assume per-second delivery.

- Simple photo widgets can use long timelines (hourly/daily) because content does not need to update frequently.
- Smart Photos rotation chooses a schedule based on rotation settings (e.g. hourly/daily) and writes a manifest so the widget always has a deterministic “current” image.

### Known issue: Photo Clock minutes frozen / wrong time on the Home Screen

If a photo template includes clock variables (like `{{time}}`) or a “Photo Clock” overlay:

- The preview can look correct while the Home Screen looks “stuck”.
- This is usually caused by resolving “now” incorrectly (using `Date()` instead of the timeline entry date), or by Home Screen snapshot caching.

If the photo clock minutes are frozen:

- confirm the render path is using the entry date provided by WidgetKit
- confirm the widget tree keys against the entry date (avoid cached snapshot reuse)
- confirm time zone offsets are not being double-applied

Relevant files:

- Variable resolution: `Shared/WidgetSpec+VariableResolutionNow.swift`
- Photo clock render path: `Shared/WidgetWeaverSpecView+TemplatePhotoClock.swift`
- Widget timeline entry plumbing: `WidgetWeaverWidget/*Provider*`

The Home Screen is the only render target that matters for correctness; previews are not sufficient proof.

---

## Featured — Clock (Home Screen)

WidgetWeaver includes a Home Screen clock widget designed to look and feel like a high-quality clock app icon, while remaining widget-safe.

### Current approach

Clock rendering aims for:

- correct time on the Home Screen
- predictable updates after customisation changes
- stable rendering across families and modes
- no expensive work at draw time

Clock rendering must remain deterministic and budget-safe.

Key areas:

- Clock model: `Shared/Clock/*`
- Clock widget: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Live view: `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`

### Clock logs (budget-safe)

Clock logging must be:

- budget-safe (no spam)
- usable from Home Screen logs
- targeted (only log what proves correctness)

If the clock seems wrong, prefer logs that prove:

- entry date
- derived components
- local time zone
- rendering phase (snapshot vs live)

### Troubleshooting (iOS 26): colour scheme + black tile regressions

iOS 26 widget rendering can cache aggressively, and can also surface transient “black tile” behaviours after certain theme changes.

#### Clock colour scheme does not change on the Home Screen (but previews look correct)

Symptoms:

- Editor preview shows the updated palette.
- Widget gallery preview shows the updated palette.
- Home Screen widget stays on an older palette.

Likely causes:

- cached Home Screen snapshot
- widget tree not keyed against the entry date
- palette changes not invalidating the view identity

Checklist:

- ensure `.id(entry.date)` (or equivalent stable entry-key) exists at the root of the widget view
- ensure palette is part of the view identity (avoid global cached palette state)
- remove and re-add the widget after major style changes

#### Clock widget renders as a solid black tile on the Home Screen

Symptoms:

- On add, the widget appears as a black tile.
- Opening the app may fix it, or it may persist.

Likely causes:

- view recursion (WidgetKit snapshot mode can surface this as black)
- invalid view identity causing cached broken snapshot reuse
- unsupported SwiftUI effects in widget context (masking / complex blending / infinite geometry loops)

Checklist:

- verify there is no infinite view recursion
- avoid complex masked text effects in widget context
- keep gradients subtle and avoid heavy compositing where possible
- bump widget kind only as a last resort (cache flush)

### 🚨 Do not break these invariants (easy to regress)

#### 1) Minute hand can look “slow” if the view only advances when WidgetKit applies the next entry (or render work blocks)

A smooth-looking minute hand can still be wrong if the Home Screen does not advance the view at the expected cadence.

When validating minute accuracy:

- ensure the minute boundary tick is close to real time
- do not accept “looks smooth” as proof
- confirm entry times and render times with logs

#### 2) Home Screen can cache a stale snapshot unless the widget tree is entry-keyed

The Home Screen can reuse a cached render even when the timeline advances.

To reduce this:

- ensure the widget root view keys against the entry date
- avoid global static caches without explicit entry scoping
- avoid hidden state that does not change across entries

#### 3) Proving minute accuracy (debug)

Prove minute correctness by logging:

- entry date
- derived hour/min/sec
- local time zone
- render phase (live vs snapshot)

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

## Feature flags and compilation conditions

WidgetWeaver uses a small set of shared feature flags (stored in the App Group) to keep the shipped surface area tight while still allowing internal experimentation.

Runtime flags live in `Shared/WidgetWeaverFeatureFlags.swift` and are read by both the app and widget extension.

Current flags:

- Reminders template: `WidgetWeaverFeatureFlags.remindersTemplateEnabled` (App Group key: `widgetweaver.feature.template.reminders.enabled`). Default: enabled.
- Clipboard Actions: `WidgetWeaverFeatureFlags.clipboardActionsEnabled` (App Group key: `widgetweaver.feature.clipboardActions.enabled`). Default: disabled.
- PawPulse: `WidgetWeaverFeatureFlags.pawPulseEnabled` (App Group key: `widgetweaver.feature.pawpulse.enabled`). Default: disabled.

### PawPulse gating

PawPulse (“Latest Cat”) is treated as a future feature. There are two independent gates:

1) Widget registration (compile-time). The PawPulse widget is only included in the widget bundle when the widget extension target has the `PAWPULSE` compilation condition set. Without this, it will not appear in the Home Screen “Add Widget” gallery.

2) Background work (runtime). Even when compiled in, PawPulse background refresh scheduling only occurs when `WidgetWeaverFeatureFlags.pawPulseEnabled` is `true`. If iOS delivers a previously scheduled task while the flag is off, the task handler completes immediately and does not reschedule.

Important: avoid runtime `if` statements inside `@WidgetBundleBuilder`. They can trigger opaque compiler failures. Prefer `#if` compilation conditions for gating widget registration.

To enable PawPulse for internal builds:

- In Xcode: select the `WidgetWeaverWidget` target → Build Settings → Active Compilation Conditions → add `PAWPULSE` (typically Debug only).
- Ensure the runtime flag is enabled (App Group default is off). In DEBUG builds, the simplest approach is to temporarily call `WidgetWeaverFeatureFlags.setPawPulseEnabled(true)` on launch.

If PawPulse appears in the widget gallery after disabling it, the Home Screen can be showing cached extension metadata. The fastest reset is usually to delete the app (removes the widget extension), reinstall, then run once.

### Clipboard Actions and Contacts

The “Action Inbox” (Clipboard Actions) widget + intents are intentionally scoped to avoid a Contacts permission prompt.

- The clipboard inbox and auto-detect intents can store text, export receipt CSV, create calendar events, and create reminders.
- The `.contact` route is hard-disabled in the auto-detect intent (it returns a disabled status rather than creating a contact).
- Clipboard Actions surfaces are runtime gated (`WidgetWeaverFeatureFlags.clipboardActionsEnabled`, default off).

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

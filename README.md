# WidgetWeaver

WidgetWeaver is an iOS app for designing widget-safe templates (Photos, Clock, Weather, Reminders, etc.) with a focused editor workflow and deterministic WidgetKit rendering.

This repo intentionally keeps widget rendering *boring*: shared cached state is written by the app (App Group) and read by widgets; heavy work is app-only.

## Targets

- `WidgetWeaver` — the app (editor, snapshot refresh, stores, export/import)
- `WidgetWeaverWidget` — widget extension (WidgetKit widgets + AppIntents)
- `Shared` — shared models, stores, and render helpers used by both

## Core constraints

- Widgets must be deterministic and budget-safe.
- Heavy work happens in the app (Vision, ranking, large I/O, networking).
- Widgets render from cached App Group state and timeline entry date.
- Home Screen behaviour is the correctness target; previews are not proof.

## Design export/import

WidgetWeaver supports exporting and importing widget designs as `.wwdesign` files (JSON payload under a custom UTType).

Key files:

- Export/share: `WidgetWeaver/ContentView+SharePackage.swift`
- Document type + UTType: `WidgetWeaver/Info.plist`
- Parser / models: `Shared/WidgetSpec.swift` and related helpers

## App Group storage

All cross-process state uses an App Group. Typical pattern:

- App writes a compact snapshot to App Group (atomic write / defaults store)
- Widget reads snapshot and renders deterministically
- App triggers widget reloads when snapshot changes

Key file:

- App Group definitions + convenience: `Shared/AppGroup.swift`

## Templates and rendering

Templates are represented as `WidgetSpec` values. A spec can be:

- created from a catalogue template
- edited in the app
- persisted to the App Group
- rendered by the widget extension

Relevant files:

- Spec model: `Shared/WidgetSpec.swift`
- Rendering helpers: `Shared/WidgetWeaverSpecView.swift` and extensions
- Variable resolution: `Shared/WidgetSpec+VariableResolutionNow.swift`
- Photo clock render path: `Shared/WidgetWeaverSpecView+TemplatePhotoClock.swift`
- Widget timeline entry plumbing: `WidgetWeaverWidget/*Provider*`

The Home Screen is the only render target that matters for correctness; previews are not sufficient proof.

---

## Featured — Clock (Home Screen)

WidgetWeaver includes a Home Screen clock widget designed to look and feel like a high-quality clock app icon, while remaining widget-safe.

### Current approach

Clock rendering aims for:

- stable geometry (no layout “jiggle” across timeline updates)
- predictable customisation
- correct timeline date usage (no “frozen minute” strings)
- high-quality “glass” and tick styling where possible

### Key implementation files

- Clock model: `Shared/Clock/*`
- Widget: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Live view: `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`
- Render helpers: `Shared/Clock/ClockRender/*`

### Notes

- Any time formatting or “now” resolution must use the timeline entry date from WidgetKit, not `Date()` directly.
- Previews can mislead; Home Screen correctness is the target.

---

## Featured — Weather (rain-first)

WidgetWeaver includes a Weather template designed to be useful at a glance, with an emphasis on the next-hour rain nowcast where available.

### Architecture

- Weather refresh runs in the app (WeatherKit allowed) and persists a compact snapshot + attribution to the App Group.
- Widgets render deterministically from the stored snapshot and do not block on network.
- Minute forecast is best-effort; the template falls back to hourly/daily data when minute data is unavailable.

### Location and permissions

Weather can use either:

- a manually entered location (geocoded; no Location permission required), or
- the device’s current location (requires Location permission when explicitly requested).

Location permission is requested only when the user chooses “Use Current Location” in Weather settings.

If the app can request Location authorisation, `WidgetWeaver/Info.plist` must contain `NSLocationWhenInUseUsageDescription` (see `Docs/RELEASE_PLAN_2026-02.md` for the ship copy).

### Built-in variables

Weather values are exposed as built-in keys that can be used in any text field, for example:

- `{{__weather_location|Set location}}`
- `{{__weather_temp|--}}°`
- `{{__weather_condition|Updating…}}`
- `{{__weather_precip|0}}%`

### Key implementation files

- Engine (fetch + throttling): `Shared/WidgetWeaverWeatherEngine.swift`
- Snapshot + location store (App Group): `Shared/WidgetWeaverWeatherStore.swift`
- Template views:
  - `Shared/WidgetWeaverWeatherTemplateView.swift`
  - `Shared/WidgetWeaverWeatherTemplateNowcastChart.swift`
  - `Shared/WidgetWeaverWeatherTemplateLayouts.swift`
  - `Shared/WidgetWeaverWeatherTemplateComponents.swift`
- Settings UI: `WidgetWeaver/WidgetWeaverWeatherSettingsView.swift`
- Widget render entry point: `WidgetWeaverWidget/WidgetWeaverWidget.swift` (`weatherBody`)

### Notes

- If no location is configured, the widget renders a stable “Set location” state rather than a blank tile.
- Weather attribution is required; the legal link appears after the first successful update.

---

## Featured — Reminders template

WidgetWeaver includes a Reminders template that can render a snapshot of reminders and supports completing reminders directly from the widget via an intent.

### Architecture

- App-only snapshot refresh uses EventKit (Full Access).
- A lightweight snapshot is persisted to the App Group.
- Widgets render from the persisted snapshot.

### Key implementation files

- Reminders engine (EventKit, app-only): `Shared/WidgetWeaverRemindersEngine.swift`
- Snapshot store (App Group): `Shared/WidgetWeaverRemindersStore.swift`
- Widget render view: `Shared/WidgetWeaverRemindersTemplateView.swift`
- Schema/config: `Shared/WidgetWeaverRemindersConfig.swift`

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

The flag defaults to enabled when unset, but can be overridden per-device via the App Group store (DEBUG builds include a toolbar toggle in the main toolbar menu).

If the template/settings show on one device but not another, check for an explicit override on the missing device (reset/remove the key).

## Variables

WidgetWeaver supports variable templates inside text fields so designs can display dynamic values (time, weather, steps, activity, and user-defined Variables).

- Basic: `{{key}}`
- Fallback: `{{key|fallback}}`
- Filters: `{{key|fallback||upper}}`, `{{amount|0|number:0}}`, `{{progress|0|bar:10}}`
- Inline maths: `{{=done/total*100|0|number:0}}`

Built-in keys (always available) include:

- Time: `__now`, `__now_unix`, `__today`, `__time`, `__weekday`
- Weather: keys prefixed `__weather_` (from the cached Weather snapshot store)
- Steps: keys prefixed `__steps_` (from the cached Steps snapshot store)
- Activity: keys prefixed `__activity_` (from the cached Activity snapshot store)

Custom variables are stored in the App Group and are Pro-gated.

Interactive widgets can also include action buttons that set a variable to “now” in a chosen format, including Unix milliseconds (milliseconds since 1970).

Reference: `Docs/VARIABLES.md`.

## Feature flags and compilation conditions

WidgetWeaver uses a small set of shared feature flags (stored in the App Group) to keep the shipped surface area tight while still allowing internal experimentation.

Runtime flags live in `Shared/WidgetWeaverFeatureFlags.swift` and are read by both the app and widget extension.

Current flags:

- Reminders template: `WidgetWeaverFeatureFlags.remindersTemplateEnabled` (App Group key: `widgetweaver.feature.template.reminders.enabled`). Default: enabled.
- Clipboard Actions (parked): `WidgetWeaverFeatureFlags.clipboardActionsEnabled` (App Group key: `widgetweaver.feature.clipboardActions.enabled`). Default: disabled. Note: the Clipboard Actions widget is also compile-time gated, so the runtime flag only matters in internal builds where the widget is compiled in.
- PawPulse: `WidgetWeaverFeatureFlags.pawPulseEnabled` (App Group key: `widgetweaver.feature.pawpulse.enabled`). Default: disabled.

### DEBUG feature flag toggles

In DEBUG builds, the main toolbar menu (ellipsis button) includes toggles for the runtime feature flags. This allows internal testing to enable/disable features per-device without code changes.

- “Debug: enable Reminders template” updates editor tool availability immediately.
- “Debug: enable Clipboard Actions” toggles the runtime gate and reloads the Clipboard Actions widget timeline (only meaningful if the Clipboard Actions widget is compiled into the widget extension).
- “Debug: enable PawPulse” toggles the runtime gate, ensures the cache directory exists, schedules (or cancels) the next background refresh request, and reloads the PawPulse widget timeline.

These toggles write to the App Group store, so the state is shared between the app and widgets but is not synced across devices.

### PawPulse gating

PawPulse (“Latest Cat”) is treated as a future feature. There are two independent gates:

1) Widget registration (compile-time). The PawPulse widget is only included in the widget bundle when the widget extension target has the `PAWPULSE` compilation condition set. Without this, it will not appear in the Home Screen “Add Widget” gallery.

2) Background work (runtime). Even when compiled in, PawPulse background refresh scheduling only occurs when `WidgetWeaverFeatureFlags.pawPulseEnabled` is `true` and a base URL is configured. If the flag is off, or the base URL is missing, any pending refresh request is cancelled. If iOS delivers a previously scheduled task while the flag is off, the task handler completes immediately and does not reschedule.

Important: avoid runtime `if` statements inside `@WidgetBundleBuilder`. They can trigger opaque compiler failures. Prefer `#if` compilation conditions for gating widget registration.

To enable PawPulse for internal builds:

- In Xcode: select the `WidgetWeaverWidget` target → Build Settings → Active Compilation Conditions → add `PAWPULSE` (typically Debug only).
- Ensure the runtime flag is enabled (App Group default is off). In DEBUG builds, use the toolbar toggle “Debug: enable PawPulse” (it sets the flag, ensures the cache directory exists, schedules the next refresh request, and reloads widget timelines).

For non-DEBUG automation (or if the toolbar toggle is unavailable), enabling the flag by calling `WidgetWeaverFeatureFlags.setPawPulseEnabled(true)` on launch is also acceptable.

If PawPulse appears in the widget gallery after disabling it, the Home Screen can be showing cached extension metadata. The fastest reset is usually to delete the app (removes the widget extension), reinstall, then run once.

### Clipboard Actions and Contacts (parked)

Clipboard Actions is parked for this release cycle. The widget + intents remain in the repo to ensure the disabled/inert behaviour stays permission-safe (especially avoiding Contacts prompts), but it must be absent from release builds.

Gating model:

1) Widget registration (compile-time). The Clipboard Actions widget is only included in the widget bundle when the widget extension target defines `CLIPBOARD_ACTIONS`. Without this flag, it does not appear in the Home Screen “Add Widget” gallery and cannot be added by a user.

2) Behaviour (runtime). When compiled in, Clipboard Actions surfaces are runtime gated (`WidgetWeaverFeatureFlags.clipboardActionsEnabled`, default off). When the flag is off, intents return “Clipboard Actions are disabled.” and only update the widget status store (no Calendar/Reminders writes). The widget renders its parked state and maps taps to opening the app.

Notes:

- Do not treat this area as a target for new work for the Feb 2026 ship. Patches should avoid touching Clipboard Actions unless the goal is to keep it inert, compile-clean, and free of permission prompts.
- The `.contact` route is hard-disabled in the auto-detect intent (it returns a disabled status rather than creating a contact).
- Release builds must not declare Contacts usage strings. `NSContactsUsageDescription` must not exist in the shipped app or widget Info.plists.

To enable Clipboard Actions for internal builds:

- In Xcode: select the `WidgetWeaverWidget` target → Build Settings → Active Compilation Conditions → add `CLIPBOARD_ACTIONS` (typically Debug only).
- Enable the runtime flag in a DEBUG build via the toolbar toggle “Debug: enable Clipboard Actions”.

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
- deterministic timelines
- zero heavy work at render time

Shared stores live in `Shared/*Store*.swift` and are written by the app and read by widgets.

---

## Notes on reliability

Widget reliability is the product.

Key principles:

- If a feature cannot be made deterministic and budget-safe in a widget, it stays in the app.
- Timeline dates are the only “now” that matters.
- Previews are not proof of correctness; Home Screen behaviour is the target.
- Prefer stable, simple state reads over clever “live” logic in widgets.

---

## Dev notes

### Avoiding WidgetCenter reload loops

Widget providers must not call `WidgetCenter.shared.reloadAllTimelines()` or similar as part of timeline generation.

Reload triggers should come from:

- app-side persistence writes
- explicit user actions
- background tasks that refresh snapshots (app-only)

### App Group state safety

Widget state reads must handle:

- missing files
- partial writes (use atomic writes in the app)
- schema evolution (versioned payloads or tolerant decoding)

---

## Licence

Private project (internal).

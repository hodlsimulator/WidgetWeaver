# WidgetWeaver roadmap (Q1 2026)

Last updated: 2026-01-24
Owner: Conor (engineering) / ChatGPT (PM support)

## Executive summary

We will ship the next public-quality release in mid-February 2026, with a hard feature freeze on 2026-01-31. The roadmap concentrates on making Photos + Clock + Weather feel like flagship capabilities, promoting Noise Machine to a higher-quality “daily use” widget, improving Variables discoverability, and reducing surface area that increases maintenance and App Review risk.

Surface-area reductions for the Feb ship are explicit:

- Remove “Reading” from Explore/catalogue surfaces (without breaking existing user widgets).
- Remove the “Photo Quote” template from Explore/catalogue surfaces.
- Clipboard Actions is parked for this ship. Keep it out of Explore / first-run surfaces and keep `WidgetWeaverFeatureFlags.clipboardActionsEnabled` default off. Contacts creation remains hard-disabled in the auto-detect app intent to avoid a Contacts permission prompt. When the flag is off, the AppIntents must return a disabled status and must not trigger Calendar/Reminders writes or any permission prompts via Shortcuts.
- Hide PawPulse / “Latest Cat” (cat adoption) entirely for this ship. The widget is compile-time gated (only built when `PAWPULSE` is defined) and background refresh is runtime gated (`WidgetWeaverFeatureFlags.pawPulseEnabled`, default off). Refresh requests are cancelled when disabled (or when no base URL is configured). Treat it as future work.

Weather is not deferred. It is a flagship widget/template for the Feb ship and must meet a baseline of “useful everywhere”: stable caching, a clear location flow, deterministic rendering, and correct attribution. AI work remains a post-ship R&D track, with small, reviewable assistive wins rather than a single large “magic” feature.

## Dates and milestones

- 2026-01-20 to 2026-01-31: Feature work (build + integrate)
- 2026-01-31: Feature freeze (no new capabilities; only bug fixes and risk-reducing scope cuts)
- 2026-02-01 to 2026-02-14: Polish phase (UX, performance, reliability, test hardening)
- Target ship window: 2026-02-14 to 2026-02-16 (two weeks after freeze)

Definition: “feature freeze” means no net-new widget types, no new pipelines, and no new complex editor surfaces. Small, clearly bounded improvements to existing features are acceptable if they reduce user friction and are low-risk.

## Prioritisation rubric

- P0: Must ship
  - Home Screen correctness, crashes, data loss, corrupt saves, black tiles, broken widget updates.
- P1: High user value, low/medium risk
  - Improves daily usefulness and reduces complexity for users.
- P2: Nice to have
  - Valuable, but can be deferred without harming the release narrative.

## Theme A: Photos (flagship)

Goal: Make photo-backed widgets and Smart Photos feel fast, reliable, and rich, while remaining widget-safe.

By feature freeze (P0/P1):

- P0: Smart Photos reliability pass
  - Fix any cases where image state is missing, stale, or corrupt.
  - Ensure thumbnails and per-family renders exist and are refreshed correctly.
  - Ensure crop metadata updates are reflected in widgets quickly and deterministically.

- P0: Performance pass
  - Prep work should not block the UI thread.
  - Ensure large image operations are isolated and do not spike memory.

- P1: Defaults and polish
  - Make the out-of-box Smart Photos experience feel good without configuration.
  - Ensure editing flows are predictable and do not strand users in “half state”.

Acceptance criteria:

- A new user can create a photo widget and get a good result within 60 seconds.
- Photo widgets do not show blank tiles after edits.
- Widget timelines do not do heavy work.

Key areas:

- Smart Photos pipeline: `WidgetWeaver/SmartPhotoPipeline/*`
- Crop editor: `WidgetWeaver/SmartPhotoCropEditorView.swift`
- Widget render: `WidgetWeaverWidget/SmartPhoto/*`
- App Group image directory: `Shared/AppGroup.swift`

## Theme B: Clock (flagship)

Goal: Ensure Home Screen clock widgets are correct, predictable, and robust across families and customisations.

By feature freeze (P0/P1):

- P0: Home Screen correctness
  - Ensure time always updates.
  - Ensure any text that depends on time resolves against the correct “now” (timeline entry date).
  - Fix any cases where minutes “freeze” in strings or labels.

- P0: Update propagation
  - Ensure customisation updates apply predictably to existing widgets.
  - Avoid cases where the widget appears “stuck” until a manual reload.
  - Ensure widget writes and reload triggers are correct and minimal.

- P1: Layout stability pass
  - Reduce any layout “jiggle” as time updates.
  - Ensure geometry is stable across families and timelines.

Acceptance criteria:

- No “frozen minutes” on the Home Screen (timeline date always used).
- Editing a clock widget updates reliably.
- Widget is stable and does not crash under memory pressure.

Key areas:

- Clock model: `Shared/Clock/*`
- Widget: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Live view: `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`

## Theme C: Weather (flagship)

Goal: Ship a Weather experience that is immediately useful, visually coherent, and robust: deterministic rendering from cached state, a clear location flow, and correct attribution.

By feature freeze (P0/P1):

- P0: Weather pipeline reliability
  - Ensure the app refreshes weather into the App Group on a predictable cadence (respect `minimumUpdateInterval`).
  - Ensure the widget can render a useful state from cached data without waiting for network.
  - Treat minute forecast as best-effort; core current/hourly/daily must be reliable.
  - Avoid WidgetCenter reload loops (no re-entrant reloads from the extension process).

- P0: Location and permissions story
  - Ensure there is a single, obvious entry point to Weather settings when using the Weather template.
  - Manual location entry (geocode search) must work without Location permission.
  - Location permission is requested only for “Use Current Location”, and denial is handled with a clear fallback.
  - Clearing location deterministically clears the snapshot and updates widgets.

- P1: Template polish and clarity
  - Make the “rain-first” nowcast story legible at a glance (chart + copy + fallback behaviour).
  - Units behaviour is consistent (preference applies to template and variables).
  - Attribution/legal link is present and reliable (appears after first successful update).

Acceptance criteria:

- A new user can add the Weather widget and see useful content within 60 seconds (either cached weather or a clear “Set location” state).
- Weather never renders as a blank tile; failure modes are explicit and stable.
- Weather updates do not cause widget reload thrash.

Key areas:

- Weather engine (fetch + throttling): `Shared/WidgetWeaverWeatherEngine.swift`
- Weather store (App Group): `Shared/WidgetWeaverWeatherStore.swift`
- Weather template views:
  - `Shared/WidgetWeaverWeatherTemplateView.swift`
  - `Shared/WidgetWeaverWeatherTemplateNowcastChart.swift`
  - `Shared/WidgetWeaverWeatherTemplateLayouts.swift`
  - `Shared/WidgetWeaverWeatherTemplateComponents.swift`
- Weather settings UX: `WidgetWeaver/WidgetWeaverWeatherSettingsView.swift`
- Variable resolution plumbing: `Shared/WidgetSpec+VariableResolutionNow.swift`, `Shared/WidgetSpec+Utilities.swift`
- Widget entry points: `WidgetWeaverWidget/WidgetWeaverWidget.swift` (weather body)

## Theme D: Noise Machine (flagship-adjacent)

Goal: Keep Noise Machine stable, responsive, and polished enough for daily use.

By feature freeze (P0/P1):

- P0: Responsiveness
  - First tap after cold start updates UI immediately.
  - Avoid delays when toggling layers or adjusting volume.

- P0: State persistence correctness
  - “Last Mix” state should persist correctly to App Group.
  - Widget should reflect the correct state on Home Screen.

- P1: Small upgrades (bounded)
  - 1–2 improvements that do not widen surface area or add permissions.
  - Examples: better defaults, small UI polish, better diagnostics.

Acceptance criteria:

- No obvious UI lag in normal use.
- No audio graph instability during common interactions.
- Widget reflects current state instantly.

Key areas:

- Controller: `Shared/NoiseMachine/NoiseMachineController.swift`
- Engine + DSP: `Shared/NoiseMachine/NoiseMachineController+Engine.swift`
- Graph: `Shared/NoiseMachine/NoiseMachineController+Graph.swift`
- Widget: `WidgetWeaverWidget/NoiseMachine/*`

## Theme E: Variables (clarity)

Goal: Make variables discoverable and easy to use in text editing, without making the editor feel complex.

By feature freeze (P0/P1):

- P0: Discoverability
  - Ensure there is at least one obvious entry point (Variables sheet).
  - Add in-context insertion when editing text (tool button or accessory entry).

- P1: Usability
  - Ensure variable insertion does not break existing text.
  - Ensure variable names are understandable and grouped sensibly.

- P1: Preview resolved text
  - Provide a quick “preview resolved text” toggle in text editing, using the correct `now` for context.

Acceptance criteria:

- A new user can find and insert a variable within 30 seconds.
- Resolved previews match Home Screen behaviour.

Key areas:

- Variable resolution: `Shared/WidgetSpec+VariableResolutionNow.swift`
- Variables UI: `WidgetWeaver/WidgetWeaverVariablesView.swift`

## Theme F: Scope cuts and surface reduction (risk reduction)

Goal: Reduce maintenance and App Review risk by shipping a coherent, minimal surface.

By feature freeze (P0/P1):

- P0: Remove/hide “Reading”
  - Ensure it is not in Explore/catalogue surfaces.
  - Ensure existing user widgets still render correctly.

- P0: Remove/hide “Photo Quote”
  - Ensure it is not in Explore/catalogue surfaces.
  - Ensure existing user widgets still render correctly.

- P0: Park Clipboard Actions
  - Ensure it is not in Explore/catalogue surfaces.
  - Keep the widget in the extension but render “Hidden by default” when `clipboardActionsEnabled` is off.
  - Ensure auto-detect does not create contacts and does not trigger a Contacts permission prompt.

- P0: Hide PawPulse / “Latest Cat”
  - Ensure it is not in Explore/catalogue surfaces.
  - Ensure the widget is not registered unless `PAWPULSE` is defined.
  - Ensure background refresh is gated behind `pawPulseEnabled` (default off).

Acceptance criteria:

- New users cannot create Reading, Photo Quote, Clipboard Actions, or PawPulse widgets from Explore.
- Existing user widgets do not break.
- No Contacts permission prompt appears in normal flows.

Key areas:

- Reading template surfaces: `WidgetWeaver/WidgetWeaverAboutCatalog.swift`
- Photo Quote helper/spec: `Shared/WidgetSpec+Utilities.swift`
- Clipboard Actions widget: `WidgetWeaverWidget/WidgetWeaverClipboardActionsWidget.swift`
- Clipboard Actions app intent: `WidgetWeaver/WidgetWeaverClipboardInboxIntents.swift` (contact creation disabled)
- Feature flags: `Shared/WidgetWeaverFeatureFlags.swift` (`clipboardActionsEnabled`, `pawPulseEnabled`)
- PawPulse widget bundle gate: `WidgetWeaverWidget/WidgetWeaverWidgetBundle.swift` (`#if PAWPULSE`)
- PawPulse / “Latest Cat”: `WidgetWeaverWidget/WidgetWeaverPawPulseLatestCatWidget.swift`, `Shared/PawPulseLatestCatDetailView.swift`

---

## Appendix: definitions and notes

- “Explore/catalogue surfaces” refers to anything visible to a new user without deep navigation (Explore tab, featured templates, first-run prompts).
- “Hidden” means the widget and code can remain present, but is not promoted and defaults to an inert/disabled state.
- “Scope cut” means it can remain in the repo as future work, but must not increase shipped surface area or permission prompts.

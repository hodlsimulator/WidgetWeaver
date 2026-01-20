# WidgetWeaver roadmap (Q1 2026)

Last updated: 2026-01-20
Owner: Conor (engineering) / ChatGPT (PM support)

## Executive summary

We will ship the next public-quality release in mid-February 2026, with a hard feature freeze on 2026-01-31. The roadmap focuses on making Photos + Clock feel like flagship capabilities, promoting Noise Machine to a higher-quality “daily use” widget, improving Variables discoverability, and removing the Reading template from the surface area (without breaking existing user widgets).

Weather and AI are strategically important, but will not block the mid-February ship. Weather is scheduled for a post-ship iteration. AI work starts as an R&D track after ship, with small, reviewable assistive wins rather than a single large “magic” feature.

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

- P0: Photo widget reliability
  - Per-family render correctness (Small/Medium/Large) where the pipeline already supports it.
  - No missing images on Home Screen after edits (App Group artefacts present, reload path works).
  - Crop and framing are stable across preview and Home Screen.

- P1: Photo editing speed and clarity
  - Reduce steps from “choose photos” → “good-looking widget”.
  - Clear status and recovery for Smart Photos prep (progress + error messages that explain what to do).

- P1: Photo template upgrades (limited scope)
  - At least one new “poster” variant that demonstrates the platform (for example: Photo + subtle caption, or Photo + single stat line).
  - Keep the number of new variants small; prioritise polish and defaults.

Acceptance criteria:

- Creating a photo widget from Explore to Home Screen takes < 60 seconds with no confusing dead ends.
- Smart Photos rotation does not cause blank tiles and does not require “remove and re-add” in normal usage.

Key areas (for engineers):

- Smart Photo pipeline: `WidgetWeaver/SmartPhotoPipeline/*`
- Crop editor: `WidgetWeaver/SmartPhotoCropEditorView.swift`
- Widget render helpers: `WidgetWeaverWidget/SmartPhoto/*`
- Poster background/overlay: `Shared/WidgetWeaverSpecView+Background.swift`, `Shared/WidgetWeaverSpecView.swift`

## Theme B: Clock (flagship)

Goal: The clock must be trustworthy on the Home Screen and customisable without regressions.

By feature freeze (P0/P1):

- P0: Home Screen ticking correctness
  - Verify minute accuracy and “no slow minute hand” behaviour across several hours of Home Screen time.
  - Guard against the black tile regressions (logging, reload loops, heavy work).

- P1: Clock customisation improvements (bounded)
  - Improve discoverability of style options that already exist (colour schemes, ticks, hands).
  - Ensure edits apply to the Home Screen within a predictable window (worst case: next minute boundary).

- P1: Photo Clock integration
  - Ensure poster templates using time variables resolve against `TimelineEntry.date`.

Acceptance criteria:

- Clock widget updates on the Home Screen at minute boundaries without visible lag.
- Editing a clock option in the widget configuration UI visibly applies to the Home Screen within 60 seconds.

Key areas:

- Widget: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Live view: `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`
- Shared render: `Shared/WidgetWeaverSpecView.swift`

## Theme C: Noise Machine (promote and expand)

Goal: Noise Machine becomes a “daily” interactive widget: fast, responsive, and better featured than a basic play/pause tile.

By feature freeze (P0/P1):

- P0: Responsiveness under host delays
  - Confirm the optimistic UI and reconciliation behaves correctly on cold start and after device reboot.
  - Avoid user confusion between Playing / Paused / Stopped.

- P1: Quality and capability upgrades (choose 1–2 only)
  - Option A: Add a third family (Large) with richer controls.
  - Option B: Add preset mixes and a “Quick switch” action.
  - Option C: Add per-layer intensity nudges (very small set of discrete steps; avoid a complex slider UI before ship).

Acceptance criteria:

- First tap after cold start visibly changes state immediately.
- Widget state is consistent with in-app state within a few seconds, without requiring a timeline reload.

Key areas:

- Widget: `WidgetWeaverWidget/WidgetWeaverNoiseMachineWidget.swift`
- App Group store and notifications: `Shared/*` (Noise mix state/store)

## Theme D: Variables (make them accessible)

Goal: Variables are a core primitive for “complex but simple” widgets. They should be easy to discover, insert, and validate.

By feature freeze (P0/P1):

- P1: Variable insertion UX
  - Provide a lightweight in-context picker when editing text fields that support variables.
  - Show examples (including fallback syntax) and allow one-tap insertion.

- P1: Built-in keys surfaced
  - Present built-in keys (for example: time, steps/activity keys) in the Variables UI as read-only items with documentation.

- P1: Validation and preview
  - Validate keys and show inline errors.
  - Provide a quick “preview resolved text” toggle in text editing, using the correct `now` for context.

Acceptance criteria:

- A new user can discover variables and successfully insert one without reading the README.
- Invalid keys are caught early with a clear message.

Key areas:

- Variable resolution: `Shared/WidgetSpec+Utilities.swift`, `Shared/WidgetSpec+VariableResolutionNow.swift`
- Variables UI: `WidgetWeaver/WidgetWeaverVariablesView.swift` (and related sheets)

## Theme E: Remove the Reading widget (reduce surface area)

Goal: Reduce catalogue complexity and maintenance load by removing the Reading template from new surfaces, while avoiding breaking existing user widgets.

By feature freeze (P0/P1):

- P0: Deprecate and hide
  - Remove “Reading” from Explore / About catalogue and any “starter templates” surfaces.
  - Keep rendering support for any existing saved widgets that already use the spec.

- P1: Replacement narrative
  - If “Reading” was showcasing progress, ensure the catalogue still has at least one “progress / goal” example via variables or another existing template.

Acceptance criteria:

- No user’s existing widget breaks after update.
- New users cannot create a Reading widget from Explore.

Key areas:

- Catalogue templates: `WidgetWeaver/WidgetWeaverAboutCatalog.swift`

## Theme F: Weather (later)

Goal: Ship Weather once it has a clear data pipeline, permissions story, and deterministic widget rendering.

Scope decision:

- Weather will not block the mid-February ship.
- During the Feb release cycle, Weather can remain hidden, experimental, or removed from Explore if it creates confusion.

Post-ship targets (Feb–Mar 2026):

- Decide data strategy (Apple WeatherKit vs other; caching; privacy; offline).
- Build an app-side snapshot pipeline and widget-safe cache.
- Restore Weather to Explore once reliability and narrative are ready.

## Theme G: AI (post-ship R&D track)

Goal: Use AI to reduce the effort to produce a great widget, without creating opaque state or unpredictable widgets.

Constraints:

- AI output must map to explicit widget specs and tool configs.
- Every AI change must be reviewable and undoable.
- Do not block the Feb ship on AI.

R&D milestones (Feb–Mar 2026):

- “Command palette” style assistant that generates or edits a widget spec draft.
- Context-aware suggestions (for example: “You are editing a photo poster; suggest caption treatments”).
- Optional text generation for captions with safe templates.

## Work plan: now to feature freeze (2026-01-20 → 2026-01-31)

Order of operations (minimise rework):

1) P0 reliability: clock correctness, photo rendering correctness, no black tiles.
2) Remove Reading from surfaces (deprecation, not breaking).
3) Variables discoverability improvements.
4) Noise Machine uplift (choose 1–2 scoped upgrades).
5) Photo template upgrades (small number).

Suggested weekly cadence:

- Daily: pick 1 P0 and 1 P1 objective; ship them to the main branch with a short changelog entry.
- Twice weekly: “Home Screen reality check” run on device (clock ticking, photo rotation, Noise Machine taps).
- End of week: prune scope and re-prioritise; anything not clearly landing by 2026-01-31 becomes polish or post-ship.

## Work plan: polish (2026-02-01 → 2026-02-14)

- No new features.
- Focus: UX clarity, defaults, performance, accessibility, crash/telemetry hygiene, App Store readiness, and test hardening.

See `docs/RELEASE_PLAN_2026-02.md` for the detailed checklist.

## Iceberg backlog (not committed for the Feb ship)

This list is intentionally broad; it is where “super complex but super simple” can expand after the first polished ship.

- Weather (full pipeline and widgets)
- AI-assisted spec authoring and edits (reviewable)
- More interactive widgets (buttons, toggles, counters) as a cohesive system
- Theming and style presets across templates
- Sharing: export/import widget specs
- Template packs / featured collections
- Advanced photo experiences (collage, mood boards, memories)
- On-device search across templates and saved drafts
- Better onboarding: guided “build your first widget”

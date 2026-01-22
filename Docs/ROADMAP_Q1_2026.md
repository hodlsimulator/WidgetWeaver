# WidgetWeaver roadmap (Q1 2026)

Last updated: 2026-01-22
Owner: Conor (engineering) / ChatGPT (PM support)

## Executive summary

We will ship the next public-quality release in mid-February 2026, with a hard feature freeze on 2026-01-31. The roadmap concentrates on making Photos + Clock feel like flagship capabilities, promoting Noise Machine to a higher-quality “daily use” widget, improving Variables discoverability, and reducing surface area that increases maintenance and App Review risk.

Surface-area reductions for the Feb ship are explicit:

- Remove “Reading” from Explore/catalogue surfaces (without breaking existing user widgets).
- Remove the “Photo Quote” template from Explore/catalogue surfaces.
- Hide Screen Actions / Clipboard Actions entirely for this ship so the app does not need Contacts permission.
- Hide PawPulse / “Latest Cat” (cat adoption) entirely for this ship; treat it as future work.

Weather and AI are strategically important, but will not block the mid-February ship. Weather is scheduled for a post-ship iteration (and may stay hidden/experimental until it has a clear pipeline + permissions story). AI work starts as an R&D track after ship, with small, reviewable assistive wins rather than a single large “magic” feature.

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
  - At most 1–2 scoped “poster” variants that demonstrate the platform.
  - Avoid expanding into many near-duplicate templates.

Acceptance criteria:

- Creating a photo widget from Explore to Home Screen takes < 60 seconds with no confusing dead ends.
- Edits visibly apply to the Home Screen within 60 seconds (worst case) and do not blank the widget.
- Smart Photos failures are actionable (permission, storage, retry) and do not leave widgets in broken state.

Key areas:

- Smart Photos pipeline: `WidgetWeaver/SmartPhotoPipeline/*`
- Crop editor: `WidgetWeaver/SmartPhotoCropEditorView.swift`
- Poster background/overlay: `Shared/WidgetWeaverSpecView+Background.swift`, `Shared/WidgetWeaverSpecView.swift`

## Theme B: Clock (flagship correctness)

Goal: The clock must be trustworthy on the Home Screen and customisable without regressions.

By feature freeze (P0/P1):

- P0: Home Screen ticking correctness
  - Verify minute hand ticks correctly across several hours of Home Screen time.
  - Guard against the black tile regression when adding/re-adding.

- P1: Customisation stability
  - Styling changes apply predictably.
  - No “frozen minute” strings; time variables resolve against timeline entry dates.

Acceptance criteria:

- Clock widget updates on the Home Screen at minute boundaries without visible lag or drift.
- Clock customisation UI visibly applies to the Home Screen within 60 seconds.

Key areas:

- Home Screen clock widget: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Live view: `WidgetWeaverWidget/Clock/WidgetWeaverClockWidgetLiveView.swift`

## Theme C: Noise Machine (daily use)

Goal: Noise Machine feels instant, stable, and trustworthy (interaction-first).

By feature freeze (P0/P1):

- P0: Responsiveness and cold-start stability
  - First tap after cold start updates UI immediately; reconcile state safely.
  - No “stuck playing” or “stuck stopped” states after host delays.

- P1: 1–2 scoped improvements only
  - Example options: clearer state labels; small control refinements; better defaults.
  - Avoid feature sprawl.

Acceptance criteria:

- The first user interaction always gives immediate visible feedback.
- Audio state is consistent across app, widget, and system state.

Key areas:

- Noise Machine widget: `WidgetWeaverWidget/WidgetWeaverNoiseMachineWidget.swift`

## Theme D: Variables (discoverability + insertion)

Goal: Make variables discoverable and easy to insert at the moment they are useful.

By feature freeze (P0/P1):

- P0: Discoverability
  - At least one obvious entry point in the editor.
  - Lightweight in-context picker when editing text fields that support variables.
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

## Theme E: Reduce surface area and permission footprint (pre-freeze)

Goal: Reduce catalogue complexity and App Review risk by removing or hiding non-flagship features, while avoiding breaking existing user widgets.

By feature freeze (P0/P1):

- P0: Deprecate and hide (Explore / catalogue / starter surfaces)
  - Remove “Reading” from Explore / About catalogue and any “starter templates” surfaces.
  - Remove “Photo Quote” from Explore / About catalogue and any “starter templates” surfaces.
  - Hide Screen Actions / Clipboard Actions entirely (do not surface as a template or feature).
  - Hide PawPulse / “Latest Cat” entirely (future feature).

- P0: Permission containment
  - Do not ship a build that requests Contacts permission.
  - If a feature would require Contacts permission, it is automatically out-of-scope for Feb.

- P1: Replacement narrative
  - Ensure the catalogue still has at least one “progress / goal” example (variables or an existing template) after Reading and Quote removal.

Acceptance criteria:

- No user’s existing widget breaks after update.
- New users cannot create Reading, Photo Quote, Screen Actions, or PawPulse widgets from Explore.
- The app does not request Contacts permission during normal use, onboarding, or template browsing.

Key areas:

- Catalogue templates: `WidgetWeaver/WidgetWeaverAboutCatalog.swift`
- “Photo Quote” spec helper: `Shared/WidgetSpec+Utilities.swift`
- Screen Actions / Clipboard Actions widget: `WidgetWeaverWidget/WidgetWeaverClipboardActionsWidget.swift`
- PawPulse / “Latest Cat”: `WidgetWeaverWidget/WidgetWeaverPawPulseLatestCatWidget.swift`, `Shared/PawPulseLatestCatDetailView.swift`

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
- Context-aware suggestions (for example: “A photo poster is being edited; suggest caption treatments”).
- Optional text generation for captions with safe templates.

## Theme H: Shipping readiness (reproducible builds + repo hygiene)

Goal: Reduce last-minute integration risk by ensuring the repo builds cleanly from a fresh checkout and does not contain shipping artefacts.

By feature freeze (P0/P1):

- P0: Dependency hygiene
  - Remove any local-path Swift Package references from the Xcode project.
  - If Screen Actions is hidden/removed for Feb, remove its dependencies (for example, ScreenActionsCore) from the shipping build.

- P0: Repository cleanliness
  - Remove stray backup files (for example, `*.bak`) from the repo and from build targets.
  - Ensure only intended resources are embedded.

- P1: Regression safety
  - Add a minimal “widget determinism” regression suite (snapshot inputs → stable outputs where feasible).
  - Add migration/persistence tests for App Group compatibility (no data loss).

Acceptance criteria:

- A clean checkout builds on another machine without manual path fixes.
- Release builds contain no unintended files and do not request Contacts permission.

## Work plan: now to feature freeze (2026-01-20 → 2026-01-31)

Order of operations (minimise rework):

1) P0 reliability: clock correctness, photo rendering correctness, no black tiles.
2) Reduce surface area: hide Reading, Photo Quote, Screen Actions, and PawPulse from Explore (deprecation, not breaking).
3) Build reproducibility: remove local-path dependencies; remove repo artefacts from targets.
4) Variables discoverability improvements.
5) Noise Machine uplift (choose 1–2 scoped upgrades).
6) Photo template upgrades (small number).

Suggested weekly cadence:

- Daily: pick 1 P0 and 1 P1 objective; ship them to the main branch with a short changelog entry.
- Twice weekly: “Home Screen reality check” run on device (clock ticking, photo rotation, Noise Machine taps).
- End of week: prune scope and re-prioritise; anything not clearly landing by 2026-01-31 becomes polish or post-ship.

## Work plan: polish (2026-02-01 → 2026-02-14)

- No new features.
- Focus: UX clarity, defaults, performance, accessibility, crash/telemetry hygiene, App Store readiness, and test hardening.

See `Docs/RELEASE_PLAN_2026-02.md` for the detailed checklist.

## Iceberg backlog (not committed for the Feb ship)

This list is intentionally broad; it is where “super complex but super simple” can expand after the first polished ship.

- Weather (full pipeline and widgets)
- AI-assisted spec authoring and edits (reviewable)
- Action-based utilities (if reintroduced, must be coherent and permission-justified)
- PawPulse / adoption experience (requires product narrative and polish)
- More interactive widgets (buttons, toggles, counters) as a cohesive system
- Theming and style presets across templates
- Sharing: export/import widget specs
- Template packs / featured collections
- Advanced photo experiences (collage, mood boards, memories)
- On-device search across templates and saved drafts
- Better onboarding: guided “build your first widget”

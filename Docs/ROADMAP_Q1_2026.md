# WidgetWeaver roadmap (Q1 2026)

Last updated: 2026-01-22
Owner: Conor (engineering) / ChatGPT (PM support)

## Executive summary

We will ship the next public-quality release in mid-February 2026, with a hard feature freeze on 2026-01-31. The roadmap concentrates on making Photos + Clock feel like flagship capabilities, promoting Noise Machine to a higher-quality “daily use” widget, improving Variables discoverability, and reducing surface area that increases maintenance and App Review risk.

Surface-area reductions for the Feb ship are explicit:

- Remove “Reading” from Explore/catalogue surfaces (without breaking existing user widgets).
- Remove the “Photo Quote” template from Explore/catalogue surfaces.
- Hide Screen Actions / Clipboard Actions entirely for this ship (no Explore / first-run surfaces). Contacts creation is hard-disabled in the auto-detect app intent to avoid a Contacts permission prompt.
- Hide PawPulse / “Latest Cat” (cat adoption) entirely for this ship. The widget is compile-time gated (only built when `PAWPULSE` is defined) and background refresh is runtime gated (`WidgetWeaverFeatureFlags.pawPulseEnabled`, default off). Treat it as future work.

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
  - Edits should update widgets promptly without reload loops.
  - Avoid excessive WidgetCenter reload calls.

- P1: Customisation reliability
  - Ensure style, font, and colour changes are reflected reliably.
  - Ensure preview matches widget render.

Acceptance criteria:

- No “frozen minute” strings.
- Changing a clock setting updates the widget within one timeline refresh.
- No reload loops.

Key areas:

- Clock widget: `WidgetWeaverWidget/WidgetWeaverHomeScreenClockWidget.swift`
- Clock render: `WidgetWeaverWidget/Clock/*`
- Clock model: `Shared/Clock/*`

## Theme C: Noise Machine (featured)

Goal: Make Noise Machine feel like a flagship daily-use widget and a safe, stable audio feature.

By feature freeze (P0/P1):

- P0: Responsiveness and correctness
  - First tap after cold start updates UI immediately.
  - State reconciles correctly between app and widget.
  - No crashes in audio graph setup/teardown.

- P1: Promotion and light upgrades
  - Promote Noise Machine in Explore/catalogue surfaces.
  - Consider 1–2 very small, low-risk improvements only.

Acceptance criteria:

- Noise Machine feels instant to start/stop.
- State persists and resumes correctly.
- No obvious audio glitches or stuck states.

Key areas:

- Noise Machine engine: `Shared/NoiseMachine/*`
- Widget: `WidgetWeaverWidget/NoiseMachine/*`

## Theme D: Variables (discoverability)

Goal: Make variables more discoverable and safer to use in text-heavy templates.

By feature freeze (P0/P1):

- P0: Discoverability
  - Ensure variables have at least one obvious entry point from the editor.
  - In text editing contexts, make variable insertion feel in-context.

- P1: Safety and clarity
  - Invalid keys should show clear, early feedback.
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
  - Hide Screen Actions / Clipboard Actions entirely (do not surface as a template or feature). Contacts creation remains disabled in the auto-detect app intent.
  - Hide PawPulse / “Latest Cat” entirely (future feature). Ensure the widget is not registered in the extension unless `PAWPULSE` is defined.

- P0: Permission containment
  - Do not ship a build that requests Contacts permission.
  - Confirm the auto-detect app intent does not import Contacts and returns a disabled status for `.contact`.
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
- Screen Actions / Clipboard Actions app intent: `WidgetWeaver/WidgetWeaverClipboardInboxIntents.swift` (contact creation disabled)
- Feature flags: `Shared/WidgetWeaverFeatureFlags.swift` (`clipboardActionsEnabled`, `pawPulseEnabled`)
- PawPulse widget bundle gate: `WidgetWeaverWidget/WidgetWeaverWidgetBundle.swift` (`#if PAWPULSE`)
- PawPulse / “Latest Cat”: `WidgetWeaverWidget/WidgetWeaverPawPulseLatestCatWidget.swift`, `Shared/PawPulseLatestCatDetailView.swift`

## Theme F: Weather (later)

Goal: Ship Weather once it has a clear data pipeline, permissions story, and deterministic widget rendering.

Not in scope for Feb ship, unless it is already rock-solid.

By post-ship iteration (P1/P2):

- Define a clear data pipeline that does not require complex sign-in flows.
- Make widget rendering deterministic and budget-safe.
- Decide on the minimum permission footprint.

Acceptance criteria:

- Weather widgets are reliable and deterministic.
- Permissions are in-context and explain why.

Key areas:

- Weather widget(s): `WidgetWeaverWidget/*Weather*`
- Data pipeline: `Shared/*Weather*`

## Theme G: AI (post-ship R&D)

Goal: Build small, reviewable assistive wins that generate explicit specs/config rather than opaque state.

Not in scope for Feb ship.

By post-ship iteration (R&D):

- Identify 1–2 small “assist” surfaces that are easy to review and undo.
- Ensure any AI output is converted into explicit widget specs or tool settings.
- Avoid “magic” hidden state.

Acceptance criteria:

- AI assistance is additive and reversible.
- No opaque state is introduced.
- Output is explicit and debuggable.

Key areas:

- TBD (post-ship)

## Risks

Primary release risks:

- Data loss or corrupt saves.
- Widgets becoming stuck or blank.
- Clock correctness regressions (time not updating, “frozen minute” labels).
- Smart Photos reliability/performance issues (slow prep, missing renders).
- Excessive permission prompts (especially Contacts).

Mitigations:

- Keep widget rendering deterministic.
- Keep heavy work in app-only codepaths.
- Keep the catalogue minimal for Feb.
- Scope cut any feature that increases App Review risk late in the cycle.

## Notes

This roadmap is a living document. As we approach feature freeze, prioritise stability and coherence over breadth.

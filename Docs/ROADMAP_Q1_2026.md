# WidgetWeaver roadmap (Q1 2026)

Last updated: 2026-01-31
Owner: Conor (engineering) / ChatGPT (PM support)

## Executive summary

We will ship the next public-quality release in mid-February 2026, with a hard feature freeze at the end of 2026-02-02 (Europe/Dublin). The roadmap concentrates on making Photos + Clock + Weather feel like flagship capabilities, promoting Noise Machine to a higher-quality “daily use” widget, improving Variables discoverability, and reducing surface area that increases maintenance and App Review risk.

UX is the primary success metric for this cycle; the Photos track has a dedicated micro-roadmap: `Docs/ROADMAP_PHOTO_SUITE_UX_2026-01.md`.

Surface-area reductions for the Feb ship are explicit (status as of 2026-01-25 / snapshot 4c7c51e9):

- “Reading” is hidden from Explore/catalogue surfaces (kept in-app for back-compat).
- “Photo Quote” is hidden from Explore/catalogue surfaces (kept in-app for back-compat).
- Legacy “Quote” starter template is not surfaced (any remaining `starter-quote` usage is for legacy/icon mapping only).
- Clipboard Actions (Screen Actions) is parked for this ship and is absent in release builds:
  - Compile-time gated behind `CLIPBOARD_ACTIONS` (release builds must not define it).
  - Not listed in Explore / first-run surfaces.
  - Not registered in the widget extension bundle (no Home Screen “Add Widget” gallery presence).
  - Default build has no ScreenActionsCore dependency and no local-path Swift Package dependencies in the Xcode project.
  - `NSContactsUsageDescription` does not exist in `WidgetWeaver/Info.plist` (nor InfoPlist.strings).
- PawPulse / “Latest Cat” (cat adoption) is treated as future work:
  - Compile-time gated (only built when `PAWPULSE` is defined).
  - Background refresh is runtime gated (`WidgetWeaverFeatureFlags.pawPulseEnabled`, default off). Refresh requests are cancelled when disabled (or when no base URL is configured).
- Weather location safety: `WidgetWeaver/Info.plist` contains `NSLocationWhenInUseUsageDescription` with in-context copy; keep permission requests limited to Weather settings / explicit “Use Current Location”.


### Progress update (2026-01-25)

Completed / locked in since the previous snapshot:

- Permissions footprint: Contacts usage string removed; Location usage string present for Weather with in-context copy.
- Clipboard Actions (Screen Actions) is parked: compile-time gated, not registered in release builds, and no local-path Swift Package dependency remains.
- PawPulse is gated behind `PAWPULSE` (future feature; not shipped).
- Catalogue curation: Reading and Photo Quote are hidden from Explore; legacy Quote starter template is not surfaced.
- Weather: unconfigured widgets deep-link into Weather settings; a dedicated deep-link host routes `widgetweaver://weather/settings` to the settings UI.
- Weather reliability: refresh throttling + small retry/backoff; minute forecast and attribution are best-effort; store clears corrupt data and heals between App Group defaults and standard defaults.
- Variables: in-app built-in key browser + syntax/filters reference; built-ins intentionally override custom keys; `Docs/VARIABLES.md` is the canonical reference.
- Design exchange: `.wwdesign` import review exists, including an import preview sheet that renders Small/Medium/Large previews before import.
- Widget reload discipline: a reload coordinator exists to coalesce/debounce reload requests and reload known widget kinds rather than using `reloadAllTimelines()`.
- Smart Photos + Clock correctness: Smart Photos crop decision logic is modularised; Clock appearance has a single resolver to reduce preview vs Home Screen drift.

Still to track (non-blockers, but visible):

- Decide whether “Reading” and “Photo Quote” remain hidden/back-compat only, or are fully removed (requires catalogue/spec clean-up and a migration strategy).
- Migrate remaining direct `WidgetCenter.shared.reloadAllTimelines()` call sites (especially App Intents) to the reload coordinator / targeted reloads.

Weather is not deferred. It is a flagship widget/template for the Feb ship and must meet a baseline of “useful everywhere”: stable caching, a clear location flow, deterministic rendering, and correct attribution. AI work is now an in-cycle track focused on safety and trust (reviewable, reversible spec authoring) plus a small set of tangible UX wins; see `Docs/ROADMAP_AI_2026-01.md`. Larger AI expansions remain optional and must not jeopardise the Feb ship.

## Dates and milestones

- Feature freeze: end of day 2026-02-02 (Europe/Dublin)
- Polish: 2026-02-03 → 2026-02-14
- Target ship: 2026-02-14 → 2026-02-16

## Themes and workstreams

### A) Photos + Smart Photos (flagship)

Goal: Photos widgets should be the “default reason to keep the app installed”.

Primary metric: time-to-first-good-widget ≤ 60 seconds after granting Photos access.

Work items (pre-freeze):

1) Smart Photos stability and correctness
- Hardening for pipeline failures: missing albums, low-memory, permission flips, and background processing cancellations.
- Make crop behaviour predictable; reduce “why is the face cut off?” errors.
- Make preview vs Home Screen more consistent (“what you see is what you get”).

2) Explore catalogue curation for Photos
- Reduce the number of photo starter templates that feel redundant.
- Keep back-compat for any already-shipped template IDs.

3) Editor “Photos first” improvements
- Make “pick a photo / pick an album / Smart Photos” obvious and close to the main editing flow.
- Keep controls progressive, not overwhelming.

Micro-roadmap: see `Docs/ROADMAP_PHOTO_SUITE_UX_2026-01.md`.

### B) Clock (flagship)

Goal: Clock widgets feel correct and predictable on the Home Screen.

Work items (pre-freeze):

- Fix any preview vs Home Screen drift.
- Ensure timeline updates propagate in a disciplined way (avoid reload storms).
- Ensure customisation changes apply quickly and reliably.

### C) Weather (flagship)

Goal: Weather is safe to ship and genuinely useful even when unconfigured.

Work items (pre-freeze):

- Baseline UX:
  - A clear and correct location flow (“use current location” vs manual).
  - A stable “no location configured” widget state that is not blank and guides the user.
  - Attribution shown correctly after first successful update.
- Baseline reliability:
  - Stable caching in App Group, deterministic rendering from cached snapshot.
  - Update throttling and retry/backoff for transient failures.
  - Make minute forecast best-effort (cannot block core usefulness).

### D) Noise Machine (promote to daily-use)

Goal: Noise Machine becomes a genuine daily-use widget, not a novelty.

Work items (pre-freeze):

- Fix any responsiveness issues (first tap after cold start, state reconciliation).
- Add one or two scoped upgrades that improve daily usefulness:
  - Better presets naming / grouping.
  - Clearer “what is playing now” surface.
  - More predictable behaviour after stopping/starting.

### E) Variables (discoverability + usefulness)

Goal: Variables feel approachable and support daily workflows (streaks, counters, weather/steps integrations).

Work items (pre-freeze):

- Improve in-app reference surfaces for variables (built-in keys, syntax, filters).
- Ensure built-in keys are discoverable and insertable while editing.
- Keep the data model deterministic: built-ins should reflect “truthful output” even if a custom key exists.

### F) Sharing/import (more user-realistic)

Goal: Users can share designs and import them confidently.

Work items (pre-freeze):

- `.wwdesign` export and import is supported and documented.
- Import flow shows previews and allows review/selection.
- Back-compat for legacy import formats is maintained (internal builds only).

### G) Cross-cutting UX/UI (cognitive load reduction)

Goal: Reduce cognitive load in the high-frequency flows (Explore → Library → Editor) without widening scope.

Primary metric: fewer “edited but nothing changed” moments (save-state confusion) and faster time-to-first-successful-widget.

Work items (polish window):

- Consolidate Library navigation bar actions: keep one primary “+” entry point and one secondary “More” menu; remove overlapping entry points.
- Make editor save state unmissable: persistent unsaved indicator, a single prominent Save action, and safe back-navigation prompts only when loss is possible.
- Standardise user-facing terminology (Template vs Design vs Widget) across Explore, Library, Editor, help text, and paywall copy.
- Apply progressive disclosure: curate 6–10 flagship templates and keep advanced/edge templates behind “More”; default advanced editor controls to collapsed.
- Accessibility pass focused on: hit targets for chips/pills, contrast over photos, Dynamic Type, and VoiceOver for primary editor controls.

These items are tracked as explicit checklist tasks in `Docs/RELEASE_PLAN_2026-02.md` (UX and product clarity + Accessibility).


### H) Widget design themes (cohesiveness layer)

Goal: make the app feel visually coherent across templates by making styling theme-first. A theme is a curated preset that overwrites `StyleSpec` in one deterministic operation.

Work items:

- Theme presets + ordered catalogue in Shared (`WidgetWeaverThemePreset`, `WidgetWeaverThemeCatalog`).
- Pure theme application for `WidgetSpec` (`WidgetWeaverThemeApplier`) with smoke tests.
- Batch store updates (`WidgetSpecStore.bulkUpdate`) so bulk restyling does not trigger widget reload storms.
- Editor theme picker UI component (self-contained module) backed by `@AppStorage("widgetweaver.theme.selectedPresetID")`.
- Wire the theme picker into the Style tool and apply themes to the active draft (style-only).
- Keep Poster templates themeable by surfacing themes + the relevant style controls while hiding irrelevant sliders.

Reference: `Docs/WIDGET_DESIGN_THEMES.md`.

### I) AI (assistive spec authoring)

Goal: Make AI a trustworthy assistive layer for creating and editing designs, producing explicit `WidgetSpec` outputs that are reviewable and reversible.

Work items (pre-freeze; small and low-risk):

- Fix token mapping gaps (alignment, backgrounds, accents) and redact unnecessary file details from context.
- Surface Apple Intelligence availability in the editor near AI controls.
- Add an App Group kill-switch so AI can be disabled quickly if regressions appear.
- Align About/help “prompt ideas” with what AI actually supports.

Work items (polish window; feature-flagged, ship only if stable):

- Add review UI for generation and patching (no silent saves), including a concise change summary.
- Add a single-step “Undo last AI apply”.
- Introduce schema v2 behind a flag to support content templates (Classic/Hero/Poster) plus poster overlays/glow/accent bar.
- Multi-option generation (3 choices) to reduce “one bad roll” frustration.

Reference: `Docs/ROADMAP_AI_2026-01.md`.

## Risks and mitigations

- Risk: Weather permissions and attribution issues cause App Review friction.
  - Mitigation: Keep permission prompts in-context only; ensure usage string matches behaviour; make attribution visible.

- Risk: Widget reload storms (battery / UI churn).
  - Mitigation: Use reload coordinator; remove direct `reloadAllTimelines()` calls where possible; reload known widget kinds only.

- Risk: Catalogue feels overwhelming / incoherent.
  - Mitigation: Hide redundant templates; keep a curated flagship story.

- Risk: Library + Editor control density increases cognitive load and reduces first-session completion.
  - Mitigation: Consolidate top-bar actions, make save state explicit, standardise terminology, and keep advanced controls behind progressive disclosure.

## Definition of done (Feb ship)

- Photos + Clock + Weather feel flagship, coherent, and stable enough for daily use.
- Widget rendering is deterministic and budget-safe (no heavy work in widgets).
- Surface area is reduced without breaking existing user widgets.
- Permissions footprint is minimal and matches shipped behaviour.
- Sharing/import works in a way that increases user confidence.

## Notes (out of scope / later)

- AI stretch goals may slip beyond the Feb ship if they are not stable behind kill-switches (matched sets, action bars, template-specific AI beyond styling).
- Revisit parked templates/features only with a clear product narrative and permissions strategy.

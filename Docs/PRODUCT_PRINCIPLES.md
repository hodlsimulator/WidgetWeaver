# Product principles

Last updated: 2026-01-31

WidgetWeaver’s differentiation is not “more widgets”. It is a repeatable workflow for building widget-safe experiences quickly, without the UI collapsing under its own feature weight.

## 1) “Super complex, super simple”

Under the hood, WidgetWeaver can be complex (capabilities, pipelines, caches, cross-process state). In the hand, it must feel simple.

Rules:

- Default UI is minimal. Advanced controls are present but hidden until context makes them relevant.
- There is always a single “next best action” on screen (usually: select, edit, preview, save).
- Every screen has a clear escape route (Back, Cancel, Done) and does not trap the user in modal stacks.
- Defaults should produce a good result; optional depth should produce a great result.

## 2) Progressive disclosure via the context-aware editor

- Tool availability is derived from the current `EditorToolContext` (focus, selection descriptor, capabilities, mode).
- If a tool is not relevant, it is not shown. If it is relevant but unavailable, it is shown as unavailable with a concrete reason and a direct action where possible.
- Focus changes must tear down tool-specific state to avoid “dangling” modals, selections, and partial edits.

## 3) The Explore catalogue is curated, not exhaustive

- Explore should showcase a small set of high-quality templates that represent the product.
- Each visible template should have a clear “why would someone keep this on their Home Screen?” story.
- Breadth that increases permissions, complexity, or App Review risk should be hidden or deferred until it has a strong narrative and polish.
- “Hidden” means not discoverable in Explore and not addable from the Home Screen widget gallery in release builds.

## 4) Widgets are deterministic and budget-safe

- Widgets do not run heavy work (Vision, ranking, network-heavy fetch, large I/O) at render time.
- Anything expensive happens in the app and is cached for widget consumption (App Group).
- Widgets render from shared state and timeline entries only.

## 5) The editor never lies about Home Screen behaviour

- The in-app preview must match Home Screen behaviour as closely as possible, but Home Screen correctness wins.
- Any known preview mismatch must be documented in-app (or avoided by design).
- Every “save” triggers the right update signals so Home Screen refresh is predictable.

## 6) Clock behaviour is correctness-first

- Minute accuracy must be demonstrable on the Home Screen, not just in previews.
- Avoid WidgetKit reload loops. Prefer short timelines and lightweight view heartbeats where justified.
- Diagnostic logging must never be able to delay rendering.

## 7) Weather is a flagship experience (reliability-first)

- Weather must be useful everywhere: it should render from cached state immediately and update best-effort in the background.
- Treat minute forecast as best-effort; core current/hourly/daily data must be reliable.
- Location is earned and explicit:
  - Manual location entry must work without requesting Location permission.
  - Location permission is requested only for “Use Current Location”, and denial has a clear fallback.
- When there is no saved location, Weather must render a stable “Set location” state (never a blank tile).
- Attribution and legal link must be present and reliable (appears after the first successful update).

## 8) Noise Machine is interaction-first

- Widget controls must feel instantaneous (optimistic UI is acceptable if it reconciles quickly).
- State changes must be resilient across cold starts and host delays.
- Audio behaviour should be predictable, with clear “playing/paused/stopped” semantics.

## 9) Variables are first-class

- Variables must be discoverable at the moment they are useful (text editing, button actions).
- Insert and preview should be easy, with guardrails (validation, examples, fallback syntax).
- Built-in keys should be documented and surfaced, not hidden in README-only knowledge.

## 10) Deprecations do not break existing widgets

- Removing a template from Explore is acceptable; breaking an existing user widget is not.
- Deprecations should be “hidden from new”, with migration paths where feasible.
- If a feature is not ready, it should be behind an “Experimental” label or disabled, rather than half-exposed.
- If a feature is scope-cut for a release, it must not appear in the widget gallery for that release (runtime “disabled” states are not enough on their own).

## 11) AI is assistive, not magical

- AI features must be optional, reviewable, and reversible.
- AI output should generate real widget specs / tool configurations, not opaque state.
- Prefer on-device and privacy-preserving approaches; AI must be shippable behind a kill-switch so it cannot block a release.

## 12) Permissions are earned and minimised

- Do not request permissions “up front”.
- Ask only at the point the user has chosen a template or tool that clearly benefits from the permission.
- Each permission prompt must have a clear in-product explanation of what changes when access is granted or denied.
- Avoid shipping with a wide permission footprint. If a feature requires a new permission (especially Contacts), it must justify itself as a flagship experience; otherwise it is hidden/deferred.
- Privacy usage strings in Info.plist count as part of the permission footprint. If a feature is removed/parked, remove its unused usage strings (for example, do not ship `NSContactsUsageDescription` if Contacts are not used).
- If the app requests authorisation (for example, `requestWhenInUseAuthorization()`), the corresponding Info.plist usage string must exist. Missing required usage strings are not “minor”; they are crash-class defects.

## 13) Release builds must be reproducible and boring

- A clean checkout should build without local-path package dependencies.
- Repository artefacts and backup files do not ship in targets.
- If a dependency is optional (for example, a feature is hidden/deferred), remove it from the shipping build to reduce risk.

## 14) Widget design themes are the cohesion layer

Widget design themes are curated style presets applied to widget specs. They exist to make the product feel cohesive across templates and to reduce styling decision fatigue.

Rules:

- Themes sit on top of the existing styling pipeline (`StyleSpec` / `StyleDraft`). Rendering stays unchanged; themes are an authoring affordance.
- Theme application is a single deterministic overwrite of `StyleSpec` followed by normalisation (no “smart merges” that create unpredictable results).
- Themes are curated and limited. They are the primary styling affordance; background/accent/typography controls are refinements.
- Themes must prioritise readability and contrast (especially over photos). A theme that produces illegible text is a defect.
- Clock-only styling is optional and must be validated; clock theme tokens only apply when the active template is `.clockIcon`.
- Do not conflate widget design themes with app appearance themes. App appearance themes change the editor/library UI only; widget design themes change widget styling.
- Bulk theme operations must not trigger widget reload storms. Use the store bulk update API and refresh widgets once.

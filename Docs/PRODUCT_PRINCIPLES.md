# Product principles

Last updated: 2026-01-20

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
- Focus changes must tear down tool-specific state to avoid dangling edits and stale UI.
- Context changes must be stable and deterministic (no flicker, no “tool roulette”).

## 3) Widgets are deterministic and budget-safe

- The widget extension never runs heavy work (Vision, ranking, photo preparation, large decoding loops).
- The app performs heavy preparation and stores widget-safe artefacts in the App Group.
- Widget rendering is pure: read shared state, resolve variables for the timeline entry date, render.

## 4) The edit loop must stay fast

- Explore → Remix → Preview → Save is the core workflow.
- The in-app preview must match Home Screen behaviour as closely as possible, but Home Screen correctness wins.
- Every “save” triggers an obvious feedback signal and a predictable widget refresh path.

## 5) Photos are a flagship capability

- “Smart Photos” is not a gallery picker; it is a widget-safe photo experience.
- Any photo feature must answer: how is it prepared in-app, stored safely, and rendered cheaply?
- Cropping and per-family renders must be consistent across templates.

## 6) Clock behaviour is correctness-first

- Minute accuracy must be demonstrable on the Home Screen, not just in previews.
- Avoid WidgetKit reload loops. Prefer short timelines and lightweight view heartbeats where justified.
- Diagnostic logging must never be able to delay rendering.

## 7) Noise Machine is interaction-first

- Widget controls must feel instantaneous (optimistic UI is acceptable if it reconciles quickly).
- State changes must be resilient across cold starts and host delays.
- Audio behaviour should be predictable, with clear “playing/paused/stopped” semantics.

## 8) Variables are first-class

- Variables must be discoverable at the moment they are useful (text editing, button actions).
- Insert and preview should be easy, with guardrails (validation, examples, fallback syntax).
- Built-in keys should be documented and surfaced, not hidden in README-only knowledge.

## 9) Deprecations do not break existing widgets

- Removing a template from Explore is acceptable; breaking an existing user widget is not.
- Deprecations should be “hidden from new”, with migration paths where feasible.
- If a feature is not ready, it should be behind an “Experimental” label or disabled, rather than half-exposed.

## 10) AI is assistive, not magical

- AI features must be optional, reviewable, and reversible.
- AI output should generate real widget specs / tool configurations, not opaque state.
- Prefer on-device and privacy-preserving approaches; do not block shipping on AI.

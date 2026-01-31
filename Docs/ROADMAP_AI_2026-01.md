# AI ENGINE — ROADMAP (2026-01)

Updated: 2026-01-31 (rev B)
Owner: Conor (engineering) / ChatGPT (PM support)

## What changed in rev B

- Stage 1 (trust hardening) is implemented: alignment mapping, background token parity, redaction of image file names in context, availability messaging, and an App Group kill-switch.
- Stage 2 (reviewability) is implemented behind an App Group flag: review sheet for Generate/Patch, candidate modelling (summary + warnings), and one-step undo for the last AI apply.
- Remaining work is validation/polish, plus optional post-freeze expansions (schema v2, multi-option generation).

## Baseline (current implementation)

- Pro-only: prompt → generate a new design and prompt → patch the current design.
- Uses Apple Intelligence on-device model when available; otherwise deterministic fallbacks.
- Master kill-switch exists:
  - `WidgetWeaverFeatureFlags.aiEnabled` (App Group key: `widgetweaver.feature.ai.enabled`, default when unset: enabled)
- Review-before-apply mode exists behind a feature flag:
  - `WidgetWeaverFeatureFlags.aiReviewUIEnabled` (App Group key: `widgetweaver.feature.ai.reviewUI.enabled`, default when unset: disabled)
  - When enabled, AI actions return a `WidgetSpecAICandidate` and show a review sheet (Apply/Cancel) rather than silently saving/applying.
  - When disabled, AI uses the legacy auto-apply behaviour (generate saves immediately; patch applies immediately).

Key implementation files:

- Service + schema/token mapping: `WidgetWeaver/WidgetSpecAIService.swift`
- Candidate pipeline: `WidgetWeaver/WidgetSpecAIService+Candidate.swift`
- Candidate model: `Shared/WidgetSpecAICandidate.swift`
- Review UI: `WidgetWeaver/Features/AI/WidgetWeaverAIReviewSheet.swift`
- Editor wiring:
  - `WidgetWeaver/ContentView+Sections.swift`
  - `WidgetWeaver/Features/AI/ContentView+AICandidateActions.swift`
- Undo snapshot store: `WidgetWeaver/Features/AI/WidgetSpecAISnapshotStore.swift`
- Feature flags: `Shared/WidgetWeaverFeatureFlags.swift`

## Target (unchanged)

- AI produces explicit specs/patches (no opaque state).
- Every AI output is reviewable (preview + short change summary) before saving/applying.
- Every AI apply is reversible (one-step undo).
- Token/schema coverage matches shipped design tokens (no “impossible” values).
- Works without Apple Intelligence via deterministic fallbacks.
- Feature-flagged and kill-switchable so it cannot jeopardise the Feb ship.
- No networking requirements. No new permissions.

## Schedule constraints

- Feature freeze: 2026-01-31
- Polish: 2026-02-01 → 2026-02-14
- Target ship: 2026-02-14 → 2026-02-16

AI is not a release gate for Feb, but it can ship if stable behind flags and if it does not create regressions in the editor.

## Operating rules (non-negotiable)

- Keep edits local and additive.
- Any user-facing AI surface must be feature-flagged (App Group boolean).
- AI must not block the primary “edit → save → add widget” path when unavailable.
- Avoid broad refactors; avoid touching unrelated editor flows.

## Stage 0: Acceptance baseline (manual verification) — IN PROGRESS

Verify the following across both “review UI enabled” and “review UI disabled” modes:

- With Apple Intelligence available:
  - Generate from prompt works end-to-end (preview renders, save succeeds).
  - Patch from prompt works end-to-end (preview renders, apply/save succeeds).
- Without Apple Intelligence:
  - Generate fallback produces a usable spec.
  - Patch fallback produces stable, bounded edits.
- No obvious UI hangs during AI actions.
- AI disabled:
  - Setting `WidgetWeaverFeatureFlags.aiEnabled = false` hides/blocks AI actions and shows a stable “AI is disabled” state.

## Stage 1: Correctness + trust hardening — DONE

Goal: tighten correctness and reduce surprising outputs without changing the core UX flow.

Implemented items:

- Alignment token mapping (centre/center).
- Background token parity with the style system.
- Image file names are redacted from AI context.
- Apple Intelligence availability is surfaced next to AI controls.
- App Group kill-switch for AI surfaces exists (and has a DEBUG toggle).
- About/help prompt ideas are aligned with the shipped AI schema (template, accents, overlays, glow).

## Stage 2: Reviewability (review-before-apply + undo) — DONE (behind flag)

Goal: stop silent saves when enabled. AI should feel safe to try.

Implemented items (gated by `WidgetWeaverFeatureFlags.aiReviewUIEnabled`):

- Candidate modelling: AI actions return a `WidgetSpecAICandidate` (candidate spec + change summary + warnings).
- Review sheet for “Generate” (preview + Apply/Cancel).
- Review sheet for “Patch” (before/after + Apply/Cancel).
- One-step “Undo last AI apply” (when a snapshot exists).

## Stage 3: Schema v2 for content templates (Classic/Hero/Poster) — TODO
(Feature-flagged; not required for Feb ship.)

Goal: structured outputs cover more real, shipped design axes (template choice, poster overlays, glow, accent bar) with fewer “creative” invalid outputs.

Potential steps:

- Add schema v2 behind a feature flag.
- Implement v2 generation payload + mapping.
- Implement v2 patch payload + mapping.
- Ensure deterministic fallback parity for v2.

## Stage 4: Multi-option generation (fast choice) — TODO
(Feature-flagged; likely post-freeze.)

- Generate 3 options and let the user pick (re-using the review sheet).
- Add small style presets (Minimal / Colourful / Bold).

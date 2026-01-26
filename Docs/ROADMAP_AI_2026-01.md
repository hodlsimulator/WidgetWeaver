# AI ENGINE — ROADMAP (2026-01)

Updated: 2026-01-26 (rev A)
Owner: Conor (engineering) / ChatGPT (PM support)

## What changed in rev A

- AI is now an in-cycle track (not post-ship).
- Plan is sequenced to deliver trust first (review-before-apply + undo + kill-switch), then broader capability.

## Baseline (what exists today)

- Pro-only: prompt → new design and prompt → patch design, saved immediately.
- Uses Apple Intelligence on-device model when available; otherwise deterministic fallbacks.
- Current gaps: no review step, limited schema/token coverage, single-shot output.

## Target

- AI produces explicit specs/patches (no opaque state).
- Every AI output is reviewable (preview + short change summary) before saving.
- Every AI apply is reversible (one-step undo).
- Token/schema coverage matches shipped design tokens (no “impossible” values).
- Works without Apple Intelligence via deterministic fallbacks.
- Feature-flagged and kill-switchable so it cannot jeopardise the Feb ship.

## Schedule constraints

- Feature freeze: 2026-01-31
- Polish: 2026-02-01 → 2026-02-14
- Target ship: 2026-02-14 → 2026-02-16

AI is not a release gate for Feb, but it is in-scope to land behind flags and ship only if stable.

## Operating rules (non-negotiable)

- One modest change-set per step (or sub-step where explicitly split).
- Build after every step/sub-step.
- Commit after every successful build.
- No broad refactors. Keep edits local and additive.
- Any new/changed user-facing AI surface must be feature-flagged (App Group boolean).
- No networking requirements. No new permissions.
- AI must not block the primary “edit → save → add widget” path when unavailable.

## Stage 0: Acceptance baseline (NO CODE) — TODO (manual verification)

- With Apple Intelligence available:
  - Generate from prompt works end-to-end (preview renders, save succeeds).
  - Patch from prompt works end-to-end (preview renders, save succeeds).
- Without Apple Intelligence:
  - Generate fallback produces a usable spec.
  - Patch fallback produces stable edits.
- No obvious UI hangs during AI actions.

## Stage 1: Correctness + trust hardening (pre-freeze; low risk) — TODO

Goal: tighten correctness and reduce surprising outputs without changing the UX flow yet.

### Step 1.1: Alignment token mapping (centre/center)

Touched file(s):
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: fix centre alignment mapping`

### Step 1.2: Background token parity with the style system

Touched file(s):
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: support full background palette`

### Step 1.3: Redact image file names from AI context

Touched file(s):
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: redact image file names in context`

### Step 1.4: Surface Apple Intelligence availability next to AI controls

Touched file(s):
- `WidgetWeaver/ContentView+Sections.swift`

Commit:
- `Editor: show Apple Intelligence status in AI section`

### Step 1.5: Add App Group kill-switch for AI surfaces

Touched file(s):
- `Shared/WidgetWeaverFeatureFlags.swift`
- `WidgetWeaver/ContentView+Sections.swift`
- (Optional DEBUG toggle) `WidgetWeaver/ContentView+Toolbar.swift`

Commit:
- `Flags: add AI enable kill-switch`

### Step 1.6: Align About/help “prompt ideas” with shipped AI schema

Touched file(s):
- `WidgetWeaver/WidgetWeaverAboutCatalog.swift`
- `WidgetWeaver/WidgetWeaverAboutSections.swift`

Commit:
- `About: align AI examples with capabilities`

## Stage 2: Reviewability (polish window; medium risk; ship only if stable) — TODO

Goal: stop silent saves. AI should feel safe to try.

### Step 2.1: Add a change-summary helper (before/after diff, human-readable)

New file(s):
- `Shared/WidgetSpecAIChangeSummary.swift`

Commit:
- `AI: add change summary helper`

### Step 2.2: Isolate AI actions into a dedicated file (reduce blast radius)

Touched file(s):
- `WidgetWeaver/ContentView+Actions.swift` (remove only AI-related methods)

New file(s):
- `WidgetWeaver/ContentView+AI.swift`

Commit:
- `Editor: move AI actions into ContentView+AI`

### Step 2.3: Review sheet for “Generate” (preview + Apply/Cancel)

Touched file(s):
- `WidgetWeaver/ContentView+AI.swift`
- `WidgetWeaver/ContentView+Sheets.swift`

New file(s):
- `WidgetWeaver/Features/AI/WidgetWeaverAIReviewSheet.swift`

Commit:
- `AI: add review sheet for generated designs`

### Step 2.4: Review sheet for “Patch” (before/after + Apply/Cancel)

Touched file(s):
- `WidgetWeaver/ContentView+AI.swift`
- `WidgetWeaver/ContentView+Sheets.swift`
- `WidgetWeaver/Features/AI/WidgetWeaverAIReviewSheet.swift`

Commit:
- `AI: add review sheet for patch results`

### Step 2.5: One-step “Undo last AI apply”

Touched file(s):
- `WidgetWeaver/ContentView+AI.swift`
- `WidgetWeaver/ContentView+Sections.swift`

Commit:
- `AI: add undo last apply`

## Stage 3: Schema v2 for content templates (Classic/Hero/Poster) — TODO
(Feature-flagged; not required for Feb ship.)

Goal: structured outputs cover real, shipped design axes (template choice, poster overlays, glow, accent bar).

### Step 3.1: Add schema v2 behind a feature flag

Touched file(s):
- `Shared/WidgetWeaverFeatureFlags.swift`
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: add schema v2 flag + plumbing`

### Step 3.2: Implement v2 generation payload + mapping

Touched file(s):
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: implement v2 generation payload + mapping`

### Step 3.3: Implement v2 patch payload + mapping

Touched file(s):
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: implement v2 patch payload + mapping`

### Step 3.4: Deterministic fallback parity for v2

Touched file(s):
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: improve v2 deterministic fallback rules`

## Stage 4: Multi-option generation (fast choice) — TODO
(Feature-flagged; likely post-freeze.)

### Step 4.1: Generate 3 options and let the user pick

Touched file(s):
- `WidgetWeaver/WidgetSpecAIService.swift`
- `WidgetWeaver/Features/AI/WidgetWeaverAIReviewSheet.swift`
- `WidgetWeaver/ContentView+AI.swift`

Commit:
- `AI: generate multiple options and pick one`

### Step 4.2: Add small style presets (Minimal / Colourful / Bold)

Touched file(s):
- `WidgetWeaver/ContentView+Sections.swift`
- `WidgetWeaver/WidgetSpecAIService.swift`

Commit:
- `AI: add preset-guided generation`

## Later (not required for Feb ship; only after Stage 2 is stable)

- Matched sets (Small/Medium/Large variants) — flagged.
- Action bar suggestions (very constrained) — flagged.
- Template-specific AI beyond styling (Weather/Reminders/Clock) — separate flags per template.

## Definition of done (for the AI upgrade track)

- Review-before-apply exists for Generate and Patch.
- One-step Undo exists for AI applies.
- Kill-switch exists and is verified.
- Token/schema coverage aligns with shipped design tokens.
- Deterministic fallback is usable without Apple Intelligence.

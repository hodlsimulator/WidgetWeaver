# Photo Suite UX micro-roadmap (Jan 2026)

Last updated: 2026-01-24
Owner: Conor (engineering) / ChatGPT (PM support)

## Why this exists

Photos are expected to be the most-used widget family in WidgetWeaver. The roadmap below is designed to:

- Improve UX first: faster “time to a great result”, fewer confusing choices, clearer editing.
- Reduce surface area: fewer starter templates and fewer “one-off” variants, without breaking existing widgets.
- Add a compelling competitive feature: a Memories mode (“On this day” / “On this week”) that feels curated, not random.

This plan is intentionally incremental. Each step is sized to avoid error storms while still moving the product meaningfully.

## Operating rules (non-negotiable)

- One modest change-set per step.
- Build after every step.
- Commit after every successful build.
- Prefer additive code and small, local edits over broad refactors.
- Avoid schema/Codable changes unless a step explicitly calls them out.
- Any new user-facing surface that could regress should be gated behind a feature flag (UserDefaults boolean).
- Do not increase template count as a proxy for discoverability. Prefer “few entry points, many editable options”.

## UX north stars

1) A new user can add a great-looking Photo widget within 60 seconds.
2) Once a Photo widget exists, editing should feel “obvious”:
   - “Choose photo / choose album / choose memories”
   - “Fit vs Fill”
   - “Caption on/off, top/bottom, scrim vs glass”
3) The app should earn trust:
   - no blank tiles
   - predictable refresh behaviour
   - clear permission prompts and fallbacks
4) Explore should feel curated, not exhaustive.

## Feature flags

Existing:

- `FeatureFlags.posterSuiteEnabled` — poster-only editing controls (Stage 1).

Planned (to be introduced as part of this roadmap):

- `FeatureFlags.photosExploreV2Enabled` — revamped Photos presentation on Explore.
- `FeatureFlags.smartPhotoMemoriesEnabled` — Memories modes (On this day/week) inside Smart Photos.

## Stage 2: Photos UX + Memories (new roadmap)

### Step 0: Acceptance baseline (NO CODE)

Checklist:

- Time-to-first-good-photo (fresh install, Photos access granted) <= 60 seconds.
- Starting from `starter-photo-single`, a user can reach: full-bleed vs framed, caption on/off, caption top/bottom, scrim vs glass.
- Smart Photos:
  - “Make Smart Photo” succeeds and produces a stable preview.
  - Album shuffle can be configured and prepares at least one batch.
- No blank tiles after edits (save → background → Home Screen).

Output:
- Capture notes/screenshots (internal) and record any friction points to resolve in later steps.

### Step 1: Prune Photos template surface area on Explore (small, high UX impact)

Goal:
- Reduce confusing duplicates and push variants into editing controls.

Scope (modest):
- Remove Photo Quote from Explore/catalogue surfaces (keep back-compat for existing widgets).
- Collapse redundant Photo variants (Top, Glass, Framed) from Explore lists where they are only “preset wrappers” around existing fields.

Implementation notes:
- Do not delete template IDs/spec builders. Only remove from surfaced lists.
- Preserve the ability to render existing saved widgets identically.

Likely files:
- `WidgetWeaver/WidgetWeaverAboutCatalog.swift`
- `WidgetWeaver/WidgetWeaverAboutView.swift` (if any bespoke Photos section depends on the removed templates)

Build + commit:
- Commit: "Explore: prune photo starter templates"

Acceptance:
- New users cannot add Photo Quote from Explore.
- Existing Photo Quote widgets still render and still open in the editor.

### Step 2: Photos-first Explore presentation (UX refresh behind flag)

Goal:
- Make Photos feel like the flagship by giving it a dedicated, curated entry point.

Scope (modest, but meaningful):
- Introduce a dedicated Photos card/section that:
  - clearly explains “Choose a photo now, customise later”
  - makes the primary CTA obvious (Add)
  - optionally offers 2–3 variants as lightweight choices (not a long list)

Gating:
- Behind `FeatureFlags.photosExploreV2Enabled` (default off until stabilised).

Likely files:
- `WidgetWeaver/WidgetWeaverAboutView.swift`
- `WidgetWeaver/WidgetWeaverAboutCatalog.swift`
- New small view file for the Photos card (to avoid bloating `WidgetWeaverAboutView.swift`)

Build + commit:
- Commit: "Explore: add Photos hero entry (flagged)"

Acceptance:
- With flag off: current Explore remains unchanged.
- With flag on: Photos entry is clearer and reduces template scrolling.

### Step 3: Photo “Essentials” editor controls (build on Poster Suite Stage 1)

Goal:
- When editing a poster/photo widget, expose the core knobs in one place.

Scope:
- Add a small Photo Essentials panel for `.poster` that reuses existing fields:
  - Overlay content: Photo-only vs Caption
  - Caption position: Top vs Bottom
  - Caption style: Scrim vs Glass
  - Treatment: Full-bleed vs Framed (Fill vs Fit)
- Keep this within existing editor sections (no major rearrangement).

Gating:
- Behind `FeatureFlags.posterSuiteEnabled` and only when `template == .poster`.

Likely files:
- `WidgetWeaver/PosterSuiteStage1Controls.swift` (extend carefully, no broad rewrite)
- `WidgetWeaver/ContentView+Sections.swift` or `WidgetWeaver/ContentView+SectionsMedia.swift` (small, local insertion)

Build + commit:
- Commit: "Editor: add Photo Essentials controls (poster-only)"

Acceptance:
- Starting from any photo poster, all four axes are reachable quickly.
- Existing saved posters remain identical until toggles change.

### Step 4: Smart Photos UX hardening pass (no new capability, just reliability + clarity)

Goal:
- Make Smart Photos feel trustworthy and easy to understand.

Scope (bounded):
- Improve state messaging for half-configured Smart Photos (missing renders, missing manifest, etc.).
- Ensure preview strip and crop editor entry points are stable and never crash on nil/missing files.
- Ensure expensive work stays off the main thread and progress UI is obvious.

Likely files:
- `WidgetWeaver/ContentView+SectionsMedia.swift`
- `WidgetWeaver/ContentView+SectionSmartPhoto*.swift`
- `WidgetWeaver/SmartPhotoPreviewStripView.swift`
- `WidgetWeaver/SmartPhotoPipeline.swift`

Build + commit:
- Commit: "Smart Photos: UX hardening pass"

Acceptance:
- No blank tile / missing-image states without an explanatory UI.
- “Make Smart Photo” is deterministic and repeatable.

### Step 5: Memories engine (On this day / On this week) — ENGINE ONLY, behind flag

Goal:
- Implement a new Smart Photos source that feels curated and intentional.

Principles (how this beats typical implementations):
- Quality-first selection (not purely random).
- Variety: avoid repeating the same few photos day after day.
- Respectful fallbacks: if no matches exist, the widget should explain and/or fall back gracefully.

Encoding (no schema changes):
- Store the mode in the shuffle manifest `sourceID` (e.g. `memories:onThisDay` / `memories:onThisWeek`).
- Persist and rotate using existing `SmartPhotoShuffleManifest` + `SmartPhotoShuffleManifestStore`.

Scope:
- Implement a manifest builder that:
  - fetches candidate PHAssets matching the date window across years
  - filters out screenshots/low-res assets (reuse existing heuristics)
  - scores and ranks (reuse `SmartPhotoQualityScorer` where possible)
  - writes a manifest file and triggers preparation of an initial batch

Gating:
- Behind `FeatureFlags.smartPhotoMemoriesEnabled` (default off).

Likely files:
- `WidgetWeaver/SmartPhotoAlbumShuffleControls+Engine.swift` (extend with new fetch helpers)
- Possibly a new small engine file for Memories selection to keep the shuffle engine readable

Build + commit:
- Commit: "Smart Photos: memories manifest builder (flagged)"

Acceptance:
- With the flag on, a developer-only call path can generate a manifest and preview at least one image.
- No changes to the widget extension are required for basic rendering.

### Step 6: Memories UI (editor surface) — small, guided, and safe

Goal:
- Expose Memories as a first-class Photo Source choice without overwhelming users.

Scope:
- Add a simple selector inside existing Smart Photos controls:
  - Album Shuffle
  - On this day
  - On this week
- Provide clear copy about Photos permissions and what will happen.
- Provide a deterministic empty state (no matches) with next-step guidance.

Gating:
- Behind `FeatureFlags.smartPhotoMemoriesEnabled`.

Likely files:
- `WidgetWeaver/SmartPhotoAlbumShuffleControls.swift`
- `WidgetWeaver/ContentView+SectionAlbumShuffle.swift` (if entry points are adjusted)

Build + commit:
- Commit: "Smart Photos: add Memories mode UI (flagged)"

Acceptance:
- A user can enable “On this day/week” and see the widget populate after preparation.
- Disabling the mode cleanly returns to single-photo or album shuffle without corrupting state.

### Step 7: Competitive polish (selection quality and user trust)

Goal:
- Make Memories feel “curated”, not like a random photo dump.

Scope (one micro-upgrade per commit):
- Add anti-repeat policy (e.g. rotate through ranked set before repeating).
- Add optional “year” affordance (implemented as a caption preset, not a new template).
- Ensure daily refresh policy is predictable (manifest regenerates at most once per day/week, not on every open).

Build + commits:
- Commit: "Memories: anti-repeat rotation"
- Commit: "Memories: optional year caption preset"
- Commit: "Memories: refresh cadence guardrails"

Acceptance:
- Consecutive days/weeks do not spam the same top 1–3 images.
- The feature remains widget-safe and does not increase extension work.

### Step 8: Ship decision and scope lock (NO CODE)

Decide what ships by Feb (feature freeze constraints apply):

- Must-ship candidates:
  - Photo Essentials editor controls (poster-only) if stable.
  - Explore pruning (remove Photo Quote surface area).
  - Smart Photos reliability + UX hardening.

- Post-ship or flagged:
  - Memories (“On this day/week”) unless it is stable, fast, and obviously delightful.

Output:
- Update `Docs/RELEASE_PLAN_2026-02.md` with any Photos-specific QA steps if the feature is promoted.

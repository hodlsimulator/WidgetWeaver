# Photo Suite UX micro-roadmap (Jan 2026)

Last updated: 2026-01-25
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

## Status update (as of 2026-01-25)

Progress already landed in the codebase:

- Explore pruning has begun: Photo Quote and several Photos “wrapper” presets are hidden from Explore to keep the Photos surface curated (back-compat preserved for existing widgets/imports).
- Smart Photos architecture is tighter: crop decision logic is isolated (family-specific defaults, subject-aware framing) to reduce preview vs Home Screen drift.

Still to do in this roadmap:

- The Step 4 Smart Photos UX hardening pass (state messaging for half-configured states, preview strip/crop editor stability, and clearer progress UI).
- Decide the long-term end-state for hidden presets (keep hidden/back-compat only vs full removal with clean-up + migration strategy).

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

### Step 1: Reduce redundant Photos templates (catalogue curation)

Intent:
- Keep Explore curated.
- Reduce choice overload while preserving back-compat.

Tasks:
- Identify “wrapper” presets that are basically style variants of the same thing (caption, frame, glass strip, etc.).
- Hide them from Explore templates list.
- Keep legacy template IDs in the app so existing widgets import and render correctly.

Constraints:
- Do not remove old template IDs unless there is a migration strategy.
- Ensure the “Photos” story is still complete (full-bleed + caption + framed should remain reachable via editing controls).

Done when:
- Explore Photos templates list is shorter and clearer.
- Existing widgets using hidden templates still render correctly.

### Step 2: Make Photos editing feel obvious

Intent:
- Make the first editing actions feel “photo-first”, not “settings-first”.

Tasks:
- In the editor, elevate the “Choose photo / Choose album / Smart Photo” entry points.
- Ensure “Fit vs Fill” is near the photo picker (not buried).
- Ensure caption controls are discoverable and match the current layout mode (caption on/off; top/bottom; scrim vs glass).

Done when:
- A new user can plausibly modify a Photos widget without reading docs.

### Step 3: Memories mode (On this day / On this week) for Smart Photos (scoped)

Intent:
- Create a curated-feeling feature that differentiates Smart Photos from basic shuffle.

Tasks:
- Add a “Memories” mode inside Smart Photos:
  - On this day (month/day match)
  - On this week (week-of-year match, scoped)
- Apply simple ranking rules:
  - Favour photos with faces.
  - Favour photos with high “quality” score.
  - Avoid very low light / blurred items when possible.
- Keep it deterministic:
  - Use a saved “seed” per widget spec so the same day produces stable results unless the user requests a refresh.

Constraints:
- Do not do heavy Vision work inside widgets.
- Any new heavy work runs in the app and saves results to App Group.

Done when:
- A user can enable Memories mode and it produces a plausible set of photos consistently.

### Step 4: Smart Photos UX hardening pass

Intent:
- Make Smart Photos feel reliable and trustworthy.

Tasks:
- Improve state messaging:
  - “Preparing photos…”
  - “No photos available”
  - “Needs Photos access”
  - “Needs album selection”
- Ensure the preview strip remains stable while background prep runs.
- Ensure the crop editor is stable and predictable for each widget family.

Done when:
- Smart Photos feels “confident”, not experimental.

### Step 5: Photos Explore V2 (optional, if time remains)

Intent:
- Make Explore feel curated and premium without increasing template count.

Tasks:
- Group Photos templates into a small number of “hero” entries.
- Provide a clear “Remix” flow.
- Make it obvious how to reach variants via editing controls.

Done when:
- Explore Photos feels like 2–3 “hero” options rather than 10 similar presets.

## Notes

- This micro-roadmap is intentionally sequenced: reduce choice → improve editing → add one compelling feature → harden.
- If any step introduces instability, revert and re-scope rather than pushing forward.

# PHOTO WIDGET SUITE — UX ROADMAP (2026-01)

Updated: 2026-01-28 (rev T)

## Delta since rev S (what changed)

- Step 7.2 “Memories: optional year caption preset” is functionally integrated (year built-in + insert snippet + diagnostics allowlist + preview + ticking paths), but remains NOT DONE until it builds and is committed (per operating rules).
- Step 7.3 “Memories: refresh cadence guardrails” moved from TODO to IN PROGRESS:
  - Cadence token is encoded in SmartPhotoShuffleManifest.sourceID (no schema/spec changes):
    - memories:onThisDay:MM-DD (daily-stable)
    - memories:onThisWeek:YYYY-Www (weekly-stable)
  - Auto-refresh attempt limiting is implemented via a per-mode, per-window attempt token stored in UserDefaults (prevents regen on every open, even on failure).
  - Auto-refresh check is wired into the existing Album Shuffle controls task flow (no new top-level UI surfaces).
  - Initial integration build issues addressed:
    - Strict concurrency: avoid static stored UserDefaults; access under @MainActor.
    - Candidate fetch implemented inside Memories engine (no dependency on missing helper API).
- No schema/spec changes.
- No new top-level UI surfaces.

## Target

- Make Photos feel like the flagship: faster time-to-a-great-result, fewer confusing choices, clearer editing.
- Reduce Photos starter-template surface area (especially duplicates/presets) without breaking existing saved widgets.
- Add a Memories source (“On this day” / “On this week”) implemented via existing Smart Photos plumbing (no spec/schema changes required).

## Operating rules (non-negotiable)

- One modest change-set per step (or explicitly listed sub-step).
- Build after every step/sub-step.
- Commit after every successful build.
- Keep edits local and additive; no broad refactors.
- Any new/changed user-facing surface that could regress must be feature-flagged (UserDefaults boolean).
- Prefer presets + editable controls over new templates (Explore should be curated, not exhaustive).
- Avoid touching shared Smart Photos schema/types unless strictly necessary.

## Stage 2 steps

### Step 0: Acceptance baseline (NO CODE) — TODO (manual verification)

- Time-to-first-good-photo widget (fresh install, Photos access granted) <= 60 seconds.
- From starter-photo-single, confirm editor can reach:
  - full-bleed vs framed
  - caption on/off
  - caption top vs bottom
  - scrim vs glass
- Confirm Smart Photos “Make Smart Photo” and Album Shuffle work end-to-end.
- Confirm no blank tiles after edits (save → background → Home Screen).
- Orientation regression check (run after each Step 2.1-related change):
  - From Explore, create a photo-based widget from at least 3 EXIF-orientations:
    - camera portrait
    - camera landscape
    - an older photo known to have non-`.up` EXIF orientation
  - Expected: preview + saved widget are not rotated/upside down.
  - Status: PASS (simulator); TODO: repeat once on physical device before shipping.
- Poster controls check:
  - On a device that has never run a DEBUG build, confirm Poster “Photo Essentials” controls appear for poster templates.

### Step 1: Explore surface-area prune (high UX impact, low risk) — DONE (code + verified)

- Remove Photo Quote from Explore/catalogue surfaces (keep back-compat).
- Collapse redundant Photos presets from Explore lists where they are only wrappers around existing fields.

Touched file(s):
- `WidgetWeaverAboutCatalog.swift`

Commit:
- `Explore: prune photo starter templates`

### Step 2: Photos-first Explore presentation (flagged) — DONE (code + verified)

- Add a dedicated Photos hero entry that reads “choose a photo now, customise later”.
- Provide 2–3 lightweight variants (not a long list).
- Gate behind FeatureFlags.photosExploreV2Enabled (default off until stable).

Touched file(s):
- `FeatureFlags.swift`
- `WidgetWeaverAboutSections+Photos.swift`
- `ContentView+Toolbar.swift` (DEBUG toggle)
- `WidgetWeaverAboutPhotosHeroEntryV2.swift`

Commit:
- `Explore: add Photos hero entry (flagged)`

### Step 2.1 (HOTFIX): Explore template photo orientation normalisation — DONE (verified)

#### Goal

- Ensure any photo chosen during Explore template creation is persisted with pixels in `.up` orientation AND orientation metadata is 1.

#### Status summary

- Regression runs show no upside-down images.
- Logs confirm picker input may arrive rotated; normaliser outputs JPEG bytes with orientation==1; Smart Photo outputs also orientation==1.

#### Step 2.1.4 Coverage audit — DONE

- Confirm no path writes raw picked bytes without normalisation.

### Step 3: Photo Essentials editor controls (poster-only) — DONE (code + verified)

- Expose the core axes in one place for template == `.poster`.
- Gate behind FeatureFlags.posterSuiteEnabled and only for template == `.poster`.

### Step 3.1: Poster Suite availability across installs/builds — DONE

- posterSuiteEnabled default set to ON (flag remains kill-switch).
- Remove Aquarium/TestFlight one-time seeding and any call sites.

### Step 4: Smart Photos UX hardening (flagged) — IN PROGRESS (split into buildable sub-steps)

- Gate all Step 4 UX changes behind FeatureFlags.smartPhotosUXHardeningEnabled (default off).
- Step 4.1 — DONE: flag
- Step 4.2 — DONE (flagged): pipeline progress surface
- Step 4.3 — DONE (flagged): preview strip missing-state hints
- Step 4.4 — DONE (flagged): crop entry safety rails
- Step 4.5 Heavy work reliability — IN PROGRESS
  - Step 4.5.1 — DONE: serialise saliency Vision requests (+ extraction)
  - Step 4.5.2 — DONE (flagged): progress surface + lock-scope fix
  - Step 4.5.3 — DONE: write opaque JPEGs without alpha
  - Step 4.5.4 — TODO (only if reproducible on device): concurrency warning audit

### Step 5: Memories engine (On this day/week) — ENGINE ONLY (flagged) — DONE (code landed; exercised via Step 6A/6B UI)

- Manifest builder implemented via existing Smart Photos shuffle plumbing.
- Gate behind FeatureFlags.smartPhotoMemoriesEnabled (default OFF).
- Writes manifests with sourceID prefixes:
  - memories:onThisDay
  - memories:onThisWeek
- Engine also prepares an initial batch so the manifest is immediately widget-renderable once surfaced by UI.

Commit:
- `Smart Photos: memories manifest builder (flagged)`

### Step 6: Memories UI selector (flagged; guided and safe) — DONE (split into moderate sub-steps)

#### Scope guardrails (to prevent error storms)

- Do not touch ContentView toolbar, Smart Photo section, or broader navigation/sheet plumbing.
- Implement within the existing Album Shuffle control surface first.
- No Smart Photos schema/spec changes.

#### Step 6A (moderate): Add “Source” selector + Build/Refresh action inside Album Shuffle controls (flagged) — DONE (code + verified on device)

- UI (Album Shuffle controls only): “Source” menu with:
  - Album Shuffle
  - On this day
  - On this week
- Behaviour:
  - Selecting a Memories mode swaps primary CTA to Build (or Refresh if already configured for that mode).
  - Build/Refresh calls the Step 5 engine to write a shuffle manifest and prep an initial batch.
  - Persist manifest filename onto the existing Smart Photo shuffle field (no schema change).
- Empty state (minimal but deterministic):
  - If no candidates: explain and suggest alternate mode or album.
  - If Photos access off: explain and point to Settings.
- Gate: FeatureFlags.smartPhotoMemoriesEnabled (default OFF)
  - UserDefaults key: widgetweaver.feature.smartPhotos.memories.enabled

Touched file(s):
- `SmartPhotoAlbumShuffleControls.swift`
- `SmartPhotoAlbumShuffleControls+Logic.swift`
- `SmartPhotoShuffleSourceSelectorRow.swift`

Commit:
- `Smart Photos: Memories source selector + build (flagged)`

Acceptance:
- Build passes (device).
- Flag OFF: Album Shuffle UI/behaviour unchanged (no selector).
- Flag ON: selector appears; Build produces a valid manifest and initial prepared entries; manifest filename persists via existing field.

#### Step 6B (moderate): Copy + naming hardening + manifest-source inference (flagged) — DONE (code change-set complete; QA verify next)

- Copy hardening:
  - Add clearer guidance copy per mode:
    - “On this day” vs “On this week” explanation, especially for sparse libraries.
- Deterministic reopen behaviour:
  - Selector selection is inferred from manifest.sourceID prefix:
    - memories:onThisDay → On this day
    - memories:onThisWeek → On this week
    - otherwise → Album Shuffle
  - Avoid confusing half-states by hydrating selection from the loaded manifest on each appearance/manifest change.
  - If user selection differs from configured manifest, show “Currently configured …” hint.
- Optional one-line editor header rename when flag is enabled:
  - “Album Shuffle” → “Shuffle”
- Disable consistency:
  - Under the flag, disable messaging uses “Shuffle …” phrasing.
- Gate: FeatureFlags.smartPhotoMemoriesEnabled.

Touched file(s):
- `SmartPhotoAlbumShuffleControls.swift`
- `SmartPhotoAlbumShuffleControls+Logic.swift`
- `ContentView+SectionAlbumShuffle.swift` (one-line header string, gated)

Commit:
- `Smart Photos: Memories copy + source inference (flagged)`

Acceptance (run after build):
- Reopen editor with an existing Memories manifest: selector reflects the correct mode.
- No confusing half-states; guidance is deterministic.
- Flag OFF: header remains “Album Shuffle”, and no other behaviour changes.

### Step 7: Competitive polish (one micro-upgrade per commit) — IN PROGRESS

#### Step 7.1 Anti-repeat rotation policy (engine-only; no UI) — READY (build + commit pending)

- Goal: reduce near-duplicate bursts and repeated events while keeping deterministic fallbacks for sparse libraries.
- Gate: FeatureFlags.smartPhotoMemoriesEnabled (no additional flag).

Commit (after successful build):
- `Memories: anti-repeat rotation`

#### Step 7.2 Optional “year” affordance implemented as a built-in caption variable (not a new template) — PENDING LAND (build + commit required)

- Approach: expose year as a built-in caption variable for Smart Photos shuffle contexts (Album Shuffle / Memories), not a new template.

Implementation requirements (now satisfied in code; pending land):
- Ensure built-in key is registered (editor diagnostics allowlist) so it does not show as “unknown”.
- Ensure the ticking/overlay variable-resolution path also injects the year variable (not just the non-ticking preview path).
- Ensure year metadata is persisted for prepared shuffle entries (and/or backfilled deterministically where missing).
- Add “Year (Smart Photos)” to Insert Variable as a preset/snippet (gated; no new templates).

Gate:
- FeatureFlags.smartPhotoMemoriesEnabled (no additional flag).

Commit (after successful build):
- `Memories: optional year caption preset`

Acceptance:
- For Album Shuffle / Memories, inserting `{{__smartphoto_year}}` renders a 4-digit year for the current render entry.
- For non-shuffle contexts (single picked photo), it resolves empty (or predictable fallback if used).
- No editor “unknown built-in keys” warnings for `__smartphoto_year`.

#### Step 7.3 Refresh cadence guardrails (regen at most daily/weekly; not on every open) — IN PROGRESS (code integration underway; build + commit pending)

- Goal:
  - Prevent repeated auto-regeneration on every editor open (especially on sparse libraries / intermittent Photos access / transient failures).
  - Keep behaviour deterministic and “quiet” (no error storms).

Implementation (no schema/spec changes):
- Encode a cadence token in SmartPhotoShuffleManifest.sourceID:
  - On this day: memories:onThisDay:MM-DD
  - On this week: memories:onThisWeek:YYYY-Www
- On editor open, if a configured Memories manifest is stale (sourceID token differs from the current token):
  - Attempt an auto-refresh at most once per cadence window (daily/weekly), tracked via a per-mode per-window attempt token in UserDefaults.
  - Manual Build/Refresh remains unchanged and always available.

Gate:
- FeatureFlags.smartPhotoMemoriesEnabled (no additional flag).

Commit (after successful build):
- `Memories: refresh cadence guardrails`

Acceptance:
- Reopening the editor multiple times within the same day/week does not repeatedly rebuild the Memories manifest.
- Moving the device date within the same ISO week does not trigger a rebuild for “On this week”.
- Crossing into a new day (On this day) or a new ISO week (On this week) triggers at most one auto-refresh attempt per window.

### Step 8: Ship decision (NO CODE) — TODO

- Decide which parts become default-on for the Feb ship (feature freeze constraints apply).
- Update release checklist only if Memories is promoted beyond flagged.

## Acceptance criteria (overall)

- Photos feels curated in Explore, not cluttered.
- Editor makes the primary photo knobs obvious and fast.
- No blank tiles; Smart Photos remains deterministic and widget-safe.
- Smart Photos hardening:
  - Half-states are explained (manifest missing / nothing prepared / render missing).
  - No saliency/pipeline crashes during “Prepare next batch” / “Regenerate smart renders”.
  - Long-running work shows obvious progress and blocks overlapping actions when hardening is enabled.
- Orientation:
  - No upside-down photos when creating from Explore templates (preview + saved widget).
  - Output files consumed by widgets always have pixels `.up` and orientation metadata == 1.
- Poster controls:
  - Poster Photo Essentials controls show consistently across devices/builds (default-ON; still poster-template-only).
- Memories:
  - Engine builds deterministic shuffle manifest per mode/date window without schema changes.
  - Step 6A yields immediately renderable entries and clear empty states within Album Shuffle controls.
  - Step 6B ensures reopen behaviour is deterministic and copy is clearer per mode.
  - Curated (quality + variety), with respectful fallbacks.

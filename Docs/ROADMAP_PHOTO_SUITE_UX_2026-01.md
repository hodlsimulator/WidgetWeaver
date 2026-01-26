# PHOTO WIDGET SUITE — UX ROADMAP (2026-01)

Updated: 2026-01-26 (rev L)

## Delta since rev K (what changed)

- Step 4.5.3 landed and verified: opaque JPEG writes now avoid alpha and encode via ImageIO with explicit orientation metadata == 1.
  - Manual crop/straighten path: crops, straightens and saves successfully.
  - Outcome: reduced decode/memory overhead for opaque JPEG outputs; eliminates reliance on UIKit jpegData for this path.
- Orientation hotfix outcome unchanged: no upside-down images observed in regression runs (keep kill-switch plan as last-resort only).
- Non-blocking simulator noise still observed (keep out of the roadmap unless it reproduces on device / release builds):
  - CFPrefsPlistSource warnings for App Group domain
  - repeated “XPC connection was invalidated”
  - LaunchServices database mapping errors (-54)
  - Swift concurrency warning: “unsafeForcedSync called from Swift Concurrent context.”

## Target

- Make Photos feel like the flagship: faster time-to-a-great-result, fewer confusing choices, clearer editing.
- Reduce Photos starter-template surface area (especially duplicates/presets) without breaking existing saved widgets.
- Add a Memories source (“On this day” / “On this week”) implemented via existing Smart Photos plumbing (no spec/schema changes required).

## Operating rules (non-negotiable)

- One modest change-set per step (or sub-step where explicitly split).
- Build after every step/sub-step.
- Commit after every successful build.
- No broad refactors. Keep edits local and additive.
- Any new/changed user-facing surface that could regress must be feature-flagged (UserDefaults boolean).
- Prefer presets + editable controls over new templates (Explore should be curated, not exhaustive).
- Avoid touching shared Smart Photos schema/types unless strictly necessary (prevents redeclaration/ambiguity and large error surfaces).

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
    - an older photo known to have non-.up EXIF orientation
  - Expected: preview + saved widget are not rotated/upside down.
  - Status: PASS (simulator; repeat once on physical device before shipping).
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
- Gate behind `FeatureFlags.photosExploreV2Enabled` (default off until stable).

Touched file(s):
- `FeatureFlags.swift`
- `WidgetWeaverAboutSections+Photos.swift`
- `ContentView+Toolbar.swift` (DEBUG toggle)
- `WidgetWeaverAboutPhotosHeroEntryV2.swift`

Commit:
- `Explore: add Photos hero entry (flagged)`

### Step 2.1 (HOTFIX): Explore template photo orientation normalisation (fix upside-down photos) — DONE (verified)

Goal:
- Ensure any photo chosen during Explore template creation is persisted with pixels in `.up` orientation AND orientation metadata is 1, so downstream rendering/widgets cannot appear upside down.

Constraints:
- Keep changes local to the “choose photo / create spec / write file” boundary.
- Avoid schema changes.
- No user-facing UI; DEBUG-only logs are allowed and must be throttled.

Status summary (rev L):
- Regression runs show no upside-down images.
- Observed logs confirm:
  - picker input may arrive with rotated EXIF orientation (e.g. 6)
  - normaliser emits JPEG bytes with orientation==1 and “already rotated” pixel dimensions
  - Smart Photo pipeline writes master/small/medium/large with orientation==1

Sub-steps (buildable micro-commits):

#### Step 2.1.1: Attempt A — renderer-based normalisation in AppGroup.writeUIImage — DONE (insufficient historically)

- Status: landed previously; not sufficient alone.

#### Step 2.1.2: Instrumentation — confirm source orientation, pipeline path, and written-file orientation — DONE (DEBUG-only)

##### Step 2.1.2a: Log picker input + chosen pipeline path — DONE

- DEBUG-only, throttled logs at the import boundary:
  - picker load result type (Data-only vs file URL representation if available)
  - input UTI (if determinable)
  - input orientation metadata (`kCGImagePropertyOrientation`) and pixel dimensions
  - UIKit decode orientation (`UIImage(data:).imageOrientation`) as secondary signal
  - whether Smart Photo pipeline succeeded or legacy fallback was used

Commit:
- `Photos: log picker input orientation + import path (DEBUG)`

##### Step 2.1.2b: Log Smart Photo outputs after encode (master + small/medium/large) — DONE

- Logs show:
  - input orientation + pixel dims at prepare
  - written-file orientation + pixel dims for each output

Commit:
- `Smart Photos: log encoded output orientation (DEBUG)`

##### Step 2.1.2c: Log widget decode inputs (pre-decode metadata) for the resolved file — DEFERRED

Reason:
- issue no longer reproduces; keep as a ready-to-apply diagnostic step if any device-only repro appears.

#### Step 2.1.3: Fix — enforce pixel + metadata normalisation for Smart Photo AND legacy writes — DONE

- Fix A is sufficient per current evidence; Fix B/C not indicated.

##### Step 2.1.3A: Fix A — prefer picker file representation and normalise bytes before any save — DONE

- Picker import now normalises source into a JPEG with:
  - pixels rotated to `.up`
  - metadata orientation set to 1
  - maxPixel sized for intended pipeline stage:
    - Smart Photo source bytes normalised at ~3072 longest edge
    - Legacy single-file normalised at ~1024 longest edge
- Applied at the import boundary (before `SmartPhotoPipeline.prepare`).

Commit:
- `Photos: normalise picker bytes before Smart Photo prepare`

##### Step 2.1.3B: Fix B — ImageIO-based JPEG encoding in Smart Photo pipeline (force orientation=1) — NOT REQUIRED

- Not indicated by logs (Smart Photo outputs already show orientation == 1).

##### Step 2.1.3C: Fix C — widget decode guardrail (kill-switch only; last resort) — NOT REQUIRED

- Keep design on file for rapid response if a future device-only regression appears.

#### Step 2.1.4: Coverage audit — ensure no path writes raw picked bytes without normalisation — TODO

- Identify all entry points that can persist a picked photo:
  - Explore → add template → auto-present picker
  - Editor → Replace photo
  - any “choose photo now” Explore flows
- Ensure all of them route through the same normalised-write boundary.

Commit:
- `Photos: audit + route all picker writes through normaliser`

#### Step 2.1.5: Repair guidance (no automatic migration) — NOT REQUIRED (for now)

- Only add user-facing guidance if support load indicates confusion.

Commit (only if copy lands):
- `Photos: add note for orientation repair`

### Step 3: Photo Essentials editor controls (poster-only, builds on existing Poster Suite work) — DONE (code + verified)

- Expose the core axes in one place for template == `.poster`:
  - Photo-only vs Caption
  - Caption top vs bottom
  - Scrim vs Glass
  - Full-bleed vs Framed (Fill vs Fit)
- Gate behind `FeatureFlags.posterSuiteEnabled` and only for template == `.poster`.

Touched file(s):
- `PosterSuiteStage1Controls.swift`
- `ContentView+Sections.swift`

Commit:
- `Editor: add Photo Essentials controls (poster-only)`

### Step 3.1: Poster Suite availability across installs/builds — DONE (decision + code)

- Change: `posterSuiteEnabled` default set to ON (flag remains as a kill-switch).
- Remove Aquarium/TestFlight one-time seeding and any call sites (eliminates iOS 18 receipt API warning and cross-device inconsistencies).
- Verify controls remain context-aware via template == `.poster` gating.

Commits:
- `Flags: default Poster Suite on`
- `App: remove Aquarium poster flag seeding`

### Step 4: Smart Photos UX hardening (no new capability; reliability + clarity) — IN PROGRESS (split into buildable sub-steps)

Goal:
- Improve half-state messaging, stabilise preview strip + crop entry points, ensure heavy work stays off the main thread, and make progress obvious.
- Gate all Step 4 UX changes behind `FeatureFlags.smartPhotosUXHardeningEnabled` (default off).

#### Step 4.1 — DONE

- `Smart Photos: add UX hardening flag`

#### Step 4.2 — DONE (flagged)

- `Smart Photos: pipeline progress surface (flagged)`

#### Step 4.3 — DONE (flagged)

- `Smart Photos: preview strip missing-state hints (flagged)`

#### Step 4.4 — DONE (flagged)

- `Smart Photos: crop entry safety rails (flagged)`

#### Step 4.5: Heavy work reliability — IN PROGRESS

##### Step 4.5.1 — DONE

- `Smart Photos: serialise saliency Vision requests`

Extraction (no functional change intended):
- `SmartPhotoPipeline+CropDecision.swift`

##### Step 4.5.2 — DONE (flagged)

- `Smart Photos: pipeline progress surface (flagged)`
- `Smart Photos: fix pipeline lock scope`

##### Step 4.5.3: Reduce decode/memory overhead when writing opaque JPEGs — DONE (verified)

- Change: encode manual crop/straighten JPEGs via ImageIO and ensure alpha-free output (opaque draw when needed), with orientation metadata forced to 1.

Commit:
- `Smart Photos: write opaque JPEGs without alpha`

##### Step 4.5.4: Concurrency warning audit (unsafeForcedSync from concurrent context) — TODO (only if reproducible on device)

- Aim: remove or isolate any forced sync calls made from async contexts in DEBUG/preview flows.
- Keep changes minimal and local; do not refactor broad pipeline ownership.

### Step 5: Memories engine (On this day/week) — ENGINE ONLY (flagged) — TODO

- Implement a manifest builder that:
  - fetches candidate assets for the date window across years
  - filters screenshots/low-res using existing heuristics
  - scores/ranks (reuse `SmartPhotoQualityScorer` where possible)
  - writes a `SmartPhotoShuffleManifest` and triggers initial prep
- Encode mode via shuffle manifest sourceID prefix (e.g. `memories:onThisDay` / `memories:onThisWeek`); no spec schema changes.
- Gate behind `FeatureFlags.smartPhotoMemoriesEnabled` (default off).

Likely file(s):
- `SmartPhotoAlbumShuffleControls+Engine.swift`
- optional small new engine file

Commit:
- `Smart Photos: memories manifest builder (flagged)`

### Step 6: Memories UI selector (flagged; guided and safe) — TODO

- Add a simple “Source” selector inside existing Smart Photos controls:
  - Album Shuffle
  - On this day
  - On this week
- Provide clear permission copy and deterministic empty state guidance.
- Gate behind `FeatureFlags.smartPhotoMemoriesEnabled`.

Likely file(s):
- `SmartPhotoAlbumShuffleControls.swift`
- possibly `ContentView+SectionAlbumShuffle.swift`

Commit:
- `Smart Photos: add Memories mode UI (flagged)`

### Step 7: Competitive polish (one micro-upgrade per commit) — TODO

- Anti-repeat rotation policy.
- Optional “year” affordance implemented as a caption preset (not a new template).
- Refresh cadence guardrails (regen at most daily/weekly; not on every open).

Commits:
- `Memories: anti-repeat rotation`
- `Memories: optional year caption preset`
- `Memories: refresh cadence guardrails`

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
  - Curated (quality + variety), with respectful fallbacks.

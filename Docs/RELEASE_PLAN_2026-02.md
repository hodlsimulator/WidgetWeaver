# WidgetWeaver release plan (Feb 2026)

Last updated: 2026-01-31

## 1) Scope summary

This release is about shipping a coherent, public-quality WidgetWeaver that feels flagship in Photos + Clock + Weather, and is stable enough to use daily.

In scope (must ship):

- Photos + Smart Photos: reliability, performance, and “good by default” results (manual crop tools and optional Photo Filters).
- Clock: Home Screen correctness and predictable update propagation (including Segmented face hardening work).
- Weather (flagship): a rain-first Weather template plus `__weather_*` variables, with a clear location flow, stable caching, and correct attribution.
- Noise Machine: stable, responsive daily-use behaviour (including start/stop fade to reduce pops).
- Reminders: Smart Stack v2 naming + non-duplicating pages (deterministic output per snapshot).
- Variables: better discoverability and in-context insertion (bounded UX improvements only).
- App appearance themes: editor/library appearance themes (no widget impact).
- Widget design themes: curated style presets applied to widget styling (StyleSpec) to keep templates cohesive and reduce styling complexity.
- Editor UX: design thumbnails in Library/pickers; guarded switching when unsaved changes exist.
- Surface-area reductions (usefulness + trust): hide/remove non-flagship templates without breaking existing user widgets, and remove unused permission declarations.

In scope (targeted; ship if stable; feature-flagged):

- AI: make the existing Pro “Generate” and “Patch” flows more trustworthy and more capable without widening permissions:
  - Token mapping parity (alignment/backgrounds/accent).
  - Clear Apple Intelligence availability messaging in the editor.
  - App Group kill-switch for AI surfaces.
  - Review-before-apply UI (no silent saves) with a short change summary and one-step undo.

Out of scope (scope cuts for this release):

- Reading (remove from surfaced catalogue paths)
- Photo Quote (remove from surfaced catalogue paths)
- Clipboard Actions / Screen Actions (parked; must be absent in release builds, including widget gallery)
- PawPulse / “Latest Cat” (future feature; not in release builds)

Weather is not deferred. It is a flagship widget/template and a release gate.

## 2) Dates

- Feature freeze: end of day 2026-02-02 (Europe/Dublin)
- Polish: 2026-02-03 to 2026-02-14
- Target ship: 2026-02-14 to 2026-02-16

### Pre-freeze focus (must be done by feature freeze)

- Clock (Segmented face): finish pixel-snapping/geometry across Small/Medium/Large and confirm Home Screen renders match previews (diagnostics overlays off by default).
- Widget design themes: wire the theme picker into the editor Style tool and apply presets to the draft spec deterministically (style-only; no schema/render changes).
- Widget reload discipline: replace remaining `WidgetCenter.shared.reloadAllTimelines()` call sites in shipping/user-driven paths (especially App Intents) with `WidgetWeaverWidgetReloadCoordinator` or targeted `reloadTimelines(ofKind:)` calls.
- Editor save state: make “saved vs unsaved” unambiguous, keep Save disabled when clean, and keep guarded design switching flows stable.
- Weather trust: confirm Location prompts are strictly in-context and that attribution appears reliably after the first successful update.
- AI (if shipped): decide the default posture for review UI (on/off), and QA both modes behind flags to ensure no editor regressions.

## 3) Release gates

### Gate A: Core widget quality

- [ ] Photo widgets: no blank tiles after edits; images load reliably from App Group.
- [x] Smart Photos: crop decision logic is isolated (family-specific defaults, subject-aware framing), reducing preview vs Home Screen drift.
- [x] Photo Filters: verified reliable and within budget in widgets; kill-switch works (`WidgetWeaverFeatureFlags.photoFiltersEnabled`).
- [ ] Smart Photo manual crop tools: crop/straighten/rotate persist correctly across families and across export/import.
- [ ] Photo Clock: time variables resolve against the timeline entry date (no “frozen minute” strings).
- [x] Clock appearance resolves through a single resolver (`WidgetWeaverClockAppearanceResolver`) to reduce preview vs Home Screen drift.
- [ ] Clock (Segmented face): verify geometry/pixel-snapping across Small/Medium/Large; keep diagnostics flags off by default.
- [ ] Weather: renders a useful widget state everywhere:
  - [ ] With a saved location: shows cached weather immediately and updates within expected intervals.
  - [x] Without a saved location or snapshot: shows a stable “Set location” state (no blank tiles).
  - [x] Unconfigured Weather widgets deep-link to Weather settings (`widgetweaver://weather/settings`) rather than leaving the user stranded.
  - [x] Minute forecast and WeatherKit attribution are treated as best-effort so they cannot block a useful widget state.
  - [ ] Weather attribution is present (legal link appears after first successful update).
- [ ] Noise Machine: first tap after cold start updates UI immediately; state reconciles correctly.
- [x] Noise Machine: start/stop uses a short master-volume fade and a stop grace period to reduce pops and avoid engine thrash.
- [ ] Reminders (Smart Stack v2): verify v2 page names + strict dedupe (Overdue → Today → Upcoming → High priority → Anytime → Lists) in widgets.

### Gate B: Data integrity and safe deprecations

- [ ] Edits do not corrupt saved widget specs.
- [ ] AI (if shipped): generation/patching produces valid specs and cannot corrupt saved designs:
  - [x] Review-before-apply UI exists behind `WidgetWeaverFeatureFlags.aiReviewUIEnabled` (no silent saves when enabled).
  - [x] One-step undo exists when review UI is enabled.
  - [x] Kill-switch exists and works (AI can be disabled without removing code) via `WidgetWeaverFeatureFlags.aiEnabled`.
  - [x] Deterministic fallback remains usable when Apple Intelligence is unavailable.
  - [ ] Decide ship posture (review UI default on/off) and QA both states.
- [x] Design sharing/export: exporting a widget design produces a `.wwdesign` file; importing from Files works; legacy `.json` import remains supported for internal builds.
- [x] Import review flow exists, including an import preview sheet that renders Small/Medium/Large previews before import.
- [ ] App Group storage migrations (if any) are forward compatible.
- [ ] Removing templates from Explore does not break existing user widgets:
  - [x] “Reading” (hidden from new)
  - [x] “Photo Quote” (hidden from new)
  - [x] Clipboard Actions / Screen Actions (parked; no release-bundle registration; internal builds only if explicitly enabled)
  - [x] PawPulse / “Latest Cat” (not registered in the widget extension unless `PAWPULSE` is defined; release builds must not define it)
- [ ] Weather cache/state is robust:
  - [x] Clearing location clears the weather snapshot deterministically (and clears attribution/refresh timestamps).
  - [x] Snapshot/location decoding tolerates failures by clearing corrupt data (no crash-class decoding failures).
  - [x] App Group / standard defaults “healing” exists so app + widget converge on the same store.
  - [x] Weather variables resolve deterministically from the stored snapshot/location.

### Gate C: Performance and stability

- [ ] No obvious jank when opening editor and scrolling tool panes on a mid-range device.
- [ ] Smart Photos prep does not block the UI thread.
- [ ] Weather updates respect the minimum update interval and do not thrash widget reloads:
  - [x] Refresh throttling exists (`shouldAttemptRefresh`, `lastRefreshAttemptAt`) to prevent repeated retries/thrashing.
  - [x] Core WeatherKit fetch has a small retry/backoff for transient failures.
  - [x] Widget reloads are coalesced for Weather updates (reload specific kinds; avoid `reloadAllTimelines()`).
- [x] A widget reload coordinator exists to coalesce/debounce reload requests and reload known widget kinds rather than using `reloadAllTimelines()`.
- [ ] Widget extension does not do heavy work during timeline generation or rendering.

### Gate D: Usefulness + trust gates (permissions, surfaces, reproducibility)

- [x] Explore/catalogue surfaces are curated for the flagship story:
  - [x] “Reading” is not listed.
  - [x] “Photo Quote” is not listed.
  - [x] Legacy “Quote” starter template is not surfaced (any remaining `starter-quote` usage is for legacy/icon mapping only).
- [x] Clipboard Actions is absent from the release build:
  - [x] Not listed in Explore.
  - [x] Not registered in `WidgetWeaverWidgetBundle` (no Home Screen widget gallery entry).
  - [x] No dependency on ScreenActionsCore in the default build.
- [x] Privacy strings match shipped behaviour:
  - [x] `WidgetWeaver/Info.plist` does not contain `NSContactsUsageDescription` (nor any InfoPlist.strings entry).
  - [x] `WidgetWeaver/Info.plist` contains `NSLocationWhenInUseUsageDescription` with the exact copy below (if Weather can request Location authorisation):
    - “WidgetWeaver uses your location to fetch local weather for your Weather widget when you choose Use Current Location.”
- [ ] Location permission is requested only in-context (Weather settings / explicit “Use Current Location”), not on launch.
- [x] Clean checkout builds without local-path package dependencies:
  - [x] No `XCLocalSwiftPackageReference` entries in `WidgetWeaver.xcodeproj/project.pbxproj` for release builds.
  - [x] A collaborator machine can build without a sibling folder such as `../ScreenActions-clone/...`.

## 4) Polish checklist

### UX and product clarity

- [ ] Explore catalogue: clearly communicates the core value (templates → remix).
- [ ] Templates: top 6–10 templates feel high quality and coherent.
- [ ] Library: consolidate top-bar actions to reduce duplication
  - [ ] Keep one primary creation entry point (“+”) and one secondary actions menu (“More” / ellipsis); remove overlapping entry points.
  - [ ] Ensure the toolbar does not duplicate the same actions already available via context menus (duplicate/rename/export/delete, pinning).
  - [ ] Confirm the primary “Add” path supports: new design from template, import (`.wwdesign`), and duplicate.
- [ ] Editor: make save state obvious and trustworthy
  - [ ] Persistent unsaved-changes indicator when edits are pending (for example, an “Unsaved” tag or a dot near the title).
  - [ ] Save action is singular, prominent, and disabled when no changes exist.
  - [ ] Navigating back with unsaved changes prompts to Save / Discard (only when the change would be lost).
  - [ ] If autosave exists for some edits, the UI still communicates “Saving…” → “Saved” to avoid uncertainty.
- [ ] Terminology: standardise labels across Explore / Library / Editor
  - [ ] Pick and enforce primary nouns for: Template (catalogue), Design (saved configuration), Widget (Home Screen instance).
  - [ ] Align paywall copy and help text with the same nouns (avoid near-synonyms like “preset”, “layout”, “skin” unless strictly necessary).
  - [ ] Add a short glossary section to in-app Help (or an existing Help screen) covering these terms.
- [ ] Progressive disclosure: reduce first-session decision points
  - [ ] Curate a “Top templates” set (6–10) and move advanced/edge templates behind “More”.
  - [ ] Default advanced editor controls to collapsed; surface them via “More” / “Advanced” panels.
  - [ ] Validate the primary path is linear: Explore → select → edit → save → add widget, with minimal branching.
- [x] AI (if shipped): review sheet + undo exist behind `WidgetWeaverFeatureFlags.aiReviewUIEnabled` (no silent saves when enabled).
- [ ] Weather is surfaced as a flagship template (not hidden/experimental in shipped surfaces).
- [x] Weather settings is easy to find from the widget when unconfigured (tap deep-links to settings).
- [x] “Reading” is removed from visible catalogue surfaces.
- [x] “Photo Quote” is removed from visible catalogue surfaces.
- [x] Clipboard Actions is absent from release builds (no Explore listing, no widget gallery registration).
- [x] PawPulse / “Latest Cat” is hidden from Explore and first-run paths (future feature; no widget gallery presence unless `PAWPULSE` is defined; release builds must not define it).
- [x] Variables: discoverability improved (built-in key browser, syntax/filters reference, one-tap snippet insertion).
- [x] Editor: design thumbnails exist in the Library list and design picker; switching designs is guarded when there are unsaved changes.
- [ ] App appearance themes: contrast/readability pass across all themes (including in Light/Dark mode and with Reduce Transparency).
- [ ] Widget design themes: wire the theme picker into the Style tool, apply presets to drafts deterministically, and do a contrast/readability pass across presets (including over photos).
- [x] Photos: Photo Filters UX is clear and non-distracting; filter thumbnails and intensity slider behave well.
- [ ] Error states: Smart Photos prep failures explain what to do (permissions, storage, retries).
- [ ] Weather error states are actionable (no “mystery blank widget”):
  - [x] “No location saved” provides an obvious route to set a location (widget tap deep-link).
  - [ ] Transient WeatherKit/network failures fall back to cached snapshot and show a light status.
  - [ ] Units and attribution are visible and consistent.

### Permissions and trust

- [ ] Permission prompts are in-context only (no “ask everything at first launch”).
- [ ] If a permission is denied, the UI explains what changes and how to enable it later.
- [ ] Location permission is requested only when using “Use Current Location” (manual location entry works without it).
- [x] `NSContactsUsageDescription` is removed from Info.plist (Contacts are not used in this release).
- [x] Weather can request Location authorisation without crashing (Info.plist usage string present).

### Accessibility

- [ ] VoiceOver labels for primary controls in Clock and Noise Machine.
- [ ] Sufficient contrast in key templates (especially over photos).
- [ ] Dynamic Type sanity pass for editor lists and primary text editing.
- [ ] Hit-target audit for chips/pills, segmented controls, and small icon buttons (≥ 44×44pt).
- [ ] Sanity pass under common system accessibility settings: Larger Text (AX sizes), Bold Text, Increase Contrast, Reduce Transparency.
- [ ] Ensure scrims/overlays guarantee text contrast over photos (including in Light/Dark Mode).
- [ ] VoiceOver: Editor controls announce value/state clearly; focus order is predictable; secondary panes do not trap focus.

### Stability / QA

- [ ] No crashes in common flows (Explore → remix → save → add widget).
- [ ] No “black tiles” or blank widget views after edits.
- [ ] Widget timelines produce predictable entries without reload loops.
- [ ] Confirm removed/hidden templates are not visible in Explore (Reading, Photo Quote).
- [ ] Confirm “Quote” starter template is not visible in Explore/templates (legacy mapping only).
- [ ] Confirm Clipboard Actions does not appear in the Home Screen “Add Widget” gallery (release builds must not register it).
- [ ] Confirm PawPulse does not appear in the Home Screen “Add Widget” gallery (release builds must not define `PAWPULSE`).
- [ ] Confirm no Contacts permission prompt appears in normal flows (and that the Contacts usage string is absent from Info.plist).
- [ ] Confirm Weather location flow:
  - [ ] Tapping “Use Current Location” prompts for Location permission (in-context).
  - [ ] Denying permission yields a clear fallback to manual location entry.
  - [ ] Accepting permission updates the saved location and refreshes cached weather.
  - [ ] No crash on the first Location prompt (usage string is present).
  - [ ] Tapping an unconfigured Weather widget opens Weather settings (deep-link works end-to-end).
- [ ] Confirm design export/import works via Share Sheet and Files (`.wwdesign` files are offered and can be opened).
- [ ] Confirm widget reload behaviour:
  - [ ] The reload coordinator is used for user-driven edits (no reload storms).
  - [ ] Remaining `reloadAllTimelines()` call sites are removed or justified.

### Engineering hygiene (to track)

These are not blockers for this check-in, but should be tracked during the polish window so the “newer” reload discipline is applied consistently.

- [ ] Replace remaining `WidgetCenter.shared.reloadAllTimelines()` calls with `WidgetWeaverWidgetReloadCoordinator` (or targeted `reloadTimelines(ofKind:)` calls).
  - Current known call sites include: `WidgetWeaver/WidgetWeaverVariableIntents.swift`, `WidgetWeaverWidget/WidgetWeaverWidgetVariableIntents.swift`, `WidgetWeaver/ContentView+Actions.swift`, `WidgetWeaver/ContentViewSupport.swift`, `Shared/WidgetSpec+Utilities.swift`, and parts of the Reminders pipeline.
- [ ] Decide end-state for hidden templates:
  - Option A: keep “Reading” and “Photo Quote” as back-compat-only (hidden, but preserved).
  - Option B: fully remove (requires catalogue/spec clean-up and a migration strategy).

## 5) Release notes (draft)

This release focuses on making WidgetWeaver feel high-quality and safe to use daily:

- More reliable photo widgets and Smart Photos behaviour, including manual crop tools and optional Photo Filters.
- Improved Home Screen clock correctness.
- Flagship Weather template with rain-first nowcast + built-in `__weather_*` variables.
- Noise Machine stability and polish.
- Better Variables discoverability and usability.
- Reminders Smart Stack v2: clearer page names and no duplicate reminders across pages per refresh.
- New app appearance themes (editor/library) and a thumbnail-first design browsing workflow.
- New widget design themes: pick a curated theme to apply cohesive styling quickly.
- More realistic design sharing and import review (with previews).

Scope cuts to keep the release coherent:

- Reading and Photo Quote templates are removed from surfaced catalogue paths.
- Clipboard Actions / Screen Actions is parked and not included in release builds.
- PawPulse (“Latest Cat”) is treated as a future feature and not included in release builds.

## 6) Notes for future iterations

After ship:

1) Weather: expand beyond the baseline (multiple saved locations, deeper forecasts, more visual variants) without widening permissions.
2) AI: expand beyond the baseline (multi-option generation, schema v2 for templates, and matched sets) only after the reviewable/undoable core is proven stable behind the kill-switch.
3) Revisit “scope cut” features with a clear permissions strategy and a coherent product narrative.

## 7) Non-negotiables

1) Keep widget rendering deterministic and budget-safe.
2) Keep heavy work (Vision, ranking) in the app.
3) Avoid WidgetCenter reload loops.
4) Do not ship a permission-heavy feature grab bag.
5) Prefer hiding/deprecation over half-polished shipping.
6) Keep the catalogue minimal: hide any non-flagship templates/features (Reading, Photo Quote, Clipboard Actions, PawPulse) rather than shipping them half-polished.
7) Privacy usage strings must match shipped behaviour (no unused Contacts string; no missing Location string if Location is requested).

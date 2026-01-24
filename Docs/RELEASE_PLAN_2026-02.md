# WidgetWeaver release plan (Feb 2026)

Last updated: 2026-01-24

## 1) Scope summary

This release is about shipping a coherent, public-quality WidgetWeaver that feels flagship in Photos + Clock + Weather, and is stable enough to use daily.

In scope (must ship):

- Photos + Smart Photos: reliability, performance, and “good by default” results.
- Clock: Home Screen correctness and predictable update propagation.
- Weather (flagship): a rain-first Weather template plus `__weather_*` variables, with a clear location flow, stable caching, and correct attribution.
- Noise Machine: stable, responsive daily-use behaviour.
- Variables: better discoverability and in-context insertion (bounded UX improvements only).
- Surface-area reductions (usefulness + trust): hide/remove non-flagship templates without breaking existing user widgets, and remove unused permission declarations.

Out of scope (scope cuts for this release):

- Reading (remove from surfaced catalogue paths)
- Photo Quote (remove from surfaced catalogue paths)
- Clipboard Actions / Screen Actions (parked; must be absent in release builds, including widget gallery)
- PawPulse / “Latest Cat” (future feature; not in release builds)
- New AI capabilities beyond what is already stable (does not block ship)

Weather is not deferred. It is a flagship widget/template and a release gate.

## 2) Dates

- Feature freeze: 2026-01-31
- Polish: 2026-02-01 to 2026-02-14
- Target ship: 2026-02-14 to 2026-02-16

## 3) Release gates

### Gate A: Core widget quality

- [ ] Photo widgets: no blank tiles after edits; images load reliably from App Group.
- [ ] Photo Clock: time variables resolve against the timeline entry date (no “frozen minute” strings).
- [ ] Weather: renders a useful widget state everywhere:
  - [ ] With a saved location: shows cached weather immediately and updates within expected intervals.
  - [ ] Without a saved location: shows a stable “Set location” state (no blank tiles; no reload loops).
  - [ ] Minute forecast is best-effort; core current/hourly/daily must be reliable.
  - [ ] Weather attribution is present (legal link appears after first successful update).
- [ ] Noise Machine: first tap after cold start updates UI immediately; state reconciles correctly.

### Gate B: Data integrity and safe deprecations

- [ ] Edits do not corrupt saved widget specs.
- [ ] Design sharing/export: exporting a widget design produces a `.wwdesign` file; importing from Files works; legacy `.json` import remains supported for internal builds.
- [ ] App Group storage migrations (if any) are forward compatible.
- [ ] Removing templates from Explore does not break existing user widgets:
  - [ ] “Reading” (hidden from new)
  - [ ] “Photo Quote” (hidden from new)
  - [ ] Clipboard Actions / Screen Actions (parked; no release-bundle registration; internal builds only if explicitly enabled)
  - [ ] PawPulse / “Latest Cat” (not registered in the widget extension unless `PAWPULSE` is defined; release builds must not define it)
- [ ] Weather cache/state is robust:
  - [ ] Clearing location clears the weather snapshot deterministically.
  - [ ] Snapshot decoding is tolerant (no crashes on partial/old data).
  - [ ] Weather variables resolve deterministically from the stored snapshot.

### Gate C: Performance and stability

- [ ] No obvious jank when opening editor and scrolling tool panes on a mid-range device.
- [ ] Smart Photos prep does not block the UI thread.
- [ ] Weather updates respect the minimum update interval and do not thrash WidgetCenter reloads.
- [ ] Widget extension does not do heavy work during timeline generation or rendering.

### Gate D: Usefulness + trust gates (permissions, surfaces, reproducibility)

- [ ] Explore/catalogue surfaces are curated for the flagship story:
  - [ ] “Reading” is not listed.
  - [ ] “Photo Quote” is not listed.
- [ ] Clipboard Actions is absent from the release build:
  - [ ] Not listed in Explore.
  - [ ] Not registered in `WidgetWeaverWidgetBundle` (no Home Screen widget gallery entry).
  - [ ] No dependency on ScreenActionsCore in the default build.
- [ ] Privacy strings match shipped behaviour:
  - [ ] `WidgetWeaver/Info.plist` does not contain `NSContactsUsageDescription` (nor any InfoPlist.strings entry).
  - [ ] `WidgetWeaver/Info.plist` contains `NSLocationWhenInUseUsageDescription` with the exact copy below (if Weather can request Location authorisation):
    - “WidgetWeaver uses your location to fetch local weather for your Weather widget when you choose Use Current Location.”
- [ ] Location permission is requested only in-context (Weather settings / explicit “Use Current Location”), not on launch.
- [ ] Clean checkout builds without local-path package dependencies:
  - [ ] No `XCLocalSwiftPackageReference` entries in `WidgetWeaver.xcodeproj/project.pbxproj` for release builds.
  - [ ] A collaborator machine can build without a sibling folder such as `../ScreenActions-clone/...`.

## 4) Polish checklist

### UX and product clarity

- [ ] Explore catalogue: clearly communicates the core value (templates → remix).
- [ ] Templates: top 6–10 templates feel high quality and coherent.
- [ ] Weather is surfaced as a flagship template (not hidden/experimental in shipped surfaces).
- [ ] Weather settings is easy to find when using Weather (one obvious entry point).
- [ ] “Reading” is removed from visible catalogue surfaces.
- [ ] “Photo Quote” is removed from visible catalogue surfaces.
- [ ] Clipboard Actions is absent from release builds (no Explore listing, no widget gallery registration).
- [ ] PawPulse / “Latest Cat” is hidden from Explore and first-run paths (future feature; no widget gallery presence unless `PAWPULSE` is defined; release builds must not define it).
- [ ] Variables: discoverability improved (at least one obvious entry point and in-context insertion when editing text).
- [ ] Error states: Smart Photos prep failures explain what to do (permissions, storage, retries).
- [ ] Weather error states are actionable (no “mystery blank widget”):
  - [ ] “No location saved” explains how to set a location.
  - [ ] Transient WeatherKit/network failures fall back to cached snapshot and show a light status.
  - [ ] Units and attribution are visible and consistent.

### Permissions and trust

- [ ] Permission prompts are in-context only (no “ask everything at first launch”).
- [ ] If a permission is denied, the UI explains what changes and how to enable it later.
- [ ] Location permission is requested only when using “Use Current Location” (manual location entry works without it).
- [ ] `NSContactsUsageDescription` is removed from Info.plist (Contacts are not used in this release).
- [ ] Weather can request Location authorisation without crashing (Info.plist usage string present).

### Accessibility

- [ ] VoiceOver labels for primary controls in Clock and Noise Machine.
- [ ] Sufficient contrast in key templates (especially over photos).
- [ ] Dynamic Type sanity pass for editor lists and primary text editing.

### Stability / QA

- [ ] No crashes in common flows (Explore → remix → save → add widget).
- [ ] No “black tiles” or blank widget views after edits.
- [ ] Widget timelines produce predictable entries without reload loops.
- [ ] Confirm removed/hidden templates are not visible in Explore (Reading, Photo Quote).
- [ ] Confirm Clipboard Actions does not appear in the Home Screen “Add Widget” gallery (release builds must not register it).
- [ ] Confirm PawPulse does not appear in the Home Screen “Add Widget” gallery (release builds must not define `PAWPULSE`).
- [ ] Confirm no Contacts permission prompt appears in normal flows (and that the Contacts usage string is absent from Info.plist).
- [ ] Confirm Weather location flow:
  - [ ] Tapping “Use Current Location” prompts for Location permission (in-context).
  - [ ] Denying permission yields a clear fallback to manual location entry.
  - [ ] Accepting permission updates the saved location and refreshes cached weather.
  - [ ] No crash on the first Location prompt (usage string is present).
- [ ] Confirm design export/import works via Share Sheet and Files (`.wwdesign` files are offered and can be opened).

## 5) Release notes (draft)

This release focuses on making WidgetWeaver feel high-quality and safe to use daily:

- More reliable photo widgets and Smart Photos behaviour.
- Improved Home Screen clock correctness.
- Flagship Weather template with rain-first nowcast + built-in `__weather_*` variables.
- Noise Machine stability and polish.
- Better Variables discoverability and usability.

Scope cuts to keep the release coherent:

- Reading and Photo Quote templates are removed from surfaced catalogue paths.
- Clipboard Actions / Screen Actions is parked and not included in release builds.
- PawPulse (“Latest Cat”) is treated as a future feature and not included in release builds.

## 6) Notes for future iterations

After ship:

1) Weather: expand beyond the baseline (multiple saved locations, deeper forecasts, more visual variants) without widening permissions.
2) AI: start with small assistive flows that produce explicit widget specs/config and are easy to undo.
3) Revisit “scope cut” features with a clear permissions strategy and a coherent product narrative.

## 7) Non-negotiables

1) Keep widget rendering deterministic and budget-safe.
2) Keep heavy work (Vision, ranking) in the app.
3) Avoid WidgetCenter reload loops.
4) Do not ship a permission-heavy feature grab bag.
5) Prefer hiding/deprecation over half-polished shipping.
6) Keep the catalogue minimal: hide any non-flagship templates/features (Reading, Photo Quote, Clipboard Actions, PawPulse) rather than shipping them half-polished.
7) Privacy usage strings must match shipped behaviour (no unused Contacts string; no missing Location string if Location is requested).

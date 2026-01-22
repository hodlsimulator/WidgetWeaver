# Release plan (feature freeze → ship)

Last updated: 2026-01-22
Target ship window: 2026-02-14 to 2026-02-16
Feature freeze: 2026-01-31

This plan is the operational checklist for the mid-February 2026 release. It assumes the feature work window is short and that correctness and polish are prioritised over breadth.

## 1) Rules of engagement

From 2026-02-01 onwards:

- No new widget categories, no new pipelines, no new complex editor screens.
- Only bug fixes, performance improvements, accessibility, copy tweaks, and risk-reducing small UX changes.
- If a change cannot be validated on-device (Home Screen, not just preview) within 30 minutes, it is too risky for polish phase.

## 2) Milestones

- By end of day 2026-01-31: feature freeze branch cut.
- 2026-02-03: first “polish build” on device with a written bug list.
- 2026-02-07: release candidate candidate (RC0) if crash rate and Home Screen behaviour look stable.
- 2026-02-10: RC1 (only critical fixes after this point).
- 2026-02-14 to 2026-02-16: ship.

## 3) Release gates (must be true to ship)

### Gate A: Widget correctness on the Home Screen

- [ ] Clock widget: minute hand ticks on time; no “slow minute hand” behaviour in a 2-hour observation window.
- [ ] Clock widget: no black tile on add; removing/re-adding is not required in normal usage.
- [ ] Photo widgets: no blank tiles after edits; images load reliably from App Group.
- [ ] Photo Clock: time variables resolve against the timeline entry date (no “frozen minute” strings).
- [ ] Noise Machine: first tap after cold start updates UI immediately; state reconciles correctly.

### Gate B: Data integrity and safe deprecations

- [ ] Edits do not corrupt saved widget specs.
- [ ] App Group storage migrations (if any) are forward compatible.
- [ ] Removing templates from Explore does not break existing user widgets:
  - [ ] “Reading”
  - [ ] “Photo Quote”
  - [ ] Screen Actions / Clipboard Actions
  - [ ] PawPulse / “Latest Cat”

### Gate C: Performance and stability

- [ ] No obvious jank when opening editor and scrolling tool panes on a mid-range device.
- [ ] Smart Photos prep does not block the UI thread.
- [ ] Widget extension does not do heavy work during timeline generation or rendering.

### Gate D: Shipping readiness

- [ ] Clean checkout builds without local-path package dependencies.
- [ ] No unintended repo artefacts (for example, `*.bak`) are included in build targets.
- [ ] The app does not request Contacts permission in onboarding or normal use.

## 4) Polish checklist

### UX and product clarity

- [ ] Explore catalogue: clearly communicates the core value (templates → remix).
- [ ] Templates: top 6–10 templates feel high quality and coherent.
- [ ] “Reading” is removed from visible catalogue surfaces.
- [ ] “Photo Quote” is removed from visible catalogue surfaces.
- [ ] Screen Actions / Clipboard Actions are hidden from Explore and first-run paths.
- [ ] PawPulse / “Latest Cat” is hidden from Explore and first-run paths (future feature).
- [ ] Variables: discoverability improved (at least one obvious entry point and in-context insertion when editing text).
- [ ] Error states: Smart Photos prep failures explain what to do (permissions, storage, retries).

### Permissions and trust

- [ ] Permission prompts are in-context only (no “ask everything at first launch”).
- [ ] If a permission is denied, the UI explains what changes and how to enable it later.
- [ ] Contacts permission is not requested (scope decision: Screen Actions is out for Feb).

### Accessibility

- [ ] VoiceOver labels for primary controls in Clock and Noise Machine.
- [ ] Sufficient contrast in key templates (especially over photos).
- [ ] Dynamic Type sanity pass for editor lists and primary text editing.

### Quality / correctness regression checks

Run these checks at least twice during polish (early and late):

- [ ] Add widgets to Home Screen fresh (no existing widgets), then test edits and refresh.
- [ ] Reboot device and re-test Noise Machine first interaction.
- [ ] Switch appearance (Light/Dark) and confirm templates remain legible.
- [ ] Disable/re-enable permissions relevant to a template (Photos/Health/Reminders) and confirm messaging.
- [ ] Confirm removed/hidden templates are not visible in Explore (Reading, Photo Quote, Screen Actions, PawPulse).
- [ ] Confirm no Contacts permission prompt appears in normal flows.

### App Store readiness

- [ ] App name, subtitle, and description align to “widget builder + editor”.
- [ ] Screenshots show Photos + Clock + one interactive widget (Noise Machine).
- [ ] Privacy labels and permissions strings are accurate and match the shipped feature set.
- [ ] Versioning and build numbers consistent.

## 5) Scope cuts (pre-approved)

If time runs short, cut in this order:

1) Keep the catalogue minimal: hide any non-flagship templates/features (Screen Actions, PawPulse, Photo Quote, Reading) rather than shipping them half-polished.
2) Any new Photo template variants beyond the minimum.
3) Noise Machine upgrades beyond responsiveness and basic controls.
4) Variables improvements beyond “discoverable + insertable”.
5) Any Weather work.
6) Any AI work.

## 6) Daily operating rhythm (during polish)

- Start of day: pick the top 3 user-facing issues and the top 3 technical risks.
- Midday: on-device Home Screen test run (10 minutes) focused on Clock + Photos + Noise Machine.
- End of day: update the short changelog and re-check release gates.

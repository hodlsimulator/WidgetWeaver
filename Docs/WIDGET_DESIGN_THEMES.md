# Widget design themes (style presets)

Last updated: 2026-01-31

Widget design themes are a curated layer that sits on top of WidgetWeaver’s existing style pipeline. They exist to make the app feel cohesive: templates from different feature areas (Photos, Clock, Weather, Reminders, etc.) should still look like they belong to the same product, and a user should be able to restyle a design (or a whole library) without re-learning a new set of controls each time.

This is separate from app appearance themes (editor/library UI themes). Widget design themes affect widget styling; app appearance themes affect the app UI only.

## What a theme is

A theme is a curated preset that overwrites widget styling in one deterministic operation:

- A `WidgetWeaverThemePreset` contains:
  - `id` (canonicalised: trimmed + lowercased for stable matching)
  - `displayName` + `detail`
  - `style: StyleSpec`
  - optional `clockThemeRaw` for the `.clockIcon` template only

Theme application is style-only. Themes do not bind content, change data sources, add variables, or change widget behaviour.

Key files:

- Theme presets + catalogue: `Shared/WidgetWeaverThemePreset.swift`
- Pure applier (style overwrite): `Shared/WidgetWeaverThemeApplier.swift`

## Why themes are integral to cohesiveness

1) A single “look” across the product
- The Explore catalogue becomes a curated set of layouts that can share a visual language.
- The Library looks intentional: saved designs feel related rather than a pile of one-off styles.

2) Reduced cognitive load in the editor
- Theme selection becomes the primary styling decision.
- Background/accent/typography controls remain available as refinements, but the first result is good by default.

3) Faster time-to-first-good-widget
- A user can pick a theme and get a coherent result immediately, without needing to understand every style token.

4) A safe way to evolve visual direction
- New presets can be added without schema migrations.
- Existing themes can be tuned (contrast/readability) centrally in Shared, so templates benefit uniformly.

## Non-goals

- No schema changes for theme support.
  - A theme ID is not persisted into `WidgetSpec` (intentionally avoided close to freeze).
  - The theme is applied by writing the concrete `StyleSpec` values into the spec.
- No renderer changes are required to “support themes”.
  - The existing render path reads `StyleSpec` as before.
- No “smart” merging.
  - Theme application is a full overwrite of `StyleSpec` in one operation, then normalisation.

## How theme application works (engineering)

Theme application is deterministic and validated:

- `WidgetWeaverThemeApplier.apply(preset:to:) -> WidgetSpec`
  - overwrites `spec.style` with the preset’s `StyleSpec` (normalised)
  - for `.clockIcon`, optionally applies `clockThemeRaw` via clock design canonicalisation
  - returns a normalised spec

All presets are validated at development time:
- Preset IDs are canonicalised for stability.
- Optional clock theme values are canonicalised; unsupported values fail fast (precondition/assert) so invalid themes do not ship accidentally.

## Editor integration plan

Themes are designed to become the top-level cohesion affordance in the editor:

- The selected theme preset ID is persisted per-device:
  - `@AppStorage("widgetweaver.theme.selectedPresetID")`
  - When unset/unknown, it falls back to `WidgetWeaverThemeCatalog.defaultPresetID`.

- Theme picker UI (self-contained component):
  - `WidgetWeaver/Features/Themes/WidgetWeaverThemePickerRow.swift`
  - Presents the current preset and a sheet-based picker list.
  - Exposes callbacks instead of mutating editor state directly:
    - `applyToDraft(themeID:)`
    - optional `applyToAllDesigns(themeID:)` (kept gated until bulk apply ships)

Planned wiring steps (high level):

1) Insert theme picker at the top of the Style tool (context-aware).
2) Apply to the active draft by replacing the `StyleDraft` from the preset’s `StyleSpec`.
3) Keep Poster templates themeable by showing the theme picker and a small set of applicable style controls.
4) Bulk apply across saved designs via `WidgetSpecStore.bulkUpdate(...)` to avoid reload storms.
5) (Optional) Auto-apply the selected theme when adding a template from Explore.

## Bulk apply and reload discipline

Theme application may be used across many designs; it must not create reload storms:

- `Shared/WidgetSpecStore.swift` includes `bulkUpdate(...)` to load once, save once, and trigger widget refresh once.
- “Apply theme to all designs” should always use the bulk API.

## Theme identity in the Library (optional)

To avoid schema risk close to freeze, theme identity can be derived for display:

- If a spec’s `StyleSpec` matches a preset closely, show the preset display name.
- Otherwise show “Custom”.

This is display-only and does not persist new tags or migrate stored specs.

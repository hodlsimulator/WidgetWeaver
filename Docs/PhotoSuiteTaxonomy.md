# Photo Suite Taxonomy

This document defines the app’s “Photo Suite” in user-meaningful terms and maps today’s starter templates to the underlying spec knobs that implement them.

The intent is to support a UX-first model (few entry points, many editable options) without growing template count as a proxy for hidden settings.

## What “Photo Suite” means

In this codebase, “Photo Suite” refers to designs that use the `.poster` template and render a photo as the primary backdrop.

A poster may be backed by either:

- A single prepared image file (single-photo posters).
- A Smart Photo payload (master + per-family renders) and, optionally, an album shuffle manifest (album-shuffle posters).

## North-star mental model

A poster can be described as:

Photo Source + Photo Treatment + Overlay Content + Overlay Style

These are the user-facing concepts that should remain stable even as implementation details change.

### Photo Source

Defines where the displayed photo comes from.

- Single Photo
  - One photo chosen by the user.
  - Backed by `ImageSpec.fileName` (and optionally `ImageSpec.smartPhoto` for per-family prepared renders).

- Smart Photos (Album Shuffle)
  - Photos rotate from an album.
  - Encoded as `ImageSpec.smartPhoto.shuffleManifestFileName != nil && != ""`.
  - The widget should still decode only one image per family per timeline entry; composition and selection happen in the app during preparation.

### Photo Treatment

Defines how the chosen photo is presented.

- Full-bleed
  - The photo fills the widget.
  - Implemented by `ImageSpec.contentMode == .fill`.

- Framed / Matte
  - A framed photo look (matte) is applied.
  - Implemented by `ImageSpec.contentMode == .fit`, which switches the poster background renderer into the matte-fit variant.

Future: Collage / composite treatments should remain within the “Photo Treatment” axis, not as separate widget templates.

### Overlay Content

Defines what, if anything, is layered on top of the photo.

- None
  - Photo-only.
  - Implemented by `LayoutSpec.posterOverlayMode == .none`.

- Caption
  - Title/subtitle overlay (poster text stack).
  - Implemented by `LayoutSpec.posterOverlayMode == .caption`.

Future: Clock and Quote are overlay content presets (still fundamentally “Caption”), implemented as deterministic edits to existing text + typography defaults.

### Overlay Style

Defines how the caption overlay is treated visually.

- Scrim
  - A soft gradient scrim fading away from the caption edge.
  - This is the default caption treatment.

- Glass
  - A frosted glass card/strip.
  - Current opt-in (no schema change):
    - `StyleSpec.backgroundOverlay == .subtleMaterial` AND
    - `StyleSpec.backgroundOverlayOpacity <= 0.0001`

Note: this overloads a global overlay token as a poster-only style hint. Stage 7 proposes making this explicit.

## Current encoding and hidden couplings

Several poster behaviours are implemented via indirect “hints” rather than explicit poster settings:

- Caption on/off: `LayoutSpec.posterOverlayMode`.
- Caption position (Top/Bottom): `LayoutAlignmentToken.topLeading/top/topTrailing` values.
- Glass caption: `StyleSpec.backgroundOverlay == .subtleMaterial` with effectively zero full-screen overlay opacity.
- Framed/matte: `ImageSpec.contentMode == .fit`.

Because these are not surfaced as first-class poster controls in the editor today, starter template count has grown to provide discoverability.

## Inventory: existing Photo starter templates

Source of truth: `WidgetWeaver/WidgetWeaverAboutCatalog.swift`.

The table below maps each starter to the taxonomy axes and the spec knobs currently used to express it.

| Starter ID | Title | Photo Source | Photo Treatment | Overlay Content | Overlay Style | Spec knobs (today) | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `starter-photo-single` | Photo (Single) | Single Photo | Full-bleed | None | n/a | `layout.template = .poster`; `layout.posterOverlayMode = .none` | Default “photo-only” poster. |
| `starter-photo-framed` | Photo (Framed) | Single Photo | Framed / Matte | None | n/a | `layout.template = .poster`; `layout.posterOverlayMode = .none` | Matte framing requires `image.contentMode = .fit` once an image exists. The starter spec does not pre-seed this because `image` is nil until a photo is chosen. |
| `starter-photo-caption` | Photo + Caption | Single Photo | Full-bleed | Caption | Scrim | `layout.posterOverlayMode = .caption`; bottom anchored (non-top alignment) | Line limits + typography defaults tuned for caption layout. |
| `starter-photo-caption-top` | Photo + Caption (Top) | Single Photo | Full-bleed | Caption | Scrim | `layout.posterOverlayMode = .caption`; `layout.alignment = .topLeading` | Top anchoring is currently an opt-in via `LayoutAlignmentToken.top*`. |
| `starter-photo-caption-glass` | Photo + Caption (Glass) | Single Photo | Full-bleed | Caption | Glass | `layout.posterOverlayMode = .caption`; `style.backgroundOverlay = .subtleMaterial`; `style.backgroundOverlayOpacity = 0` | Glass is currently inferred (material token + opacity gate). |
| `starter-photo-clock` | Photo Clock | Single Photo | Full-bleed | Caption (Clock preset) | Scrim | `layout.posterOverlayMode = .caption`; `primaryText = "{{__time}}"`; `secondaryText = "{{__weekday}}"` | The caption overlay supports minute-level ticking without re-decoding the background photo. |
| `starter-photo-quote` | Photo Quote | Single Photo | Full-bleed | Caption (Quote preset) | Glass | `layout.posterOverlayMode = .caption`; `style.backgroundOverlay = .subtleMaterial`; `style.backgroundOverlayOpacity = 0` | Quote is a text/typography preset on top of the caption overlay. |

## Guardrails

1) Avoid template proliferation.

- Prefer a small number of Explore entry points and express variety via presets and editable controls.
- Keep legacy template IDs for back-compat (imports, deep links, existing saved designs) even when they are removed from surfaced lists.

2) Keep the widget extension cheap.

- One image decode per family per timeline entry.
- Any heavy work (cropping, selection, multi-photo composition) happens in the app during Smart Photo preparation.

3) Prefer explicit UX objects over implementation hacks.

- Poster-only settings should be represented as poster concepts (source/treatment/content/style), even if implementation temporarily reuses existing spec fields.

## Feature flag

New poster-specific editor surfaces should be gated for staged rollout.

- Flag: `FeatureFlags.posterSuiteEnabled`
- Key: `widgetweaver.feature.editor.posterSuite.enabled`

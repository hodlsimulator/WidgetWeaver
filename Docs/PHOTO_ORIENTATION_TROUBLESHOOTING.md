# Photo orientation troubleshooting

This note documents a real regression where picked photos (and Smart Photo renders) could appear upside down or sideways in the editor preview and/or widgets.

The fix is intentionally conservative: normalise all imported photo bytes into an upright JPEG (`orient=1`) and keep all downstream code paths orientation-agnostic.

## Symptoms

Typical symptoms:

- A newly picked photo widget renders upside down.
- Regenerating Smart Photo renders (“smart-*” files) produces upside-down results.
- Different source images produce different failures (one portrait correct; another portrait rotated 90°).

When this happens, it can look like “WidgetKit decoding is wrong”. In practice the problem is usually earlier: the bytes being saved are not consistently upright, even when the metadata claims they are.

## Why this can happen

There are several overlapping sources of non-determinism:

1) PhotosPicker can provide multiple representations of the same selection (file URL, data blob, or a SwiftUI-rendered image). These representations can disagree about whether EXIF orientation has already been applied to the pixel data.

2) Some pipelines “fix” images by writing EXIF orientation `1` without first baking the rotation into the pixels. That creates a file that claims it is upright but is not.

3) Separate “rare” code paths (for example, converting alpha images to opaque before JPEG encoding) can introduce coordinate system flips if implemented with raw Core Graphics contexts.

When these overlap, the bug can look random across images and hard to reproduce.

## Invariants (what the pipeline expects)

WidgetWeaver’s photo cache assumes:

- All persisted JPEGs are stored with pixels oriented up.
- All persisted JPEGs are written with EXIF orientation `1`.

If either invariant is broken, downstream decode behaviour can vary by API and platform.

## Quick diagnosis (DEBUG)

WidgetWeaver already has a compact diagnostic helper:

- `AppGroup.debugPickedImageInfo(data:)`
- `AppGroup.debugPickedImageInfo(fileName:)`

The logs should show (examples):

- `[WWPhotoImport] postNormalise ... out=... orient=1 ...`
- `[WWSmartPhoto] prepare input=... orient=1 ...`
- `[WWSmartPhoto] wrote ... orient=1 ...`

If everything says `orient=1` but the output still appears rotated, the issue is that the *pixels* are wrong while the metadata is “clean”. That indicates the normalisation step is not consistently applying transforms.

Important: previously-generated cached files remain wrong until re-picked or regenerated.

## Known-good fix (Jan 2026)

Two changes together made the pipeline deterministic again.

### 1) Import: ImageIO is the single source of truth

Do not rasterise `SwiftUI.Image` from PhotosPicker as a normalisation step. SwiftUI rasterisation can be inconsistent about applying EXIF orientation for some assets.

Instead:

- Load the picked image bytes (prefer a file transfer, then data transfer, then `Data`).
- Normalise bytes via ImageIO thumbnail decode with transform.
- Re-encode to JPEG with explicit `kCGImagePropertyOrientation = 1`.

Reference implementation:

- `WidgetWeaver/ContentView+PhotoImport.swift`
  - `WWPhotoImportNormaliser.loadNormalisedJPEGUpData(...)`
  - Uses `AppGroup.normalisePickedImageDataToJPEGUp(...)`

Optional (when an identifier exists and Photos permission is granted):

- Use PhotoKit (`PHImageManager.requestImage`) to fetch a rendered `UIImage` matching Photos’ presentation (including edits), then normalise via the standard UIImage-to-JPEG-up path.

### 2) Smart Photo JPEG encoding: avoid Core Graphics coordinate flips

Some images enter the JPEG encoder with alpha-bearing pixel formats (notably PNGs and some intermediate renders). JPEG does not support alpha, so the pipeline strips alpha.

The fix is to implement alpha stripping via `UIGraphicsImageRenderer` (UIKit coordinates) rather than manual `CGContext` drawing with `translate/scale` flips.

Reference implementation:

- `WidgetWeaver/SmartPhotoPipeline.swift`
  - `SmartPhotoJPEG.ensureOpaquePixelFormatIfNeeded(...)`
  - `SmartPhotoJPEG.normalisedOrientationIfNeeded(...)`
  - JPEG encode writes EXIF orientation `1`

## Regression checklist (recommended)

When touching photo import, downsampling, or encoding, validate:

- A portrait HEIC from the Photos library (EXIF orientation typically 6 or 8).
- A portrait JPEG from Files.
- A landscape JPEG (orientation 1).
- A PNG with alpha (to force the alpha-stripping path).
- A screenshot (often already upright).
- A Photos-edited image (crop/rotate edits).

For each case, verify:

- Post-normalisation output: `orient=1`.
- Saved `smart-*` files: `orient=1`.
- On-device Home Screen widget render matches Photos app orientation.

## If this regresses again

Suggested triage order:

1) Confirm which import path was used (`source=imageIO+...` is expected).
2) Confirm whether alpha stripping was triggered (`[WWSmartPhoto] alphaFix ...` log).
3) Inspect the bytes written to the App Group cache (open the file and run `AppGroup.debugPickedImageInfo(fileName:)`).
4) Delete/re-pick/regenerate to remove stale cached files before judging the fix.

If a future iOS update changes PhotosPicker behaviour, keeping the import normalisation “byte-based via ImageIO” is usually the least fragile approach.

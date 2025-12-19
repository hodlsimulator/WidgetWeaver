# WidgetWeaver

WidgetWeaver is an **iOS 26** app for building WidgetKit widgets from a **typed widget specification** (“WidgetSpec”).

- The iOS app creates/edits/saves widget designs (specs).
- The Widget Extension reads a selected spec via the App Group boundary and renders it.
- Specs are always **normalised/clamped** with safe fallbacks, so the widget never crashes on bad data.

WidgetWeaver supports both:
- **Manual editing** (always available)
- **Optional on-device prompt → spec generation** (Apple Intelligence / Foundation Models), with deterministic fallbacks when unavailable


## Current status (0.9.4 (8))

### Core pipeline
✅ iOS app target created and runs on a real device  
✅ Widget extension target added and shows in the widget gallery  
✅ Shared renderer parity (app previews + widget use the same render path)  
✅ App can edit and save specs into the App Group store  
✅ Multiple saved specs (design library)  
✅ Per-widget instance selection (Edit Widget → choose a saved design)  
✅ “Default (App)” selection supported (widget can follow the app’s current default design)  
✅ Preview dock supports **Preview | Live** (Live runs interactive widget buttons locally)

### Layout + style
✅ Shared `WidgetSpec` tokens (layout + style)  
✅ Layout templates: **Classic / Hero / Poster**  
✅ Accent bar toggle (per design; useful for Hero/Poster)  
✅ Expanded style tokens (Radial Glow / Solid Accent backgrounds; Indigo / Yellow accents)  
✅ “Wow” background overlays: **Aurora / Sunset / Midnight / Candy** (adds depth over the base background)  
✅ Style exploration tool: **Randomise Style** (draft-only)

### Components
✅ SF Symbol component (optional) with placement + size + weight + rendering + tint  
✅ Image component (optional) using PhotosPicker  
✅ Picked images are stored in the App Group container and referenced by filename in the spec  
✅ Image maintenance tool: **Clean Up Unused Images** (removes unreferenced files)

### Image-driven design helpers
✅ **Theme extraction from photo** (auto accent + auto background suggestion, with one-tap apply)  
✅ **Remix** (one tap generates **5** visually distinct variants of the current design without touching the text)

### Interactivity + automation
✅ **Widget Action Bar** (interactive buttons on iOS 17+) to run AppIntents  
✅ **Live preview simulator** (toggle **Live** in the preview dock to tap Action Bar buttons in-app)  
✅ **Variables + Shortcuts** (text templates + Variables manager + App Intents actions to update variables and refresh widgets)

### AI (optional)
✅ Prompt → Spec generation (Foundation Models) with validation + repair + deterministic fallback  
✅ Patch edits (e.g. “more minimal”) against an existing spec, with deterministic fallback

### Sharing + inspection
✅ Sharing / import / export (versioned exchange JSON; embeds images when available)  
✅ Inspector (view/copy Design JSON + resolved JSON + exchange JSON; inspect image references)  
✅ Unsaved changes indicator + revert (discard current draft edits and reload last saved)

### Product
✅ About page with template gallery (Starter + Pro), examples, and one-tap add  
✅ Monetisation scaffolding (StoreKit 2 Pro unlock + free-tier limits for designs; Pro-only matched sets + variables)


## Quick start

1. Open `WidgetWeaver.xcodeproj` in Xcode 26+.
2. Ensure **both targets** have the App Group entitlement:
   - `group.com.conornolan.widgetweaver`
3. Run the app on a real device.
4. Add the “WidgetWeaver” widget to the Home Screen (Small/Medium/Large).
5. Fastest start: toolbar menu (**…**) → **About** → add a template.
6. In the editor, create/edit a design and tap **Save & Make Default** (recommended while iterating).
7. Optional: toolbar menu (**…**) → **Inspector** to view/copy the exact JSON being rendered.

Per-widget selection:
- Long-press the widget → **Edit Widget** → choose **Design**
- To follow the app’s current default design, choose **Default (App)**

Matched sets (Small/Medium/Large):
- Enable **Matched set (Small/Medium/Large)** in the editor.
- Use the preview size picker (Small/Medium/Large) to edit each size.
- Style and typography are shared across the set; content/layout components can differ per size.


## Editor features

### Layout templates (Classic / Hero / Poster)
In the editor, pick **Layout → Template**:
- **Classic**
  - The original layout: name + text + optional image banner + optional symbol.
- **Hero**
  - Big headline style with optional **symbol watermark** for a more “designed” look.
- **Poster**
  - Full-bleed image background (when an image is set) with a glass card overlay for readable text.

### Background themes (Aurora / Sunset / Midnight / Candy)
These are style backgrounds designed to look less flat: subtle gradients/glows layered over the base background.

### Symbol component
- Fill **Symbol → SF Symbol name** (for example: `sparkles`)
- Control placement, size, weight, rendering mode, and tint.

### Image component
- Choose **Image → Choose photo**, then save.
- Notes:
  - PhotosPicker does not require photo library permission prompts.
  - Picked images are saved into the App Group container so the widget can render them offline.


## Photo theme extraction (auto accent + auto background)

When a design has a photo, WidgetWeaver can extract a palette and suggest a matching look:
- **Suggested Accent**: pulled from the photo’s dominant/vibrant tones.
- **Suggested Background**: picked to support contrast/readability with the chosen accent.

In the editor (Image section):
- Enable **Auto theme from photo** to apply suggestions automatically when you pick a new photo.
- Or tap **Extract theme now** to recompute and apply on demand.

This only affects the current draft until you **Save**.


## Remix (5 variants, text untouched)

Remix is a one-tap “make this look different” tool:
- Generates **5** visually distinct variants of the current widget.
- Changes things like template/background/typography/style accents.
- Keeps the current text content intact.

Use it to explore directions quickly:
- Tap the wand/Remix action, browse the 5 previews, then apply one to your draft and save if you like.


## Action Bar (interactive widget buttons)

You can attach a small **Action Bar** to a design.
- Shows at the bottom of the widget.
- On **Small** widgets it will show up to **1** button; on Medium/Large up to **2**.
- Buttons run **AppIntents** (iOS 17+) and can update your App Group variable store:
  - **Increment variable** (key + amount)
  - **Set variable to now** (key + format)

Notes:
- Buttons are interactive when rendered as a real widget (Home Screen / StandBy).
- In the editor preview dock, switch to **Live** to tap Action Bar buttons in-app (no Home Screen round-trip).
- In normal **Preview** mode, buttons render as non-interactive (safe while editing).


## About page + templates

WidgetWeaver includes an in-app **About** page that doubles as a template gallery and quick reference.

In the app:
- Open the toolbar menu (**…**) → **About**

From there you can:
- Browse **Starter** and **Pro** templates, each with Small/Medium/Large previews.
- Add a template to your design library, optionally **Add & Make Default**.
- Copy Variable template syntax + examples.
- Copy AI prompt and patch ideas (for on-device generation).

Template scope (what’s included today):
- Templates only use capabilities already supported: text, optional SF Symbol, optional photo (picked manually), layout/style/typography tokens, optional matched sets (Pro), optional variables + Shortcuts (Pro), and optional Action Bar buttons.
- No live external data sources are bundled yet (for example weather). For dynamic values today, use **Variables + Shortcuts** (and/or Action Bar buttons).


## Sharing / import / export

WidgetWeaver can export one design or all designs as a single file, and import designs back into the app.
- Export format: versioned exchange JSON (validated on import).
- Images: exports embed image bytes when the referenced files exist in the App Group container.

Import behaviour:
- Imported designs are duplicated with new IDs to avoid overwriting existing designs.
- Embedded images are restored into the App Group container and references are rewritten.
- Widget refresh: imports and exports trigger a widget refresh so changes show quickly.

Maintenance:
- “Clean Up Unused Images” deletes image files in the App Group container that are not referenced by any saved design.

In the app:
- Toolbar menu (**…**) → **Share this design** / **Share all designs**
- **Import designs…**
- Toolbar menu (**…**) → **Clean Up Unused Images**


## Inspector

The Inspector is a debug view for understanding exactly what the widget will render.

In the app:
- Toolbar menu (**…**) → **Inspector**

From there you can:
- View/copy the base **Design JSON** (what’s saved).
- View/copy the **Resolved JSON** for a selected size (applies matched-set overrides + variables + render-time resolution).
- View/copy the **Exchange JSON** (export format without embedded images).
- See referenced image file names and whether they exist on disk.


## Variables + Shortcuts

WidgetWeaver supports simple text templating in spec text fields, backed by a shared variable store in the App Group.

Pro:
- There’s an in-app **Variables** screen (toolbar menu **…** → **Variables**) to view/edit keys, copy templates, and quickly increment/decrement numeric values.

Template syntax:
- `{{key}}` replaces with the value of `key`
- `{{key|fallback}}` uses `fallback` if `key` is missing or empty

Filters (examples):
- `{{amount|0|number:0}}`
- `{{last_done|Never|relative}}`
- `{{progress|0|bar:10}}`

Built-ins (no stored variable needed):
- `{{__now||date:HH:mm}}`
- `{{__today}}`

Inline maths (example):
- `{{=done/total*100|0|number:0}}%`

Examples:
- Primary text: `Streak: {{streak|0}} days`
- Secondary text: `Last done: {{last_done|Never}}`

Keys are canonicalised (trimmed + lowercased; whitespace normalised).

Updating variables (Shortcuts):
WidgetWeaver exposes App Intents that appear as Shortcuts actions:
- Set WidgetWeaver Variable (key, value)
- Get WidgetWeaver Variable (key)
- Remove WidgetWeaver Variable (key)
- Increment WidgetWeaver Variable (key, amount)
- Set WidgetWeaver Variable to Now (key, format)

When a variable changes, WidgetWeaver triggers widget refresh so widgets re-render with the latest values.

Updating variables (Action Bar buttons):
If a design includes an Action Bar, you can tap those buttons directly on the widget (iOS 17+) to update variables.

Practical testing recipe:
1. Set Primary text to something visible, e.g. `Clicks: {{clicks|0}}`
2. Add an Action Bar button:
   - kind: Increment variable
   - key: `clicks`
   - amount: `1`
3. Save & Make Default
4. Add a widget set to **Default (App)**
5. Either:
   - Toggle **Live** in the editor preview dock and tap the button there, or
   - Tap the button on the Home Screen and watch `Clicks:` update.


## AI (prompt → spec + patch edits)

WidgetWeaver can generate and edit designs from natural language using **Foundation Models** when available.

Generate a new design:
- Use the **AI** section in the app
- Example prompts:
  - “minimal habit tracker, teal accent, no icon”
  - “bold countdown widget, centred, bigger title”
- Tap **Generate New Design**
- Optionally enable **Make generated design default**

Patch an existing design:
- Example patch instructions:
  - “more minimal”
  - “bigger title”
  - “change accent to teal”
  - “remove image”
  - “remove symbol”
- Tap **Apply Patch To Current Design**

Availability + fallbacks:
- If Apple Intelligence / Foundation Models are available, the app generates a constrained payload and maps it into `WidgetSpec`.
- If unavailable (device not eligible, Apple Intelligence disabled, model not ready, etc.), WidgetWeaver still works:
  - New designs fall back to deterministic templates/rules
  - Patch edits fall back to deterministic rules

Privacy:
- Prompt generation is designed to run on-device.
- Images are never generated; images are picked by PhotosPicker and stored locally in the App Group container.


## Architecture

Targets:
- **WidgetWeaver** (iOS app)
  - Create/edit/save a `WidgetSpec`
  - In-app previews (Small/Medium/Large) + **Live** interactive simulator mode
  - Manage a library of saved designs
  - Pick an optional image for a design
  - About page (templates + examples)
  - Optional AI prompt/patch workflow
  - Variables store + App Intents (Shortcuts actions)
  - Action Bar editor (interactive widget buttons)
  - Sharing / import / export
  - Inspector (JSON + image references)
- **WidgetWeaverWidget** (Widget Extension)
  - Reads specs from App Group storage
  - Renders Small/Medium/Large
  - Uses per-instance configuration to select a saved design (or “Default (App)”)
  - Loads an optional image from the App Group container (by filename)
  - Resolves variables at render time
  - Runs Action Bar intents on iOS 17+ when buttons are tapped

Shared boundary:
- App Group: `group.com.conornolan.widgetweaver`

Storage:
- Specs: `UserDefaults(suiteName:)` (JSON-encoded specs)
- Variables: `UserDefaults(suiteName:)` (JSON-encoded dictionary)
- Images: files in the App Group container directory `WidgetWeaverImages/`
- Sharing files: exported JSON exchange (versioned, validated), optionally embedding image bytes

Safety:
- Load failures fall back to `WidgetSpec.defaultSpec()`
- Specs are normalised/clamped before save and after load
- Missing image files simply render as “no image” (no crash)


## Milestones

- Milestone 0 — Scaffold (DONE)
- Milestone 1 — Widget extension scaffold (DONE)
- Milestone 2 — Shared storage + render a saved spec (DONE)
- Milestone 3 — Manual editor + preview loop (DONE)
- Milestone 3.6 — Symbol component (DONE)
- Milestone 3.7 — Image component (DONE)
- Milestone 3.8 — Layout templates + wow backgrounds (DONE)
- Milestone 3.9 — Action Bar (DONE)
- Milestone 3.95 — Photo theme extraction + Remix (DONE)
- Milestone 4 — Prompt → WidgetSpec generation + patch edits (DONE)
- Milestone 5 — Matched sets (Small/Medium/Large) (DONE)
- Milestone 6 — Variables + Shortcuts (DONE)
- Milestone 7 — Sharing / import / export (DONE)
- Milestone 7.5 — About page + template gallery (DONE)
- Milestone 7.6 — Inspector + revert (DONE)
- Milestone 7.7 — Live preview simulator (DONE)
- Milestone 8 — Monetisation (IN PROGRESS)
- Milestone 9 — Control Widgets (OPTIONAL)


## Troubleshooting

### Image not showing in the widget
- Ensure an image was picked and then **Save** was tapped.
- Ensure both targets have the App Group entitlement: `group.com.conornolan.widgetweaver`.
- If the app was reinstalled, previously saved specs may reference image filenames that no longer exist in the App Group container; remove/re-pick the image and save again.
- If re-selecting the same photo seems to do nothing, pick a different photo once, then pick the original again, and save.

### Widget not updating
- Save again (prefer **Save & Make Default** while iterating).
- If you’ve just imported designs, give it a moment and/or re-open the Home Screen; WidgetKit can throttle refreshes.

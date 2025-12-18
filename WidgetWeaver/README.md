# WidgetWeaver

WidgetWeaver is an iOS 26 app for building WidgetKit widgets from a **typed widget specification** (“WidgetSpec”).

- The iOS app creates/edits/saves widget designs (specs).
- The Widget Extension reads a selected spec via the App Group boundary and renders it.
- Specs are always **normalised/clamped** and have safe fallbacks, so the widget never crashes on bad data.

WidgetWeaver supports both:
- **Manual editing** (always available)
- **Optional on-device prompt → spec generation** (Apple Intelligence / Foundation Models), with deterministic fallbacks when unavailable


## Current status (0.9.4 (6))

✅ iOS app target created and runs on a real device  
✅ Widget extension target added and shows in the widget gallery  
✅ Shared `WidgetSpec` tokens (layout + style)  
✅ Expanded style tokens (Radial Glow / Solid Accent backgrounds; Indigo / Yellow accents)  
✅ **New “wow” backgrounds** (Aurora / Sunset / Midnight / Candy overlays for extra depth)  
✅ **Layout templates**: Classic / Hero / Poster  
✅ **Accent bar toggle** (per design; useful for Hero/Poster)  
✅ **Widget Action Bar** (interactive buttons on iOS 17+) to run AppIntents  
✅ Style exploration tool: Randomise Style (draft-only)  
✅ Image maintenance tool: Clean Up Unused Images (removes unreferenced files)  
✅ Shared renderer parity (app previews + widget use the same render path)  
✅ App can edit and save specs into the App Group store  
✅ Multiple saved specs (design library)  
✅ Per-widget instance selection (Edit Widget → choose a saved design)  
✅ “Default (App)” selection supported (widget can follow the app’s current default design)  
✅ SF Symbol component (optional) with placement + size + weight + rendering + tint  
✅ Image component (optional) using PhotosPicker; image files are stored in the App Group container and referenced by filename in the spec  
✅ Prompt → Spec generation (Foundation Models) with validation + repair + deterministic fallback  
✅ Patch edits (e.g. “more minimal”) against an existing spec, with deterministic fallback  
✅ **Matched sets (Small/Medium/Large)** with shared style/typography and per-size overrides (edited via the preview size picker)  
✅ **Variables + Shortcuts** (text templates + in-app Variables manager + App Intents actions to update variables and refresh widgets)  
✅ **Sharing / import / export** (versioned exchange JSON; embeds images when available)  
✅ **Inspector** (view/copy Design JSON + resolved JSON + exchange JSON; inspect image references)  
✅ **Unsaved changes indicator + revert** (discard current draft edits and reload last saved)  
✅ About page with template gallery (starter + Pro), examples, and one-tap add  
✅ **Monetisation scaffolding** (StoreKit 2 Pro unlock + free-tier limits for designs; Pro-only matched sets + variables)


## Quick start

1. Open `WidgetWeaver.xcodeproj` in Xcode 26+.
2. Ensure both targets have the App Group entitlement:
   - `group.com.conornolan.widgetweaver`
3. Run the app on a real device.
4. Add the “WidgetWeaver” widget to the Home Screen (Small/Medium/Large).
5. Optional: open the toolbar menu (**…**) → **About** and add a template (fastest way to get started).
6. In the app, create/edit a design and tap **Save & Make Default** (recommended while iterating).
7. Optional: open the toolbar menu (**…**) → **Inspector** to view/copy the exact JSON being rendered.

Per-widget selection:
- Long-press the widget → **Edit Widget** → choose **Design**
- To follow the app’s current default design, choose **Default (App)**

Matched sets (Small/Medium/Large):
- Enable **Matched set (Small/Medium/Large)** in the editor.
- Use the preview size picker (Small/Medium/Large) to edit each size.
- Style and typography are shared across the set; content/layout components can differ per size.

Optional symbol:
- Fill **Symbol → SF Symbol name** (for example: `sparkles`).

Optional image:
- Choose **Image → Choose photo**, then save.
- Notes:
  - PhotosPicker does not require photo library permission prompts.
  - Picked images are saved into the App Group container so the widget can render them offline.


## New “wow” features

### Layout templates (Classic / Hero / Poster)

In the editor, pick **Layout → Template**:

- **Classic**  
  The original layout: name + text + optional image banner + optional symbol.

- **Hero**  
  Big headline style with optional **symbol watermark** for a more “designed” look.

- **Poster**  
  Full-bleed image background (when an image is set) with a glass card overlay for readable text.

### Action Bar (interactive widget buttons)

You can attach a small **Action Bar** to a design.

- Shows at the bottom of the widget.
- On **Small** widgets it will show up to **1** button; on Medium/Large up to **2**.
- Buttons run **AppIntents** (iOS 17+) and can update your App Group variable store:
  - **Increment variable** (key + amount)
  - **Set variable to now** (key + format)

Notes:
- Buttons are only truly interactive when rendered in a real widget context (Home Screen / StandBy).
- In the app preview they render as non-interactive.

### Background themes (Aurora / Sunset / Midnight / Candy)

These are style backgrounds designed to look less flat (subtle gradients/glows over the base style background).


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
- Templates only use capabilities already supported: **text**, optional **SF Symbol**, optional **photo banner** (picked manually), layout/style/typography tokens, optional **Matched Sets** (Pro), optional **Variables + Shortcuts** (Pro), and optional **Action Bar** buttons.
- No live external data sources are bundled yet (for example weather). If you want dynamic text/numbers today, use **Variables + Shortcuts** (and/or Action Bar buttons).


## Sharing / import / export

WidgetWeaver can export one design or all designs as a single file, and import designs back into the app.

- **Export format:** versioned exchange JSON (validated on import).
- **Images:** exports embed image bytes when the referenced files exist in the App Group container.
- **Import behaviour:** imported designs are duplicated with new IDs to avoid overwriting existing designs; embedded images are restored into the App Group container and references are rewritten.
- **Widget refresh:** imports and exports trigger a widget refresh so changes show quickly.
- **Maintenance:** “Clean Up Unused Images” deletes image files in the App Group container that are not referenced by any saved design.

In the app:
- Use the toolbar menu (**…**) → **Share this design** / **Share all designs**.
- Use **Import designs…** to bring designs back in.
- Use the toolbar menu (**…**) → **Clean Up Unused Images** to delete unreferenced image files.


## Inspector

The Inspector is a debug view for understanding exactly what the widget will render.

In the app:
- Open the toolbar menu (**…**) → **Inspector**

From there you can:
- View/copy the base **Design JSON** (what’s saved).
- View/copy the **Resolved JSON** for a selected size (applies matched-set overrides + variables + render-time resolution).
- View/copy the **Exchange JSON** (export format without embedded images).
- See referenced image file names and whether they exist on disk.


## Variables + Shortcuts

WidgetWeaver supports simple text templating in spec text fields, backed by a shared variable store in the App Group.

Pro:
- There’s an in-app **Variables** screen (toolbar menu **…** → **Variables**) to view/edit keys, copy templates, and quickly increment/decrement numeric values.

### Template syntax

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

### Updating variables (Shortcuts)

WidgetWeaver exposes App Intents that appear as Shortcuts actions:

- **Set WidgetWeaver Variable** (key, value)
- **Get WidgetWeaver Variable** (key)
- **Remove WidgetWeaver Variable** (key)
- **Increment WidgetWeaver Variable** (key, amount)
- **Set WidgetWeaver Variable to Now** (key, format)

When a variable changes, WidgetWeaver triggers widget refresh so widgets re-render with the latest values.

### Updating variables (Action Bar buttons)

If a design includes an **Action Bar**, you can tap those buttons directly on the widget (iOS 17+) to update variables.

Practical testing recipe:
1. Set Primary text to something visible, e.g. `Clicks: {{clicks|0}}`
2. Add an Action Bar button:
   - kind: Increment variable
   - key: `clicks`
   - amount: `1`
3. Save & Make Default
4. Add a widget set to **Default (App)**
5. Tap the button on the Home Screen and watch `Clicks:` update.


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

### Targets

- **WidgetWeaver** (iOS app)
  - Create/edit/save a `WidgetSpec`
  - In-app previews (Small/Medium/Large)
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

### Shared boundary

App Group: `group.com.conornolan.widgetweaver`

Storage:
- Specs: `UserDefaults(suiteName:)` (JSON-encoded specs)
- Variables: `UserDefaults(suiteName:)` (JSON-encoded dictionary)
- Images: files in the App Group container directory `WidgetWeaverImages/`
- Sharing files: exported JSON exchange (versioned, validated), optionally embedding image bytes

### Safety

- Load failures fall back to `WidgetSpec.defaultSpec()`
- Specs are normalised/clamped before save and after load
- Missing image files simply render as “no image” (no crash)


## Milestones

### Milestone 0 — Scaffold (DONE)
- Create app (SwiftUI, iOS 26)
- Add icon
- Initialise repo + push

### Milestone 1 — Widget extension scaffold (DONE)
- Add Widget Extension (no Controls / Live Activity for now)
- Ensure widget appears in gallery and can be added on-device

### Milestone 2 — Shared storage + render a saved spec (DONE)
- Add App Group entitlement to app + widget extension:
  - `group.com.conornolan.widgetweaver`
- Add shared model + store:
  - `WidgetSpec`
  - `WidgetSpecStore` (JSON in App Group UserDefaults)
- Update app UI to save a spec and call:
  - `WidgetCenter.shared.reloadTimelines(ofKind:)`
- Update widget to load from store and render via the shared renderer

### Milestone 3 — Manual editor + preview loop (DONE)
- Expand WidgetSpec v0 to support:
  - layout tokens
  - style tokens
- Add an in-app editor for those fields
- Add in-app previews that use the same renderer as the widget

### Milestone 3.6 — Symbol component (DONE)
- Add optional `SymbolSpec` to `WidgetSpec`
- Expose symbol controls in the editor
- Render symbols in both previews and widget (shared renderer)

### Milestone 3.7 — Image component (DONE)
- Add optional `ImageSpec` to `WidgetSpec`
- Store image files in the App Group container
- Load and render the image in both previews and widget (shared renderer)

### Milestone 3.8 — Layout templates + wow backgrounds (DONE)
- Layout templates: Classic / Hero / Poster
- Accent bar show/hide toggle
- Background themes: Aurora / Sunset / Midnight / Candy

### Milestone 3.9 — Action Bar (DONE)
- Add Action Bar to specs
- Render up to 1–2 interactive buttons (depending on widget size)
- Buttons run AppIntents (iOS 17+) to update variables and refresh widgets

### Milestone 3.5 — Multiple specs + per-widget selection (DONE)
- Store multiple specs in the App Group store
- Choose a saved spec per widget instance (Edit Widget → Design)

### Milestone 4 — Prompt → WidgetSpec generation + patch edits (DONE)
- Constrained generation contract (guided payloads mapped into `WidgetSpec`)
- Always run normalisation/clamping/repair at the boundary
- Deterministic fallback when the model is unavailable
- Patch edits like:
  - “more minimal”
  - “bigger title”
  - “change accent to teal”
  - “remove image / remove symbol”

### Milestone 5 — Matched sets (Small/Medium/Large) (DONE)
- Optional `matchedSet` that stores per-size variant overrides
- Medium stored as the base; Small/Large can override
- Shared style + typography across the set
- Editor behaviour is driven by the preview size picker (edits apply to the selected size)
- Shared renderer resolves the correct per-family variant automatically

### Milestone 6 — Variables + Shortcuts (DONE)
- Variables (“slots”) referenced by specs using `{{key}}` / `{{key|fallback}}`
- Variables stored in the App Group for app + widget
- Widget resolves variables at render time
- App Intents (Shortcuts) to:
  - set / get / remove variables
  - increment numeric variables
  - set a variable to the current date/time
- Variable changes trigger widget refresh

### Milestone 7 — Sharing / import / export (DONE)
- Export/import designs (validated, versioned exchange JSON)
- Optional embedded images (restored on import)
- Import duplicates designs with new IDs to avoid overwriting

### Milestone 7.5 — About page + template gallery (DONE)
- Add an in-app About page that explains current capabilities
- Starter + Pro template gallery with Small/Medium/Large previews
- One-tap **Add** / **Add & Make Default** actions
- Quick reference: Variables syntax + Shortcuts actions + AI prompt/patch ideas

### Milestone 7.6 — Inspector + revert (DONE)
- Inspector: copy base/resolved/exchange JSON + view image references
- Unsaved changes indicator + revert to last saved

### Milestone 8 — Monetisation (IN PROGRESS)
- Free tier limits (max designs)
- Pro unlock (StoreKit 2) for:
  - matched sets
  - variables
  - unlimited designs
  - (optionally) Action Bar buttons, depending on current gating

### Milestone 9 — Control Widgets (OPTIONAL)
- Add only after the main widget pipeline is stable


## Troubleshooting

### Image not showing in the widget
- Ensure an image was picked and then **Save** was tapped.
- Ensure both targets have the App Group entitlement: `group.com.conornolan.widgetweaver`.
- If the app was reinstalled, previously saved specs may reference image filenames that no longer exist in the App Group container; remove/re-pick the image and save again.
- If re-selecting the same photo seems to do nothing, pick a different photo once, then pick the original again, and save.

### Widget not updating
- Save again (prefer **Save & Make Default** while iterating).
- Ensure the widget instance is set to either:
  - **Default (App)** (recommended while iterating), or
  - the specific saved design being edited
- If Matched set is enabled, ensure edits are being made to the intended size (Small/Medium/Large) via the preview size picker.
- Remove/re-add the widget after significant schema changes.
- Use **Inspector** to confirm what the app thinks is saved (base JSON) and what the widget will resolve for a size (resolved JSON).

### Variables not updating in the widget
- Confirm the spec contains `{{...}}` tokens (for example `{{streak|0}}`).
- Run a Shortcut action (Set/Increment/Set to Now) and verify the key matches (keys are lowercased and whitespace-normalised).
- If a widget instance is configured to a specific saved design, ensure that design is the one using the variable tokens.

### Action Bar buttons not doing anything
- Buttons are only interactive on iOS 17+ and only when tapped on a real widget (Home Screen / StandBy).
- If a button updates a variable, make sure the variable key matches what your text is reading (canonicalised keys).
- If Pro gating is enabled for variable updates, confirm Pro is unlocked when testing button behaviour.
- If the UI updates but the widget text doesn’t, re-check that the widget instance is set to **Default (App)** or the correct design, then force a refresh by re-saving once.

### Import not behaving as expected
- Imports always create new designs (new IDs). If you expected an overwrite, delete the old design manually.
- If an imported design used embedded images but the widget shows “no image”, open the design, re-save it once, then refresh widgets.

### AI shows “Unavailable”
- The app still works (deterministic fallbacks).
- For on-device generation, enable Apple Intelligence in Settings and allow time for the model to become ready.


## Repo notes

- Marketing version / build: `0.9.4 (6)` (from target settings / Info.plist values, not hardcoded in code)
- Widget kind string: `Shared/WidgetWeaverWidgetKinds.swift`
- About page: `WidgetWeaver/WidgetWeaverAboutView.swift`
- Working principle: ship small commits where the app + widget always build and run

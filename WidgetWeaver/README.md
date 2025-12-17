# WidgetWeaver

WidgetWeaver is an iOS 26 app for building WidgetKit widgets from a **typed widget specification** (“WidgetSpec”).

Right now the spec is edited manually in-app. Natural-language → spec generation is planned as a later milestone.

The widget extension renders a selected saved spec from the App Group boundary, with normalisation/clamping and safe fallbacks. This repo is being built milestone-by-milestone with working commits.

---

## Current status (0.9.4 (1))

✅ iOS app target created and runs on a real device  
✅ Widget extension target added and shows in the widget gallery  
✅ Shared `WidgetSpec` tokens (layout + style)  
✅ Shared renderer parity (app previews + widget use the same render path)  
✅ App can edit and save specs into the App Group store  
✅ Multiple saved specs (design library)  
✅ Per-widget instance selection (Edit Widget → choose a saved design)  
✅ SF Symbol component (optional) with placement + size + weight + rendering + tint

Next:
- ⏭ Add v0 components beyond text + symbol (image, etc.)
- ⏭ Prompt → Spec generation (Foundation Models) with validation + repair
- ⏭ “Patch edits” (e.g. “more minimal”) against an existing spec
- ⏭ Matched sets (Small/Medium/Large) + design system tokens
- ⏭ Variables + Shortcuts

---

## Quick start

1. Open `WidgetWeaver.xcodeproj` in Xcode 26+.
2. Ensure both targets have the App Group entitlement:
   - `group.com.conornolan.widgetweaver`
3. Run the app on a real device.
4. Add the “WidgetWeaver” widget to the Home Screen (Small/Medium/Large).
5. In the app, create/edit a design and tap **Save to Widget**.
6. To choose a design per widget instance:
   - Long-press the widget → **Edit Widget** → select a **Design**
7. To show an icon:
   - In the app, fill **Symbol → SF Symbol name** (for example: `sparkles`)

---

## Architecture

### Targets

- **WidgetWeaver** (iOS app)
  - Create/edit/save a `WidgetSpec`
  - In-app previews (Small/Medium/Large)
  - Manage a library of saved designs
- **WidgetWeaverWidget** (Widget Extension)
  - Reads specs from App Group storage
  - Renders Small/Medium/Large
  - Uses per-instance configuration to select a saved design

### Shared boundary

- App Group: `group.com.conornolan.widgetweaver`
- Storage: `UserDefaults(suiteName:)` (JSON-encoded specs) for v0.9.x simplicity
- Safety:
  - Load failures fall back to `WidgetSpec.defaultSpec()`
  - Specs are normalised/clamped before save and after load

---

## WidgetSpec

`WidgetSpec` is the contract between the app and the widget. It’s versioned and designed to be:

- Strictly typed (Codable)
- Easy to validate/repair
- Deterministic to render

### v0 components (current direction)

- Text:
  - `name`, `primaryText`, optional `secondaryText`
- Symbol (optional):
  - SF Symbol name string
  - placement (above/before name)
  - size + weight
  - rendering mode (monochrome / hierarchical / multicolour)
  - tint (accent / primary / secondary)
- Layout tokens:
  - axis / alignment / spacing / line limits
- Style tokens:
  - padding / corner radius / background / accent / typography tokens
- Shared renderer:
  - a single SwiftUI view that both the app previews and the widget render through

---

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

### Milestone 3.5 — Multiple specs + per-widget selection (DONE)
- Store multiple specs in the App Group store
- Choose a saved spec per widget instance (Edit Widget → Design)

### Milestone 3.6 — Symbol component (DONE)
- Add optional `SymbolSpec` to `WidgetSpec`
- Expose symbol controls in the editor
- Render symbols in both previews and widget (shared renderer)

### Milestone 4 — Prompt → WidgetSpec generation (NEXT)
- Define a constrained generation contract (“generate WidgetSpec v0”)
- Always run validation/clamping/repair at the boundary
- Deterministic fallback when model unavailable (templates/rules)
- Add “patch edits” (small diffs) like:
  - “more minimal”
  - “bigger title”
  - “change accent to teal”

### Milestone 5 — Matched sets (Small/Medium/Large) (LATER)
- Introduce a `DesignSystem` token set shared across widget sizes
- Generate coherent sets that reference shared tokens
- “Update the vibe” modifies tokens and updates the whole set

### Milestone 6 — Variables + Shortcuts (LATER)
- Variables (“slots”) referenced by specs
- App Intents to update variables (Shortcuts integration)
- Widget reads values at render time from App Group storage

### Milestone 7 — Sharing / import / export (LATER)
- Export/import specs (validated, versioned)

### Milestone 8 — Monetisation (LATER)
- Free tier limits
- Pro unlocks advanced components, matched sets, variables, unlimited specs

### Milestone 9 — Control Widgets (OPTIONAL)
- Add only after the main widget pipeline is stable

---

## Repo notes

- Marketing version / build: `0.9.4 (1)` (stays fixed until TestFlight starts)
- Widget kind string: `Shared/WidgetWeaverWidgetKinds.swift`
- Working principle:
  - ship small commits where the app + widget always build and run

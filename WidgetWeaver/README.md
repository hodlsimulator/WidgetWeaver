# WidgetWeaver

WidgetWeaver is an iOS 26 app for building WidgetKit widgets from natural language by generating a **typed widget specification** (“WidgetSpec”). The widget extension renders the saved specs reliably, with validation and safe fallbacks.

This repo is being built milestone-by-milestone with working commits.

---

## Current status (v0.9.4)

✅ iOS app target created and runs on a real device  
✅ App icon set  
✅ Widget extension target added  
✅ Widget now renders a saved spec (App Group storage + `WidgetSpecStore`)  
✅ App UI can edit/save a basic spec and trigger widget reloads  

Next:
- ⏭ Formalise WidgetSpec v0 (layout + style tokens)
- ⏭ Manual editor for v0 components
- ⏭ In-app preview parity with widget renderer
- ⏭ Prompt → Spec generation (Foundation Models) with validation + repair

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
- Update widget to load spec from store and render it

### Milestone 3 — Manual editor + preview loop (NEXT)
- Expand WidgetSpec v0 to support:
  - layout (stack/grid)
  - basic components (text/symbol/image)
  - style tokens (typography/spacing/corner/background/accent/contrast rules)
- Add an in-app editor for those fields
- Add an in-app preview that uses the same renderer logic as the widget

### Milestone 4 — Prompt → WidgetSpec generation (NEXT)
- Define a constrained generation contract (“generate WidgetSpec v0”)
- Use structured generation into typed models when available
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
- Optional QR export later

### Milestone 8 — Monetisation (LATER)
- Free tier limits
- Pro unlocks advanced components, matched sets, variables, unlimited specs

### Milestone 9 — Control Widgets (OPTIONAL)
- Add only after the main widget pipeline is stable

---

## Architecture

### Targets
- **WidgetWeaver** (iOS app)
  - Create/edit/save WidgetSpec
  - Preview specs
  - Prompt → spec generation (later)
- **WidgetWeaverWidget** (Widget Extension)
  - Reads the current spec from App Group storage
  - Renders Small/Medium/Large

### Shared boundary
- App Group: `group.com.conornolan.widgetweaver`
- Storage: `UserDefaults(suiteName:)` for v0.9.x simplicity
- Safety:
  - load failures fall back to `WidgetSpec.defaultSpec()`
  - values are normalised/clamped before save and after load

---

## Repo notes

- Versioning:
  - Marketing version: `0.9.4`
  - Build number: tracked via Xcode build settings
  - Widget extension Info.plist references `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` for consistency.
- Working principle:
  - ship small commits where the app + widget always build and run.

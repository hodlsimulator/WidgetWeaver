# WidgetWeaver

WidgetWeaver is a prototype iOS app that turns a typed “widget design spec” into a real WidgetKit widget.

It’s intended as a playground for exploring:

- A simple typed JSON-ish design spec (`WidgetSpec`)
- Deterministic SwiftUI rendering in a WidgetKit extension (`WidgetWeaverSpecView`)
- A lightweight template catalogue (About sheet) for seeding designs
- Pro features (matched sets + variables + interactive buttons)
- Optional on-device AI for spec generation and patch edits

The app and widget extension communicate via an App Group (UserDefaults + shared files) so widgets can render offline.

---

## Featured — Weather

WidgetWeaver includes a built-in **WeatherKit-powered Weather layout template** (`LayoutTemplateToken.weather`):

- Rain-first “next hour” nowcast chart (Dark Sky-ish)
- Hourly strip + daily highs/lows (when data is available)
- Glass container + glow styling
- Adaptive Small / Medium / Large layouts
- Also exposes `__weather_*` **built-in variables** that can be used in any text field (no Pro required)

### Weather setup

1. In the app, open the toolbar menu (`…`) → **Weather**, then choose a location (Current Location or search).
2. Open `…` → **About** and add the **Weather** template (optionally “Add & Make Default”).
3. Add the **WidgetWeaver** widget to your Home Screen.

Notes:

- Widgets refresh on a schedule, but **WidgetKit may throttle updates**.
- Use **Weather → Update now** to refresh the cached snapshot used by the widget.

---

## Current status (0.9.4 (9))

### App
- ✅ Local editor for `WidgetSpec`
- ✅ Library of saved specs + Default selection
- ✅ Free tier: up to `WidgetWeaverEntitlements.maxFreeDesigns` saved designs
- ✅ Pro: unlimited saved designs
- ✅ Pro: matched sets (S/M/L) share style tokens
- ✅ Share/export/import JSON (optionally embedding images)
- ✅ Optional on-device AI (generate + patch)
- ✅ Weather screen (location + units + cached snapshot + attribution)

### Widget
- ✅ One WidgetKit widget (“WidgetWeaver”) which reads the default spec from App Group
- ✅ Per-widget configuration: Default (App) or pick a spec
- ✅ iOS 17+: optional interactive action bar (2 buttons) that runs App Intents and updates Pro variables
- ✅ Built-in Weather template (`.weather`) reads cached WeatherKit snapshot from the App Group
- ✅ App Group: user defaults + shared image files

### Layout + style
- ✅ Layout templates: Classic / Hero / Poster / Weather
- ✅ Axis: vertical/horizontal; alignment; spacing; line limits
- ✅ Accent bar toggle
- ✅ Style tokens: padding, corner radius, background token, overlay, glow, accent
- ✅ Optional SF Symbol spec (name/size/weight/rendering/tint/placement)
- ✅ Optional banner image (stored in App Group container)

### Components
- ✅ Built-in typed models: `WidgetSpec`, `LayoutSpec`, `StyleSpec`, `SymbolSpec`, `ImageSpec`
- ✅ Rendering path: `WidgetWeaverSpecView` (SwiftUI)
- ✅ Variable template engine: `WidgetWeaverVariableTemplate` (stored vars are Pro-only)
- ✅ WeatherKit integration: `WidgetWeaverWeatherEngine`, `WidgetWeaverWeatherStore`, Weather template renderer
- ✅ App Group store: `WidgetSpecStore`, `WidgetWeaverVariableStore`, `AppGroup`

---

## Quick start

- Open the Xcode project
- Set a Team + bundle identifiers for app + widget targets
- Run the app
- Add the **WidgetWeaver** widget to the Home Screen
- Use the toolbar menu → **About** to add templates
- If using Weather: toolbar menu → **Weather** to pick a location and cache a snapshot
- For Pro features: unlock Pro, then use **Variables** + **Actions** in the editor

---

## Editor features

### Layout templates

- **Classic**: stacked header + text, optional symbol, optional accent bar
- **Hero**: text left, big symbol right (when present), optional accent bar
- **Poster**: photo-first with a gradient overlay for text
- **Weather**: WeatherKit-powered, rain-first nowcast layout with glass panels and adaptive S/M/L layouts

The layout is controlled via `LayoutSpec` (template + axis + alignment + spacing + line limits).

### Photo theme extraction

The app can extract a simple “image theme” from a chosen photo (to help pick an accent colour/background), but the photo itself is always chosen manually.

### Remix

Remix generates several deterministic variants of a design by perturbing layout/style tokens. It’s intended as a fast way to explore alternatives without losing the original.

### Action bar (Pro)

On iOS 17+, widgets can show a compact action bar with up to 2 buttons. Buttons run App Intents and update Pro variables in the App Group so widgets can refresh without opening the app.

### About page + templates

The About sheet includes a built-in template catalogue.

- **Starter templates** are free.
- **Pro templates** can include matched sets, variables, and interactive buttons.
- Templates are designed to be offline-friendly (shared App Group storage).
- Weather is built-in and uses a cached snapshot (widgets do not need to fetch directly).

### Sharing

Designs can be exported as JSON, optionally embedding images. Imports duplicate designs with new IDs to avoid overwriting existing ones.

### Inspector

Inspector shows the current spec JSON and allows quick checks while tuning the renderer.

### Variables + Shortcuts

WidgetWeaver supports template variables in text fields:

- `{{key}}`
- `{{key|fallback}}`
- `{{amount|0|number:0}}`
- `{{last_done|Never|relative}}`
- Inline maths: `{{=done/total*100|0|number:0}}`

#### Built-in keys (available to everyone)

- `__now`, `__now_unix`
- `__today`
- `__time`
- `__weekday`

#### Weather built-in keys (available to everyone)

Once a Weather location is set (and a snapshot is cached), these are available in any text field:

- `__weather_location`
- `__weather_condition`
- `__weather_symbol`
- `__weather_updated_iso`
- `__weather_temp`, `__weather_temp_c`, `__weather_temp_f`, `__weather_feels`
- `__weather_high`, `__weather_low`
- `__weather_precip`, `__weather_humidity`

Example:

- `Weather: {{__weather_temp|--}}° • {{__weather_condition|Updating…}}`

#### Stored variables (Pro)

The shared variable store is Pro-only and can be updated in-app or via Shortcuts actions:

- Set WidgetWeaver Variable
- Get WidgetWeaver Variable
- Remove WidgetWeaver Variable
- Increment WidgetWeaver Variable
- Set WidgetWeaver Variable to Now

### AI (Optional)

AI features are designed to run on-device and generate or patch the design spec. Images are never generated.

---

## Architecture notes

- **App Group** is the single source of truth for widgets:
  - Specs: JSON in App Group `UserDefaults`
  - Images: files in App Group container
  - Variables (Pro): JSON dictionary in App Group `UserDefaults`
  - Weather: location + cached snapshot + attribution in App Group `UserDefaults`
- The widget reads the selected spec and renders it via `WidgetWeaverSpecView`.

---

## Milestones (high level)

- Typed spec + deterministic renderer
- Multi-design library + per-widget configuration
- Pro: matched sets + variables + actions
- Weather template + WeatherKit caching
- Optional on-device AI

---

## Troubleshooting

- **Weather shows “Set a location in the app”**
  - Open toolbar menu (`…`) → **Weather**
  - Choose a location, then tap **Update now**

- **Weather isn’t updating**
  - Weather updates are cached; WidgetKit may throttle refreshes
  - Use **Weather → Update now**
  - Check Location permissions if using Current Location

- **Widgets don’t reflect edits**
  - Make sure the design is saved
  - Use toolbar menu → Refresh Widgets (or remove/re-add the widget)

- **Images don’t appear**
  - Ensure the banner image is saved to the App Group container (the app handles this)
  - Try Clean Up Unused Images then re-add the image

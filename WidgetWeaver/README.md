# WidgetWeaver

WidgetWeaver is an **iOS 26-only** prototype app that turns a typed “widget design spec” into real WidgetKit widgets.

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
- Exposes `__weather_*` **built-in variables** usable in any text field (no Pro required)
- Includes a Lock Screen companion widget: **Rain (WidgetWeaver)** (accessory rectangular)

### Weather setup

1. In the app, open the toolbar menu (`…`) → **Weather**, then choose a location (Current Location or search).
2. Open `…` → **About** and add the **Weather** template (optionally “Add & Make Default”).
3. Add widgets:
   - Home Screen: **WidgetWeaver** (pick a Weather design), and/or
   - Lock Screen: **Rain (WidgetWeaver)**

Notes:

- Widgets refresh on a schedule, but **WidgetKit may throttle updates**.
- Use **Weather → Update now** to refresh the cached snapshot used by widgets.

---

## Featured — Next Up (Calendar)

WidgetWeaver includes a built-in **Next Up (Calendar) layout template** (`LayoutTemplateToken.nextUpCalendar`):

- Shows your next calendar event with a live countdown
- Medium/Large can also show a “Then” line (second upcoming event)
- Uses a cached calendar snapshot stored in the App Group (offline-friendly)
- Looks ahead until it finds upcoming events (not limited to “next 24 hours”)
- Includes a Lock Screen companion widget: **Next Up (WidgetWeaver)** (inline / circular / rectangular)

### Next Up (Calendar) setup

1. In the app, open `…` → **About** and add the **Next Up (Calendar)** template.
2. When prompted, allow Calendar access (the app will refresh the cached snapshot after permission is granted).
3. Add widgets:
   - Home Screen: **WidgetWeaver** (pick a Next Up design), and/or
   - Lock Screen: **Next Up (WidgetWeaver)**

Notes:

- Calendar widgets render from a cache; if the widget looks stale, open the app and use `…` → **Refresh Widgets**.

---

## Featured — Steps (Pedometer)

WidgetWeaver includes a built-in **HealthKit-powered Steps snapshot + Lock Screen widget**:

- Shows today’s step count
- Optional daily goal (the circular widget shows progress)
- Offline-friendly: widgets render from a cached snapshot stored in the App Group
- Includes a Lock Screen companion widget: **Steps (WidgetWeaver)** (inline / circular / rectangular)

### Steps setup

1. In the app, open `…` → **Steps**.
2. Tap **Enable Steps Access** (Health permission prompt).
3. Tap **Update now** to cache today’s steps for widgets.
4. Add the Lock Screen widget: **Steps (WidgetWeaver)**.

Notes:

- Widgets cannot request Health permission; access must be granted in the app (or in the Health app).
- If you see **0 steps**, that can be normal (early in the day) or it can mean no step samples are being recorded.
  - Check **Settings → Privacy & Security → Motion & Fitness → Fitness Tracking** is enabled.
- If you see **Denied**, enable Step Count for WidgetWeaver in the Health app (profile → Apps → WidgetWeaver).

---

## Current status (0.9.4 (13))

### App
- ✅ Local editor for `WidgetSpec`
- ✅ Library of saved specs + Default selection
- ✅ Free tier: up to `WidgetWeaverEntitlements.maxFreeDesigns` saved designs
- ✅ Pro: unlimited saved designs
- ✅ Pro: matched sets (S/M/L) share style tokens
- ✅ Share/export/import JSON (optionally embedding images)
- ✅ Optional on-device AI (generate + patch)
- ✅ Weather screen (location + units + cached snapshot + attribution)
- ✅ Calendar snapshot engine for Next Up (permission + cached “next/second” events)
- ✅ Steps screen (HealthKit permission + cached step snapshot + daily goal)
- ✅ Inspector sheet (resolved spec + JSON + quick checks)
- ✅ In-app preview dock (preview vs live, Small/Medium/Large)

### Widgets
- ✅ **Home Screen widget (“WidgetWeaver”)** renders a saved design (Small / Medium / Large)
- ✅ **Lock Screen widget (“Rain (WidgetWeaver)”)** next hour precipitation + temperature + nowcast (accessory rectangular)
- ✅ **Lock Screen widget (“Next Up (WidgetWeaver)”)** next calendar event + countdown (inline / circular / rectangular)
- ✅ **Lock Screen widget (“Steps (WidgetWeaver)”)** today’s step count + optional goal gauge (inline / circular / rectangular)
- ✅ Per-widget configuration (Home Screen widget): Default (App) or pick a specific saved design
- ✅ Optional interactive action bar (Pro) with up to 2 buttons that run App Intents and update Pro variables (no Shortcuts setup required)
- ✅ Weather + Calendar templates render from cached snapshots stored in the App Group
- ✅ Steps widget renders from a cached step snapshot stored in the App Group
- ✅ Time-sensitive designs can attempt minute-level timelines (still subject to WidgetKit throttling)

### Layout + style
- ✅ Layout templates: Classic / Hero / Poster / Weather / Next Up (Calendar)
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
- ✅ Calendar integration: `WidgetWeaverCalendarEngine`, `WidgetWeaverCalendarStore`, Next Up template renderer
- ✅ HealthKit steps integration: `WidgetWeaverStepsEngine`, `WidgetWeaverStepsStore`, Steps settings + Lock Screen widget
- ✅ App Group store: `WidgetSpecStore`, `WidgetWeaverVariableStore`, `AppGroup`

---

## Quick start

- Open the Xcode project
- Set a Team + bundle identifiers for app + widget targets
- Configure **App Groups**:
  - Ensure both targets have the App Group capability enabled
  - The default identifier is `group.com.conornolan.widgetweaver` (see `Shared/AppGroup.swift`)
  - If changing it, update:
    - `Shared/AppGroup.swift` (`AppGroup.identifier`)
    - `WidgetWeaver/WidgetWeaver.entitlements`
    - `WidgetWeaverWidgetExtension.entitlements`
- Run the app
- Use the toolbar menu → **About** to add templates
- If using Weather: toolbar menu → **Weather** to pick a location and cache a snapshot
- If using Next Up (Calendar): add the template from **About**, then grant Calendar access when prompted
- If using Steps:
  - Add the **HealthKit** capability to both targets (app + widget extension)
  - Add `NSHealthShareUsageDescription` to the app Info.plist
  - In the app: `…` → **Steps** → enable access → **Update now**
- Add widgets:
  - Home Screen: **WidgetWeaver**
  - Lock Screen: **Rain (WidgetWeaver)** and/or **Next Up (WidgetWeaver)** and/or **Steps (WidgetWeaver)**
- For Pro features: unlock Pro, then use **Variables** + **Actions** in the editor

---

## Editor features

### Layout templates

- **Classic**: stacked header + text, optional symbol, optional accent bar
- **Hero**: text left, big symbol right (when present), optional accent bar
- **Poster**: photo-first with a gradient overlay for text
- **Weather**: WeatherKit-powered, rain-first nowcast layout with glass panels and adaptive S/M/L layouts
- **Next Up (Calendar)**: next event + countdown (optionally “Then” on Medium/Large)

The layout is controlled via `LayoutSpec` (template + axis + alignment + spacing + line limits).

### Preview dock

The editor includes a collapsible preview dock:

- Switch size (Small / Medium / Large)
- Switch mode (Preview vs Live) to mimic widget rendering

### Photo theme extraction

The app can extract a simple “image theme” from a chosen photo (to help pick an accent colour/background), but the photo itself is always chosen manually.

### Remix

Remix generates several deterministic variants of a design by perturbing layout/style tokens. It’s intended as a fast way to explore alternatives without losing the original.

### Interactive actions (Pro)

Designs can include an action bar with up to 2 buttons:

- Buttons run App Intents directly from the widget
- Designed for quick “tap to update” workflows (increment a counter, set a timestamp)
- No Shortcuts app setup required for end users

### About page + templates

The About sheet includes a built-in template catalogue.

- **Starter templates** are free.
- **Pro templates** can include matched sets, variables, and interactive buttons.
- Templates are designed to be offline-friendly (shared App Group storage).
- Weather and Next Up (Calendar) use cached snapshots (widgets do not fetch directly).

### Sharing

Designs can be exported as JSON, optionally embedding images. Imports duplicate designs with new IDs to avoid overwriting existing ones.

### Inspector

Inspector shows the current spec JSON and allows quick checks while tuning the renderer.

### Variables + App Intents

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

- `__weather_temp`, `__weather_temp_c`, `__weather_temp_f`
- `__weather_feels`, `__weather_feels_c`, `__weather_feels_f` (when available)
- `__weather_high`, `__weather_low` (when available)

- `__weather_precip`, `__weather_precip_fraction` (when available)
- `__weather_humidity`, `__weather_humidity_fraction` (when available)

When a location is set but a snapshot hasn’t been cached yet, these can still be present:

- `__weather_lat`
- `__weather_lon`

Example:

- `Weather: {{__weather_temp|--}}° • {{__weather_condition|Updating…}}`

#### Stored variables (Pro)

The shared variable store is Pro-only and can be updated in-app or via widget buttons (App Intents).

---

## AI (Optional)

AI features are designed to run on-device to generate or patch the design spec. Images are never generated.

---

## Architecture notes

- **App Group** is the single source of truth for widgets:
  - Specs: JSON in App Group `UserDefaults`
  - Images: files in App Group container
  - Variables (Pro): JSON dictionary in App Group `UserDefaults`
  - Weather: location + cached snapshot + attribution in App Group `UserDefaults`
  - Calendar: cached “next/second event” snapshot in App Group `UserDefaults`
  - Steps: cached “today steps” snapshot + goal in App Group `UserDefaults`
- Widgets render using `WidgetWeaverSpecView` (for Home Screen designs) or lightweight dedicated views (for Lock Screen widgets).

---

## Milestones (high level)

- Typed spec + deterministic renderer
- Multi-design library + per-widget configuration
- Pro: matched sets + variables + actions
- Weather template + WeatherKit caching (+ Lock Screen Rain widget)
- Next Up (Calendar) template + calendar snapshot caching (+ Lock Screen Next Up widget)
- Steps snapshot + HealthKit permission flow (+ Lock Screen Steps widget)
- Optional on-device AI

---

## Troubleshooting

- **Weather shows “Set a location”**
  - Open toolbar menu (`…`) → **Weather**
  - Choose a location, then tap **Update now**

- **Weather isn’t updating**
  - Weather updates are cached; WidgetKit may throttle refreshes
  - Use **Weather → Update now**
  - Check Location permissions if using Current Location

- **Next Up shows “Calendar access off”**
  - Open the app → `…` → **About** → add **Next Up (Calendar)** (or re-add it)
  - Grant Calendar access when prompted (or enable it in Settings)

- **Next Up shows “No upcoming events”**
  - Confirm there’s an event ahead of the current time
  - Open the app and use `…` → **Refresh Widgets** to force a widget timeline reload

- **Steps shows “Open app” / “No cached steps yet”**
  - Open the app → `…` → **Steps**
  - Enable Health access, then tap **Update now**

- **Steps shows “Denied”**
  - Enable Step Count for WidgetWeaver in the Health app (profile → Apps → WidgetWeaver)
  - Return to WidgetWeaver → **Steps** → **Refresh** / **Update now**

- **Steps shows 0**
  - This can be normal (especially early in the day)
  - If you expect steps but always get 0, check **Settings → Privacy & Security → Motion & Fitness → Fitness Tracking**

- **Widgets don’t reflect edits**
  - Make sure the design is saved
  - Use toolbar menu → **Refresh Widgets** (or remove/re-add the widget)

- **Images don’t appear**
  - Ensure the banner image is saved to the App Group container (the app handles this)
  - Try **Clean Up Unused Images** then re-add the image

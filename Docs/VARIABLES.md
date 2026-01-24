# Variables

Last updated: 2026-01-24

WidgetWeaver supports lightweight variable templates inside text fields so a widget can display dynamic values (time, weather, steps, activity) and, if Pro is unlocked, user-defined variables stored in the App Group.

This document describes the template syntax, the built-in keys, and the supported filters and maths.

## Where variables are used

- Text fields in widget specs can contain templates like `{{__time}}` or `{{__weather_temp|--}}°`.
- Rendering uses an explicit “now”:
  - In the widget extension, “now” comes from the WidgetKit timeline entry date.
  - In the app, previews resolve using the same render clock so “Home Screen correctness” remains the reference.

## Template syntax

Basic replacement:

- `{{key}}` resolves to the value for `key`.
- `{{key|fallback}}` uses `fallback` when the key is missing or resolves to an empty string.

Filters:

- Filters can be applied after the base key and fallback.
- Use the explicit filter delimiter `||` when the fallback might contain `|` characters.

Examples:

- `{{key|fallback||upper}}`
- `{{amount|0|number:0}}`
- `{{progress|0|bar:10}}`
- `{{__now||date:HH:mm}}`

Key normalisation:

- Keys are canonicalised by trimming whitespace, lowercasing, and collapsing internal whitespace to single spaces.
- `last_done`, `Last Done`, and ` last   done ` resolve to the same key.

## Pro gating

Custom variables (stored variables) are Pro-gated.

- When Pro is not unlocked, custom variables do not resolve.
- Built-in keys (time/weather/steps/activity) are still available without Pro.

Note: Weather, Steps, and Activity variables intentionally override any existing keys to keep the widget truthful.

## Built-in keys

### Time

These are always available:

- `__now` — ISO8601 UTC (internet date time, with fractional seconds).
- `__now_unix` — Unix seconds since 1970 (integer string).
- `__today` — `yyyy-MM-dd` (local calendar day).
- `__time` — `HH:mm` (local time).
- `__weekday` — `EEE` (Mon/Tue/…).

### Weather

Weather keys are prefixed `__weather_` and come from `Shared/WidgetWeaverWeatherStore.swift`.

If a cached Weather snapshot exists, keys include:

- `__weather_location`
- `__weather_condition`
- `__weather_symbol`
- `__weather_updated_iso`
- `__weather_temp`, `__weather_temp_c`, `__weather_temp_f`
- `__weather_feels`, `__weather_feels_c`, `__weather_feels_f` (only when apparent temperature is available)
- `__weather_high` (only when the daily high is available)
- `__weather_low` (only when the daily low is available)
- `__weather_precip`, `__weather_precip_fraction` (only when precipitation chance is available)
- `__weather_humidity`, `__weather_humidity_fraction` (only when humidity is available)
- `__weather_nowcast`
- `__weather_nowcast_secondary` (only when available)
- `__weather_rain_start_min` (only when available)
- `__weather_rain_end_min` (only when available)
- `__weather_rain_start` (only when available)
- `__weather_rain_peak_intensity_mmh`
- `__weather_rain_peak_chance`
- `__weather_rain_peak_chance_fraction`

If no snapshot exists but a saved location exists, Weather resolves a minimal set:

- `__weather_location`
- `__weather_lat`
- `__weather_lon`
- `__weather_updated_iso`

### Steps

Steps keys are prefixed `__steps_` and come from `Shared/WidgetWeaverStepsStore.swift`.

Keys include:

- `__steps_goal_weekday`
- `__steps_goal_weekend`
- `__steps_goal_today`
- `__steps_streak_rule`
- `__steps_access`
- `__steps_today` (only when a “today” snapshot exists)
- `__steps_updated_iso` (only when a “today” snapshot exists)
- `__steps_today_fraction` (only when a “today” snapshot exists)
- `__steps_today_percent` (only when a “today” snapshot exists)
- `__steps_goal_hit_today` (only when a “today” snapshot exists)
- `__steps_streak` (only when history exists)
- `__steps_avg_7`, `__steps_avg_7_exact` (only when history exists)
- `__steps_avg_30`, `__steps_avg_30_exact` (only when history exists)
- `__steps_best_day` (only when history exists and a “best day” exists)
- `__steps_best_day_date_iso` (only when history exists and a “best day” exists)
- `__steps_best_day_date` (only when history exists and a “best day” exists)

### Activity

Activity keys are prefixed `__activity_` and come from `Shared/WidgetWeaverActivityStore` (currently implemented alongside Steps in `Shared/WidgetWeaverSteps.swift`).

Keys include:

- `__activity_access`
- `__activity_updated_iso` (only when a “today” snapshot exists)
- `__activity_steps_today` (only when available)
- `__activity_flights_today` (only when available)
- `__activity_distance_m`, `__activity_distance_m_exact` (only when available)
- `__activity_distance_km`, `__activity_distance_km_exact` (only when available)
- `__activity_active_energy_kcal`, `__activity_active_energy_kcal_exact` (only when available)

## Filters

Filters are applied left-to-right. Unsupported filters are ignored (the value passes through unchanged).

Text filters:

- `upper` — uppercases the value.
- `lower` — lowercases the value.
- `title` — capitalises words.
- `trim` — trims leading/trailing whitespace.
- `prefix:TEXT` — prepends `TEXT`.
- `suffix:TEXT` — appends `TEXT`.
- `pad:N` — left-pads with zeroes to length `N`.

Numeric formatting:

- `number` or `number:N` — formats as a locale-aware decimal number, with optional fixed decimals.
- `percent` or `percent:N` — formats as a percentage:
  - values in 0–1 are treated as fractions (0.42 → 42%)
  - values greater than 1 are treated as already-percent (42 → 42%)
- `currency` or `currency:CODE` — formats as a currency value (optional currency code).

Numeric transforms:

- `round` or `round:N`
- `floor`
- `ceil`
- `abs`
- `clamp:MIN:MAX`

Date/time:

- `date` or `date:FORMAT` — formats a date/time value.
  - Without a format string, it uses a medium date style.
  - With a format string, it uses `DateFormatter` patterns (for example `HH:mm`, `EEE`, `yyyy-MM-dd`).
- `relative` — returns a localised relative string (for example “2 hours ago”).
- `daysuntil`, `hoursuntil`, `minutesuntil` — ceiling of the time until a target date.
- `sincedays`, `sincehours`, `sinceminutes` — ceiling of the time since a target date.

Pluralisation:

- `plural:SINGULAR:PLURAL` — chooses based on the numeric value (absolute value equals 1 uses singular).

Progress bar:

- `bar:WIDTH` — renders a bar using `█`/`░`.
  - values in 0–1 are treated as fractions
  - values greater than 1 are treated as percentages (75 → 0.75)

## Date parsing used by date/relative filters

When a filter needs a date, the engine accepts:

- Special values: `now`, `today`, `tomorrow`, `yesterday`
- Numeric timestamps:
  - Unix seconds (`1735689600`)
  - Unix milliseconds (`1735689600000`)
- ISO8601 strings (with or without fractional seconds)
- Common local formats:
  - `yyyy-MM-dd`
  - `yyyy-MM-dd HH:mm`
  - `yyyy-MM-dd HH:mm:ss`
  - `yyyy/MM/dd`
  - `yyyy/MM/dd HH:mm`
  - `yyyy/MM/dd HH:mm:ss`
- `HH:mm` (interpreted as “today at HH:mm” in the local time zone)

## Inline maths

A token that begins with `=` is evaluated as a numeric expression.

Examples:

- `{{=streak+1|0}}`
- `{{=done/total*100|0|number:0}}`
- `{{=min(steps_today, steps_goal_today)|0}}`

Supported operators:

- `+`, `-`, `*`, `/`, `%`, `^` (power)
- parentheses `(` `)`

Supported constants:

- `pi`
- `e`

Supported functions:

- `min(a, b, ...)`
- `max(a, b, ...)`
- `clamp(x, lo, hi)`
- `abs(x)`
- `floor(x)`
- `ceil(x)`
- `round(x)`
- `pow(a, b)`
- `sqrt(x)`
- `log(x)` (natural log; non-positive inputs return 0)
- `exp(x)`
- `var(KEY)` — reads a variable as a number.
  - `var("key with spaces")` works via a quoted string.
  - `var(key_name)` works via an identifier (underscores map to spaces).
- `now()` — returns Unix seconds for the current render “now”.

Identifiers in maths expressions resolve as variable keys (underscores map to spaces). Missing or non-numeric values resolve as 0.

## Intents and widget actions

### Set variable

- App intent: `WidgetWeaverSetVariableIntent` (Pro-gated)
- Removes/updates a stored variable value in the App Group.

### Set variable to Now

- App intent: `WidgetWeaverSetVariableToNowIntent` (Pro-gated)
- Writes a “now” value to a stored variable, with a chosen format:

  - ISO8601 (UTC)
  - Unix seconds
  - Unix milliseconds
  - Date only (`yyyy-MM-dd`)
  - Time only (`HH:mm`)

Unix milliseconds writes an integer string (milliseconds since 1970). This is intended to pair cleanly with `date`, `relative`, and `since*` filters (the date parser automatically treats large numeric values as milliseconds).

Relevant files:

- Template engine: `Shared/WidgetSpec+Utilities.swift`
- Render-time resolution with explicit now: `Shared/WidgetSpec+VariableResolutionNow.swift`
- App intents: `WidgetWeaver/WidgetWeaverVariableIntents.swift`
- Widget extension intents: `WidgetWeaverWidget/WidgetWeaverWidgetVariableIntents.swift`
- Action bar mapping: `Shared/WidgetWeaverSpecView+Actions.swift`
- Built-in keys browser: `WidgetWeaver/WidgetWeaverBuiltInKeysView.swift`

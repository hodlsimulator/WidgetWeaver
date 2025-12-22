//
//  WidgetWeaverWeather.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import Foundation
import CoreLocation

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(WeatherKit)
import WeatherKit
#endif

// MARK: - Preferences

public enum WidgetWeaverWeatherUnitPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case celsius
    case fahrenheit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }
}

// MARK: - Location

public struct WidgetWeaverWeatherLocation: Codable, Hashable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var updatedAt: Date

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        updatedAt: Date = Date()
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
    }

    public var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    public var latitudeString: String { String(format: "%.4f", latitude) }
    public var longitudeString: String { String(format: "%.4f", longitude) }
}

// MARK: - Snapshot models

public struct WidgetWeaverWeatherHourlyPoint: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var temperatureC: Double
    public var symbolName: String
    public var precipitationChance01: Double?
    /// Precipitation intensity in **mm/hour**.
    public var precipitationIntensityMMPerHour: Double?

    public init(
        date: Date,
        temperatureC: Double,
        symbolName: String,
        precipitationChance01: Double?,
        precipitationIntensityMMPerHour: Double? = nil
    ) {
        self.date = date
        self.temperatureC = temperatureC
        self.symbolName = symbolName
        self.precipitationChance01 = precipitationChance01
        self.precipitationIntensityMMPerHour = precipitationIntensityMMPerHour
    }
}

public struct WidgetWeaverWeatherDailyPoint: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var highTemperatureC: Double?
    public var lowTemperatureC: Double?
    public var symbolName: String
    public var precipitationChance01: Double?

    public init(
        date: Date,
        highTemperatureC: Double?,
        lowTemperatureC: Double?,
        symbolName: String,
        precipitationChance01: Double?
    ) {
        self.date = date
        self.highTemperatureC = highTemperatureC
        self.lowTemperatureC = lowTemperatureC
        self.symbolName = symbolName
        self.precipitationChance01 = precipitationChance01
    }
}

public struct WidgetWeaverWeatherMinutePoint: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var precipitationChance01: Double?
    /// Precipitation intensity in **mm/hour**.
    public var precipitationIntensityMMPerHour: Double?

    public init(
        date: Date,
        precipitationChance01: Double?,
        precipitationIntensityMMPerHour: Double?
    ) {
        self.date = date
        self.precipitationChance01 = precipitationChance01
        self.precipitationIntensityMMPerHour = precipitationIntensityMMPerHour
    }
}

public struct WidgetWeaverWeatherSnapshot: Codable, Hashable, Sendable {
    public var fetchedAt: Date
    public var locationName: String
    public var latitude: Double
    public var longitude: Double
    public var isDaylight: Bool
    public var conditionDescription: String
    public var symbolName: String
    public var temperatureC: Double
    public var apparentTemperatureC: Double?
    public var precipitationChance01: Double?
    public var humidity01: Double?
    public var highTemperatureC: Double?
    public var lowTemperatureC: Double?
    /// Minute-by-minute precipitation points for the next ~hour when available.
    public var minute: [WidgetWeaverWeatherMinutePoint]?
    public var hourly: [WidgetWeaverWeatherHourlyPoint]
    public var daily: [WidgetWeaverWeatherDailyPoint]

    public init(
        fetchedAt: Date,
        locationName: String,
        latitude: Double,
        longitude: Double,
        isDaylight: Bool,
        conditionDescription: String,
        symbolName: String,
        temperatureC: Double,
        apparentTemperatureC: Double?,
        precipitationChance01: Double?,
        humidity01: Double?,
        highTemperatureC: Double?,
        lowTemperatureC: Double?,
        minute: [WidgetWeaverWeatherMinutePoint]? = nil,
        hourly: [WidgetWeaverWeatherHourlyPoint],
        daily: [WidgetWeaverWeatherDailyPoint]
    ) {
        self.fetchedAt = fetchedAt
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.isDaylight = isDaylight
        self.conditionDescription = conditionDescription
        self.symbolName = symbolName
        self.temperatureC = temperatureC
        self.apparentTemperatureC = apparentTemperatureC
        self.precipitationChance01 = precipitationChance01
        self.humidity01 = humidity01
        self.highTemperatureC = highTemperatureC
        self.lowTemperatureC = lowTemperatureC
        self.minute = minute
        self.hourly = hourly
        self.daily = daily
    }

    public static func sampleSunny(now: Date = Date()) -> WidgetWeaverWeatherSnapshot {
        let cal = Calendar.current
        let base = cal.dateInterval(of: .hour, for: now)?.start ?? now

        let minuteBase = cal.dateInterval(of: .minute, for: now)?.start ?? now

        let minute: [WidgetWeaverWeatherMinutePoint] = (0..<60).compactMap { i in
            guard let d = cal.date(byAdding: .minute, value: i, to: minuteBase) else { return nil }

            // A simple "rain comes and goes" pattern so previews show the nowcast chart.
            let intensity: Double
            let chance: Double

            switch i {
            case 0..<10:
                intensity = 0.0
                chance = 0.08
            case 10..<20:
                intensity = 0.25
                chance = 0.35
            case 20..<35:
                intensity = 0.90
                chance = 0.75
            case 35..<45:
                intensity = 1.60
                chance = 0.85
            case 45..<55:
                intensity = 0.55
                chance = 0.55
            default:
                intensity = 0.0
                chance = 0.15
            }

            return WidgetWeaverWeatherMinutePoint(
                date: d,
                precipitationChance01: chance,
                precipitationIntensityMMPerHour: intensity
            )
        }

        let hourly: [WidgetWeaverWeatherHourlyPoint] = (0..<8).compactMap { i in
            guard let d = cal.date(byAdding: .hour, value: i, to: base) else { return nil }
            return WidgetWeaverWeatherHourlyPoint(
                date: d,
                temperatureC: 18.0 + Double(i) * 0.6,
                symbolName: i < 3 ? "sun.max.fill" : "cloud.sun.fill",
                precipitationChance01: i < 6 ? 0.05 : 0.15
            )
        }

        let daily: [WidgetWeaverWeatherDailyPoint] = (0..<6).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: base) else { return nil }
            let sym = (i == 2) ? "cloud.rain.fill" : ((i == 4) ? "cloud.bolt.rain.fill" : "sun.max.fill")
            return WidgetWeaverWeatherDailyPoint(
                date: d,
                highTemperatureC: 23.0 + Double(i) * 0.5,
                lowTemperatureC: 14.0 + Double(i) * 0.3,
                symbolName: sym,
                precipitationChance01: (i == 2) ? 0.45 : ((i == 4) ? 0.35 : 0.10)
            )
        }

        return WidgetWeaverWeatherSnapshot(
            fetchedAt: now,
            locationName: "Weather",
            latitude: 0,
            longitude: 0,
            isDaylight: true,
            conditionDescription: "Mostly Sunny",
            symbolName: "sun.max.fill",
            temperatureC: 20.0,
            apparentTemperatureC: 21.0,
            precipitationChance01: 0.08,
            humidity01: 0.55,
            highTemperatureC: 23.0,
            lowTemperatureC: 14.0,
            minute: minute,
            hourly: hourly,
            daily: daily
        )
    }
}

// MARK: - Attribution

public struct WidgetWeaverWeatherAttribution: Codable, Hashable, Sendable {
    public var legalPageURLString: String?

    public init(legalPageURLString: String?) {
        self.legalPageURLString = legalPageURLString
    }

    public var legalPageURL: URL? {
        guard let s = legalPageURLString else { return nil }
        return URL(string: s)
    }
}

// MARK: - Store

public final class WidgetWeaverWeatherStore: @unchecked Sendable {
    public static let shared = WidgetWeaverWeatherStore()

    public enum Keys {
        public static let locationData = "widgetweaver.weather.location.v1"
        public static let snapshotData = "widgetweaver.weather.snapshot.v1"
        public static let unitPreference = "widgetweaver.weather.unitPreference.v1"
        public static let attributionData = "widgetweaver.weather.attribution.v1"
        public static let lastError = "widgetweaver.weather.lastError.v1"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    @inline(__always)
    private func sync() {
        defaults.synchronize()
        UserDefaults.standard.synchronize()
    }

    private init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Location

    public func loadLocation() -> WidgetWeaverWeatherLocation? {
        sync()

        if let data = defaults.data(forKey: Keys.locationData),
           let loc = try? decoder.decode(WidgetWeaverWeatherLocation.self, from: data) {
            return loc
        }

        // Fallback for any legacy/misconfigured container situations.
        if let data = UserDefaults.standard.data(forKey: Keys.locationData),
           let loc = try? decoder.decode(WidgetWeaverWeatherLocation.self, from: data) {
            // Heal: copy into the App Group store so the widget and app converge.
            if let healed = try? encoder.encode(loc) {
                defaults.set(healed, forKey: Keys.locationData)
            }
            sync()
            return loc
        }

        return nil
    }

    public func saveLocation(_ location: WidgetWeaverWeatherLocation?) {
        if let location, let data = try? encoder.encode(location) {
            defaults.set(data, forKey: Keys.locationData)
            UserDefaults.standard.set(data, forKey: Keys.locationData)
        } else {
            defaults.removeObject(forKey: Keys.locationData)
            UserDefaults.standard.removeObject(forKey: Keys.locationData)
        }
        sync()
    }

    public func preferredCLLocation() -> CLLocation? {
        loadLocation()?.clLocation
    }

    // MARK: Snapshot

    public func loadSnapshot() -> WidgetWeaverWeatherSnapshot? {
        sync()

        if let data = defaults.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverWeatherSnapshot.self, from: data) {
            return snap
        }

        if let data = UserDefaults.standard.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverWeatherSnapshot.self, from: data) {
            if let healed = try? encoder.encode(snap) {
                defaults.set(healed, forKey: Keys.snapshotData)
            }
            sync()
            return snap
        }

        return nil
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverWeatherSnapshot?) {
        if let snapshot, let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Keys.snapshotData)
            UserDefaults.standard.set(data, forKey: Keys.snapshotData)
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
            UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        }
        sync()
    }

    public func clearSnapshot() {
        defaults.removeObject(forKey: Keys.snapshotData)
        UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        sync()
    }

    // MARK: Units

    public func loadUnitPreference() -> WidgetWeaverWeatherUnitPreference {
        sync()
        let raw = (defaults.string(forKey: Keys.unitPreference) ??
                   UserDefaults.standard.string(forKey: Keys.unitPreference) ??
                   WidgetWeaverWeatherUnitPreference.automatic.rawValue)
        return WidgetWeaverWeatherUnitPreference(rawValue: raw) ?? .automatic
    }

    public func saveUnitPreference(_ preference: WidgetWeaverWeatherUnitPreference) {
        defaults.set(preference.rawValue, forKey: Keys.unitPreference)
        UserDefaults.standard.set(preference.rawValue, forKey: Keys.unitPreference)
        sync()
    }

    public func resolvedUnitTemperature() -> UnitTemperature {
        switch loadUnitPreference() {
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        case .automatic:
            switch Locale.current.measurementSystem {
            case .us: return .fahrenheit
            default: return .celsius
            }
        }
    }

    // MARK: Attribution

    public func loadAttribution() -> WidgetWeaverWeatherAttribution? {
        sync()

        if let data = defaults.data(forKey: Keys.attributionData),
           let attr = try? decoder.decode(WidgetWeaverWeatherAttribution.self, from: data) {
            return attr
        }

        if let data = UserDefaults.standard.data(forKey: Keys.attributionData),
           let attr = try? decoder.decode(WidgetWeaverWeatherAttribution.self, from: data) {
            if let healed = try? encoder.encode(attr) {
                defaults.set(healed, forKey: Keys.attributionData)
            }
            sync()
            return attr
        }

        return nil
    }

    public func saveAttribution(_ attribution: WidgetWeaverWeatherAttribution?) {
        if let attribution, let data = try? encoder.encode(attribution) {
            defaults.set(data, forKey: Keys.attributionData)
            UserDefaults.standard.set(data, forKey: Keys.attributionData)
        } else {
            defaults.removeObject(forKey: Keys.attributionData)
            UserDefaults.standard.removeObject(forKey: Keys.attributionData)
        }
        sync()
    }

    public func attributionLegalURL() -> URL? {
        loadAttribution()?.legalPageURL
    }

    // MARK: Rendering helpers

    public func recommendedRefreshIntervalSeconds() -> TimeInterval {
        60
    }

    /// Recommended cadence to refresh the cached WeatherKit snapshot.
    /// This is distinct from the widget UI's minute-level timeline tick.
    public func recommendedDataRefreshIntervalSeconds() -> TimeInterval {
        60 * 10
    }

    public func snapshotForRender(context: WidgetWeaverRenderContext) -> WidgetWeaverWeatherSnapshot? {
        if let snap = loadSnapshot() { return snap }
        switch context {
        case .preview, .simulator: return .sampleSunny()
        case .widget: return nil
        }
    }

    /// Weather variables are treated as “built-in” keys.
    /// If there is no snapshot yet, the location key still resolves so the widget stops showing the “set a location” prompt.
    public func variablesDictionary(now: Date = Date()) -> [String: String] {
        if let snap = loadSnapshot() {
            var vars: [String: String] = [:]
            let unit = resolvedUnitTemperature()

            vars["__weather_location"] = snap.locationName
            vars["__weather_condition"] = snap.conditionDescription
            vars["__weather_symbol"] = snap.symbolName
            vars["__weather_updated_iso"] = WidgetWeaverVariableTemplate.iso8601String(snap.fetchedAt)

            let temp = temperatureString(snap.temperatureC, unit: unit)
            vars["__weather_temp"] = temp.value
            vars["__weather_temp_c"] = temperatureString(snap.temperatureC, unit: .celsius).value
            vars["__weather_temp_f"] = temperatureString(snap.temperatureC, unit: .fahrenheit).value

            if let feels = snap.apparentTemperatureC {
                vars["__weather_feels"] = temperatureString(feels, unit: unit).value
                vars["__weather_feels_c"] = temperatureString(feels, unit: .celsius).value
                vars["__weather_feels_f"] = temperatureString(feels, unit: .fahrenheit).value
            }

            if let hi = snap.highTemperatureC {
                vars["__weather_high"] = temperatureString(hi, unit: unit).value
            }
            if let lo = snap.lowTemperatureC {
                vars["__weather_low"] = temperatureString(lo, unit: unit).value
            }

            if let p = snap.precipitationChance01 {
                vars["__weather_precip"] = percentString(fromChance01: p)
                vars["__weather_precip_fraction"] = String(p)
            }

            if let h = snap.humidity01 {
                vars["__weather_humidity"] = percentString(fromChance01: h)
                vars["__weather_humidity_fraction"] = String(h)
            }

            let nowcast = WeatherNowcast(snapshot: snap, now: now)
            vars["__weather_nowcast"] = nowcast.primaryText

            if let s = nowcast.secondaryText {
                vars["__weather_nowcast_secondary"] = s
            }

            if let startM = nowcast.startOffsetMinutes {
                vars["__weather_rain_start_min"] = String(startM)
            }

            if let endM = nowcast.endOffsetMinutes {
                vars["__weather_rain_end_min"] = String(endM)
            }

            if let startText = nowcast.startTimeText {
                vars["__weather_rain_start"] = startText
            }

            @inline(__always)
            func oneDecimal(_ x: Double) -> String { String(format: "%.1f", x) }

            vars["__weather_rain_peak_intensity_mmh"] = oneDecimal(nowcast.peakIntensityMMPerHour)
            vars["__weather_rain_peak_chance"] = percentString(fromChance01: nowcast.peakChance01)
            vars["__weather_rain_peak_chance_fraction"] = String(nowcast.peakChance01)

            // Steps built-ins (so any design can use __steps_today, __steps_avg_7, __steps_streak, etc.)
            let stepsVars = WidgetWeaverStepsStore.shared.variablesDictionary()
            for (k, v) in stepsVars { vars[k] = v }

            return vars
        }

        // No snapshot yet — still expose the saved location so templates can render immediately.
        guard let loc = loadLocation() else { return [:] }

        var vars: [String: String] = [:]
        vars["__weather_location"] = loc.name
        vars["__weather_lat"] = loc.latitudeString
        vars["__weather_lon"] = loc.longitudeString
        vars["__weather_updated_iso"] = WidgetWeaverVariableTemplate.iso8601String(loc.updatedAt)
        return vars
    }

    private struct TempValue { var value: String }

    private func temperatureString(_ celsius: Double, unit: UnitTemperature) -> TempValue {
        let m = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit)
        let rounded = Int(round(m.value))
        return TempValue(value: String(rounded))
    }

    private func percentString(fromChance01 chance: Double) -> String {
        let pct = Int(round(chance * 100.0))
        return String(pct)
    }
    
    // MARK: Last error

    public func loadLastError() -> String? {
        sync()

        if let s = defaults.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }

        if let s = UserDefaults.standard.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                defaults.set(t, forKey: Keys.lastError)
                sync()
                return t
            }
        }

        return nil
    }

    public func saveLastError(_ error: String?) {
        let trimmed = error?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: Keys.lastError)
            UserDefaults.standard.set(trimmed, forKey: Keys.lastError)
        } else {
            defaults.removeObject(forKey: Keys.lastError)
            UserDefaults.standard.removeObject(forKey: Keys.lastError)
        }

        sync()
    }

    public func clearLastError() {
        defaults.removeObject(forKey: Keys.lastError)
        UserDefaults.standard.removeObject(forKey: Keys.lastError)
        sync()
    }
}

// MARK: - Engine

public actor WidgetWeaverWeatherEngine {
    public static let shared = WidgetWeaverWeatherEngine()

    public struct Result: Sendable {
        public var snapshot: WidgetWeaverWeatherSnapshot?
        public var attribution: WidgetWeaverWeatherAttribution?
        public var errorDescription: String?

        public init(
            snapshot: WidgetWeaverWeatherSnapshot?,
            attribution: WidgetWeaverWeatherAttribution?,
            errorDescription: String?
        ) {
            self.snapshot = snapshot
            self.attribution = attribution
            self.errorDescription = errorDescription
        }
    }

    public var minimumUpdateInterval: TimeInterval = 60 * 10
    private var inFlight: Task<Result, Never>?

    public func updateIfNeeded(force: Bool = false) async -> Result {
        if let inFlight { return await inFlight.value }

        let task = Task { () -> Result in
            await self.update(force: force)
        }
        inFlight = task

        let out = await task.value
        inFlight = nil
        return out
    }

    private func update(force: Bool) async -> Result {
        let store = WidgetWeaverWeatherStore.shared

        guard let location = store.loadLocation() else {
            store.saveLastError("No location configured")
            notifyWidgetsWeatherUpdated()
            return Result(snapshot: nil, attribution: store.loadAttribution(), errorDescription: "No location configured")
        }

        if !force, let existing = store.loadSnapshot() {
            let age = Date().timeIntervalSince(existing.fetchedAt)
            if age < minimumUpdateInterval {
                store.saveLastError(nil)
                return Result(snapshot: existing, attribution: store.loadAttribution(), errorDescription: nil)
            }
        }

        #if canImport(WeatherKit)
        do {
            async let wxTask = WeatherService.shared.weather(
                for: location.clLocation,
                including: .current, .minute, .hourly, .daily
            )
            async let attributionTask = WeatherService.shared.attribution

            let (current, minute, hourly, daily) = try await wxTask
            let attribution = try await attributionTask

            let snap = Self.makeSnapshot(
                current: current,
                minuteForecast: minute,
                hourlyForecast: hourly,
                dailyForecast: daily,
                location: location
            )
            let attr = WidgetWeaverWeatherAttribution(legalPageURLString: attribution.legalPageURL.absoluteString)

            store.saveSnapshot(snap)
            store.saveAttribution(attr)
            store.saveLastError(nil)

            notifyWidgetsWeatherUpdated()
            return Result(snapshot: snap, attribution: attr, errorDescription: nil)
        } catch {
            let message = String(describing: error)
            store.saveLastError(message)
            notifyWidgetsWeatherUpdated()

            return Result(
                snapshot: store.loadSnapshot(),
                attribution: store.loadAttribution(),
                errorDescription: message
            )
        }
        #else
        store.saveLastError("WeatherKit unavailable")
        notifyWidgetsWeatherUpdated()
        return Result(snapshot: store.loadSnapshot(), attribution: store.loadAttribution(), errorDescription: "WeatherKit unavailable")
        #endif
    }

    private func notifyWidgetsWeatherUpdated() {
        #if canImport(WidgetKit)
        let kind = WidgetWeaverWidgetKinds.main
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
        #endif
    }

    #if canImport(WeatherKit)
    private static func makeSnapshot(
        current: CurrentWeather,
        minuteForecast: Forecast<MinuteWeather>?,
        hourlyForecast: Forecast<HourWeather>,
        dailyForecast: Forecast<DayWeather>,
        location: WidgetWeaverWeatherLocation
    ) -> WidgetWeaverWeatherSnapshot {
        let now = Date()

        @inline(__always)
        func mmPerHour(_ intensity: Measurement<UnitSpeed>) -> Double {
            // Convert to m/s first (always available), then to mm/hour.
            let mps = intensity.converted(to: .metersPerSecond).value
            return mps * 3_600_000.0
        }

        @inline(__always)
        func mmPerHourFromHourAmount(_ amount: Measurement<UnitLength>) -> Double {
            // HourWeather exposes a per-hour precipitation amount (length), not an intensity.
            // Treat the amount as "mm in that hour" → mm/hour.
            amount.converted(to: .millimeters).value
        }

        let minute: [WidgetWeaverWeatherMinutePoint]? = minuteForecast.map { mf in
            mf.forecast.prefix(60).map { m in
                WidgetWeaverWeatherMinutePoint(
                    date: m.date,
                    precipitationChance01: m.precipitationChance,
                    precipitationIntensityMMPerHour: mmPerHour(m.precipitationIntensity)
                )
            }
        }

        let precipChance01 = hourlyForecast.forecast.first?.precipitationChance

        let today = dailyForecast.forecast.first.map { day -> WidgetWeaverWeatherDailyPoint in
            WidgetWeaverWeatherDailyPoint(
                date: day.date,
                highTemperatureC: day.highTemperature.converted(to: .celsius).value,
                lowTemperatureC: day.lowTemperature.converted(to: .celsius).value,
                symbolName: day.symbolName,
                precipitationChance01: day.precipitationChance
            )
        }

        let hourly: [WidgetWeaverWeatherHourlyPoint] = hourlyForecast.forecast.prefix(8).map { h in
            WidgetWeaverWeatherHourlyPoint(
                date: h.date,
                temperatureC: h.temperature.converted(to: .celsius).value,
                symbolName: h.symbolName,
                precipitationChance01: h.precipitationChance,
                precipitationIntensityMMPerHour: mmPerHourFromHourAmount(h.precipitationAmount)
            )
        }

        let daily: [WidgetWeaverWeatherDailyPoint] = dailyForecast.forecast.prefix(6).map { d in
            WidgetWeaverWeatherDailyPoint(
                date: d.date,
                highTemperatureC: d.highTemperature.converted(to: .celsius).value,
                lowTemperatureC: d.lowTemperature.converted(to: .celsius).value,
                symbolName: d.symbolName,
                precipitationChance01: d.precipitationChance
            )
        }

        return WidgetWeaverWeatherSnapshot(
            fetchedAt: now,
            locationName: location.name,
            latitude: location.latitude,
            longitude: location.longitude,
            isDaylight: current.isDaylight,
            conditionDescription: current.condition.description,
            symbolName: current.symbolName,
            temperatureC: current.temperature.converted(to: .celsius).value,
            apparentTemperatureC: current.apparentTemperature.converted(to: .celsius).value,
            precipitationChance01: precipChance01,
            humidity01: current.humidity,
            highTemperatureC: today?.highTemperatureC,
            lowTemperatureC: today?.lowTemperatureC,
            minute: minute,
            hourly: hourly,
            daily: daily
        )
    }
    #endif
}

//
//  WidgetWeaverWeatherStore.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//  Split out of WidgetWeaverWeather.swift on 12/23/25.
//

import Foundation
import CoreLocation

#if canImport(WidgetKit)
import WidgetKit
#endif

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
    private let lock = NSLock()

    private init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func notifyWidgetsWeatherUpdated() {
        #if canImport(WidgetKit)
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenWeather)
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
        #endif
    }

    // MARK: Location

    public func loadLocation() -> WidgetWeaverWeatherLocation? {
        lock.withLock {
            let decoder = makeDecoder()

            if let data = defaults.data(forKey: Keys.locationData),
               let loc = try? decoder.decode(WidgetWeaverWeatherLocation.self, from: data) {
                return loc
            }

            if let data = UserDefaults.standard.data(forKey: Keys.locationData),
               let loc = try? decoder.decode(WidgetWeaverWeatherLocation.self, from: data) {
                let encoder = makeEncoder()
                if let healed = try? encoder.encode(loc) {
                    defaults.set(healed, forKey: Keys.locationData)
                }
                return loc
            }

            return nil
        }
    }

    public func saveLocation(_ location: WidgetWeaverWeatherLocation?) {
        lock.withLock {
            if let location {
                let encoder = makeEncoder()
                if let data = try? encoder.encode(location) {
                    defaults.set(data, forKey: Keys.locationData)
                    UserDefaults.standard.set(data, forKey: Keys.locationData)
                } else {
                    defaults.removeObject(forKey: Keys.locationData)
                    UserDefaults.standard.removeObject(forKey: Keys.locationData)
                }
            } else {
                defaults.removeObject(forKey: Keys.locationData)
                UserDefaults.standard.removeObject(forKey: Keys.locationData)
            }
        }

        notifyWidgetsWeatherUpdated()
    }

    public func preferredCLLocation() -> CLLocation? {
        loadLocation()?.clLocation
    }

    // MARK: Snapshot

    public func loadSnapshot() -> WidgetWeaverWeatherSnapshot? {
        lock.withLock {
            let decoder = makeDecoder()

            if let data = defaults.data(forKey: Keys.snapshotData),
               let snap = try? decoder.decode(WidgetWeaverWeatherSnapshot.self, from: data) {
                return snap
            }

            if let data = UserDefaults.standard.data(forKey: Keys.snapshotData),
               let snap = try? decoder.decode(WidgetWeaverWeatherSnapshot.self, from: data) {
                let encoder = makeEncoder()
                if let healed = try? encoder.encode(snap) {
                    defaults.set(healed, forKey: Keys.snapshotData)
                }
                return snap
            }

            return nil
        }
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverWeatherSnapshot?) {
        lock.withLock {
            if let snapshot {
                let encoder = makeEncoder()
                if let data = try? encoder.encode(snapshot) {
                    defaults.set(data, forKey: Keys.snapshotData)
                    UserDefaults.standard.set(data, forKey: Keys.snapshotData)
                } else {
                    defaults.removeObject(forKey: Keys.snapshotData)
                    UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
                }
            } else {
                defaults.removeObject(forKey: Keys.snapshotData)
                UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
            }
        }

        notifyWidgetsWeatherUpdated()
    }

    public func clearSnapshot() {
        lock.withLock {
            defaults.removeObject(forKey: Keys.snapshotData)
            UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        }

        notifyWidgetsWeatherUpdated()
    }

    // MARK: Units

    public func loadUnitPreference() -> WidgetWeaverWeatherUnitPreference {
        lock.withLock {
            let raw =
                defaults.string(forKey: Keys.unitPreference)
                ?? UserDefaults.standard.string(forKey: Keys.unitPreference)
                ?? WidgetWeaverWeatherUnitPreference.automatic.rawValue

            return WidgetWeaverWeatherUnitPreference(rawValue: raw) ?? .automatic
        }
    }

    public func saveUnitPreference(_ preference: WidgetWeaverWeatherUnitPreference) {
        lock.withLock {
            defaults.set(preference.rawValue, forKey: Keys.unitPreference)
            UserDefaults.standard.set(preference.rawValue, forKey: Keys.unitPreference)
        }

        notifyWidgetsWeatherUpdated()
    }

    public func resolvedUnitTemperature() -> UnitTemperature {
        switch loadUnitPreference() {
        case .celsius:
            return .celsius
        case .fahrenheit:
            return .fahrenheit
        case .automatic:
            switch Locale.current.measurementSystem {
            case .us:
                return .fahrenheit
            default:
                return .celsius
            }
        }
    }

    // MARK: Attribution

    public func loadAttribution() -> WidgetWeaverWeatherAttribution? {
        lock.withLock {
            let decoder = makeDecoder()

            if let data = defaults.data(forKey: Keys.attributionData),
               let attr = try? decoder.decode(WidgetWeaverWeatherAttribution.self, from: data) {
                return attr
            }

            if let data = UserDefaults.standard.data(forKey: Keys.attributionData),
               let attr = try? decoder.decode(WidgetWeaverWeatherAttribution.self, from: data) {
                let encoder = makeEncoder()
                if let healed = try? encoder.encode(attr) {
                    defaults.set(healed, forKey: Keys.attributionData)
                }
                return attr
            }

            return nil
        }
    }

    public func saveAttribution(_ attribution: WidgetWeaverWeatherAttribution?) {
        lock.withLock {
            if let attribution {
                let encoder = makeEncoder()
                if let data = try? encoder.encode(attribution) {
                    defaults.set(data, forKey: Keys.attributionData)
                    UserDefaults.standard.set(data, forKey: Keys.attributionData)
                } else {
                    defaults.removeObject(forKey: Keys.attributionData)
                    UserDefaults.standard.removeObject(forKey: Keys.attributionData)
                }
            } else {
                defaults.removeObject(forKey: Keys.attributionData)
                UserDefaults.standard.removeObject(forKey: Keys.attributionData)
            }
        }

        notifyWidgetsWeatherUpdated()
    }

    public func attributionLegalURL() -> URL? {
        loadAttribution()?.legalPageURL
    }

    // MARK: Rendering helpers

    public func recommendedRefreshIntervalSeconds() -> TimeInterval { 60 }

    public func recommendedDataRefreshIntervalSeconds() -> TimeInterval { 60 * 10 }

    public func snapshotForRender(context: WidgetWeaverRenderContext) -> WidgetWeaverWeatherSnapshot? {
        if let snap = loadSnapshot() { return snap }
        switch context {
        case .preview, .simulator:
            return .sampleSunny()
        case .widget:
            return nil
        }
    }

    public func variablesDictionary(now: Date = WidgetWeaverRenderClock.now) -> [String: String] {
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
            if let s = nowcast.secondaryText { vars["__weather_nowcast_secondary"] = s }
            if let startM = nowcast.startOffsetMinutes { vars["__weather_rain_start_min"] = String(startM) }
            if let endM = nowcast.endOffsetMinutes { vars["__weather_rain_end_min"] = String(endM) }
            if let startText = nowcast.startTimeText { vars["__weather_rain_start"] = startText }

            @inline(__always) func oneDecimal(_ x: Double) -> String { String(format: "%.1f", x) }
            vars["__weather_rain_peak_intensity_mmh"] = oneDecimal(nowcast.peakIntensityMMPerHour)
            vars["__weather_rain_peak_chance"] = percentString(fromChance01: nowcast.peakChance01)
            vars["__weather_rain_peak_chance_fraction"] = String(nowcast.peakChance01)

            let stepsVars = WidgetWeaverStepsStore.shared.variablesDictionary()
            for (k, v) in stepsVars { vars[k] = v }

            return vars
        }

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
        lock.withLock {
            if let s = defaults.string(forKey: Keys.lastError) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }

            if let s = UserDefaults.standard.string(forKey: Keys.lastError) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    defaults.set(t, forKey: Keys.lastError)
                    return t
                }
            }

            return nil
        }
    }

    public func saveLastError(_ error: String?) {
        lock.withLock {
            let trimmed = error?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: Keys.lastError)
                UserDefaults.standard.set(trimmed, forKey: Keys.lastError)
            } else {
                defaults.removeObject(forKey: Keys.lastError)
                UserDefaults.standard.removeObject(forKey: Keys.lastError)
            }
        }

        notifyWidgetsWeatherUpdated()
    }

    public func clearLastError() {
        lock.withLock {
            defaults.removeObject(forKey: Keys.lastError)
            UserDefaults.standard.removeObject(forKey: Keys.lastError)
        }

        notifyWidgetsWeatherUpdated()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

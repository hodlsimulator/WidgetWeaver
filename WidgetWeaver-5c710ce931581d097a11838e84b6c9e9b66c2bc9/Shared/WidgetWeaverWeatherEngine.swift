//
//  WidgetWeaverWeatherEngine.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Split out of WidgetWeaverWeather.swift on 12/23/25.
//

import Foundation
import CoreLocation

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(WeatherKit)
import WeatherKit
#endif

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
            // Avoid forcing widget reloads when there is no location; this can create re-entrant
            // reload/render loops inside the widget extension.
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
            // Core weather must succeed for the widget to be useful everywhere.
            // Minute forecast + attribution are treated as best-effort so they can't block the widget.
            let (current, hourly, daily) = try await fetchCoreWeatherWithRetry(for: location.clLocation)

            let minuteForecast = await fetchMinuteForecastBestEffort(for: location.clLocation)

            let snap = Self.makeSnapshot(
                current: current,
                minuteForecast: minuteForecast,
                hourlyForecast: hourly,
                dailyForecast: daily,
                location: location
            )

            store.saveSnapshot(snap)

            // Attribution is best-effort. Keep the existing attribution if fetch fails.
            let existingAttr = store.loadAttribution()
            if let newAttr = await fetchAttributionBestEffort() {
                store.saveAttribution(newAttr)
            } else if existingAttr == nil {
                // No-op: leave it nil. The UI already handles "link appears after first success".
            }

            store.saveLastError(nil)

            notifyWidgetsWeatherUpdated()
            return Result(snapshot: snap, attribution: store.loadAttribution(), errorDescription: nil)
        } catch {
            let message = Self.describe(error: error)
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
        // Avoid re-entrant reload loops while the widget extension is rendering.
        guard !WidgetWeaverRuntime.isRunningInAppExtension else { return }

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

    // MARK: - Fetching (robust)

    private func fetchCoreWeatherWithRetry(
        for location: CLLocation,
        maxAttempts: Int = 2
    ) async throws -> (CurrentWeather, Forecast<HourWeather>, Forecast<DayWeather>) {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await WeatherService.shared.weather(
                    for: location,
                    including: .current, .hourly, .daily
                )
            } catch {
                lastError = error

                // Tiny backoff. Helps with transient WeatherKit/network flakiness without stalling the widget.
                if attempt < maxAttempts {
                    let delayNanos: UInt64 = (attempt == 1) ? 250_000_000 : 600_000_000
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
            }
        }

        throw lastError ?? NSError(domain: "WidgetWeaverWeatherEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown WeatherKit error"])
    }

    private func fetchMinuteForecastBestEffort(
        for location: CLLocation
    ) async -> Forecast<MinuteWeather>? {
        do {
            // This can throw intermittently even in regions where Weather is supported.
            return try await WeatherService.shared.weather(for: location, including: .minute)
        } catch {
            return nil
        }
    }

    private func fetchAttributionBestEffort() async -> WidgetWeaverWeatherAttribution? {
        do {
            let attribution = try await WeatherService.shared.attribution
            return WidgetWeaverWeatherAttribution(legalPageURLString: attribution.legalPageURL.absoluteString)
        } catch {
            return nil
        }
    }

    private static func describe(error: Error) -> String {
        // Keep it simple but stable for debugging.
        if let urlError = error as? URLError {
            return "Network error (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
        }
        return String(describing: error)
    }

    // MARK: - Snapshot building

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

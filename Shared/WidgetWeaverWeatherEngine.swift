//
//  WidgetWeaverWeatherEngine.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  WeatherKit-backed engine that maintains cached weather state in the App Group store.
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

    // MARK: - Refresh throttling

    nonisolated static func shouldAttemptRefresh(
        force: Bool,
        now: Date,
        lastAttemptAt: Date?,
        minimumUpdateInterval: TimeInterval
    ) -> Bool {
        if force { return true }
        if minimumUpdateInterval <= 0 { return true }
        guard let lastAttemptAt else { return true }

        let age = now.timeIntervalSince(lastAttemptAt)

        // If the device clock changed (or lastAttemptAt is corrupt), avoid freezing refresh for a long time.
        if age < 0 { return true }

        return age >= minimumUpdateInterval
    }

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

        // Weather refresh is app-only. Widgets should render deterministically from cached App Group state.
        if WidgetWeaverRuntime.isRunningInAppExtension {
            return Result(snapshot: store.loadSnapshot(), attribution: store.loadAttribution(), errorDescription: nil)
        }

        guard let location = store.loadLocation() else {
            store.saveLastError("No location configured")
            // Widget reloads are not forced when there is no location, which prevents
            // re-entrant reload/render loops inside the widget extension.
            return Result(snapshot: nil, attribution: store.loadAttribution(), errorDescription: "No location configured")
        }

        let now = Date()

        // Fast-path: if the cached snapshot is fresh enough, skip WeatherKit.
        //
        // A stored error must not be cleared here. If the most recent attempt failed, the widget can
        // surface a light status until a successful refresh occurs.
        if !force, store.loadLastError() == nil, let existing = store.loadSnapshot() {
            let age = now.timeIntervalSince(existing.fetchedAt)
            if age >= 0, age < minimumUpdateInterval {
                #if canImport(WeatherKit)
                await ensureAttributionIfMissing()
                #endif
                return Result(snapshot: existing, attribution: store.loadAttribution(), errorDescription: nil)
            }
        }

        // Throttle repeated attempts (including failures) so foreground/background triggers do not spam WeatherKit.
        if !Self.shouldAttemptRefresh(
            force: force,
            now: now,
            lastAttemptAt: store.loadLastRefreshAttemptAt(),
            minimumUpdateInterval: minimumUpdateInterval
        ) {
            #if canImport(WeatherKit)
            await ensureAttributionIfMissing()
            #endif
            return Result(
                snapshot: store.loadSnapshot(),
                attribution: store.loadAttribution(),
                errorDescription: store.loadLastError()
            )
        }

        store.saveLastRefreshAttemptAt(now)

        #if canImport(WeatherKit)
        do {
            // Core weather must succeed for the widget to be useful everywhere.
            // Minute forecast + attribution are treated as best-effort so they cannot block the widget.
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
            store.saveLastSuccessfulRefreshAt(snap.fetchedAt)

            // Attribution is required for display in both the app and widgets.
            // Persist it as soon as a first successful weather update occurs.
            if store.loadAttribution() == nil, let newAttr = await fetchAttributionBestEffort() {
                store.saveAttribution(newAttr)
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
        Task { @MainActor in
            WidgetWeaverWeatherWidgetReloadDebouncer.shared.scheduleReloadCoalesced()
        }
        #endif
    }

    #if canImport(WeatherKit)

    // MARK: - Fetching (robust)

    private func ensureAttributionIfMissing() async {
        let store = WidgetWeaverWeatherStore.shared
        guard store.loadAttribution() == nil else { return }

        if let attr = await fetchAttributionBestEffort() {
            store.saveAttribution(attr)
            notifyWidgetsWeatherUpdated()
        }
    }

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

                // Tiny backoff for transient WeatherKit/network flakiness.
                if attempt < maxAttempts {
                    let delayNanos: UInt64 = (attempt == 1) ? 250_000_000 : 600_000_000
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
            }
        }

        throw lastError ?? NSError(
            domain: "WidgetWeaverWeatherEngine",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown WeatherKit error"]
        )
    }

    private func fetchMinuteForecastBestEffort(
        for location: CLLocation
    ) async -> Forecast<MinuteWeather>? {
        do {
            return try await WeatherService.shared.weather(for: location, including: .minute)
        } catch {
            return nil
        }
    }

    private func fetchAttributionBestEffort(maxAttempts: Int = 3) async -> WidgetWeaverWeatherAttribution? {
        for attempt in 1...maxAttempts {
            do {
                let attribution = try await WeatherService.shared.attribution
                return WidgetWeaverWeatherAttribution(legalPageURLString: attribution.legalPageURL.absoluteString)
            } catch {
                if attempt < maxAttempts {
                    let delayNanos: UInt64 = (attempt == 1) ? 250_000_000 : 650_000_000
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
            }
        }
        return nil
    }


    private static func describe(error: Error) -> String {
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
            // Treat the amount as "mm in that hour" -> mm/hour.
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

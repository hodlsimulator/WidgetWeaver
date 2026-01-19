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

        @inline(__always)
        func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }

        @inline(__always)
        func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
            if edge0 == edge1 { return 0.0 }
            let t = clamp01((x - edge0) / (edge1 - edge0))
            return t * t * (3.0 - 2.0 * t)
        }

        @inline(__always)
        func gaussian(_ x: Double, mu: Double, sigma: Double) -> Double {
            if sigma <= 0.0 { return 0.0 }
            let z = (x - mu) / sigma
            return exp(-0.5 * z * z)
        }

        // Deterministic preview curve: rain starts in ~9 minutes, peaks around the middle of the hour,
        // then dissipates. Uses minute-level variation to avoid blocky step plateaus in previews.
        let startM = 9.0
        let peakM = 34.0
        let endM = 53.0

        let minute: [WidgetWeaverWeatherMinutePoint] = (0..<60).compactMap { i in
            guard let d = cal.date(byAdding: .minute, value: i, to: minuteBase) else { return nil }

            let t = Double(i)

            // 0 -> 1 over ~5 minutes.
            let gateIn = smoothstep(startM - 2.0, startM + 3.0, t)

            // 1 -> 0 over ~5 minutes.
            let gateOut = 1.0 - smoothstep(endM - 3.0, endM + 2.0, t)

            let gate = clamp01(gateIn * gateOut)

            // Broad hump with gentle deterministic wiggle so the line reads more like real data.
            let hump = gaussian(t, mu: peakM, sigma: 9.0)
            let wiggle = 0.06 * sin(t * 0.90) + 0.04 * sin(t * 0.23 + 1.40)

            var intensity = max(0.0, (0.12 + 1.55 * hump) * gate * (1.0 + wiggle))
            var chance = clamp01((0.10 + 0.85 * hump) * gate + 0.05)

            // Hard clamp before/after to avoid accidental “early drizzle” affecting the headline.
            if t < startM {
                intensity = 0.0
                chance = 0.08
            } else if t > endM + 1.0 {
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

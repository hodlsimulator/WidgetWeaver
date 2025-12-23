//
//  WidgetWeaverWeatherTemplateModels.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  Nowcast model + text generation.
//
//  IMPORTANT DEFINITION CONTRACT
//  -----------------------------
//  The nowcast headline text and the nowcast chart must agree on what “wet” means.
//  This file owns the single source of truth via `WeatherNowcast.isWet(intensityMMPerHour:)`.
//
//  Any change to wet thresholds or drizzle/rain categorisation must be reviewed with:
//  - WeatherNowcast.analyse(...)
//  - WeatherNowcastChart rendering (uses the same `isWet` helper)
//  to avoid subtle minute-by-minute mismatches.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Nowcast Model

struct WeatherNowcastBucket: Identifiable, Hashable {
    var id: Int
    var intensityMMPerHour: Double
    var chance01: Double

    /// A 0...1 cue for how uncertain the next-hour rain forecast is for this bucket.
    /// Used only for rendering a faint halo around the ribbon (Dark Sky style).
    var rainUncertainty01: Double
}

struct WeatherNowcast: Hashable {

    // MARK: Shared wetness definition

    /// Very low threshold so mist/drizzle counts as “wet”.
    /// Units: millimetres per hour (mm/h).
    ///
    /// This value is intentionally conservative against false negatives.
    /// A tiny baseline drizzle is acceptable; missing real drizzle is not.
    static let wetIntensityThresholdMMPerHour: Double = 0.005

    /// Chance threshold used only for wording (“possible”) when rain starts in the future.
    /// The chart still renders the ribbon based on intensity alone (using `isWet`).
    static let lowChanceWordingThreshold01: Double = 0.35

    @inline(__always)
    static func isWet(intensityMMPerHour: Double) -> Bool {
        intensityMMPerHour >= wetIntensityThresholdMMPerHour
    }

    /// Visual scaling helper so drizzle does not “fill the chart”.
    /// This keeps the chart’s height meaningfully tied to real-world intensity.
    static func visualMaxIntensityMMPerHour(forPeak peak: Double) -> Double {
        // Floor to keep the chart stable and readable in drizzle/light rain cases.
        if peak <= 0 { return 1.0 }

        // Quantise to sensible steps so the chart does not wildly rescale minute-to-minute.
        if peak < 1.0 { return 1.0 }
        if peak < 2.5 { return 2.5 }
        if peak < 5.0 { return 5.0 }
        if peak < 10.0 { return 10.0 }

        return peak
    }

    // MARK: Stored results

    let points: [WidgetWeaverWeatherMinutePoint]
    let startOffsetMinutes: Int?
    let endOffsetMinutes: Int?
    let peakIntensityMMPerHour: Double
    let peakChance01: Double
    let primaryText: String
    let secondaryText: String?
    let startTimeText: String?

    init(snapshot: WidgetWeaverWeatherSnapshot, now: Date) {
        let hasMinuteData = snapshot.minute != nil
        let raw = snapshot.minute ?? []

        let filtered = raw
            .filter { $0.date >= now.addingTimeInterval(-30) }
            .sorted(by: { $0.date < $1.date })

        // Take a forward-looking hour from 'now'.
        let forward = filtered.filter { $0.date >= now }.prefix(60)
        self.points = Array(forward)

        let analysis = WeatherNowcast.analyse(
            points: self.points,
            now: now,
            hasMinuteData: hasMinuteData,
            isRainingNow: WeatherNowcast.isRainingNow(snapshot: snapshot)
        )

        self.startOffsetMinutes = analysis.startOffsetMinutes
        self.endOffsetMinutes = analysis.endOffsetMinutes
        self.peakIntensityMMPerHour = analysis.peakIntensityMMPerHour
        self.peakChance01 = analysis.peakChance01
        self.primaryText = analysis.primaryText
        self.secondaryText = analysis.secondaryText
        self.startTimeText = analysis.startTimeText
    }

    private static func isRainingNow(snapshot: WidgetWeaverWeatherSnapshot) -> Bool {
        let s = snapshot.symbolName.lowercased()
        return s.contains("rain") || s.contains("drizzle") || s.contains("thunderstorm")
    }

    func buckets(for family: WidgetFamily) -> [WeatherNowcastBucket] {
        guard !points.isEmpty else { return [] }

        let bucketSize: Int
        switch family {
        case .systemSmall:
            bucketSize = 5
        case .systemMedium:
            bucketSize = 3
        default:
            bucketSize = 1
        }

        let intensities = points.map { max(0.0, $0.precipitationIntensityMMPerHour ?? 0.0) }
        let chances = points.map { WeatherNowcast.clamp01($0.precipitationChance01 ?? 0.0) }

        var out: [WeatherNowcastBucket] = []
        out.reserveCapacity(Int((Double(points.count) / Double(bucketSize)).rounded(.up)))

        var idx = 0
        var bucketId = 0

        while idx < points.count {
            let end = min(points.count, idx + bucketSize)
            let sliceI = Array(intensities[idx..<end])
            let sliceC = Array(chances[idx..<end])

            // Use max so short drizzle bursts are not averaged away.
            let maxIntensity = sliceI.max() ?? 0.0
            let maxChance = sliceC.max() ?? 0.0

            let minIntensity = sliceI.min() ?? 0.0
            let intensityRange = max(0.0, maxIntensity - minIntensity)

            let minChance = sliceC.min() ?? 0.0
            let chanceRange = max(0.0, maxChance - minChance)

            let chanceUncertainty01 = (maxChance > 0.0) ? Self.clamp01(chanceRange / maxChance) : 0.0
            let intensityUncertainty01 = (maxIntensity > 0.0) ? Self.clamp01(intensityRange / maxIntensity) : 0.0
            let rainUncertainty01 = Self.clamp01(0.75 * chanceUncertainty01 + 0.25 * intensityUncertainty01)

            out.append(.init(
                id: bucketId,
                intensityMMPerHour: maxIntensity,
                chance01: maxChance,
                rainUncertainty01: rainUncertainty01
            ))

            bucketId += 1
            idx += bucketSize
        }

        return out
    }

    // MARK: Analysis

    private struct Analysis: Hashable {
        var startOffsetMinutes: Int?
        var endOffsetMinutes: Int?
        var peakIntensityMMPerHour: Double
        var peakChance01: Double
        var primaryText: String
        var secondaryText: String?
        var startTimeText: String?
    }

    private static func analyse(
        points: [WidgetWeaverWeatherMinutePoint],
        now: Date,
        hasMinuteData: Bool,
        isRainingNow: Bool
    ) -> Analysis {

        guard !points.isEmpty else {
            if !hasMinuteData {
                if isRainingNow {
                    return Analysis(
                        startOffsetMinutes: 0,
                        endOffsetMinutes: nil,
                        peakIntensityMMPerHour: 0,
                        peakChance01: 0,
                        primaryText: "Rain now",
                        secondaryText: "Next-hour rain unavailable",
                        startTimeText: "Now"
                    )
                }
                return Analysis(
                    startOffsetMinutes: nil,
                    endOffsetMinutes: nil,
                    peakIntensityMMPerHour: 0,
                    peakChance01: 0,
                    primaryText: "Next-hour rain unavailable",
                    secondaryText: nil,
                    startTimeText: nil
                )
            }

            return Analysis(
                startOffsetMinutes: nil,
                endOffsetMinutes: nil,
                peakIntensityMMPerHour: 0,
                peakChance01: 0,
                primaryText: "No rain next hour",
                secondaryText: nil,
                startTimeText: nil
            )
        }

        struct Sample {
            var offsetM: Int
            var intensity: Double
            var chance: Double
        }

        let samples: [Sample] = points.map { p in
            let intensity = max(0.0, p.precipitationIntensityMMPerHour ?? 0.0)
            let chance = clamp01(p.precipitationChance01 ?? 0.0)
            let offsetM = max(0, Int(p.date.timeIntervalSince(now) / 60.0))
            return Sample(offsetM: offsetM, intensity: intensity, chance: chance)
        }

        // Wet minutes use the shared intensity-only definition.
        let wetIdx: [Int] = samples.enumerated().compactMap { (i, s) in
            return isWet(intensityMMPerHour: s.intensity) ? i : nil
        }

        if wetIdx.isEmpty {
            let peakChance = samples.map { $0.chance }.max() ?? 0.0
            let secondary: String? = (peakChance > 0.15) ? "Low chance precipitation" : nil

            return Analysis(
                startOffsetMinutes: nil,
                endOffsetMinutes: nil,
                peakIntensityMMPerHour: 0,
                peakChance01: peakChance,
                primaryText: "No rain next hour",
                secondaryText: secondary,
                startTimeText: nil
            )
        }

        let startIndex = wetIdx.first ?? 0
        let endIndex = wetIdx.last ?? startIndex

        let startOffset = samples[startIndex].offsetM
        let endOffset = samples[endIndex].offsetM

        let peakIntensity = wetIdx.map { samples[$0].intensity }.max() ?? 0.0
        let peakChance = wetIdx.map { samples[$0].chance }.max() ?? 0.0

        let label = precipitationLabel(peakIntensity)

        let startTimeText: String?
        if startOffset <= 0 {
            startTimeText = "Now"
        } else {
            startTimeText = "Starts in \(startOffset)m"
        }

        if startOffset <= 0 {
            let primary = "\(label) now"
            let secondary: String?
            if endOffset < 55 {
                secondary = "Stopping in \(endOffset)m"
            } else {
                secondary = "Continuing for ~\(endOffset)m"
            }

            return Analysis(
                startOffsetMinutes: 0,
                endOffsetMinutes: endOffset,
                peakIntensityMMPerHour: peakIntensity,
                peakChance01: peakChance,
                primaryText: primary,
                secondaryText: secondary,
                startTimeText: startTimeText
            )
        }

        if startOffset < 55 {
            let isLowChance = (peakChance > 0.0 && peakChance < lowChanceWordingThreshold01)
            let primary = isLowChance ? "\(label) possible in \(startOffset)m" : "\(label) in \(startOffset)m"

            let secondary: String?
            if endOffset < 55 {
                secondary = "Ending in \(endOffset)m"
            } else {
                secondary = "Likely within the hour"
            }

            return Analysis(
                startOffsetMinutes: startOffset,
                endOffsetMinutes: endOffset,
                peakIntensityMMPerHour: peakIntensity,
                peakChance01: peakChance,
                primaryText: primary,
                secondaryText: secondary,
                startTimeText: startTimeText
            )
        }

        return Analysis(
            startOffsetMinutes: startOffset,
            endOffsetMinutes: endOffset,
            peakIntensityMMPerHour: peakIntensity,
            peakChance01: peakChance,
            primaryText: "Light rain later",
            secondaryText: nil,
            startTimeText: startTimeText
        )
    }

    private static func precipitationLabel(_ intensity: Double) -> String {
        // Drizzle buckets
        if intensity < 0.05 { return "Light drizzle" }
        if intensity < 0.25 { return "Drizzle" }

        // Rain buckets (keep the existing style of short, familiar words)
        if intensity < 1.20 { return "Light rain" }
        if intensity < 3.50 { return "Moderate rain" }
        if intensity < 10.0 { return "Heavy rain" }
        return "Very heavy rain"
    }

    private static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }
}

// MARK: - Later Today / Tomorrow

struct WeatherLaterToday: Hashable {
    let hourlyPoints: [WidgetWeaverWeatherHourlyPoint]

    init(snapshot: WidgetWeaverWeatherSnapshot, now: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(60 * 60 * 24)

        let remaining = snapshot.hourly
            .filter { $0.date >= now && $0.date < endOfToday }
            .prefix(8)

        self.hourlyPoints = Array(remaining)
    }
}

struct WeatherTomorrow: Hashable {
    let day: WidgetWeaverWeatherDailyPoint

    var summaryText: String {
        if let chance = day.precipitationChance01 {
            let pct = Int((chance * 100).rounded())
            if pct <= 10 { return "Mostly dry" }
            return "\(pct)% chance of rain"
        }
        return "—"
    }

    func hiLoText(unit: UnitTemperature) -> String? {
        guard let hi = day.highTemperatureC, let lo = day.lowTemperatureC else { return nil }
        let hiText = wwTempString(hi, unit: unit)
        let loText = wwTempString(lo, unit: unit)
        return "H \(hiText) L \(loText)"
    }

    init?(snapshot: WidgetWeaverWeatherSnapshot, now: Date) {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(60 * 60 * 24)

        if let match = snapshot.daily.first(where: { cal.isDate($0.date, inSameDayAs: tomorrow) }) {
            self.day = match
        } else if snapshot.daily.count >= 2 {
            self.day = snapshot.daily[1]
        } else {
            return nil
        }
    }
}

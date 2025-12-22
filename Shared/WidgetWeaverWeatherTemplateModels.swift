//
//  WidgetWeaverWeatherTemplateModels.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
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
    /// This is used purely for rendering a faint "envelope" around bars (Dark Sky style).
    var rainUncertainty01: Double
}

struct WeatherNowcast: Hashable {
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
            isRainingNow: WeatherNowcast.isRainingNow(snapshot: snapshot),
            snapshotSymbolName: snapshot.symbolName
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

            let sliceI = intensities[idx..<end]
            let sliceC = chances[idx..<end]

            // Bucket values are averaged (rather than max) so the chart changes smoothly as `now` advances.
            // Using max-values here can make small/medium widgets appear “stuck” for several minutes
            // because each bar covers multiple minutes.
            let n = Double(sliceI.count)

            let avgIntensity = (n > 0) ? (sliceI.reduce(0.0, +) / n) : 0.0
            let avgChance = (n > 0) ? (sliceC.reduce(0.0, +) / n) : 0.0

            let maxIntensity = sliceI.max() ?? 0.0
            let minIntensity = sliceI.min() ?? 0.0
            let intensityRange = max(0.0, maxIntensity - minIntensity)

            let maxChance = sliceC.max() ?? 0.0
            let minChance = sliceC.min() ?? 0.0
            let chanceRange = max(0.0, maxChance - minChance)

            let chanceUncertainty01 = (maxChance > 0.0) ? Self.clamp01(chanceRange / maxChance) : 0.0
            let intensityUncertainty01 = (maxIntensity > 0.0) ? Self.clamp01(intensityRange / maxIntensity) : 0.0

            let rainUncertainty01 = Self.clamp01(0.75 * chanceUncertainty01 + 0.25 * intensityUncertainty01)

            out.append(.init(
                id: bucketId,
                intensityMMPerHour: avgIntensity,
                chance01: avgChance,
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
        isRainingNow: Bool,
        snapshotSymbolName: String
    ) -> Analysis {
        guard !points.isEmpty else {
            if !hasMinuteData {
                if isRainingNow {
                    let nowPhrase = nowPrecipPhrase(fromSymbolName: snapshotSymbolName)
                    return Analysis(
                        startOffsetMinutes: 0,
                        endOffsetMinutes: nil,
                        peakIntensityMMPerHour: 0,
                        peakChance01: 0,
                        primaryText: "\(nowPhrase) now",
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

        // Use expected intensity to decide if it's meaningfully wet.
        // Lower = more sensitive.
        // Units: mm/hour of expected precip (intensity * chance).
        let wetThreshold: Double = 0.001
        let wetIdx: [Int] = samples.enumerated().compactMap { (i, s) in
            let expected = s.intensity * s.chance
            return (expected >= wetThreshold) ? i : nil
        }

        if wetIdx.isEmpty {
            let peakChance = samples.map { $0.chance }.max() ?? 0
            let secondary: String? = (peakChance > 0.15) ? "Low chance showers" : nil
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

        let peakIntensity = wetIdx.map { samples[$0].intensity }.max() ?? 0
        let peakChance = wetIdx.map { samples[$0].chance }.max() ?? 0

        let phrase = precipitationPhrase(peakIntensity)

        let startTimeText: String?
        if startOffset <= 0 {
            startTimeText = "Now"
        } else {
            startTimeText = "Starts in \(startOffset)m"
        }

        if startOffset <= 0 {
            // Raining now.
            let primary = "\(phrase) now"
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
            // Starts later.
            let primary = "\(phrase) in \(startOffset)m"
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

        // Edge: only at the end.
        return Analysis(
            startOffsetMinutes: startOffset,
            endOffsetMinutes: endOffset,
            peakIntensityMMPerHour: peakIntensity,
            peakChance01: peakChance,
            primaryText: "\(phrase) later",
            secondaryText: nil,
            startTimeText: startTimeText
        )
    }

    private static func nowPrecipPhrase(fromSymbolName symbolName: String) -> String {
        let s = symbolName.lowercased()
        if s.contains("drizzle") { return "Drizzle" }
        return "Rain"
    }

    private static func precipitationPhrase(_ intensity: Double) -> String {
        // Intensities are mm/hour.
        if intensity < 0.08 { return "Light drizzle" }
        if intensity < 0.25 { return "Drizzle" }
        if intensity < 1.20 { return "Light rain" }
        if intensity < 3.50 { return "Moderate rain" }
        if intensity < 7.00 { return "Heavy rain" }
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

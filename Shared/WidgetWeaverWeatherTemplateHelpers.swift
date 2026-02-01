//
//  WidgetWeaverWeatherTemplateHelpers.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation

@inline(__always)
func wwTempString(_ celsius: Double, unit: UnitTemperature) -> String {
    let m = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit)
    return String(Int(round(m.value)))
}

@inline(__always)
func wwTempDegreesString(_ celsius: Double, unit: UnitTemperature) -> String {
    "\(wwTempString(celsius, unit: unit))°"
}

@inline(__always)
func wwUnitSuffix(_ unit: UnitTemperature) -> String {
    let symbol = unit.symbol.uppercased()
    if symbol.contains("F") { return "F" }
    if symbol.contains("C") { return "C" }

    let trimmed = symbol
        .replacingOccurrences(of: "°", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty { return "C" }
    return trimmed
}

@inline(__always)
func wwTempDegreesWithUnitString(_ celsius: Double, unit: UnitTemperature) -> String {
    "\(wwTempString(celsius, unit: unit))°\(wwUnitSuffix(unit))"
}

@inline(__always)
func wwHourString(_ date: Date) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    return String(format: "%02d", hour)
}

@inline(__always)
func wwShortTimeString(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

@inline(__always)
func wwUpdatedAgoString(from fetchedAt: Date, now: Date) -> String {
    let seconds = max(0.0, now.timeIntervalSince(fetchedAt))

    // No seconds in the UI.
    if seconds < 60 { return "now" }

    let minutes = Int(floor(seconds / 60.0))
    if minutes < 60 {
        if minutes == 1 { return "1 min ago" }
        return "\(minutes) mins ago"
    }

    let hours = Int(floor(Double(minutes) / 60.0))
    if hours < 24 {
        if hours == 1 { return "1 hr ago" }
        return "\(hours) hrs ago"
    }

    let days = Int(floor(Double(hours) / 24.0))
    if days == 1 { return "1 day ago" }
    return "\(days) days ago"
}

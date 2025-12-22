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

    // Treat anything under a minute as "now".
    if seconds < 60 { return "now" }

    let minutes = Int(floor(seconds / 60.0))
    if minutes < 60 { return "\(minutes)m ago" }

    let hours = Int(floor(Double(minutes) / 60.0))
    if hours < 24 { return "\(hours)h ago" }

    let days = Int(floor(Double(hours) / 24.0))
    return "\(days)d ago"
}

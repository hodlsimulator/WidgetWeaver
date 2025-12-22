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
    let minutes = Int(floor(seconds / 60.0))

    if minutes <= 0 { return "now" }
    if minutes == 1 { return "1 min ago" }
    return "\(minutes) mins ago"
}

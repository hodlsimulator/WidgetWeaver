//
//  WidgetWeaverRenderClock.swift
//  WidgetWeaver
//
//  Created by . . on 12/22/25.
//

import Foundation

public enum WidgetWeaverRenderClock {
    @TaskLocal public static var overrideNow: Date?

    public static var now: Date {
        overrideNow ?? Date()
    }

    public static func withNow<T>(_ date: Date, operation: () -> T) -> T {
        $overrideNow.withValue(date, operation: operation)
    }
}

//
//  WidgetWeaverRenderClock.swift
//  WidgetWeaver
//
//  Created by . . on 12/22/25.
//

import Foundation
import SwiftUI

public enum WidgetWeaverRenderClock {
    fileprivate static let threadDictionaryKey: String = "com.widgetweaver.renderclock.now"

    /// Returns the current render-time date.
    ///
    /// WidgetKit can render views ahead-of-time (for future timeline entries). In those cases,
    /// `Date()` is not stable. Prefer `WidgetWeaverRenderClock.now` in time-dependent widget UI,
    /// and wrap widget rendering in `WidgetWeaverRenderClock.withNow(entry.date)`.
    public static var now: Date {
        (Thread.current.threadDictionary[threadDictionaryKey] as? Date) ?? Date()
    }

    @discardableResult
    public static func withNow<T>(_ date: Date, operation: () -> T) -> T {
        let dict = Thread.current.threadDictionary
        let key = threadDictionaryKey
        let previous = dict[key]

        dict[key] = date
        defer {
            if let previous {
                dict[key] = previous
            } else {
                dict.removeObject(forKey: key)
            }
        }

        return operation()
    }

    @MainActor
    @ViewBuilder
    public static func withNow<Content: View>(_ date: Date, @ViewBuilder _ content: () -> Content) -> some View {
        WidgetWeaverRenderClockScope(now: date, content: content())
    }
}

@MainActor
private struct WidgetWeaverRenderClockScope<Content: View>: View {
    let now: Date
    let content: Content

    var body: some View {
        WidgetWeaverRenderClock.withNow(now) {
            content
        }
    }
}

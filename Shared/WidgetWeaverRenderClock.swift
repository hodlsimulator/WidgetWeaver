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
        // WARNING:
        // `WidgetWeaverRenderClock.withNow(now) { content }` must not be called from within this scope.
        // Overload resolution can pick the ViewBuilder `withNow` and re-wrap another scope, causing
        // infinite SwiftUI view recursion and a widget render crash (Home Screen widgets appear black).
        //
        // The scope’s job is only to set the threadDictionary key for the current render pass and
        // return `content` directly.
        Thread.current.threadDictionary[WidgetWeaverRenderClock.threadDictionaryKey] = now
        return content
    }
}

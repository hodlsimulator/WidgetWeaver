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

    public static var now: Date {
        (Thread.current.threadDictionary[threadDictionaryKey] as? Date) ?? Date()
    }

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
        Thread.current.threadDictionary[WidgetWeaverRenderClock.threadDictionaryKey] = now
        return content
    }
}

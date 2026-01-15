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
    /// WidgetKit can render timelines for future dates; by default SwiftUI's `Date()` reflects real-time.
    /// Using a thread-local override lets any render-time code use the correct timeline date.
    public static var now: Date {
        Thread.current.threadDictionary[threadDictionaryKey] as? Date ?? Date()
    }

    /// Executes `content` with the render clock overridden to `date` (thread-local).
    public static func withNow<T>(_ date: Date, _ content: () -> T) -> T {
        let td = Thread.current.threadDictionary
        let prev = td[threadDictionaryKey]
        td[threadDictionaryKey] = date
        defer {
            if let prev {
                td[threadDictionaryKey] = prev
            } else {
                td.removeObject(forKey: threadDictionaryKey)
            }
        }
        return content()
    }

    /// Returns an aligned start date for `.periodic(from:by:)` so independent TimelineViews tick together.
    ///
    /// A TimelineView scheduled from `Date()` starts at a slightly different phase per view, which can
    /// cause multiple previews to advance at different moments. Aligning to a fixed epoch boundary
    /// keeps all preview surfaces in sync.
    public static func alignedTimelineStartDate(interval: TimeInterval, now: Date = Date()) -> Date {
        let i = max(0.001, interval)
        let t = now.timeIntervalSince1970
        let aligned = floor(t / i) * i
        return Date(timeIntervalSince1970: aligned)
    }
}

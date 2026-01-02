//
//  WWClockDebugLog.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation

public enum WWClockDebugLog {
    private static let logKey = "widgetweaver.clock.debug.log.v1"
    private static let throttlePrefix = "widgetweaver.clock.debug.log.throttle."
    private static let maxLinesDefault: Int = 240

    private static func timestampString(_ date: Date) -> String {
        // Local formatter per call avoids shared mutable state / Sendable warnings under strict concurrency.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Appends a message if the throttle window allows it.
    /// The closure is only evaluated when a log entry will actually be written.
    public static func appendLazy(
        category: String = "clock",
        throttleID: String? = nil,
        minInterval: TimeInterval = 20.0,
        now: Date = Date(),
        _ makeMessage: () -> String
    ) {
        let defaults = AppGroup.userDefaults

        if let throttleID {
            let key = throttlePrefix + throttleID
            let last = defaults.object(forKey: key) as? Date ?? .distantPast
            if now.timeIntervalSince(last) < minInterval { return }
            defaults.set(now, forKey: key)
        }

        let trimmed = makeMessage().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ts = timestampString(now)
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        let line = "\(ts) [\(category)] [\(bundleID)] \(trimmed)"

        var lines = defaults.stringArray(forKey: logKey) ?? []
        lines.append(line)

        if lines.count > maxLinesDefault {
            lines.removeFirst(lines.count - maxLinesDefault)
        }

        defaults.set(lines, forKey: logKey)
        defaults.synchronize()
    }

    /// Convenience wrapper (eager string).
    public static func append(
        _ message: String,
        category: String = "clock",
        throttleID: String? = nil,
        minInterval: TimeInterval = 20.0,
        now: Date = Date()
    ) {
        appendLazy(category: category, throttleID: throttleID, minInterval: minInterval, now: now) {
            message
        }
    }

    public static func readLines() -> [String] {
        AppGroup.userDefaults.stringArray(forKey: logKey) ?? []
    }

    public static func readText(maxLines: Int? = nil) -> String {
        let lines = readLines()
        if let maxLines, lines.count > maxLines {
            return lines.suffix(maxLines).joined(separator: "\n")
        }
        return lines.joined(separator: "\n")
    }

    public static func clear() {
        let defaults = AppGroup.userDefaults
        defaults.removeObject(forKey: logKey)
        defaults.synchronize()
    }
}

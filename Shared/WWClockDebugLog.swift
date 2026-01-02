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

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func append(
        _ message: String,
        category: String = "clock",
        throttleID: String? = nil,
        minInterval: TimeInterval = 20.0,
        now: Date = Date()
    ) {
        let defaults = AppGroup.userDefaults

        if let throttleID {
            let key = throttlePrefix + throttleID
            let last = defaults.object(forKey: key) as? Date ?? .distantPast
            if now.timeIntervalSince(last) < minInterval { return }
            defaults.set(now, forKey: key)
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ts = isoFormatter.string(from: now)
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

//
//  WWClockDebugLog.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Dispatch
import Foundation

public enum WWClockDebugLog {
    #if DEBUG
    private static let defaultEnabled: Bool = true
    #else
    private static let defaultEnabled: Bool = false
    #endif

    private static let enabledKey = "widgetweaver.clock.debug.log.enabled.v1"

    // Legacy key used by older builds that stored log lines as a [String] in App Group defaults.
    private static let legacyDefaultsLogKey = "widgetweaver.clock.debug.log.v1"

    private static let logFileName = "WidgetWeaverClockDebugLog.txt"

    /// Hard cap to prevent logs growing without bound.
    /// Kept small because this can be written from a widget extension.
    private static let maxBytes: Int = 256 * 1024

    private static let maxLinesDefault: Int = 240
    private static let maxCharsPerLine: Int = 1024

    private static var logFileURL: URL {
        AppGroup.containerURL.appendingPathComponent(logFileName)
    }

    private static let ioQueue = DispatchQueue(label: "widgetweaver.clock.debug.log.io")

    // MARK: - Throttling (in-memory)

    private final class ThrottleState: @unchecked Sendable {
        private let lock = NSLock()
        private var lastByID: [String: TimeInterval] = [:]

        func shouldLog(id: String, now: Date, minInterval: TimeInterval) -> Bool {
            let t = now.timeIntervalSinceReferenceDate

            lock.lock()
            defer { lock.unlock() }

            let last = lastByID[id] ?? -Double.greatestFiniteMagnitude
            if (t - last) < minInterval { return false }
            lastByID[id] = t
            return true
        }

        func reset() {
            lock.lock()
            lastByID.removeAll(keepingCapacity: false)
            lock.unlock()
        }
    }

    private static let throttleState = ThrottleState()

    // MARK: - Public API

    public static func isEnabled() -> Bool {
        let defaults = AppGroup.userDefaults
        if defaults.object(forKey: enabledKey) == nil { return defaultEnabled }
        return defaults.bool(forKey: enabledKey)
    }

    public static func setEnabled(_ enabled: Bool) {
        let defaults = AppGroup.userDefaults
        defaults.set(enabled, forKey: enabledKey)
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
        guard isEnabled() else { return }

        if let throttleID {
            if !throttleState.shouldLog(id: throttleID, now: now, minInterval: minInterval) {
                return
            }
        }

        let trimmed = makeMessage().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ts = timestampString(now)
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.bundle"

        let lineOut: String = {
            var s = "\(ts) [\(category)] [\(bundleID)] \(trimmed)"
            if s.count > maxCharsPerLine {
                s = String(s.prefix(maxCharsPerLine)) + "…"
            }
            return s
        }()

        // Avoid blocking widget rendering on file I/O.
        ioQueue.async {
            dropLegacyDefaultsLogIfNeededLocked()
            appendLineLocked(lineOut)
        }
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
        ioQueue.sync {
            dropLegacyDefaultsLogIfNeededLocked()

            guard FileManager.default.fileExists(atPath: logFileURL.path) else { return [] }
            guard let data = try? Data(contentsOf: logFileURL) else { return [] }
            guard let text = String(data: data, encoding: .utf8) else { return [] }

            let rawLines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if rawLines.count <= maxLinesDefault { return rawLines }
            return Array(rawLines.suffix(maxLinesDefault))
        }
    }

    public static func readText(maxLines: Int? = nil) -> String {
        let lines = readLines()
        if let maxLines, lines.count > maxLines {
            return lines.suffix(maxLines).joined(separator: "\n")
        }
        return lines.joined(separator: "\n")
    }

    public static func clear() {
        ioQueue.sync {
            let defaults = AppGroup.userDefaults
            defaults.removeObject(forKey: legacyDefaultsLogKey)

            if FileManager.default.fileExists(atPath: logFileURL.path) {
                try? FileManager.default.removeItem(at: logFileURL)
            }

            throttleState.reset()
        }
    }

    // MARK: - Helpers

    private static func timestampString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    // MARK: - File I/O (serialised on ioQueue)

    private static func ensureFileExistsLocked() {
        if FileManager.default.fileExists(atPath: logFileURL.path) { return }
        _ = FileManager.default.createFile(atPath: logFileURL.path, contents: Data(), attributes: nil)
    }

    private static func appendLineLocked(_ line: String) {
        ensureFileExistsLocked()

        guard let data = (line + "\n").data(using: .utf8) else { return }

        do {
            let h = try FileHandle(forWritingTo: logFileURL)
            _ = try h.seekToEnd()
            try h.write(contentsOf: data)
            try h.close()
        } catch {
            // Best-effort logging only.
            return
        }

        pruneIfNeededLocked()
    }

    private static func pruneIfNeededLocked() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let n = attrs[.size] as? NSNumber
        else { return }

        if n.intValue <= maxBytes { return }

        guard let data = try? Data(contentsOf: logFileURL) else { return }
        if data.count <= maxBytes { return }

        var trimmed = Data(data.suffix(maxBytes))

        // Drop a partial first line if the slice started mid-line.
        if let nl = trimmed.firstIndex(of: 0x0A) {
            let start = trimmed.index(after: nl)
            if start < trimmed.endIndex {
                trimmed = Data(trimmed[start..<trimmed.endIndex])
            }
        }

        try? trimmed.write(to: logFileURL, options: [.atomic])
    }

    private static func dropLegacyDefaultsLogIfNeededLocked() {
        let defaults = AppGroup.userDefaults
        guard defaults.object(forKey: legacyDefaultsLogKey) != nil else { return }

        // Do not migrate large legacy logs; they were the source of the original performance issue.
        defaults.removeObject(forKey: legacyDefaultsLogKey)
    }
}

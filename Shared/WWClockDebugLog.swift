//
//  WWClockDebugLog.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation

public enum WWClockDebugLog {

    // MARK: - Keys

    private static let enabledKey = "WWClockDebugLog.enabled"
    private static let balloonEnabledKey = "WWClockDebugLog.balloonEnabled"

    // Legacy balloon backend key (UserDefaults array).
    private static let legacyDefaultsLogKey = "WWClockDebugLog.legacyLines"

    // MARK: - Settings

    #if DEBUG
    private static let defaultEnabled: Bool = true
    private static let defaultBalloonEnabled: Bool = true
    #else
    private static let defaultEnabled: Bool = false
    private static let defaultBalloonEnabled: Bool = false
    #endif

    // MARK: - File backend

    private static let ioQueue = DispatchQueue(label: "com.conornolan.WidgetWeaver.WWClockDebugLog.io", qos: .utility)

    private static let logFileName = "WidgetWeaverClockDebugLog.txt"

    private static let maxBytesDefault: Int = 512 * 1024
    private static let maxCharsPerLine: Int = 1400
    private static let maxLinesDefault: Int = 6000

    private static var logFileURL: URL {
        AppGroup.containerURL.appendingPathComponent(logFileName, isDirectory: false)
    }

    // MARK: - Throttling

    private static var throttleState = WWThrottleState()

    private struct WWThrottleState {
        private var lastWrite: [String: Date] = [:]

        mutating func shouldLog(id: String, now: Date, minInterval: TimeInterval) -> Bool {
            if minInterval <= 0 { return true }
            if let last = lastWrite[id], now.timeIntervalSince(last) < minInterval {
                return false
            }
            lastWrite[id] = now
            return true
        }

        mutating func reset() {
            lastWrite.removeAll()
        }
    }

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

    public static func isBallooningEnabled() -> Bool {
        let defaults = AppGroup.userDefaults
        if defaults.object(forKey: balloonEnabledKey) == nil { return defaultBalloonEnabled }
        return defaults.bool(forKey: balloonEnabledKey)
    }

    public static func setBallooningEnabled(_ enabled: Bool) {
        let defaults = AppGroup.userDefaults
        defaults.set(enabled, forKey: balloonEnabledKey)
    }

    /// Convenience wrapper used by existing call sites (including WWClockSecondHandFont.swift).
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

    /// Appends a message if enabled.
    /// In balloon mode, throttling is bypassed to reproduce the old “enormous logs” behaviour.
    public static func appendLazy(
        category: String = "clock",
        throttleID: String? = nil,
        minInterval: TimeInterval = 20.0,
        now: Date = Date(),
        _ makeMessage: () -> String
    ) {
        guard isEnabled() else { return }

        let balloon = isBallooningEnabled()

        if !balloon, let throttleID {
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

        #if DEBUG
        print(lineOut)
        #endif

        if balloon {
            // Legacy balloon behaviour (slow + huge + synchronous).
            appendLegacyDefaultsBlocking(lineOut)

            // Mirror to file so file-based viewers still show something.
            ioQueue.async {
                appendLineLocked(lineOut)
            }
        } else {
            // Avoid blocking widget rendering on file I/O.
            ioQueue.async {
                dropLegacyDefaultsLogIfNeededLocked()
                appendLineLocked(lineOut)
            }
        }
    }


    /// Synchronous variant of `appendLazy`.
    ///
    /// This exists for widget render-path diagnostics where the widget host may tear down the
    /// extension process quickly, making async file writes unreliable.
    public static func appendLazySync(
        category: String = "clock",
        throttleID: String? = nil,
        minInterval: TimeInterval = 20.0,
        now: Date = Date(),
        _ makeMessage: () -> String
    ) {
        guard isEnabled() else { return }

        let balloon = isBallooningEnabled()

        if !balloon, let throttleID {
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

        #if DEBUG
        print(lineOut)
        #endif

        if balloon {
            // Legacy balloon behaviour (slow + huge + synchronous).
            appendLegacyDefaultsBlocking(lineOut)
        }

        // Synchronous file write (and legacy cleanup when ballooning is off).
        ioQueue.sync {
            dropLegacyDefaultsLogIfNeededLocked()
            appendLineLocked(lineOut)
        }
    }

    public static func readLines() -> [String] {
        // If ballooning is on, prefer showing the balloon source if it exists.
        if isBallooningEnabled() {
            let defaults = AppGroup.userDefaults
            let raw = (defaults.array(forKey: legacyDefaultsLogKey) as? [String]) ?? []
            if !raw.isEmpty {
                if raw.count <= maxLinesDefault { return raw }
                return Array(raw.suffix(maxLinesDefault))
            }
        }

        return ioQueue.sync {
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

    // MARK: - Balloon backend (legacy UserDefaults array)

    private static func appendLegacyDefaultsBlocking(_ line: String) {
        let defaults = AppGroup.userDefaults

        var lines = (defaults.array(forKey: legacyDefaultsLogKey) as? [String]) ?? []
        lines.append(line)

        // Keep it huge in balloon mode, but still cap so it doesn’t brick settings storage forever.
        if lines.count > 200_000 {
            lines = Array(lines.suffix(200_000))
        }

        defaults.set(lines, forKey: legacyDefaultsLogKey)
        defaults.synchronize()
    }

    private static func dropLegacyDefaultsLogIfNeededLocked() {
        if isBallooningEnabled() { return }
        let defaults = AppGroup.userDefaults
        if defaults.object(forKey: legacyDefaultsLogKey) != nil {
            defaults.removeObject(forKey: legacyDefaultsLogKey)
        }
    }

    // MARK: - File backend append

    private static func appendLineLocked(_ line: String) {
        let url = logFileURL

        // Read existing data (bounded).
        let existing: String = {
            guard FileManager.default.fileExists(atPath: url.path) else { return "" }
            guard let data = try? Data(contentsOf: url) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }()

        var combined = existing
        if !combined.isEmpty, !combined.hasSuffix("\n") {
            combined.append("\n")
        }
        combined.append(line)
        combined.append("\n")

        // Trim if too large.
        if combined.utf8.count > maxBytesDefault {
            let lines = combined.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            let suffix = lines.suffix(maxLinesDefault)
            combined = suffix.joined(separator: "\n") + "\n"
        }

        if let data = combined.data(using: .utf8) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}

// MARK: - WWPhoto logging (must stay, other files depend on it)

public struct WWPhotoLogContext {
    public let widgetKind: String
    public let requestID: String
    public let urlHash: String
    public let isPlaceholder: Bool

    public init(widgetKind: String, requestID: String, urlHash: String, isPlaceholder: Bool) {
        self.widgetKind = widgetKind
        self.requestID = requestID
        self.urlHash = urlHash
        self.isPlaceholder = isPlaceholder
    }
}

public enum WWPhotoDebugLog {

    private static let enabledKey = "WWPhotoDebugLog.enabled"
    private static let logFileName = "WidgetWeaverPhotoDebugLog.txt"

    #if DEBUG
    private static let defaultEnabled: Bool = true
    #else
    private static let defaultEnabled: Bool = false
    #endif

    private static let ioQueue = DispatchQueue(label: "com.conornolan.WidgetWeaver.WWPhotoDebugLog.io", qos: .utility)

    private static let maxBytesDefault: Int = 1024 * 1024
    private static let maxCharsPerLine: Int = 2400
    private static let maxLinesDefault: Int = 12000

    private static var logFileURL: URL {
        AppGroup.containerURL.appendingPathComponent(logFileName, isDirectory: false)
    }

    private static var throttleState = WWThrottleState()

    private struct WWThrottleState {
        private var lastWrite: [String: Date] = [:]

        mutating func shouldLog(id: String, now: Date, minInterval: TimeInterval) -> Bool {
            if minInterval <= 0 { return true }
            if let last = lastWrite[id], now.timeIntervalSince(last) < minInterval {
                return false
            }
            lastWrite[id] = now
            return true
        }

        mutating func reset() {
            lastWrite.removeAll()
        }
    }

    public static func isEnabled() -> Bool {
        let defaults = AppGroup.userDefaults
        if defaults.object(forKey: enabledKey) == nil { return defaultEnabled }
        return defaults.bool(forKey: enabledKey)
    }

    public static func setEnabled(_ enabled: Bool) {
        let defaults = AppGroup.userDefaults
        defaults.set(enabled, forKey: enabledKey)
    }

    public static func appendLazy(
        category: String = "photo",
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

        #if DEBUG
        print(lineOut)
        #endif

        ioQueue.async {
            appendLineLocked(lineOut)
        }
    }

    public static func readLines() -> [String] {
        return ioQueue.sync {
            guard FileManager.default.fileExists(atPath: logFileURL.path) else { return [] }
            guard let data = try? Data(contentsOf: logFileURL) else { return [] }
            guard let text = String(data: data, encoding: .utf8) else { return [] }

            let rawLines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if rawLines.count <= maxLinesDefault { return rawLines }
            return Array(rawLines.suffix(maxLinesDefault))
        }
    }

    public static func clear() {
        ioQueue.sync {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                try? FileManager.default.removeItem(at: logFileURL)
            }
            throttleState.reset()
        }
    }

    private static func timestampString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func appendLineLocked(_ line: String) {
        let url = logFileURL

        let existing: String = {
            guard FileManager.default.fileExists(atPath: url.path) else { return "" }
            guard let data = try? Data(contentsOf: url) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }()

        var combined = existing
        if !combined.isEmpty, !combined.hasSuffix("\n") {
            combined.append("\n")
        }
        combined.append(line)
        combined.append("\n")

        if combined.utf8.count > maxBytesDefault {
            let lines = combined.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            let suffix = lines.suffix(maxLinesDefault)
            combined = suffix.joined(separator: "\n") + "\n"
        }

        if let data = combined.data(using: .utf8) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}

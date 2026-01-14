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
    private static let defaultBalloonEnabled: Bool = true
    #else
    private static let defaultEnabled: Bool = false
    private static let defaultBalloonEnabled: Bool = false
    #endif

    private static let enabledKey = "widgetweaver.clock.debug.log.enabled.v1"

    // DEBUG-only toggle that re-enables the legacy ballooning behaviour.
    private static let balloonEnabledKey = "widgetweaver.clock.debug.log.balloon.enabled.v1"

    // Legacy key used by older builds that stored log lines as a [String] in App Group defaults.
    private static let legacyDefaultsLogKey = "widgetweaver.clock.debug.log.v1"

    private static let logFileName = "WidgetWeaverClockDebugLog.txt"

    /// Hard cap to prevent logs growing without bound in the file backend.
    /// Kept small because this can be written from a widget extension.
    private static let maxBytes: Int = 512 * 1024

    private static let maxLinesDefault: Int = 400
    private static let maxCharsPerLine: Int = 1200

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

        defaults.set(lines, forKey: legacyDefaultsLogKey)
        defaults.synchronize()
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

        // Keep the last maxBytes.
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
        // If ballooning is on, do not delete the balloon source.
        #if DEBUG
        if isBallooningEnabled() { return }
        #endif

        let defaults = AppGroup.userDefaults
        guard defaults.object(forKey: legacyDefaultsLogKey) != nil else { return }

        // Do not migrate large legacy logs; they were a performance footgun.
        defaults.removeObject(forKey: legacyDefaultsLogKey)
    }
}

// MARK: - Photo debug log (budget-safe)

public struct WWPhotoLogContext: Hashable, Sendable {
    public var renderContext: String?
    public var family: String?
    public var template: String?
    public var specID: String?
    public var specName: String?
    public var isAppExtension: Bool?

    public init(
        renderContext: String? = nil,
        family: String? = nil,
        template: String? = nil,
        specID: String? = nil,
        specName: String? = nil,
        isAppExtension: Bool? = nil
    ) {
        self.renderContext = renderContext
        self.family = family
        self.template = template
        self.specID = specID
        self.specName = specName
        self.isAppExtension = isAppExtension
    }

    public func compactFields(maxNameChars: Int = 42) -> String {
        func norm(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        var parts: [String] = []

        if let v = norm(renderContext) { parts.append("ctx=\(v)") }
        if let v = norm(family) { parts.append("family=\(v)") }
        if let v = norm(template) { parts.append("tpl=\(v)") }
        if let v = norm(specID) { parts.append("spec=\(v)") }
        if let v = norm(specName) {
            let singleLine = v.replacingOccurrences(of: "\n", with: " ")
            let safe: String
            if singleLine.count > maxNameChars {
                safe = String(singleLine.prefix(maxNameChars)) + "…"
            } else {
                safe = singleLine
            }
            parts.append("name=\"\(safe)\"")
        }
        if let isAppExtension {
            parts.append("appex=\(isAppExtension ? 1 : 0)")
        }

        if parts.isEmpty { return "" }
        return parts.joined(separator: " ")
    }
}

public enum WWPhotoDebugLog {
    #if DEBUG
    private static let defaultEnabled: Bool = true
    #else
    private static let defaultEnabled: Bool = false
    #endif

    private static let enabledKey = "widgetweaver.photo.debug.log.enabled.v1"
    private static let logFileName = "WidgetWeaverPhotoDebugLog.txt"

    /// Hard cap to prevent logs growing without bound.
    /// Kept small because this can be written from a widget extension.
    private static let maxBytes: Int = 512 * 1024

    private static let maxLinesDefault: Int = 500
    private static let maxCharsPerLine: Int = 1400

    private static var logFileURL: URL {
        AppGroup.containerURL.appendingPathComponent(logFileName)
    }

    private static let ioQueue = DispatchQueue(label: "widgetweaver.photo.debug.log.io")

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

    public static func append(
        _ message: String,
        category: String = "photo",
        throttleID: String? = nil,
        minInterval: TimeInterval = 12.0,
        now: Date = Date(),
        context: WWPhotoLogContext? = nil
    ) {
        appendLazy(category: category, throttleID: throttleID, minInterval: minInterval, now: now, context: context) {
            message
        }
    }

    /// Appends a message if the throttle window allows it.
    /// The closure is only evaluated when a log entry will actually be written.
    public static func appendLazy(
        category: String = "photo",
        throttleID: String? = nil,
        minInterval: TimeInterval = 12.0,
        now: Date = Date(),
        context: WWPhotoLogContext? = nil,
        _ makeMessage: () -> String
    ) {
        guard isEnabled() else { return }

        if let throttleID {
            if !throttleState.shouldLog(id: throttleID, now: now, minInterval: minInterval) {
                return
            }
        }

        let msg = makeMessage().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }

        let ctx = context?.compactFields() ?? ""
        let merged = ctx.isEmpty ? msg : (msg + " " + ctx)

        let ts = timestampString(now)
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.bundle"

        let lineOut: String = {
            var s = "\(ts) [\(category)] [\(bundleID)] \(merged)"
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
        ioQueue.sync {
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

        // Keep the last maxBytes.
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
}

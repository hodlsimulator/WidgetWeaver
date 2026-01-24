//
//  NoiseMixStore.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation
import WidgetKit

public final class NoiseMixStore: @unchecked Sendable {
    public static let shared = NoiseMixStore()

    private let lastMixKey = "NoiseMachine.LastMixState.v1"
    private let resumeOnLaunchKey = "NoiseMachine.ResumeOnLaunch.Enabled.v1"

    private let defaults = AppGroup.userDefaults

    // JSONEncoder/JSONDecoder instances are not safe to share across threads.
    // These helpers create a fresh instance per call.
    @inline(__always)
    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    @inline(__always)
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private let queue = DispatchQueue(label: "NoiseMixStore.queue", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var pendingWorkItem: DispatchWorkItem?
    private var lastSavedDataHash: Int?

    // Widget timeline reloads can be throttled by the system. Coalesce repeated requests.
    private var lastWidgetReloadUptime: TimeInterval = 0
    private let widgetReloadCoalesceSeconds: TimeInterval = 0.30

    private init() {
        queue.setSpecific(key: queueKey, value: 1)
    }

    public func loadLastMix() -> NoiseMixState {
        guard let data = defaults.data(forKey: lastMixKey) else {
            return NoiseMixState.default
        }

        do {
            let decoder = makeDecoder()
            let state = try decoder.decode(NoiseMixState.self, from: data)
            return state.sanitised()
        } catch {
            return NoiseMixState.default
        }
    }

    /// Writes synchronously so widget-triggered AppIntents can reliably reload after a state change.
    public func saveImmediate(_ state: NoiseMixState) {
        let state = state.sanitised()
        performOnQueueSync {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil

            do {
                let encoder = makeEncoder()
                let data = try encoder.encode(state)
                let hash = data.hashValue
                if lastSavedDataHash == hash { return }
                lastSavedDataHash = hash

                defaults.set(data, forKey: lastMixKey)
                defaults.synchronize()

                AppGroupDarwinNotificationCenter.post(AppGroupDarwinNotifications.noiseMachineStateDidChange)
                notifyWidgetsCoalesced()
            } catch {
                // ignore
            }
        }
    }

    public func saveThrottled(_ state: NoiseMixState, delay: TimeInterval = 0.22) {
        let state = state.sanitised()
        queue.async { [weak self] in
            guard let self else { return }

            self.pendingWorkItem?.cancel()

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                do {
                    let encoder = self.makeEncoder()
                    let data = try encoder.encode(state)
                    let hash = data.hashValue
                    if self.lastSavedDataHash == hash { return }
                    self.lastSavedDataHash = hash

                    self.defaults.set(data, forKey: self.lastMixKey)
                    self.defaults.synchronize()

                    AppGroupDarwinNotificationCenter.post(AppGroupDarwinNotifications.noiseMachineStateDidChange)
                    self.notifyWidgetsCoalesced()
                } catch {
                    // ignore
                }
            }

            self.pendingWorkItem = work
            self.queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    public func flushPendingWrites() {
        performOnQueueSync {
            guard let item = pendingWorkItem else { return }
            pendingWorkItem = nil
            item.cancel()
            item.perform()
        }
    }

    public func isResumeOnLaunchEnabled() -> Bool {
        defaults.object(forKey: resumeOnLaunchKey) as? Bool ?? false
    }

    public func hasResumeOnLaunchValue() -> Bool {
        defaults.object(forKey: resumeOnLaunchKey) != nil
    }

    public func setResumeOnLaunchEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: resumeOnLaunchKey)
        defaults.synchronize()

        AppGroupDarwinNotificationCenter.post(AppGroupDarwinNotifications.noiseMachineStateDidChange)
        notifyWidgetsCoalesced()
    }

    // MARK: - Internals

    private func performOnQueueSync(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    private func notifyWidgetsCoalesced() {
        // Runs on queue (serial), so no extra synchronisation needed.
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastWidgetReloadUptime < widgetReloadCoalesceSeconds {
            return
        }
        lastWidgetReloadUptime = now

        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }
    }
}

// MARK: - Debug Log (App Group)

public enum NoiseMachineLogLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct NoiseMachineLogEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var level: NoiseMachineLogLevel
    public var origin: String
    public var message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: NoiseMachineLogLevel,
        origin: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.origin = origin
        self.message = message
    }
}

public final class NoiseMachineDebugLogStore: @unchecked Sendable {
    public static let shared = NoiseMachineDebugLogStore()

    private let key = "NoiseMachine.DebugLog.v1"
    private let maxEntries: Int = 250

    private let defaults = AppGroup.userDefaults
    private let queue = DispatchQueue(label: "NoiseMachineDebugLogStore.queue", qos: .utility)

    // JSONEncoder/JSONDecoder instances are not safe to share across threads.
    // These helpers create a fresh instance per call.
    @inline(__always)
    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    @inline(__always)
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private init() {}

    public func append(
        _ level: NoiseMachineLogLevel = .info,
        _ message: String,
        origin: String? = nil
    ) {
        let resolvedOrigin = origin ?? (Bundle.main.bundleIdentifier ?? "unknown.bundle")
        queue.async { [weak self] in
            guard let self else { return }

            var entries = self.loadUnsafe()
            entries.append(NoiseMachineLogEntry(level: level, origin: resolvedOrigin, message: message))
            if entries.count > self.maxEntries {
                entries.removeFirst(entries.count - self.maxEntries)
            }

            do {
                let encoder = self.makeEncoder()
                let data = try encoder.encode(entries)
                self.defaults.set(data, forKey: self.key)
                self.defaults.synchronize()
            } catch {
                // ignore
            }
        }
    }

    public func load() -> [NoiseMachineLogEntry] {
        queue.sync {
            loadUnsafe()
        }
    }

    public func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.defaults.removeObject(forKey: self.key)
            self.defaults.synchronize()
        }
    }

    public func exportText() -> String {
        load().map { entry in
            let date = ISO8601DateFormatter().string(from: entry.timestamp)
            return "\(date) [\(entry.level.rawValue.uppercased())] [\(entry.origin)] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    private func loadUnsafe() -> [NoiseMachineLogEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            let decoder = makeDecoder()
            return try decoder.decode([NoiseMachineLogEntry].self, from: data)
        } catch {
            return []
        }
    }
}

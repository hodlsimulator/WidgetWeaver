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

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let defaults = AppGroup.userDefaults

    private let queue = DispatchQueue(label: "NoiseMixStore.queue", qos: .utility)

    private var pendingWorkItem: DispatchWorkItem?
    private var lastSavedDataHash: Int?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadLastMix() -> NoiseMixState {
        guard let data = defaults.data(forKey: lastMixKey) else {
            return NoiseMixState.default
        }

        do {
            let state = try decoder.decode(NoiseMixState.self, from: data)
            return state.sanitised()
        } catch {
            return NoiseMixState.default
        }
    }

    public func saveImmediate(_ state: NoiseMixState) {
        let state = state.sanitised()
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil

            do {
                let data = try self.encoder.encode(state)
                let hash = data.hashValue
                if self.lastSavedDataHash == hash { return }
                self.lastSavedDataHash = hash

                self.defaults.set(data, forKey: self.lastMixKey)
                self.defaults.synchronize()
                self.notifyWidgets()
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
                    let data = try self.encoder.encode(state)
                    let hash = data.hashValue
                    if self.lastSavedDataHash == hash { return }
                    self.lastSavedDataHash = hash

                    self.defaults.set(data, forKey: self.lastMixKey)
                    self.defaults.synchronize()
                    self.notifyWidgets()
                } catch {
                    // ignore
                }
            }

            self.pendingWorkItem = work
            self.queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    public func flushPendingWrites() {
        queue.sync {
            pendingWorkItem?.perform()
            pendingWorkItem = nil
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
        notifyWidgets()
    }

    private func notifyWidgets() {
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }
    }
}

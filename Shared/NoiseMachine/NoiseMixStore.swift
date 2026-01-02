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
    
    private let lastMixKey = "ww.noisemachine.lastmix.v1"
    private let resumeOnLaunchKey = "ww.noisemachine.resumeOnLaunch.v1"
    
    private let writeQueue = DispatchQueue(label: "ww.noisemachine.store", qos: .utility)
    
    private var pendingWork: DispatchWorkItem?
    private var pendingState: NoiseMixState?
    
    private init() {}
    
    public func loadLastMix() -> NoiseMixState {
        guard let data = AppGroup.userDefaults.data(forKey: lastMixKey) else {
            return .default()
        }
        
        do {
            let decoded = try JSONDecoder().decode(NoiseMixState.self, from: data)
            var s = decoded
            s.normalise()
            return s
        } catch {
            return .default()
        }
    }
    
    public func saveImmediate(_ state: NoiseMixState) {
        let s = state.normalisedWithUpdateTimestamp
        
        writeQueue.sync {
            self.pendingWork?.cancel()
            self.pendingWork = nil
            self.pendingState = nil
            
            self.persist(s)
            self.notifyWidgets()
        }
    }
    
    public func saveThrottled(_ state: NoiseMixState, interval: TimeInterval = 0.25) {
        let s = state.normalisedWithUpdateTimestamp
        
        writeQueue.async {
            self.pendingState = s
            self.pendingWork?.cancel()
            
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let latest = self.pendingState ?? s
                self.pendingWork = nil
                self.pendingState = nil
                self.persist(latest)
            }
            
            self.pendingWork = work
            self.writeQueue.asyncAfter(deadline: .now() + interval, execute: work)
        }
    }
    
    public func flushPending() {
        writeQueue.sync {
            if let state = self.pendingState {
                self.pendingWork?.cancel()
                self.pendingWork = nil
                self.pendingState = nil
                self.persist(state)
            }
        }
    }
    
    public func isResumeOnLaunchEnabled() -> Bool {
        AppGroup.userDefaults.bool(forKey: resumeOnLaunchKey)
    }
    
    public func hasResumeOnLaunchValue() -> Bool {
        AppGroup.userDefaults.object(forKey: resumeOnLaunchKey) != nil
    }
    
    public func setResumeOnLaunchEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: resumeOnLaunchKey)
        AppGroup.userDefaults.synchronize()
        notifyWidgets()
    }
    
    private func persist(_ state: NoiseMixState) {
        do {
            let data = try JSONEncoder().encode(state)
            AppGroup.userDefaults.set(data, forKey: lastMixKey)
            AppGroup.userDefaults.synchronize()
        } catch {
            AppGroup.userDefaults.removeObject(forKey: lastMixKey)
            AppGroup.userDefaults.synchronize()
        }
    }
    
    private func notifyWidgets() {
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }
    }
}

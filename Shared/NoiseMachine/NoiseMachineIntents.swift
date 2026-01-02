//
//  NoiseMachineIntents.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import AppIntents
import Foundation
import WidgetKit

public struct TogglePlayPauseIntent: AppIntent, AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Toggle Noise Playback" }
    public static var description: IntentDescription {
        IntentDescription("Play or pause the Noise Machine without opening the app.")
    }
    
    public static var openAppWhenRun: Bool { false }
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        let store = NoiseMixStore.shared
        var state = store.loadLastMix()
        
        await NoiseMachineController.shared.prepareIfNeeded()
        
        if state.wasPlaying {
            state.wasPlaying = false
            await NoiseMachineController.shared.apply(state: state)
            await NoiseMachineController.shared.pause()
        } else {
            state.wasPlaying = true
            await NoiseMachineController.shared.apply(state: state)
            await NoiseMachineController.shared.play()
        }
        
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }
        
        return .result()
    }
}

public struct StopNoiseIntent: AppIntent, AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Stop Noise" }
    public static var description: IntentDescription {
        IntentDescription("Stop and silence the Noise Machine.")
    }
    
    public static var openAppWhenRun: Bool { false }
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        let store = NoiseMixStore.shared
        var state = store.loadLastMix()
        state.wasPlaying = false
        
        await NoiseMachineController.shared.prepareIfNeeded()
        await NoiseMachineController.shared.apply(state: state)
        await NoiseMachineController.shared.stop()
        
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }
        
        return .result()
    }
}

public struct ToggleSlotIntent: AppIntent, AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Toggle Noise Layer" }
    public static var description: IntentDescription {
        IntentDescription("Enable or disable an individual Noise Machine layer.")
    }
    
    public static var openAppWhenRun: Bool { false }
    
    @Parameter(title: "Layer (1–4)")
    public var layerIndex: Int
    
    public init() {}
    
    public init(layerIndex: Int) {
        self.layerIndex = layerIndex
    }
    
    public func perform() async throws -> some IntentResult {
        let store = NoiseMixStore.shared
        var state = store.loadLastMix()
        
        let idx = max(0, min(NoiseMixState.slotCount - 1, layerIndex - 1))
        if state.slots.indices.contains(idx) {
            state.slots[idx].enabled.toggle()
        }
        
        await NoiseMachineController.shared.prepareIfNeeded()
        await NoiseMachineController.shared.apply(state: state)
        
        if state.wasPlaying {
            await NoiseMachineController.shared.play()
        } else {
            await NoiseMachineController.shared.pause()
        }
        
        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }
        
        return .result()
    }
}

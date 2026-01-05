//
//  NoiseMachineController+State.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import Foundation

extension NoiseMachineController {
    // MARK: - Applying state

    func applyTargets(from state: NoiseMixState, savePolicy: SavePolicy) {
        let state = state.sanitised()

        // The engine is deliberately kept alive for a grace period after pausing to avoid
        // rapid stop/start cycles from widget taps (which can trigger '!pla' / StartIO failures).
        //
        // When paused, keep the output muted so that simply applying state (e.g. when the Noise
        // Machine screen appears) cannot accidentally unmute and start playback.
        let effectiveMasterVolume: Float = state.wasPlaying ? state.masterVolume : 0
        masterMixer?.outputVolume = effectiveMasterVolume

        for idx in 0..<NoiseMixState.slotCount {
            guard slotNodes.indices.contains(idx) else { continue }
            let slot = slotNodes[idx]
            let slotState = state.slots.indices.contains(idx) ? state.slots[idx] : .default
            slot.apply(slot: slotState)
        }

        switch savePolicy {
        case .none:
            break
        case .throttled:
            store.saveThrottled(state)
        case .immediate:
            store.saveImmediate(state)
        }
    }
}

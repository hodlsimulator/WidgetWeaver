//
//  NoiseMachineController+State.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import Foundation

extension NoiseMachineController {
    // MARK: - Applying state

    func applyTargets(
        from state: NoiseMixState,
        savePolicy: SavePolicy,
        masterVolumeOverride: Float? = nil,
        slotVolumeOverrides: [Int: Float] = [:]
    ) {
        let state = state.sanitised()

        // The engine is deliberately kept alive for a grace period after pausing to avoid
        // rapid stop/start cycles from widget taps (which can trigger '!pla' / StartIO failures).
        //
        // When paused, keep the output muted so that simply applying state (e.g. when the Noise
        // Machine screen appears) cannot accidentally unmute and start playback.
        if !state.wasPlaying {
            cancelAllFades()
        }

        if let masterMixer {
            if !state.wasPlaying {
                masterMixer.outputVolume = 0
            } else if let masterVolumeOverride {
                masterMixer.outputVolume = masterVolumeOverride.clamped(to: 0...1)
            } else if masterFadeTask == nil {
                masterMixer.outputVolume = state.masterVolume
            }
        }

        for idx in 0..<NoiseMixState.slotCount {
            guard slotNodes.indices.contains(idx) else { continue }
            let slot = slotNodes[idx]
            let slotState = state.slots.indices.contains(idx) ? state.slots[idx] : .default

            if !slotState.enabled {
                cancelSlotFade(index: idx)
            }

            let volumeBehaviour: NoiseSlotNode.VolumeBehaviour
            if !slotState.enabled {
                volumeBehaviour = .normal
            } else if let forced = slotVolumeOverrides[idx] {
                volumeBehaviour = .force(forced.clamped(to: 0...1))
            } else if slotFadeTasks[idx] != nil {
                volumeBehaviour = .preserve
            } else {
                volumeBehaviour = .normal
            }

            slot.apply(slot: slotState, volumeBehaviour: volumeBehaviour)
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

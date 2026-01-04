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

        masterMixer?.outputVolume = state.masterVolume

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

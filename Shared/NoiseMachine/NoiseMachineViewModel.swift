//
//  NoiseMachineViewModel.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation
import SwiftUI

@MainActor
final class NoiseMachineViewModel: ObservableObject {
    @Published private(set) var state: NoiseMixState
    @Published var resumeOnLaunch: Bool

    private let store = NoiseMixStore.shared

    init() {
        let loaded = store.loadLastMix()
        self.state = loaded
        self.resumeOnLaunch = store.isResumeOnLaunchEnabled()
    }

    func onAppear() {
        Task {
            await NoiseMachineController.shared.prepareIfNeeded()
            await NoiseMachineController.shared.apply(state: store.loadLastMix())
            refreshFromStore()
        }
    }

    func refreshFromStore() {
        state = store.loadLastMix()
        resumeOnLaunch = store.isResumeOnLaunchEnabled()
    }

    func setResumeOnLaunch(_ enabled: Bool) {
        store.setResumeOnLaunchEnabled(enabled)
        resumeOnLaunch = enabled
    }

    func togglePlayPause() {
        Task {
            await NoiseMachineController.shared.togglePlayPause()
            refreshFromStore()
        }
    }

    func stop() {
        Task {
            await NoiseMachineController.shared.stop()
            refreshFromStore()
        }
    }

    func setMasterVolume(_ volume: Float, commit: Bool) {
        state.masterVolume = volume

        Task {
            await NoiseMachineController.shared.setMasterVolume(volume, savePolicy: commit ? .immediate : .throttled)
            if commit {
                await NoiseMachineController.shared.flushPersistence()
            }
            refreshFromStore()
        }
    }

    func setSlotEnabled(_ index: Int, enabled: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].enabled = enabled

        Task {
            await NoiseMachineController.shared.setSlotEnabled(index, enabled: enabled)
            refreshFromStore()
        }
    }

    func setSlotVolume(_ index: Int, volume: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].volume = volume

        Task {
            await NoiseMachineController.shared.setSlotVolume(index, volume: volume, savePolicy: commit ? .immediate : .throttled)
            if commit {
                await NoiseMachineController.shared.flushPersistence()
            }
            refreshFromStore()
        }
    }

    func setSlotColour(_ index: Int, colour: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].colour = colour

        Task {
            await NoiseMachineController.shared.setSlotColour(index, colour: colour, savePolicy: commit ? .immediate : .throttled)
            if commit {
                await NoiseMachineController.shared.flushPersistence()
            }
            refreshFromStore()
        }
    }

    func setSlotLowCut(_ index: Int, hz: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].lowCutHz = hz

        Task {
            await NoiseMachineController.shared.setSlotLowCut(index, hz: hz, savePolicy: commit ? .immediate : .throttled)
            if commit {
                await NoiseMachineController.shared.flushPersistence()
            }
            refreshFromStore()
        }
    }

    func setSlotHighCut(_ index: Int, hz: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].highCutHz = hz

        Task {
            await NoiseMachineController.shared.setSlotHighCut(index, hz: hz, savePolicy: commit ? .immediate : .throttled)
            if commit {
                await NoiseMachineController.shared.flushPersistence()
            }
            refreshFromStore()
        }
    }

    func setSlotEQ(_ index: Int, eq: EQState, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].eq = eq

        Task {
            await NoiseMachineController.shared.setSlotEQ(index, eq: eq, savePolicy: commit ? .immediate : .throttled)
            if commit {
                await NoiseMachineController.shared.flushPersistence()
            }
            refreshFromStore()
        }
    }
}

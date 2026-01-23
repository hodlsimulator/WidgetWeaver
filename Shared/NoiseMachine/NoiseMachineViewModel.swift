//
//  NoiseMachineViewModel.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class NoiseMachineViewModel: ObservableObject {
    @Published private(set) var state: NoiseMixState
    @Published var resumeOnLaunch: Bool
    @Published var audioStatus: String = ""

    private let store = NoiseMixStore.shared

    private var darwinToken: DarwinNotificationToken?
    private var lastExternalRefreshUptime: TimeInterval = 0
    private let externalRefreshCoalesceSeconds: TimeInterval = 0.08

    init() {
        let loaded = store.loadLastMix()
        self.state = loaded
        self.resumeOnLaunch = store.isResumeOnLaunchEnabled()

        darwinToken = DarwinNotificationToken(name: AppGroupDarwinNotifications.noiseMachineStateDidChange) { [weak self] in
            self?.handleExternalStateChange()
        }
    }

    private func handleExternalStateChange() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastExternalRefreshUptime < externalRefreshCoalesceSeconds {
            return
        }
        lastExternalRefreshUptime = now

        let newState = store.loadLastMix()
        let newResumeOnLaunch = store.isResumeOnLaunchEnabled()

        if state != newState {
            state = newState
        }

        if resumeOnLaunch != newResumeOnLaunch {
            resumeOnLaunch = newResumeOnLaunch
        }
    }

    private func reloadNoiseMachineWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
    }

    func onAppear() {
        NoiseMachineDebugLogStore.shared.append(.info, "NoiseMachineViewModel onAppear")
        Task {
            await NoiseMachineController.shared.prepareIfNeeded()
            await NoiseMachineController.shared.apply(state: store.loadLastMix())
            state = await NoiseMachineController.shared.currentMixState()
            await refreshAudioStatus()
            reloadNoiseMachineWidget()
        }
    }

    func refreshFromStore() {
        state = store.loadLastMix()
        resumeOnLaunch = store.isResumeOnLaunchEnabled()
    }

    func refreshFromController() {
        Task {
            state = await NoiseMachineController.shared.currentMixState()
        }
    }

    func refreshAudioStatus() async {
        audioStatus = await NoiseMachineController.shared.debugAudioStatusString()
    }

    func dumpAudioStatus() {
        NoiseMachineDebugLogStore.shared.append(.info, "UI dumpAudioStatus")
        Task {
            await NoiseMachineController.shared.debugDumpAudioStatus(reason: "ui")
            await refreshAudioStatus()
        }
    }

    func rebuildEngine() {
        NoiseMachineDebugLogStore.shared.append(.warning, "UI rebuildEngine")
        Task {
            await NoiseMachineController.shared.debugRebuildEngine()
            state = await NoiseMachineController.shared.currentMixState()
            await refreshAudioStatus()
        }
    }

    func resetToDefaults() {
        NoiseMachineDebugLogStore.shared.append(.warning, "UI resetToDefaults")
        Task {
            await NoiseMachineController.shared.stop()
            await NoiseMachineController.shared.apply(state: .default)
            state = await NoiseMachineController.shared.currentMixState()
            await refreshAudioStatus()
            reloadNoiseMachineWidget()
        }
    }

    func setResumeOnLaunch(_ enabled: Bool) {
        store.setResumeOnLaunchEnabled(enabled)
        resumeOnLaunch = enabled
    }

    func togglePlayPause() {
        NoiseMachineDebugLogStore.shared.append(.info, "UI togglePlayPause")

        state.wasPlaying.toggle()
        state.updatedAt = Date()

        Task {
            await NoiseMachineController.shared.togglePlayPause()
            state = await NoiseMachineController.shared.currentMixState()
            await refreshAudioStatus()
            reloadNoiseMachineWidget()
        }
    }

    func stop() {
        NoiseMachineDebugLogStore.shared.append(.info, "UI stop")

        state.wasPlaying = false
        state.updatedAt = Date()

        Task {
            await NoiseMachineController.shared.stop()
            state = await NoiseMachineController.shared.currentMixState()
            await refreshAudioStatus()
            reloadNoiseMachineWidget()
        }
    }

    func setMasterVolume(_ volume: Float, commit: Bool) {
        state.masterVolume = volume

        Task {
            await NoiseMachineController.shared.setMasterVolume(volume, savePolicy: commit ? .immediate : .none)
            if commit {
                state = await NoiseMachineController.shared.currentMixState()
            }
        }
    }

    func setSlotEnabled(_ index: Int, enabled: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].enabled = enabled

        Task {
            await NoiseMachineController.shared.setSlotEnabled(index, enabled: enabled)
            state = await NoiseMachineController.shared.currentMixState()
            await refreshAudioStatus()
            reloadNoiseMachineWidget()
        }
    }

    func setSlotVolume(_ index: Int, volume: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].volume = volume

        Task {
            await NoiseMachineController.shared.setSlotVolume(index, volume: volume, savePolicy: commit ? .immediate : .none)
            if commit {
                state = await NoiseMachineController.shared.currentMixState()
            }
        }
    }

    func setSlotColour(_ index: Int, colour: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].colour = colour

        Task {
            await NoiseMachineController.shared.setSlotColour(index, colour: colour, savePolicy: commit ? .immediate : .none)
            if commit {
                state = await NoiseMachineController.shared.currentMixState()
            }
        }
    }

    func setSlotLowCut(_ index: Int, hz: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].lowCutHz = hz

        Task {
            await NoiseMachineController.shared.setSlotLowCut(index, hz: hz, savePolicy: commit ? .immediate : .none)
            if commit {
                state = await NoiseMachineController.shared.currentMixState()
            }
        }
    }

    func setSlotHighCut(_ index: Int, hz: Float, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].highCutHz = hz

        Task {
            await NoiseMachineController.shared.setSlotHighCut(index, hz: hz, savePolicy: commit ? .immediate : .none)
            if commit {
                state = await NoiseMachineController.shared.currentMixState()
            }
        }
    }

    func setSlotEQ(_ index: Int, eq: EQState, commit: Bool) {
        guard state.slots.indices.contains(index) else { return }
        state.slots[index].eq = eq

        Task {
            await NoiseMachineController.shared.setSlotEQ(index, eq: eq, savePolicy: commit ? .immediate : .none)
            if commit {
                state = await NoiseMachineController.shared.currentMixState()
            }
        }
    }
}

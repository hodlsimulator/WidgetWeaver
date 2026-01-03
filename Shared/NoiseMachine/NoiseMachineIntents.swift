//
//  NoiseMachineIntents.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import AppIntents
import Foundation
import WidgetKit

public struct PlayNoiseIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Play Noise" }
    public static var description: IntentDescription {
        IntentDescription("Start the Noise Machine without opening the app.")
    }

    public static var openAppWhenRun: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        let origin = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(.info, "Intent PlayNoise", origin: origin)

        await NoiseMachineController.shared.play()
        await NoiseMachineController.shared.debugDumpAudioStatus(reason: "intent-play")

        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }

        return .result()
    }
}

public struct PauseNoiseIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Pause Noise" }
    public static var description: IntentDescription {
        IntentDescription("Pause the Noise Machine without opening the app.")
    }

    public static var openAppWhenRun: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        let origin = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(.info, "Intent PauseNoise", origin: origin)

        await NoiseMachineController.shared.pause()
        await NoiseMachineController.shared.debugDumpAudioStatus(reason: "intent-pause")

        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }

        return .result()
    }
}

public struct TogglePlayPauseIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Toggle Noise Playback" }
    public static var description: IntentDescription {
        IntentDescription("Play or pause the Noise Machine without opening the app.")
    }

    public static var openAppWhenRun: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        let origin = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(.info, "Intent TogglePlayPause", origin: origin)

        await NoiseMachineController.shared.togglePlayPause()
        await NoiseMachineController.shared.debugDumpAudioStatus(reason: "intent-toggle")

        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }

        return .result()
    }
}

public struct StopNoiseIntent: AudioPlaybackIntent {
    public static var title: LocalizedStringResource { "Stop Noise" }
    public static var description: IntentDescription {
        IntentDescription("Stop and silence the Noise Machine.")
    }

    public static var openAppWhenRun: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        let origin = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(.info, "Intent StopNoise", origin: origin)

        await NoiseMachineController.shared.stop()
        await NoiseMachineController.shared.debugDumpAudioStatus(reason: "intent-stop")

        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }

        return .result()
    }
}

public struct ToggleSlotIntent: AudioPlaybackIntent {
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
        let origin = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(.info, "Intent ToggleSlot layerIndex=\(layerIndex)", origin: origin)

        let store = NoiseMixStore.shared
        let state = store.loadLastMix()

        let idx = max(0, min(NoiseMixState.slotCount - 1, layerIndex - 1))
        let enabled = (state.slots.indices.contains(idx) ? !state.slots[idx].enabled : true)

        await NoiseMachineController.shared.setSlotEnabled(idx, enabled: enabled)
        await NoiseMachineController.shared.debugDumpAudioStatus(reason: "intent-toggleSlot")

        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.noiseMachine)
        }

        return .result()
    }
}

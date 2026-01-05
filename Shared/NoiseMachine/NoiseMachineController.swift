//
//  NoiseMachineController.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import AVFoundation
import Foundation

public actor NoiseMachineController {
    public enum SavePolicy: Sendable {
        case none
        case throttled
        case immediate
    }

    public static let shared = NoiseMachineController()

    // Implementation details (kept on the actor so extensions in other files can share state).
    let store = NoiseMixStore.shared

    var engine: AVAudioEngine?
    var masterMixer: AVAudioMixerNode?

    var slotNodes: [NoiseSlotNode] = []

    var didConfigureSession: Bool = false
    var observersInstalled: Bool = false
    var notificationTokens: [NSObjectProtocol] = []

    var isSessionActive: Bool = false
    var pendingSessionDeactivationTask: Task<Void, Never>?
    // Widget-driven App Intents can take noticeably longer to reflect in the widget UI because
    // WidgetKit timeline refreshes are async and throttled. If the engine/session are torn down
    // too quickly after a pause, a subsequent "Play" tap can arrive after teardown and then fail
    // to restart while the app is running in the background (e.g. '!pla' / cannotStartPlaying).
    //
    // Keep the session alive longer so the common "pause → wait for widget to update → play" flow
    // can resume by unmuting instead of forcing a full session re-activation.
    let sessionDeactivationGraceSeconds: TimeInterval = 180.0

    // When pausing via widget taps, immediate stop/start cycles can trigger AVAudioEngine init failures.
    // Keep the engine alive briefly (muted) and only stop after a short idle grace period.
    var pendingEngineStopTask: Task<Void, Never>?
    // Keep the engine alive (muted) for longer after pausing so a resume tap has a high chance of
    // happening before teardown, even if WidgetKit updates lag behind the user’s taps.
    let engineStopGraceSeconds: TimeInterval = 180.0

    var currentState: NoiseMixState = .default
    var isEngineRunning: Bool = false
    var playbackRequestID: UInt64 = 0

    let fallbackSampleRate: Double = 48_000
    let preferredSampleRate: Double = 48_000

    // Preference only; some routes reject very small values with OSStatus -50.
    let preferredIOBufferCandidates: [TimeInterval] = [0.01, 0.02, 0.03]

    var graphSampleRate: Double = 48_000
    var graphChannelCount: AVAudioChannelCount = 2

    private init() {}

    @discardableResult
    func bumpPlaybackRequestID() -> UInt64 {
        playbackRequestID &+= 1
        return playbackRequestID
    }

    // MARK: - Lifecycle

    public func bootstrapOnLaunch() async {
        log("bootstrapOnLaunch")
        let state = store.loadLastMix()
        currentState = state

        await prepareIfNeeded()
        await apply(state: state)

        if store.isResumeOnLaunchEnabled(), state.wasPlaying {
            await play()
        }
    }

    public func prepareIfNeeded() async {
        if engine != nil { return }

        log("prepareIfNeeded: building audio engine")
        await configureSessionIfNeeded()
        buildGraph()
        installObserversIfNeeded()
        applyTargets(from: currentState, savePolicy: .none)
    }

    // MARK: - Public API

    public func currentMixState() async -> NoiseMixState {
        currentState
    }

    public func apply(state: NoiseMixState) async {
        await prepareIfNeeded()
        let s = state.sanitised()
        currentState = s
        applyTargets(from: s, savePolicy: .none)
    }

    public func setMasterVolume(_ v: Float, savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        var s = currentState
        s.masterVolume = v
        s.updatedAt = Date()
        currentState = s
        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotEnabled(_ index: Int, enabled: Bool) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].enabled = enabled
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: .immediate)

        if s.wasPlaying {
            await startEngineIfNeeded(requestID: playbackRequestID)
        }
    }

    public func setSlotVolume(_ index: Int, volume: Float, savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].volume = volume
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotColour(_ index: Int, colour: Float, savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].colour = colour
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotLowCut(_ index: Int, hz: Float, savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].lowCutHz = hz
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotHighCut(_ index: Int, hz: Float, savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].highCutHz = hz
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotEQ(_ index: Int, eq: EQState, savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].eq = eq
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func play() async {
        await prepareIfNeeded()
        log("play")

        cancelPendingSessionDeactivation()
        cancelPendingEngineStop()

        if currentState.wasPlaying, engine?.isRunning == true {
            // Playback already active; ensure the master gain is restored in case the engine was muted for pause.
            masterMixer?.outputVolume = currentState.masterVolume
            isEngineRunning = true
            return
        }

        let requestID = bumpPlaybackRequestID()

        var s = currentState
        s.wasPlaying = true
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: .immediate)
        await startEngineIfNeeded(requestID: requestID)
    }

    public func pause() async {
        await pause(savePolicy: .immediate)
    }

    public func pauseWithoutSaving() async {
        await pause(savePolicy: .none)
    }

    public func stop() async {
        await prepareIfNeeded()
        log("stop")

        cancelPendingEngineStop()
        bumpPlaybackRequestID()

        var s = currentState
        s.wasPlaying = false
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: .immediate)
        await stopEngineSoon()
    }

    public func togglePlayPause() async {
        if currentState.wasPlaying {
            await pause()
        } else {
            await play()
        }
    }

    public func flushPersistence() async {
        store.flushPendingWrites()
    }
}

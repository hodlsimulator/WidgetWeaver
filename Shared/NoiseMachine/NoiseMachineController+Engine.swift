//
//  NoiseMachineController+Engine.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import AVFoundation
import Foundation

extension NoiseMachineController {
    // MARK: - Engine start/stop

    func cancelPendingEngineStop() {
        pendingEngineStopTask?.cancel()
        pendingEngineStopTask = nil
    }

    private func scheduleEngineStopIfIdle(after delay: TimeInterval, requestID: UInt64) {
        cancelPendingEngineStop()

        pendingEngineStopTask = Task { [delay, requestID] in
            let ns = UInt64(max(0, delay) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: ns)
            } catch {
                return
            }

            if Task.isCancelled { return }
            if currentState.wasPlaying { return }
            if playbackRequestID != requestID { return }

            await stopEngineSoon()
        }
    }

    func startEngineIfNeeded(requestID: UInt64) async {
        if engine == nil {
            await prepareIfNeeded()
        }

        cancelPendingEngineStop()

        guard currentState.wasPlaying, playbackRequestID == requestID else { return }
        guard let engine else { return }

        if engine.isRunning {
            isEngineRunning = true
            for slot in slotNodes {
                slot.playIfNeeded()
            }
            return
        }

        do {
            log("startEngineIfNeeded: activating session")
            try await activateSessionIfNeeded(requestID: requestID)

            guard currentState.wasPlaying, playbackRequestID == requestID else { return }

            engine.prepare()

            log("startEngineIfNeeded: starting engine")
            try engine.start()

            guard currentState.wasPlaying, playbackRequestID == requestID else {
                engine.stop()
                isEngineRunning = false
                deactivateSessionIfPossible()
                return
            }

            for slot in slotNodes {
                slot.playIfNeeded()
            }

            isEngineRunning = true
            log("Engine started")
        } catch is CancellationError {
            log("startEngineIfNeeded: cancelled", level: .warning)

            // If this is still the current request, treat a cancellation as a failed start (this
            // can happen when widget-driven App Intents exceed the system’s execution budget).
            if currentState.wasPlaying, playbackRequestID == requestID {
                await handleFailedStart(error: CancellationError())
            }
        } catch {
            isEngineRunning = false
            isSessionActive = false
            logError("AVAudioEngine start", error, level: .error)

            await recoverFromEngineStartFailure(originalError: error, requestID: requestID)

            if self.engine?.isRunning != true,
               currentState.wasPlaying,
               playbackRequestID == requestID {
                await handleFailedStart(error: error)
            }
        }
    }

    private func handleFailedStart(error _: Error) async {
        if currentState.wasPlaying {
            var s = currentState
            s.wasPlaying = false
            s.updatedAt = Date()
            currentState = s
            applyTargets(from: s, savePolicy: .immediate)
        }

        await stopEngineSoon()
    }

    func teardownEngine() {
        cancelPendingEngineStop()

        for slot in slotNodes {
            slot.stop()
        }

        engine?.stop()
        engine?.reset()
        engine = nil
        masterMixer = nil
        slotNodes = []
        isEngineRunning = false
    }

    func rebuildEngine(reason: String) async {
        log("Rebuilding audio engine (\(reason))", level: .warning)
        cancelPendingSessionDeactivation()
        cancelPendingEngineStop()
        isSessionActive = false
        teardownEngine()
        didConfigureSession = false
        await configureSessionIfNeeded()
        buildGraph()
        applyTargets(from: currentState, savePolicy: .none)
    }

    private func recoverFromEngineStartFailure(originalError: Error, requestID: UInt64) async {
        guard currentState.wasPlaying, playbackRequestID == requestID else { return }

        isSessionActive = false

        if isStartIOFailure(originalError) {
            log("Detected StartIO/session failure; hard-resetting audio session", level: .warning)
            await hardResetSessionForStartIOFailure()
        }

        log("Attempting recovery after engine start failure…", level: .warning)

        // Attempt 1: reset engine and retry.
        do {
            engine?.stop()
            engine?.reset()
            isEngineRunning = false

            try await activateSessionIfNeeded(requestID: requestID)
            guard currentState.wasPlaying, playbackRequestID == requestID else { throw CancellationError() }

            engine?.prepare()
            try engine?.start()

            guard currentState.wasPlaying, playbackRequestID == requestID else {
                engine?.stop()
                isEngineRunning = false
                deactivateSessionIfPossible()
                return
            }

            for slot in slotNodes {
                slot.playIfNeeded()
            }

            isEngineRunning = true
            log("Recovery succeeded after engine reset")
            return
        } catch is CancellationError {
            return
        } catch {
            isEngineRunning = false
            isSessionActive = false
            logError("AVAudioEngine restart after reset", error, level: .error)
        }

        guard currentState.wasPlaying, playbackRequestID == requestID else { return }

        // Attempt 2: rebuild graph and retry.
        await rebuildEngine(reason: "engine.start failed")
        do {
            guard let engine else { return }

            try await activateSessionIfNeeded(requestID: requestID)
            guard currentState.wasPlaying, playbackRequestID == requestID else { throw CancellationError() }

            engine.prepare()
            try engine.start()

            guard currentState.wasPlaying, playbackRequestID == requestID else {
                engine.stop()
                isEngineRunning = false
                deactivateSessionIfPossible()
                return
            }

            for slot in slotNodes {
                slot.playIfNeeded()
            }

            isEngineRunning = true
            log("Recovery succeeded after rebuild")
        } catch is CancellationError {
            return
        } catch {
            isEngineRunning = false
            isSessionActive = false
            logError("AVAudioEngine start after rebuild", error, level: .error)
        }
    }

    // MARK: - Playback state

    func pause(savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        log("pause")

        if !currentState.wasPlaying, engine?.isRunning != true {
            applyTargets(from: currentState, savePolicy: savePolicy)
            deactivateSessionIfPossible()
            return
        }

        let requestID = bumpPlaybackRequestID()

        var s = currentState
        s.wasPlaying = false
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)

        // Mute quickly but keep the engine alive briefly to avoid rapid stop/start thrash
        // from widget taps (which can trigger '!pla' / StartIO failures).
        await muteEngineForPause()

        if currentState.wasPlaying {
            return
        }

        scheduleEngineStopIfIdle(after: engineStopGraceSeconds, requestID: requestID)
    }

    private func muteEngineForPause() async {
        guard let engine else { return }

        if !engine.isRunning {
            masterMixer?.outputVolume = 0
            isEngineRunning = false
            deactivateSessionIfPossible()
            return
        }

        await fadeMaster(to: 0, over: 0.06)

        if currentState.wasPlaying {
            masterMixer?.outputVolume = currentState.masterVolume
            isEngineRunning = true
            return
        }

        masterMixer?.outputVolume = 0
        isEngineRunning = true
    }

    func stopEngineSoon() async {
        cancelPendingEngineStop()

        guard let engine else { return }
        if !engine.isRunning {
            isEngineRunning = false
            deactivateSessionIfPossible()
            return
        }

        // Fade down quickly to avoid pops.
        await fadeMaster(to: 0, over: 0.08)

        // Actor methods can interleave at await points. If playback was re-enabled while fading,
        // avoid stopping the engine and restore the intended master volume.
        if currentState.wasPlaying {
            masterMixer?.outputVolume = currentState.masterVolume
            isEngineRunning = true
            return
        }

        for slot in slotNodes {
            slot.stop()
        }

        engine.stop()
        isEngineRunning = false
        deactivateSessionIfPossible()
    }

    private func fadeMaster(to target: Float, over seconds: TimeInterval) async {
        guard let masterMixer else { return }

        let steps = max(1, Int(seconds * 60))
        let start = masterMixer.outputVolume
        let delta = target - start

        for i in 1...steps {
            let t = Float(i) / Float(steps)
            masterMixer.outputVolume = start + delta * t
            let ns = UInt64(1_000_000_000.0 / 60.0)
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    func fadeMaster(
        to target: Float,
        over seconds: TimeInterval,
        requestID: UInt64,
        requiresWasPlaying: Bool,
        abortIfOutputVolumeChangedExternally: Bool
    ) async {
        guard let masterMixer else { return }

        let steps = max(1, Int(seconds * 60))
        let start = masterMixer.outputVolume
        let delta = target - start

        var lastSet = start

        for i in 1...steps {
            if Task.isCancelled { return }
            if playbackRequestID != requestID { return }
            if currentState.wasPlaying != requiresWasPlaying { return }

            if abortIfOutputVolumeChangedExternally {
                let current = masterMixer.outputVolume
                if abs(current - lastSet) > 0.04 {
                    return
                }
            }

            let t = Float(i) / Float(steps)
            let next = start + delta * t
            masterMixer.outputVolume = next
            lastSet = next

            let ns = UInt64(1_000_000_000.0 / 60.0)
            do {
                try await Task.sleep(nanoseconds: ns)
            } catch {
                return
            }
        }
    }
}

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

    func startEngineIfNeeded(requestID: UInt64) async {
        if engine == nil {
            await prepareIfNeeded()
        }

        guard currentState.wasPlaying, playbackRequestID == requestID else { return }
        guard let engine else { return }
        if isEngineRunning, engine.isRunning { return }

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
        for slot in slotNodes {
            slot.stop()
        }

        engine?.stop()
        engine?.reset()
        engine = nil
        masterMixer = nil
        limiter = nil
        slotNodes = []
        isEngineRunning = false
    }

    func rebuildEngine(reason: String) async {
        log("Rebuilding audio engine (\(reason))", level: .warning)
        cancelPendingSessionDeactivation()
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
            log("Detected StartIO failure ('what'); hard-resetting audio session", level: .warning)
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

        bumpPlaybackRequestID()

        var s = currentState
        s.wasPlaying = false
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
        await stopEngineSoon()
    }

    func stopEngineSoon() async {
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
}

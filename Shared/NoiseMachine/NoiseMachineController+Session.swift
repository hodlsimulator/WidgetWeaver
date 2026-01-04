//
//  NoiseMachineController+Session.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import AVFoundation
import AudioToolbox
import Foundation

extension NoiseMachineController {
    // MARK: - Session configuration

    func configureSessionIfNeeded() async {
        if didConfigureSession { return }
        didConfigureSession = configureSessionBestEffort()
    }

    private func configureSessionBestEffort() -> Bool {
        let session = AVAudioSession.sharedInstance()
        log("AVAudioSession configure begin")

        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            log("AVAudioSession setCategory(.playback, options: [.mixWithOthers]) ok")
        } catch {
            // Refuse an exclusive fallback. Plain `.playback` can stop other audio (podcasts/music),
            // which is never acceptable for the Noise Machine.
            logError("AVAudioSession setCategory(.playback, .mixWithOthers)", error, level: .warning)

            // Best-effort mix-safe fallback: duck instead of interrupting.
            do {
                try session.setCategory(.playback, mode: .default, options: [.duckOthers])
                log("AVAudioSession setCategory(.playback, options: [.duckOthers]) ok (mix-safe fallback)", level: .warning)
            } catch {
                logError("AVAudioSession setCategory(.playback, .duckOthers) fallback", error, level: .error)
                return false
            }
        }

        do {
            try session.setPreferredSampleRate(preferredSampleRate)
            log("AVAudioSession setPreferredSampleRate(\(preferredSampleRate)) ok")
        } catch {
            logError("AVAudioSession setPreferredSampleRate", error, level: .warning)
        }

        var didSetIO = false
        for cand in preferredIOBufferCandidates {
            do {
                try session.setPreferredIOBufferDuration(cand)
                log("AVAudioSession setPreferredIOBufferDuration(\(String(format: "%.4f", cand))) ok")
                didSetIO = true
                break
            } catch {
                logError("AVAudioSession setPreferredIOBufferDuration(\(String(format: "%.4f", cand)))", error, level: .warning)
            }
        }
        if !didSetIO {
            log("AVAudioSession IO buffer: using system default", level: .warning)
        }

        log("AVAudioSession configure end")
        return true
    }

    func cancelPendingSessionDeactivation() {
        pendingSessionDeactivationTask?.cancel()
        pendingSessionDeactivationTask = nil
    }

    func deactivateSessionIfPossible() {
        scheduleSessionDeactivationIfIdle(after: sessionDeactivationGraceSeconds)
    }

    private func scheduleSessionDeactivationIfIdle(after delay: TimeInterval) {
        cancelPendingSessionDeactivation()

        pendingSessionDeactivationTask = Task { [delay] in
            let ns = UInt64(max(0, delay) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: ns)
            } catch {
                return
            }

            if Task.isCancelled {
                return
            }

            // Task { } inherits actor context here, so no await needed.
            self.performSessionDeactivationIfIdle()
        }
    }

    private func performSessionDeactivationIfIdle() {
        pendingSessionDeactivationTask = nil

        guard !currentState.wasPlaying else { return }
        guard engine?.isRunning != true else { return }
        guard isSessionActive else { return }

        let session = AVAudioSession.sharedInstance()

        // Avoid deactivating while other audio is playing.
        if session.isOtherAudioPlaying {
            log("AVAudioSession deactivation skipped (otherAudioPlaying=true); will retry later", level: .warning)
            scheduleSessionDeactivationIfIdle(after: max(sessionDeactivationGraceSeconds, 15.0))
            return
        }

        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            isSessionActive = false
            log("AVAudioSession setActive(false) ok")
        } catch {
            logError("AVAudioSession setActive(false)", error, level: .warning)
        }
    }

    private func isTransientSessionActivationError(_ error: Error) -> Bool {
        let ns = error as NSError

        if ns.domain == "AVAudioSessionErrorDomain" {
            if let code = AVAudioSession.ErrorCode(rawValue: ns.code) {
                switch code {
                case .isBusy, .cannotStartPlaying:
                    return true
                default:
                    break
                }
            }
        }

        if ns.domain == NSOSStatusErrorDomain {
            let status = OSStatus(ns.code)
            switch status {
            case 561015905: // '!pla'
                return true
            case 561017449: // '!pri'
                return true
            case 2003329396: // 'what'
                return true
            default:
                return false
            }
        }

        return false
    }

    func isStartIOFailure(_ error: Error) -> Bool {
        let ns = error as NSError

        // In practice these can show up either when starting IO ("what") or when the output
        // unit fails to initialise because the session is in a bad state ("!pla"/"!pri").
        if ns.code == 2003329396 || ns.code == 561015905 || ns.code == 561017449 {
            return true
        }

        if ns.domain == NSOSStatusErrorDomain {
            let status = OSStatus(ns.code)
            if status == 2003329396 || status == 561015905 || status == 561017449 {
                return true
            }
        }

        return false
    }

    func hardResetSessionForStartIOFailure() async {
        cancelPendingSessionDeactivation()

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            log("AVAudioSession hard reset: setActive(false) ok", level: .warning)
        } catch {
            logError("AVAudioSession hard reset: setActive(false)", error, level: .warning)
        }

        isSessionActive = false
        didConfigureSession = configureSessionBestEffort()

        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    private func activationBackoffSeconds(forAttempt attempt: Int) -> TimeInterval {
        switch attempt {
        case 1: return 0.05
        case 2: return 0.10
        case 3: return 0.20
        case 4: return 0.35
        default: return 0.50
        }
    }

    func activateSessionIfNeeded(requestID: UInt64) async throws {
        cancelPendingSessionDeactivation()

        guard currentState.wasPlaying, playbackRequestID == requestID else {
            throw CancellationError()
        }

        let session = AVAudioSession.sharedInstance()

        if !didConfigureSession {
            didConfigureSession = configureSessionBestEffort()
        }

        if !didConfigureSession {
            throw NSError(
                domain: "NoiseMachine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Audio session category configuration failed"]
            )
        }

        var lastError: Error?

        let maxAttempts = 4

        for attempt in 1...maxAttempts {
            guard currentState.wasPlaying, playbackRequestID == requestID else {
                throw CancellationError()
            }

            do {
                if attempt > 1 {
                    didConfigureSession = configureSessionBestEffort()
                }

                // Never switch to an exclusive category while other audio is playing. If the audio
                // system is in a bad state (e.g. after another audio app was force-quit) and we
                // cannot activate with mixing, fail instead of stopping the user’s podcast/music.
                try session.setActive(true, options: [])
                isSessionActive = true
                log("AVAudioSession setActive(true) ok (attempt=\(attempt) sr=\(String(format: "%.1f", session.sampleRate)) io=\(String(format: "%.4f", session.ioBufferDuration)))")
                return
            } catch {
                lastError = error
                isSessionActive = false

                let level: NoiseMachineLogLevel = (attempt == maxAttempts) ? .error : .warning
                logError("AVAudioSession setActive(true) attempt \(attempt)", error, level: level)

                guard attempt < maxAttempts, isTransientSessionActivationError(error) else { break }

                let delay = activationBackoffSeconds(forAttempt: attempt)
                let ns = UInt64(delay * 1_000_000_000)

                do {
                    try await Task.sleep(nanoseconds: ns)
                } catch {
                    throw CancellationError()
                }
            }
        }

        throw lastError ?? NSError(
            domain: "NoiseMachine",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Audio session activation failed"]
        )
    }
}

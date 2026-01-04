//
//  NoiseMachineController+Observers.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import AVFoundation
import Foundation

extension NoiseMachineController {
    func installObserversIfNeeded() {
        if observersInstalled { return }
        observersInstalled = true

        let nc = NotificationCenter.default

        notificationTokens.append(
            nc.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { n in
                let typeRaw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                Task {
                    await NoiseMachineController.shared.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
                }
            }
        )

        notificationTokens.append(
            nc.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { n in
                let reasonRaw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                Task {
                    await NoiseMachineController.shared.handleRouteChange(reasonRaw: reasonRaw)
                }
            }
        )

        notificationTokens.append(
            nc.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task {
                    await NoiseMachineController.shared.handleMediaServicesReset()
                }
            }
        )
    }

    // MARK: - Notifications

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) async {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            log("AVAudioSession interruption began", level: .warning)
            isEngineRunning = false
            isSessionActive = false
            engine?.pause()
            for slot in slotNodes { slot.stop() }

        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            log("AVAudioSession interruption ended (shouldResume=\(opts.contains(.shouldResume)))", level: .warning)

            isSessionActive = false
            if currentState.wasPlaying, opts.contains(.shouldResume) {
                await startEngineIfNeeded(requestID: playbackRequestID)
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) async {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

        log("AVAudioSession routeChange reason=\(reason.rawValue)", level: .warning)

        // Route changes can make an engine stop or leave the graph using a stale hardware format.
        // Rebuild even if currently paused so the next widget play has a clean, route-matched graph.
        isEngineRunning = false
        isSessionActive = false

        await rebuildEngine(reason: "routeChange(\(reason.rawValue))")

        if currentState.wasPlaying {
            await startEngineIfNeeded(requestID: playbackRequestID)
        }
    }

    private func handleMediaServicesReset() async {
        log("AVAudioSession mediaServicesWereReset", level: .warning)
        observersInstalled = false
        notificationTokens.removeAll()
        teardownEngine()
        didConfigureSession = false
        isSessionActive = false
        await prepareIfNeeded()

        if currentState.wasPlaying {
            await startEngineIfNeeded(requestID: playbackRequestID)
        }
    }
}

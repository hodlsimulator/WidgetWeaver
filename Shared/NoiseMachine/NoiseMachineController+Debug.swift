//
//  NoiseMachineController+Debug.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import AVFoundation
import AudioToolbox
import Foundation

extension NoiseMachineController {
    // MARK: - Debug

    func log(_ message: String, level: NoiseMachineLogLevel = .info) {
        let bundle = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(level, message, origin: bundle)

        #if DEBUG
        print("[NoiseMachine][\(bundle)] \(message)")
        #endif
    }

    func logError(_ context: String, _ error: Error, level: NoiseMachineLogLevel = .error) {
        let bundle = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        let ns = error as NSError

        if ns.domain == NSOSStatusErrorDomain {
            let status = OSStatus(ns.code)
            let hex = String(format: "0x%08X", UInt32(bitPattern: status))
            let fourcc = Self.fourCCString(status).map { "'\($0)'" } ?? "n/a"
            let msg = "\(context): OSStatus \(status) (\(hex), \(fourcc)) \(ns.localizedDescription)"
            NoiseMachineDebugLogStore.shared.append(level, msg, origin: bundle)

            #if DEBUG
            print("[NoiseMachine][\(bundle)] \(msg)")
            #endif
        } else {
            let msg = "\(context): \(ns.domain) \(ns.code) \(ns.localizedDescription)"
            NoiseMachineDebugLogStore.shared.append(level, msg, origin: bundle)

            #if DEBUG
            print("[NoiseMachine][\(bundle)] \(msg)")
            #endif
        }
    }

    private static func fourCCString(_ status: OSStatus) -> String? {
        let n = UInt32(bitPattern: status)
        let bytes: [UInt8] = [
            UInt8((n >> 24) & 0xFF),
            UInt8((n >> 16) & 0xFF),
            UInt8((n >> 8) & 0xFF),
            UInt8(n & 0xFF)
        ]
        guard bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    // MARK: - Debugging / Diagnostics

    public func debugDumpAudioStatus(reason: String) async {
        let snap = await debugSnapshot()
        log("Debug snapshot (\(reason)):\n\(snap)")
    }

    public func debugAudioStatusString() async -> String {
        await debugSnapshot()
    }

    private func debugSnapshot() async -> String {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        let enabled = currentState.slots.enumerated().filter { $0.element.enabled }.map { $0.offset + 1 }
        let layerVols = currentState.slots.enumerated().map { "L\($0.offset + 1)=\(String(format: "%.2f", $0.element.volume))" }.joined(separator: " ")

        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
        let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }

        let fmt = "time=\(ISO8601DateFormatter().string(from: Date()))\n" +
        "engineExists=\(engine != nil) engineRunning=\(engine?.isRunning == true) internalFlag=\(isEngineRunning)\n" +
        "graph sr=\(String(format: "%.1f", graphSampleRate)) ch=\(graphChannelCount)\n" +
        "sessionCategory=\(session.category.rawValue) mode=\(session.mode.rawValue)\n" +
        "sampleRate=\(String(format: "%.1f", session.sampleRate)) preferred=\(String(format: "%.1f", session.preferredSampleRate))\n" +
        "ioBuffer=\(String(format: "%.4f", session.ioBufferDuration)) preferred=\(String(format: "%.4f", session.preferredIOBufferDuration))\n" +
        "outputVolume=\(String(format: "%.2f", session.outputVolume)) otherAudioPlaying=\(session.isOtherAudioPlaying)\n" +
        "routeOutputs=\(outputs) routeInputs=\(inputs)\n" +
        "state.wasPlaying=\(currentState.wasPlaying) master=\(String(format: "%.2f", currentState.masterVolume)) enabledSlots=\(enabled) \(layerVols)"

        return fmt
    }

    public func debugRebuildEngine() async {
        await rebuildEngine(reason: "manual")
        if currentState.wasPlaying {
            await startEngineIfNeeded(requestID: playbackRequestID)
        }
    }
}

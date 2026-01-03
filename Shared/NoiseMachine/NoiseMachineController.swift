//
//  NoiseMachineController.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import AVFoundation
import AudioToolbox
import Foundation

public actor NoiseMachineController {
    public enum SavePolicy: Sendable {
        case none
        case throttled
        case immediate
    }

    public static let shared = NoiseMachineController()

    private let store = NoiseMixStore.shared

    private var engine: AVAudioEngine?
    private var masterMixer: AVAudioMixerNode?
    private var limiter: AVAudioUnitEffect?

    private var slotNodes: [NoiseSlotNode] = []

    private var didConfigureSession: Bool = false
    private var observersInstalled: Bool = false
    private var notificationTokens: [NSObjectProtocol] = []

    private var currentState: NoiseMixState = .default
    private var isEngineRunning: Bool = false

    private let fallbackSampleRate: Double = 48_000
    private let preferredSampleRate: Double = 48_000

    // Preference only; some routes reject very small values with OSStatus -50.
    private let preferredIOBufferCandidates: [TimeInterval] = [0.01, 0.02, 0.03]

    private var graphSampleRate: Double = 48_000
    private var graphChannelCount: AVAudioChannelCount = 2

    private init() {}

    // MARK: - Debug

    private func log(_ message: String, level: NoiseMachineLogLevel = .info) {
        let bundle = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(level, message, origin: bundle)

        #if DEBUG
        print("[NoiseMachine][\(bundle)] \(message)")
        #endif
    }

    private func logError(_ context: String, _ error: Error, level: NoiseMachineLogLevel = .error) {
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

        currentState = store.loadLastMix()
        applyTargets(from: currentState, savePolicy: .none)
    }

    // MARK: - Public API

    public func apply(state: NoiseMixState) async {
        await prepareIfNeeded()
        let s = state.sanitised()
        currentState = s
        applyTargets(from: s, savePolicy: .immediate)
    }

    public func play() async {
        await prepareIfNeeded()
        log("play")

        var s = currentState
        s.wasPlaying = true
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: .immediate)
        await startEngineIfNeeded()
    }

    public func pause() async {
        await pause(savePolicy: .immediate)
    }

    public func stop() async {
        await prepareIfNeeded()
        log("stop")

        var s = currentState
        s.wasPlaying = false
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: .immediate)
        await stopEngineSoon()
    }

    public func togglePlayPause() async {
        log("togglePlayPause")
        await prepareIfNeeded()

        if currentState.wasPlaying {
            await pause()
        } else {
            await play()
        }
    }

    public func setSlotEnabled(_ index: Int, enabled: Bool, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].enabled = enabled
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)

        if s.wasPlaying {
            await startEngineIfNeeded()
        }
    }

    public func setSlotVolume(_ index: Int, volume: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].volume = volume
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotColour(_ index: Int, colour: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].colour = colour
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotLowCut(_ index: Int, hz: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].lowCutHz = hz
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotHighCut(_ index: Int, hz: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].highCutHz = hz
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotEQ(_ index: Int, eq: EQState, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard currentState.slots.indices.contains(index) else { return }

        var s = currentState
        s.slots[index].eq = eq
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func setMasterVolume(_ volume: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()

        var s = currentState
        s.masterVolume = volume
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
    }

    public func flushPersistence() async {
        store.flushPendingWrites()
    }

    public func currentMixState() async -> NoiseMixState {
        currentState
    }

    public func debugDumpAudioStatus(reason: String = "manual") async {
        let snapshot = await debugSnapshot()
        log("Debug snapshot (\(reason)):\n\(snapshot)")
    }

    public func debugAudioStatusString() async -> String {
        await debugSnapshot()
    }

    public func debugRebuildEngine() async {
        await rebuildEngine(reason: "manual")
        if currentState.wasPlaying {
            await startEngineIfNeeded()
        }
    }

    // MARK: - Session (best-effort preferences)

    private func configureSessionIfNeeded() async {
        if didConfigureSession { return }
        didConfigureSession = configureSessionBestEffort()
    }

    private func configureSessionBestEffort() -> Bool {
        let session = AVAudioSession.sharedInstance()

        log("AVAudioSession configure begin")

        // Some category options combinations can fail with OSStatus -50 on certain routes.
        // Prefer mixing (so other audio can continue), but fall back to plain playback if needed.
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            log("AVAudioSession setCategory(.playback, options: [.mixWithOthers]) ok")
        } catch {
            logError("AVAudioSession setCategory(.playback, options: [.mixWithOthers])", error, level: .warning)

            do {
                try session.setCategory(.playback, mode: .default)
                log("AVAudioSession setCategory(.playback) ok (no options)")
            } catch {
                logError("AVAudioSession setCategory(.playback)", error, level: .error)
                return false
            }
        }

        // Preferences: useful when accepted, but not required for playback.
        do {
            try session.setPreferredSampleRate(preferredSampleRate)
            log("AVAudioSession setPreferredSampleRate(\(preferredSampleRate)) ok")
        } catch {
            logError("AVAudioSession setPreferredSampleRate(\(preferredSampleRate))", error, level: .warning)
        }

        var didSetBuffer = false
        for d in preferredIOBufferCandidates {
            do {
                try session.setPreferredIOBufferDuration(d)
                log("AVAudioSession setPreferredIOBufferDuration(\(String(format: "%.4f", d))) ok")
                didSetBuffer = true
                break
            } catch {
                logError("AVAudioSession setPreferredIOBufferDuration(\(String(format: "%.4f", d)))", error, level: .warning)
            }
        }
        if !didSetBuffer {
            log("AVAudioSession preferred IO buffer not set (using system default)", level: .warning)
        }

        log("AVAudioSession configure end")
        return true
    }

    private func activateSessionIfNeeded() throws {
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

        do {
            try session.setActive(true, options: [])
            log("AVAudioSession setActive(true) ok (sr=\(String(format: "%.1f", session.sampleRate)) io=\(String(format: "%.4f", session.ioBufferDuration)))")
        } catch {
            logError("AVAudioSession setActive(true)", error, level: .error)
            throw error
        }
    }

    private func deactivateSessionIfPossible() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            log("AVAudioSession setActive(false) ok")
        } catch {
            logError("AVAudioSession setActive(false)", error, level: .warning)
        }
    }

    // MARK: - Graph

    private func buildGraph() {
        let engine = AVAudioEngine()

        let hwFormat = engine.outputNode.inputFormat(forBus: 0)
        let sr = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : fallbackSampleRate
        let ch = hwFormat.channelCount > 0 ? hwFormat.channelCount : 2

        graphSampleRate = sr
        graphChannelCount = ch

        log("buildGraph: hw sr=\(String(format: "%.1f", sr)) ch=\(ch)")

        let outFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: ch)!

        let master = AVAudioMixerNode()
        master.outputVolume = 1.0

        let limiterDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)

        engine.attach(master)
        engine.attach(limiter)

        var slots: [NoiseSlotNode] = []

        for idx in 0..<NoiseMixState.slotCount {
            let slot = NoiseSlotNode(index: idx, sampleRate: sr, channelCount: ch)
            slots.append(slot)

            engine.attach(slot.playerNode)
            engine.attach(slot.eqNode)
            engine.attach(slot.slotMixer)

            engine.connect(slot.playerNode, to: slot.eqNode, format: slot.format)
            engine.connect(slot.eqNode, to: slot.slotMixer, format: slot.format)
            engine.connect(slot.slotMixer, to: master, format: slot.format)

            slot.scheduleIfNeeded()
        }

        engine.connect(master, to: limiter, format: outFormat)
        engine.connect(limiter, to: engine.outputNode, format: outFormat)

        engine.prepare()

        self.engine = engine
        self.masterMixer = master
        self.limiter = limiter
        self.slotNodes = slots
        self.isEngineRunning = false
    }

    private func startEngineIfNeeded() async {
        if engine == nil {
            await prepareIfNeeded()
        }
        guard let engine else { return }
        if isEngineRunning, engine.isRunning { return }

        do {
            log("startEngineIfNeeded: activating session")
            try activateSessionIfNeeded()

            engine.prepare()

            log("startEngineIfNeeded: starting engine")
            try engine.start()

            for slot in slotNodes {
                slot.playIfNeeded()
            }

            isEngineRunning = true
            log("Engine started")
        } catch {
            isEngineRunning = false
            logError("AVAudioEngine start", error, level: .error)
            await recoverFromEngineStartFailure(originalError: error)
        }
    }

    private func teardownEngine() {
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

    private func rebuildEngine(reason: String) async {
        log("Rebuilding audio engine (\(reason))", level: .warning)
        teardownEngine()
        didConfigureSession = false
        await configureSessionIfNeeded()
        buildGraph()
        applyTargets(from: currentState, savePolicy: .none)
    }

    private func recoverFromEngineStartFailure(originalError: Error) async {
        log("Attempting recovery after engine start failure…", level: .warning)

        // Attempt 1: reset engine and retry.
        do {
            engine?.stop()
            engine?.reset()
            isEngineRunning = false
            try activateSessionIfNeeded()
            engine?.prepare()
            try engine?.start()

            for slot in slotNodes {
                slot.playIfNeeded()
            }

            isEngineRunning = true
            log("Recovery succeeded after engine reset")
            return
        } catch {
            isEngineRunning = false
            logError("AVAudioEngine restart after reset", error, level: .error)
        }

        // Attempt 2: rebuild graph and retry.
        await rebuildEngine(reason: "engine.start failed")
        do {
            guard let engine else { return }
            try activateSessionIfNeeded()
            engine.prepare()
            try engine.start()

            for slot in slotNodes {
                slot.playIfNeeded()
            }

            isEngineRunning = true
            log("Recovery succeeded after rebuild")
        } catch {
            isEngineRunning = false
            logError("AVAudioEngine start after rebuild", error, level: .error)
        }
    }

    // MARK: - Playback state

    private func pause(savePolicy: SavePolicy) async {
        await prepareIfNeeded()
        log("pause")

        var s = currentState
        s.wasPlaying = false
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
        await stopEngineSoon()
    }

    private func stopEngineSoon() async {
        guard let engine else { return }
        if !engine.isRunning {
            isEngineRunning = false
            deactivateSessionIfPossible()
            return
        }

        // Fade down quickly to avoid pops.
        await fadeMaster(to: 0, over: 0.08)

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

    // MARK: - Applying state

    private func applyTargets(from state: NoiseMixState, savePolicy: SavePolicy) {
        let state = state.sanitised()

        switch savePolicy {
        case .none:
            break
        case .throttled:
            store.saveThrottled(state)
        case .immediate:
            store.saveImmediate(state)
        }

        masterMixer?.outputVolume = state.masterVolume

        for idx in 0..<min(slotNodes.count, state.slots.count) {
            slotNodes[idx].apply(slot: state.slots[idx])
        }
    }

    // MARK: - Observers

    private func installObserversIfNeeded() {
        if observersInstalled { return }
        observersInstalled = true

        let nc = NotificationCenter.default

        let interruptionToken = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { await NoiseMachineController.shared.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw) }
        }

        let routeChangeToken = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { await NoiseMachineController.shared.handleRouteChange(reasonRaw: reasonRaw) }
        }

        let lostToken = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await NoiseMachineController.shared.handleMediaServicesLost() }
        }

        let resetToken = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await NoiseMachineController.shared.handleMediaServicesReset() }
        }

        notificationTokens = [interruptionToken, routeChangeToken, lostToken, resetToken]
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) async {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            log("AVAudioSession interruption began", level: .warning)
            isEngineRunning = false

        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            log("AVAudioSession interruption ended (shouldResume=\(opts.contains(.shouldResume)))", level: .warning)

            if currentState.wasPlaying, opts.contains(.shouldResume) {
                await startEngineIfNeeded()
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) async {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

        log("AVAudioSession route change reason=\(reason.rawValue)", level: .warning)

        if currentState.wasPlaying {
            await startEngineIfNeeded()
        }
    }

    private func handleMediaServicesLost() async {
        log("AVAudioSession media services were lost", level: .warning)
        isEngineRunning = false
        teardownEngine()
    }

    private func handleMediaServicesReset() async {
        log("AVAudioSession media services were reset", level: .warning)
        isEngineRunning = false
        teardownEngine()
        didConfigureSession = false
        await prepareIfNeeded()

        if currentState.wasPlaying {
            await startEngineIfNeeded()
        }
    }

    // MARK: - Debug Snapshot

    private func debugSnapshot() async -> String {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
        let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }

        var enabledSlots: [Int] = []
        for idx in 0..<NoiseMixState.slotCount {
            if currentState.slots[idx].enabled { enabledSlots.append(idx + 1) }
        }

        let lines: [String] = [
            "time=\(ISO8601DateFormatter().string(from: Date()))",
            "engineExists=\(engine != nil) engineRunning=\(engine?.isRunning == true) internalFlag=\(isEngineRunning)",
            "graph sr=\(String(format: "%.1f", graphSampleRate)) ch=\(graphChannelCount)",
            "sessionCategory=\(session.category.rawValue) mode=\(session.mode.rawValue)",
            "sampleRate=\(String(format: "%.1f", session.sampleRate)) preferred=\(String(format: "%.1f", session.preferredSampleRate))",
            "ioBuffer=\(String(format: "%.4f", session.ioBufferDuration)) preferred=\(String(format: "%.4f", session.preferredIOBufferDuration))",
            "outputVolume=\(String(format: "%.2f", session.outputVolume)) otherAudioPlaying=\(session.isOtherAudioPlaying)",
            "routeOutputs=\(outputs) routeInputs=\(inputs)",
            "state.wasPlaying=\(currentState.wasPlaying) master=\(String(format: "%.2f", currentState.masterVolume)) enabledSlots=\(enabledSlots) L1=\(String(format: "%.2f", currentState.slots[0].volume)) L2=\(String(format: "%.2f", currentState.slots[1].volume)) L3=\(String(format: "%.2f", currentState.slots[2].volume)) L4=\(String(format: "%.2f", currentState.slots[3].volume))"
        ]

        return lines.joined(separator: "\n")
    }
}

private final class NoiseSlotNode {
    let index: Int
    let format: AVAudioFormat

    let playerNode: AVAudioPlayerNode
    let eqNode: AVAudioUnitEQ
    let slotMixer: AVAudioMixerNode

    private var buffer: AVAudioPCMBuffer
    private var hasScheduled: Bool = false

    private var lastEnabled: Bool = false
    private var lastVolume: Float = 0

    init(index: Int, sampleRate: Double, channelCount: AVAudioChannelCount) {
        self.index = index
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!

        self.playerNode = AVAudioPlayerNode()
        self.eqNode = AVAudioUnitEQ(numberOfBands: 5)
        self.slotMixer = AVAudioMixerNode()

        self.slotMixer.outputVolume = 0
        self.eqNode.globalGain = 0

        self.buffer = NoiseSlotNode.makeNoiseBuffer(format: self.format, seconds: 8.0, seed: UInt64(0xC0FFEE) &+ UInt64(index) &* 17)

        configureEQBands()
    }

    func scheduleIfNeeded() {
        guard !hasScheduled else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        hasScheduled = true
    }

    func playIfNeeded() {
        scheduleIfNeeded()
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func stop() {
        playerNode.stop()
        hasScheduled = false
        scheduleIfNeeded()

        if lastEnabled {
            slotMixer.outputVolume = lastVolume
        } else {
            slotMixer.outputVolume = 0
        }
    }

    func apply(slot: NoiseSlotState) {
        lastEnabled = slot.enabled
        lastVolume = slot.volume

        slotMixer.outputVolume = slot.enabled ? slot.volume : 0

        let lowCut = slot.lowCutHz.clamped(to: 10...2000)
        let highCut = slot.highCutHz.clamped(to: 500...20_000)

        let colour = slot.colour.clamped(to: 0...2)
        let tilt = colour * 4.0

        let lowGain = (slot.eq.lowGainDB + tilt).clamped(to: -12...12)
        let midGain = slot.eq.midGainDB.clamped(to: -12...12)
        let highGain = (slot.eq.highGainDB - tilt).clamped(to: -12...12)

        let hp = eqNode.bands[0]
        hp.filterType = .highPass
        hp.frequency = lowCut
        hp.bypass = false

        let lp = eqNode.bands[1]
        lp.filterType = .lowPass
        lp.frequency = highCut
        lp.bypass = false

        let lowShelf = eqNode.bands[2]
        lowShelf.filterType = .lowShelf
        lowShelf.frequency = 160
        lowShelf.gain = lowGain
        lowShelf.bypass = false

        let mid = eqNode.bands[3]
        mid.filterType = .parametric
        mid.frequency = 1200
        mid.bandwidth = 1.0
        mid.gain = midGain
        mid.bypass = false

        let highShelf = eqNode.bands[4]
        highShelf.filterType = .highShelf
        highShelf.frequency = 6000
        highShelf.gain = highGain
        highShelf.bypass = false
    }

    private func configureEQBands() {
        guard eqNode.bands.count == 5 else { return }

        let hp = eqNode.bands[0]
        hp.filterType = .highPass
        hp.frequency = 20
        hp.bypass = false

        let lp = eqNode.bands[1]
        lp.filterType = .lowPass
        lp.frequency = 18_000
        lp.bypass = false

        let lowShelf = eqNode.bands[2]
        lowShelf.filterType = .lowShelf
        lowShelf.frequency = 160
        lowShelf.gain = 0
        lowShelf.bypass = false

        let mid = eqNode.bands[3]
        mid.filterType = .parametric
        mid.frequency = 1200
        mid.bandwidth = 1.0
        mid.gain = 0
        mid.bypass = false

        let highShelf = eqNode.bands[4]
        highShelf.filterType = .highShelf
        highShelf.frequency = 6000
        highShelf.gain = 0
        highShelf.bypass = false
    }

    private static func makeNoiseBuffer(format: AVAudioFormat, seconds: Double, seed: UInt64) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(max(1, Int(format.sampleRate * seconds)))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames

        guard let channels = buffer.floatChannelData else {
            return buffer
        }

        var rng = SeededRandom(seed: seed)
        let chCount = Int(format.channelCount)
        let frameCount = Int(frames)

        for ch in 0..<chCount {
            let out = channels[ch]
            for i in 0..<frameCount {
                let r = rng.nextFloatMinus1To1()
                out[i] = r * 0.22
            }
        }

        return buffer
    }

    private struct SeededRandom {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0xDEADBEEF : seed
        }

        mutating func nextUInt32() -> UInt32 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            let x = z ^ (z >> 31)
            return UInt32(truncatingIfNeeded: x)
        }

        mutating func nextFloatMinus1To1() -> Float {
            let u = Float(nextUInt32()) / Float(UInt32.max)
            return (u * 2.0) - 1.0
        }
    }
}

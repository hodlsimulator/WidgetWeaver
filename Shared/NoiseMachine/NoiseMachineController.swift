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

    private let renderSampleRate: Double = 48_000
    private let preferredIOBufferDuration: TimeInterval = 0.0053

    private init() {}


    // MARK: - Debug

    private func log(_ message: String, level: NoiseMachineLogLevel = .info) {
        let bundle = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        NoiseMachineDebugLogStore.shared.append(level, message, origin: bundle)

        #if DEBUG
        print("[NoiseMachine][\(bundle)] \(message)")
        #endif
    }

    private func logError(_ context: String, _ error: Error) {
        let bundle = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        let ns = error as NSError

        if ns.domain == NSOSStatusErrorDomain {
            let status = OSStatus(ns.code)
            let hex = String(format: "0x%08X", UInt32(bitPattern: status))
            let fourcc = Self.fourCCString(status).map { "'\($0)'" } ?? "n/a"
            let msg = "\(context): OSStatus \(status) (\(hex), \(fourcc)) \(ns.localizedDescription)"
            NoiseMachineDebugLogStore.shared.append(.error, msg, origin: bundle)

            #if DEBUG
            print("[NoiseMachine][\(bundle)] \(msg)")
            #endif
        } else {
            let msg = "\(context): \(ns.domain) \(ns.code) \(ns.localizedDescription)"
            NoiseMachineDebugLogStore.shared.append(.error, msg, origin: bundle)

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
        applyTargets(from: currentState, savePolicy: .immediate)
    }

    // MARK: - Engine API

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

    // MARK: - Session

    private func configureSessionIfNeeded() async {
        if didConfigureSession { return }

        do {
            try configureSession()
            didConfigureSession = true
        } catch {
            didConfigureSession = false
            logError("AVAudioSession configure", error)
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .default,
            options: [
                .mixWithOthers,
                .allowAirPlay,
                .allowBluetoothA2DP
            ]
        )
        try session.setPreferredSampleRate(renderSampleRate)
        try session.setPreferredIOBufferDuration(preferredIOBufferDuration)
    }

    private func activateSessionIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()

        if !didConfigureSession {
            try configureSession()
            didConfigureSession = true
        }

        try session.setActive(true, options: [])
    }

    private func deactivateSessionIfPossible() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            logError("AVAudioSession deactivate", error)
        }
    }

    // MARK: - Graph

    private func buildGraph() {
        let engine = AVAudioEngine()

        let outFormat = AVAudioFormat(standardFormatWithSampleRate: renderSampleRate, channels: 2)!

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
            let slot = NoiseSlotNode(index: idx, sampleRate: renderSampleRate)
            slots.append(slot)

            engine.attach(slot.sourceNode)
            engine.attach(slot.eqNode)

            engine.connect(slot.sourceNode, to: slot.eqNode, format: slot.format)
            engine.connect(slot.eqNode, to: master, format: slot.format)
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
        guard let engine else { return }
        if isEngineRunning, engine.isRunning { return }

        do {
            log("startEngineIfNeeded: activating session")
            try activateSessionIfNeeded()
            engine.prepare()
            log("startEngineIfNeeded: starting engine")
            try engine.start()
            isEngineRunning = true
            log("Engine started")
        } catch {
            isEngineRunning = false
            logError("AVAudioEngine start", error)
            await recoverFromEngineStartFailure(originalError: error)
        }
    }

    private func teardownEngine() {
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
        applyTargets(from: currentState, savePolicy: .immediate)
    }

    private func recoverFromEngineStartFailure(originalError: Error) async {
        log("Attempting recovery after engine start failure…", level: .warning)

        if let engine {
            engine.stop()
            engine.reset()

            do {
                try activateSessionIfNeeded()
                engine.prepare()
                try engine.start()
                isEngineRunning = true
                log("Recovered: reset + restart", level: .warning)
                return
            } catch {
                logError("AVAudioEngine restart after reset", error)
            }
        }

        await rebuildEngine(reason: "engine.start failed")

        guard let engine else { return }
        do {
            try activateSessionIfNeeded()
            engine.prepare()
            try engine.start()
            isEngineRunning = true
            log("Recovered: rebuild + start", level: .warning)
        } catch {
            isEngineRunning = false
            logError("AVAudioEngine start after rebuild", error)
        }
    }

    private func stopEngineSoon() async {
        guard let engine else { return }

        if !engine.isRunning {
            isEngineRunning = false
            deactivateSessionIfPossible()
            return
        }

        for slot in slotNodes {
            slot.generator.setTargetGain(0)
        }

        try? await Task.sleep(nanoseconds: 70_000_000)

        engine.stop()
        engine.reset()
        isEngineRunning = false
        deactivateSessionIfPossible()
    }

    private func pause(savePolicy: SavePolicy) async {
        await prepareIfNeeded()

        var s = currentState
        s.wasPlaying = false
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: savePolicy)
        await stopEngineSoon()
    }

    // MARK: - Apply targets

    private func applyTargets(from state: NoiseMixState, savePolicy: SavePolicy) {
        let s = state.sanitised()

        for idx in 0..<NoiseMixState.slotCount {
            guard s.slots.indices.contains(idx),
                  slotNodes.indices.contains(idx) else { continue }

            let slot = s.slots[idx]
            let gain: Float = (s.wasPlaying && slot.enabled) ? (slot.volume * s.masterVolume) : 0

            let node = slotNodes[idx]
            node.generator.setTargetGain(gain)
            node.generator.setTargetColour(slot.colour)
            node.generator.setTargetLowCutHz(slot.lowCutHz)
            node.generator.setTargetHighCutHz(slot.highCutHz)

            node.applyEQ(slot.eq.sanitised())
        }

        var toSave = s
        toSave.updatedAt = Date()

        switch savePolicy {
        case .none:
            break
        case .immediate:
            store.saveImmediate(toSave)
        case .throttled:
            store.saveThrottled(toSave)
        }
    }

    // MARK: - Observers (Sendable-safe)

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { @Sendable note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt

            Task {
                await NoiseMachineController.shared.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }

        let routeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { @Sendable note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task {
                await NoiseMachineController.shared.handleRouteChange(reasonRaw: reasonRaw)
            }
        }

        let mediaLostToken = center.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: session,
            queue: nil
        ) { @Sendable _ in
            Task {
                await NoiseMachineController.shared.handleMediaServicesWereLost()
            }
        }

        let mediaResetToken = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: nil
        ) { @Sendable _ in
            Task {
                await NoiseMachineController.shared.handleMediaServicesWereReset()
            }
        }

        let configToken = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { @Sendable _ in
            Task {
                await NoiseMachineController.shared.handleEngineConfigurationChange()
            }
        }

        notificationTokens.append(interruptionToken)
        notificationTokens.append(routeToken)
        notificationTokens.append(mediaLostToken)
        notificationTokens.append(mediaResetToken)
        notificationTokens.append(configToken)
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) async {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            await pause(savePolicy: .immediate)

        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            if opts.contains(.shouldResume), currentState.wasPlaying {
                await play()
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) async {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

        switch reason {
        case .newDeviceAvailable,
             .oldDeviceUnavailable,
             .routeConfigurationChange:
            if currentState.wasPlaying {
                await startEngineIfNeeded()
            }

        default:
            break
        }
    }

    private func handleEngineConfigurationChange() async {
        if currentState.wasPlaying {
            await startEngineIfNeeded()
        }
    }


    private func handleMediaServicesWereLost() async {
        log("AVAudioSession media services were lost", level: .warning)
        teardownEngine()
        didConfigureSession = false
    }

    private func handleMediaServicesWereReset() async {
        log("AVAudioSession media services were reset", level: .warning)
        await rebuildEngine(reason: "mediaServicesWereReset")
        if currentState.wasPlaying {
            await startEngineIfNeeded()
        }
    }
}

// MARK: - Debug snapshot

private extension NoiseMachineController {
    func debugSnapshot() async -> String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let inputs = session.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")

        let engineExists = engine != nil
        let engineRunning = engine?.isRunning ?? false

        let enabledSlots = currentState.slots.enumerated().filter { $0.element.enabled }.map { "\($0.offset + 1)" }.joined(separator: ",")
        let vols = currentState.slots.enumerated().map { idx, slot in
            "L\(idx + 1)=\(String(format: "%.2f", slot.volume))"
        }.joined(separator: " ")

        var lines: [String] = []
        lines.append("time=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("engineExists=\(engineExists) engineRunning=\(engineRunning) internalFlag=\(isEngineRunning)")
        lines.append("sessionCategory=\(session.category.rawValue) mode=\(session.mode.rawValue)")
        lines.append(String(format: "sampleRate=%.1f preferred=%.1f", session.sampleRate, session.preferredSampleRate))
        lines.append(String(format: "ioBuffer=%.4f preferred=%.4f", session.ioBufferDuration, session.preferredIOBufferDuration))
        lines.append(String(format: "outputVolume=%.2f otherAudioPlaying=\(session.isOtherAudioPlaying)", session.outputVolume))
        lines.append("routeOutputs=[\(outputs)] routeInputs=[\(inputs)]")
        lines.append("state.wasPlaying=\(currentState.wasPlaying) master=\(String(format: "%.2f", currentState.masterVolume)) enabledSlots=[\(enabledSlots)] \(vols)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Slot node

private final class NoiseSlotNode {
    let index: Int
    let format: AVAudioFormat

    let generator: NoiseSlotGenerator
    let sourceNode: AVAudioSourceNode
    let eqNode: AVAudioUnitEQ

    init(index: Int, sampleRate: Double) {
        self.index = index
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let gen = NoiseSlotGenerator(sampleRate: Float(sampleRate), seed: UInt64(0x9E3779B97F4A7C15 &+ UInt64(index &* 101)))
        self.generator = gen

        self.sourceNode = AVAudioSourceNode(format: self.format) { _, _, frameCount, audioBufferList in
            gen.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }

        let eq = AVAudioUnitEQ(numberOfBands: 3)
        eq.globalGain = 0

        let low = eq.bands[0]
        low.filterType = .lowShelf
        low.frequency = 180
        low.bandwidth = 1.0
        low.gain = 0
        low.bypass = false

        let mid = eq.bands[1]
        mid.filterType = .parametric
        mid.frequency = 1_000
        mid.bandwidth = 1.0
        mid.gain = 0
        mid.bypass = false

        let high = eq.bands[2]
        high.filterType = .highShelf
        high.frequency = 8_000
        high.bandwidth = 1.0
        high.gain = 0
        high.bypass = false

        self.eqNode = eq
    }

    func applyEQ(_ eq: EQState) {
        eqNode.bands[0].gain = eq.lowGainDB
        eqNode.bands[1].gain = eq.midGainDB
        eqNode.bands[2].gain = eq.highGainDB
    }
}

// MARK: - Procedural generator

private final class NoiseSlotGenerator: @unchecked Sendable {
    private let sampleRate: Float
    private var rng: SplitMix64

    private var pink = PinkNoiseState()
    private var brown: Float = 0

    private var hpLP: Float = 0
    private var lp: Float = 0

    private var currentGain: Float = 0
    private var currentColour: Float = 0
    private var currentLowCutHz: Float = 20
    private var currentHighCutHz: Float = 18_000

    private var targetGain = AtomicFloat(0)
    private var targetColour = AtomicFloat(0)
    private var targetLowCutHz = AtomicFloat(20)
    private var targetHighCutHz = AtomicFloat(18_000)

    init(sampleRate: Float, seed: UInt64) {
        self.sampleRate = sampleRate
        self.rng = SplitMix64(seed: seed == 0 ? 0x123456789ABCDEF : seed)
    }

    func setTargetGain(_ gain: Float) {
        targetGain.store(gain)
    }

    func setTargetColour(_ colour: Float) {
        targetColour.store(max(0, min(2, colour)))
    }

    func setTargetLowCutHz(_ hz: Float) {
        targetLowCutHz.store(max(10, min(2_000, hz)))
    }

    func setTargetHighCutHz(_ hz: Float) {
        targetHighCutHz.store(max(500, min(20_000, hz)))
    }

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let tg = targetGain.load()
        let tc = targetColour.load()
        let tLow = targetLowCutHz.load()
        let tHigh = targetHighCutHz.load()

        let rampFrames = max(1, Int(sampleRate * 0.02))
        let gStep = (tg - currentGain) / Float(rampFrames)
        let cStep = (tc - currentColour) / Float(rampFrames)
        let lowStep = (tLow - currentLowCutHz) / Float(rampFrames)
        let highStep = (tHigh - currentHighCutHz) / Float(rampFrames)

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let left = buffers[0]
        let right = buffers.count > 1 ? buffers[1] : buffers[0]

        let lPtr = left.mData!.assumingMemoryBound(to: Float.self)
        let rPtr = right.mData!.assumingMemoryBound(to: Float.self)

        for i in 0..<frameCount {
            currentGain += gStep
            currentColour += cStep
            currentLowCutHz += lowStep
            currentHighCutHz += highStep

            let white = rng.nextFloatSigned()
            let pinkS = pink.next(white: white)
            brown += white * 0.02
            brown = max(-1, min(1, brown))

            let c = max(0, min(2, currentColour))
            let coloured: Float
            if c <= 1 {
                let mix = c
                coloured = (1 - mix) * white + mix * pinkS
            } else {
                let mix = c - 1
                coloured = (1 - mix) * pinkS + mix * brown
            }

            let hpAlpha = Self.hpAlpha(sampleRate: sampleRate, cutoffHz: currentLowCutHz)
            hpLP = hpAlpha * (hpLP + coloured - lp)

            let lpAlpha = Self.lpAlpha(sampleRate: sampleRate, cutoffHz: currentHighCutHz)
            lp = lp + lpAlpha * (hpLP - lp)

            let out = lp * currentGain
            lPtr[i] = out
            rPtr[i] = out
        }
    }

    private static func lpAlpha(sampleRate: Float, cutoffHz: Float) -> Float {
        let x = 2 * Float.pi * cutoffHz / sampleRate
        return x / (x + 1)
    }

    private static func hpAlpha(sampleRate: Float, cutoffHz: Float) -> Float {
        let x = 2 * Float.pi * cutoffHz / sampleRate
        return 1 / (x + 1)
    }
}

private struct PinkNoiseState {
    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var b3: Float = 0
    private var b4: Float = 0
    private var b5: Float = 0
    private var b6: Float = 0

    mutating func next(white: Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return pink * 0.11
    }
}

private struct AtomicFloat {
    private var value: Float
    init(_ value: Float) { self.value = value }

    mutating func store(_ newValue: Float) {
        value = newValue
    }

    func load() -> Float {
        value
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextFloatSigned() -> Float {
        let u = next() >> 40
        let f = Float(u) / Float(1 << 24)
        return (f * 2) - 1
    }
}

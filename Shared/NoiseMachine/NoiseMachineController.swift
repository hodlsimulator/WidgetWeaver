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

    // MARK: - Lifecycle

    public func bootstrapOnLaunch() async {
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

        var s = currentState
        s.wasPlaying = true
        s.updatedAt = Date()
        currentState = s

        if !store.hasResumeOnLaunchValue() {
            store.setResumeOnLaunchEnabled(true)
        }

        applyTargets(from: s, savePolicy: .immediate)
        await startEngineIfNeeded()
    }

    public func pause() async {
        await pause(savePolicy: .immediate)
    }

    public func stop() async {
        await prepareIfNeeded()

        var s = currentState
        s.wasPlaying = false
        s.updatedAt = Date()
        currentState = s

        applyTargets(from: s, savePolicy: .immediate)
        await stopEngineSoon()
    }

    public func togglePlayPause() async {
        let s = store.loadLastMix()
        if s.wasPlaying {
            await pause()
        } else {
            await play()
        }
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

    // MARK: - Session

    private func configureSessionIfNeeded() async {
        if didConfigureSession { return }
        didConfigureSession = true

        let session = AVAudioSession.sharedInstance()
        do {
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
            try session.setActive(true, options: [])
        } catch {
            // ignore
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
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
        }
    }

    private func stopEngineSoon() async {
        guard let engine else { return }
        if !engine.isRunning { return }

        for slot in slotNodes {
            slot.generator.setTargetGain(0)
        }

        try? await Task.sleep(nanoseconds: 70_000_000)

        engine.pause()
        isEngineRunning = false
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

        let configToken = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { @Sendable _ in
            Task {
                await NoiseMachineController.shared.handleEngineConfigurationChange()
            }
        }

        notificationTokens.append(interruptionToken)
        notificationTokens.append(routeToken)
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
        targetColour.store(colour)
    }

    func setTargetLowCutHz(_ hz: Float) {
        targetLowCutHz.store(hz)
    }

    func setTargetHighCutHz(_ hz: Float) {
        targetHighCutHz.store(hz)
    }

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        if frameCount <= 0 || buffers.count == 0 { return }

        let gainAlpha = onePoleAlpha(timeConstantSeconds: 0.06)
        let colourAlpha = onePoleAlpha(timeConstantSeconds: 0.12)
        let cutAlpha = onePoleAlpha(timeConstantSeconds: 0.18)

        let tg = targetGain.load()
        let tc = targetColour.load()
        let tl = targetLowCutHz.load()
        let th = targetHighCutHz.load()

        currentGain += (tg - currentGain) * gainAlpha
        currentColour += (tc - currentColour) * colourAlpha
        currentLowCutHz += (tl - currentLowCutHz) * cutAlpha
        currentHighCutHz += (th - currentHighCutHz) * cutAlpha

        let lowCutHz = max(10, min(currentLowCutHz, 2_000))
        let highCutHz = max(500, min(currentHighCutHz, 20_000))
        let lowAlpha = lowCutHz > 20 ? onePoleCutoffAlpha(cutoffHz: lowCutHz) : 0
        let highAlpha = highCutHz < 20_000 ? onePoleCutoffAlpha(cutoffHz: highCutHz) : 0

        let silent = abs(currentGain) < 0.00005

        if silent {
            for b in buffers {
                guard let mData = b.mData else { continue }
                let ptr = mData.assumingMemoryBound(to: Float.self)
                let samples = frameCount * Int(b.mNumberChannels)
                for i in 0..<samples { ptr[i] = 0 }
            }
            return
        }

        if buffers.count == 1 {
            let b = buffers[0]
            let channels = Int(b.mNumberChannels)
            guard let mData = b.mData else { return }
            let ptr = mData.assumingMemoryBound(to: Float.self)

            if channels <= 1 {
                for i in 0..<frameCount {
                    ptr[i] = renderOneSample(lowAlpha: lowAlpha, highAlpha: highAlpha)
                }
            } else {
                for i in 0..<frameCount {
                    let s = renderOneSample(lowAlpha: lowAlpha, highAlpha: highAlpha)
                    let base = i * channels
                    ptr[base] = s
                    ptr[base + 1] = s
                    if channels > 2 {
                        for c in 2..<channels { ptr[base + c] = s }
                    }
                }
            }
        } else {
            guard buffers.count >= 2 else { return }

            let left = buffers[0]
            let right = buffers[1]

            guard let lData = left.mData, let rData = right.mData else { return }
            let lPtr = lData.assumingMemoryBound(to: Float.self)
            let rPtr = rData.assumingMemoryBound(to: Float.self)

            for i in 0..<frameCount {
                let s = renderOneSample(lowAlpha: lowAlpha, highAlpha: highAlpha)
                lPtr[i] = s
                rPtr[i] = s
            }

            if buffers.count > 2 {
                for b in 2..<buffers.count {
                    guard let mData = buffers[b].mData else { continue }
                    let ptr = mData.assumingMemoryBound(to: Float.self)
                    for i in 0..<frameCount { ptr[i] = lPtr[i] }
                }
            }
        }
    }

    private func renderOneSample(lowAlpha: Float, highAlpha: Float) -> Float {
        let white = rng.nextFloatSigned()

        let pinkSample = pink.process(white)
        brown = (brown + white * 0.02) * 0.99
        brown = brown.clamped(to: -1...1)

        let w = white * 0.28
        let p = pinkSample * 0.18
        let b = brown * 0.12

        let c = currentColour.clamped(to: 0...2)
        let mixed: Float
        if c <= 1 {
            mixed = lerp(w, p, t: c)
        } else {
            mixed = lerp(p, b, t: (c - 1))
        }

        var x = mixed

        if lowAlpha > 0 {
            hpLP += lowAlpha * (x - hpLP)
            x = x - hpLP
        }

        if highAlpha > 0 {
            lp += highAlpha * (x - lp)
            x = lp
        }

        return tanhf(x * currentGain)
    }

    private func onePoleAlpha(timeConstantSeconds: Float) -> Float {
        let tau = max(0.001, timeConstantSeconds)
        let a = 1 - expf(-1 / (sampleRate * tau))
        return a.clamped(to: 0...1)
    }

    private func onePoleCutoffAlpha(cutoffHz: Float) -> Float {
        let fc = max(1, cutoffHz)
        return (1 - expf(-2 * Float.pi * fc / sampleRate)).clamped(to: 0...1)
    }

    private func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t.clamped(to: 0...1)
    }
}

private struct PinkNoiseState {
    var b0: Float = 0
    var b1: Float = 0
    var b2: Float = 0
    var b3: Float = 0
    var b4: Float = 0
    var b5: Float = 0
    var b6: Float = 0

    mutating func process(_ white: Float) -> Float {
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

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
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

private struct AtomicFloat {
    private var raw: UInt32

    init(_ value: Float) {
        raw = value.bitPattern
    }

    mutating func store(_ value: Float) {
        raw = value.bitPattern
    }

    func load() -> Float {
        Float(bitPattern: raw)
    }
}

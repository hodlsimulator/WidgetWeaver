//
//  NoiseMachineController.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import AVFoundation
import AudioToolbox
import Darwin
import Foundation

public actor NoiseMachineController {
    public static let shared = NoiseMachineController()

    private let store = NoiseMixStore.shared

    private var engine: AVAudioEngine?
    private var masterMixer: AVAudioMixerNode?
    private var limiter: AVAudioUnitDynamicsProcessor?

    private var slotNodes: [NoiseSlotNode] = []
    private var sessionConfigured: Bool = false
    private var observersInstalled: Bool = false

    private var currentState: NoiseMixState = .default()
    private var isEngineRunning: Bool = false

    private init() {
        currentState = store.loadLastMix()
    }

    public func stateSnapshot() -> NoiseMixState {
        currentState
    }

    public func bootstrapOnLaunch() async {
        await prepareIfNeeded()

        let stored = store.loadLastMix()
        let resume = store.isResumeOnLaunchEnabled()

        await apply(state: stored)

        if resume, stored.wasPlaying {
            await play()
        } else if stored.wasPlaying, !resume {
            var s = stored
            s.wasPlaying = false
            store.saveImmediate(s)
            currentState = s
        }
    }

    public func prepareIfNeeded() async {
        if engine != nil {
            return
        }

        configureSessionIfNeeded()
        buildGraph()
        installObserversIfNeeded()
    }

    public func flushPersistence() async {
        store.flushPending()
    }

    // MARK: - Public control

    public func apply(state: NoiseMixState) async {
        var s = state
        s.normalise()

        currentState = s
        updateGeneratorTargets(from: s, savePolicy: .immediate)
        updateEQFromState(s)
    }

    public func play() async {
        await prepareIfNeeded()

        var s = currentState
        s.wasPlaying = true
        currentState = s

        if !store.hasResumeOnLaunchValue() {
            store.setResumeOnLaunchEnabled(true)
        }

        store.saveImmediate(s)

        do {
            try startEngineIfNeeded()
        } catch {
            return
        }

        updateGeneratorTargets(from: s, savePolicy: .none)
    }

    public func pause() async {
        await pause(savePolicy: .immediate)
    }

    public func stop() async {
        await prepareIfNeeded()

        var s = currentState
        s.wasPlaying = false
        currentState = s
        store.saveImmediate(s)

        updateGeneratorTargets(from: s, savePolicy: .none)
        await stopEngineSoon()
    }

    public func togglePlayPause() async {
        if currentState.wasPlaying {
            await pause()
        } else {
            await play()
        }
    }

    public func setMasterVolume(_ volume: Float, savePolicy: SavePolicy = .throttled) async {
        var s = currentState
        s.masterVolume = volume
        s.normalise()
        currentState = s

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotEnabled(_ index: Int, enabled: Bool) async {
        guard currentState.slots.indices.contains(index) else { return }
        var s = currentState
        s.slots[index].enabled = enabled
        s.normalise()
        currentState = s

        updateGeneratorTargets(from: s, savePolicy: .immediate)
    }

    public func setSlotVolume(_ index: Int, volume: Float, savePolicy: SavePolicy = .throttled) async {
        guard currentState.slots.indices.contains(index) else { return }
        var s = currentState
        s.slots[index].volume = volume
        s.normalise()
        currentState = s

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotColour(_ index: Int, colour: Float, savePolicy: SavePolicy = .throttled) async {
        guard currentState.slots.indices.contains(index) else { return }
        var s = currentState
        s.slots[index].colour = colour
        s.normalise()
        currentState = s

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotLowCut(_ index: Int, hz: Float, savePolicy: SavePolicy = .throttled) async {
        guard currentState.slots.indices.contains(index) else { return }
        var s = currentState
        s.slots[index].lowCutHz = hz
        s.normalise()
        currentState = s

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotHighCut(_ index: Int, hz: Float, savePolicy: SavePolicy = .throttled) async {
        guard currentState.slots.indices.contains(index) else { return }
        var s = currentState
        s.slots[index].highCutHz = hz
        s.normalise()
        currentState = s

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotEQ(_ index: Int, eq: EQState, savePolicy: SavePolicy = .throttled) async {
        guard currentState.slots.indices.contains(index) else { return }
        var s = currentState
        s.slots[index].eq = eq
        s.normalise()
        currentState = s

        updateEQFromState(s)
        persistState(s, savePolicy: savePolicy)
    }

    // MARK: - Persistence

    public enum SavePolicy: Sendable {
        case immediate
        case throttled
        case none
    }

    private func persistState(_ state: NoiseMixState, savePolicy: SavePolicy) {
        switch savePolicy {
        case .immediate:
            store.saveImmediate(state)
        case .throttled:
            store.saveThrottled(state, interval: 0.25)
        case .none:
            break
        }
    }

    // MARK: - AVAudioSession + Graph

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [
                    .mixWithOthers,
                    .allowAirPlay,
                    .allowBluetooth
                ]
            )
            try session.setActive(true, options: [])
            sessionConfigured = true
        } catch {
            sessionConfigured = false
        }
    }

    private func buildGraph() {
        let engine = AVAudioEngine()
        let master = AVAudioMixerNode()
        master.outputVolume = 1.0

        let limiter = AVAudioUnitDynamicsProcessor()
        limiter.threshold = -6
        limiter.headRoom = 3
        limiter.expansionRatio = 1
        limiter.attackTime = 0.001
        limiter.releaseTime = 0.05
        limiter.masterGain = 0

        engine.attach(master)
        engine.attach(limiter)

        let outFormat = engine.outputNode.inputFormat(forBus: 0)

        let slotNodes: [NoiseSlotNode] = (0..<NoiseMixState.slotCount).map { index in
            let node = NoiseSlotNode(index: index, sampleRate: outFormat.sampleRate)
            node.attach(to: engine)
            return node
        }

        for node in slotNodes {
            engine.connect(node.outputNode, to: master, format: node.outputFormat)
        }

        engine.connect(master, to: limiter, format: outFormat)
        engine.connect(limiter, to: engine.outputNode, format: outFormat)

        engine.prepare()

        self.engine = engine
        self.masterMixer = master
        self.limiter = limiter
        self.slotNodes = slotNodes
        self.isEngineRunning = false
    }

    private func startEngineIfNeeded() throws {
        guard let engine else { return }

        if isEngineRunning, engine.isRunning {
            return
        }

        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            buildGraph()
            guard let newEngine = self.engine else { throw error }
            try newEngine.start()
            isEngineRunning = true
        }
    }

    private func stopEngineSoon() async {
        guard let engine else { return }

        for node in slotNodes {
            node.setTargetGain(0)
        }

        try? await Task.sleep(nanoseconds: 90_000_000)

        engine.pause()
        isEngineRunning = false
    }

    // MARK: - Observers

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            Task { await self.handleInterruption(note) }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            Task { await self.handleRouteChange(note) }
        }

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleEngineConfigurationChange() }
        }
    }

    private func handleInterruption(_ note: Notification) async {
        guard let info = note.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            await pause(savePolicy: .immediate)

        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                if currentState.wasPlaying {
                    await play()
                }
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) async {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else {
            return
        }

        switch reason {
        case .newDeviceAvailable,
             .oldDeviceUnavailable,
             .routeConfigurationChange:
            await restartEngineIfNeededForRouteChange()

        default:
            break
        }
    }

    private func handleEngineConfigurationChange() async {
        await restartEngineIfNeededForRouteChange()
    }

    private func restartEngineIfNeededForRouteChange() async {
        guard let engine else { return }

        let shouldKeepPlaying = currentState.wasPlaying

        if engine.isRunning {
            engine.pause()
            isEngineRunning = false
        }

        do {
            try startEngineIfNeeded()
        } catch {
            return
        }

        if shouldKeepPlaying {
            updateGeneratorTargets(from: currentState, savePolicy: .none)
        } else {
            for node in slotNodes {
                node.setTargetGain(0)
            }
        }
    }

    private func pause(savePolicy: SavePolicy) async {
        await prepareIfNeeded()

        var s = currentState
        s.wasPlaying = false
        currentState = s

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
        await stopEngineSoon()
    }

    // MARK: - Parameter application

    private func updateGeneratorTargets(from state: NoiseMixState, savePolicy: SavePolicy) {
        let masterGain = state.masterVolume

        for (i, slot) in state.slots.enumerated() {
            guard slotNodes.indices.contains(i) else { continue }

            let gain = state.wasPlaying && slot.enabled ? (slot.volume * masterGain) : 0
            slotNodes[i].setTargetGain(gain)

            slotNodes[i].setTargetColour(slot.colour)
            slotNodes[i].setTargetLowCut(slot.lowCutHz)
            slotNodes[i].setTargetHighCut(slot.highCutHz)
        }

        persistState(state, savePolicy: savePolicy)
    }

    private func updateEQFromState(_ state: NoiseMixState) {
        for (i, slot) in state.slots.enumerated() {
            guard slotNodes.indices.contains(i) else { continue }
            slotNodes[i].setEQ(slot.eq)
        }
    }
}

// MARK: - Slot node (Noise -> Filters -> EQ -> Mixer)

private final class NoiseSlotNode {
    let index: Int

    private let format: AVAudioFormat
    private let sourceNode: AVAudioSourceNode

    private let eq: AVAudioUnitEQ
    private let generator: NoiseGenerator

    private(set) var outputNode: AVAudioNode
    private(set) var outputFormat: AVAudioFormat

    init(index: Int, sampleRate: Double) {
        self.index = index
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        self.generator = NoiseGenerator(sampleRate: Float(sampleRate), seed: UInt64(0xA11CE + index * 97))

        self.sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            self.generator.render(frames: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }

        self.eq = AVAudioUnitEQ(numberOfBands: 3)
        self.eq.globalGain = 0

        if eq.bands.count >= 3 {
            let low = eq.bands[0]
            low.filterType = .lowShelf
            low.frequency = 200
            low.bandwidth = 1.0
            low.gain = 0
            low.bypass = false

            let mid = eq.bands[1]
            mid.filterType = .parametric
            mid.frequency = 1000
            mid.bandwidth = 1.0
            mid.gain = 0
            mid.bypass = false

            let high = eq.bands[2]
            high.filterType = .highShelf
            high.frequency = 8000
            high.bandwidth = 1.0
            high.gain = 0
            high.bypass = false
        }

        self.outputNode = eq
        self.outputFormat = format
    }

    func attach(to engine: AVAudioEngine) {
        engine.attach(sourceNode)
        engine.attach(eq)

        engine.connect(sourceNode, to: eq, format: format)
        outputNode = eq
        outputFormat = format
    }

    func setTargetGain(_ gain: Float) {
        generator.setTargetGain(gain)
    }

    func setTargetColour(_ colour: Float) {
        generator.setTargetColour(colour)
    }

    func setTargetLowCut(_ hz: Float) {
        generator.setTargetLowCut(hz)
    }

    func setTargetHighCut(_ hz: Float) {
        generator.setTargetHighCut(hz)
    }

    func setEQ(_ eqState: EQState) {
        guard eq.bands.count >= 3 else { return }
        let low = eq.bands[0]
        let mid = eq.bands[1]
        let high = eq.bands[2]

        low.gain = eqState.lowGainDB
        mid.gain = eqState.midGainDB
        high.gain = eqState.highGainDB
    }
}

// MARK: - Render DSP (no allocation / no locks)

private final class NoiseGenerator {
    private let sampleRate: Float

    private var rng: SplitMix64

    private var whiteL: Float = 0
    private var whiteR: Float = 0

    private var pinkL: PinkNoise = .init()
    private var pinkR: PinkNoise = .init()

    private var brownL: BrownNoise = .init()
    private var brownR: BrownNoise = .init()

    private var lowPassL: OnePoleLP = .init()
    private var lowPassR: OnePoleLP = .init()

    private var highPassL: OnePoleHP = .init()
    private var highPassR: OnePoleHP = .init()

    private var currentGain: Float = 0
    private var targetGain: AtomicFloat = .init(0)

    private var currentColour: Float = 1
    private var targetColour: AtomicFloat = .init(1)

    private var currentLowCutHz: Float = 20
    private var targetLowCutHz: AtomicFloat = .init(20)

    private var currentHighCutHz: Float = 18_000
    private var targetHighCutHz: AtomicFloat = .init(18_000)

    init(sampleRate: Float, seed: UInt64) {
        self.sampleRate = sampleRate
        self.rng = SplitMix64(state: seed == 0 ? 0x12345678ABCDEF : seed)
        updateFilterCoefficients()
    }

    func setTargetGain(_ value: Float) {
        targetGain.store(value)
    }

    func setTargetColour(_ value: Float) {
        targetColour.store(value)
    }

    func setTargetLowCut(_ value: Float) {
        targetLowCutHz.store(value)
    }

    func setTargetHighCut(_ value: Float) {
        targetHighCutHz.store(value)
    }

    func render(frames: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard buffers.count > 0 else { return }

        let bufferCount = buffers.count
        let interleavedChannels = bufferCount == 1 ? Int(buffers[0].mNumberChannels) : 0

        let buf0 = buffers[0]
        let ptr0 = buf0.mData!.assumingMemoryBound(to: Float.self)

        let ptr1: UnsafeMutablePointer<Float>?
        if bufferCount > 1 {
            ptr1 = buffers[1].mData!.assumingMemoryBound(to: Float.self)
        } else {
            ptr1 = nil
        }

        for frame in 0..<frames {
            smoothParameters()

            let (outL, outR) = renderStereoSample()

            if bufferCount == 1 {
                if interleavedChannels <= 1 {
                    ptr0[frame] = (outL + outR) * 0.5
                } else {
                    let base = frame * interleavedChannels
                    ptr0[base] = outL
                    if interleavedChannels > 1 {
                        ptr0[base + 1] = outR
                    }
                    if interleavedChannels > 2 {
                        let avg = (outL + outR) * 0.5
                        for c in 2..<interleavedChannels {
                            ptr0[base + c] = avg
                        }
                    }
                }
            } else {
                ptr0[frame] = outL
                ptr1?[frame] = outR

                if bufferCount > 2 {
                    let avg = (outL + outR) * 0.5
                    for b in 2..<bufferCount {
                        let p = buffers[b].mData!.assumingMemoryBound(to: Float.self)
                        p[frame] = avg
                    }
                }
            }
        }
    }

    private func smoothParameters() {
        let smoothing: Float = 1.0 - expf(-1.0 / (sampleRate * 0.06))

        let tg = targetGain.load()
        currentGain += (tg - currentGain) * smoothing

        let tc = targetColour.load()
        currentColour += (tc - currentColour) * smoothing

        let tl = targetLowCutHz.load()
        currentLowCutHz += (tl - currentLowCutHz) * smoothing

        let th = targetHighCutHz.load()
        currentHighCutHz += (th - currentHighCutHz) * smoothing

        updateFilterCoefficients()
    }

    private func updateFilterCoefficients() {
        let lowCut = max(10, min(currentLowCutHz, 10_000))
        let highCut = max(50, min(currentHighCutHz, 20_000))

        let hpCut = min(lowCut, sampleRate * 0.45)
        let lpCut = min(max(highCut, hpCut + 10), sampleRate * 0.45)

        highPassL.setCutoff(hpCut, sampleRate: sampleRate)
        highPassR.setCutoff(hpCut, sampleRate: sampleRate)

        lowPassL.setCutoff(lpCut, sampleRate: sampleRate)
        lowPassR.setCutoff(lpCut, sampleRate: sampleRate)
    }

    private func renderStereoSample() -> (Float, Float) {
        whiteL = rng.nextFloatSigned()
        whiteR = rng.nextFloatSigned()

        let pinkOutL = pinkL.process(whiteL)
        let pinkOutR = pinkR.process(whiteR)

        let brownOutL = brownL.process(whiteL)
        let brownOutR = brownR.process(whiteR)

        let (mixWL, mixWR) = colourMix(whiteL, whiteR, pinkOutL, pinkOutR, brownOutL, brownOutR)

        let hpL = highPassL.process(mixWL)
        let hpR = highPassR.process(mixWR)

        let lpL = lowPassL.process(hpL)
        let lpR = lowPassR.process(hpR)

        let scaledL = softClip(lpL * currentGain)
        let scaledR = softClip(lpR * currentGain)

        return (scaledL, scaledR)
    }

    private func colourMix(
        _ wL: Float,
        _ wR: Float,
        _ pL: Float,
        _ pR: Float,
        _ bL: Float,
        _ bR: Float
    ) -> (Float, Float) {
        let c = max(0, min(currentColour, 2))

        if c <= 1 {
            let t = c
            return (
                wL * (1 - t) + pL * t,
                wR * (1 - t) + pR * t
            )
        } else {
            let t = c - 1
            return (
                pL * (1 - t) + bL * t,
                pR * (1 - t) + bR * t
            )
        }
    }

    private func softClip(_ x: Float) -> Float {
        tanhf(x)
    }
}

private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextFloatSigned() -> Float {
        let u = next() >> 11
        let v = Float(u) / Float(1 << 53)
        return (v * 2) - 1
    }
}

private struct PinkNoise {
    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var b3: Float = 0
    private var b4: Float = 0
    private var b5: Float = 0
    private var b6: Float = 0

    mutating func process(_ white: Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return out * 0.11
    }
}

private struct BrownNoise {
    private var last: Float = 0

    mutating func process(_ white: Float) -> Float {
        last += white * 0.02
        last = max(-1, min(1, last))
        return last * 3.5
    }
}

private struct OnePoleLP {
    private var a0: Float = 0
    private var b1: Float = 0
    private var z1: Float = 0

    mutating func setCutoff(_ hz: Float, sampleRate: Float) {
        let x = expf(-2 * Float.pi * hz / sampleRate)
        b1 = x
        a0 = 1 - x
    }

    mutating func process(_ input: Float) -> Float {
        z1 = input * a0 + z1 * b1
        return z1
    }
}

private struct OnePoleHP {
    private var lp: OnePoleLP = .init()
    private var lastIn: Float = 0

    mutating func setCutoff(_ hz: Float, sampleRate: Float) {
        lp.setCutoff(hz, sampleRate: sampleRate)
    }

    mutating func process(_ input: Float) -> Float {
        let low = lp.process(input)
        let high = input - low + (lastIn - low) * 0
        lastIn = input
        return high
    }
}

private final class AtomicFloat {
    private var raw: UInt32

    init(_ value: Float) {
        raw = value.bitPattern
    }

    func store(_ value: Float) {
        raw = value.bitPattern
    }

    func load() -> Float {
        Float(bitPattern: raw)
    }
}

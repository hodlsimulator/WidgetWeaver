//
//  NoiseMachineController.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import AVFAudio
import AVFoundation
import AudioToolbox
import Darwin
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
    private var isEngineRunning: Bool = false
    private var didConfigureSession: Bool = false

    private var currentState: NoiseMixState = .default

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
        installObservers()
        currentState = store.loadLastMix()
        updateGeneratorTargets(from: currentState, savePolicy: .immediate)
    }

    public func apply(state: NoiseMixState) async {
        await prepareIfNeeded()

        let state = state.sanitised()
        currentState = state

        updateGeneratorTargets(from: state, savePolicy: .immediate)
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

        updateGeneratorTargets(from: s, savePolicy: .immediate)
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

        for slot in slotNodes {
            slot.setTargetEnabled(false)
        }

        updateGeneratorTargets(from: s, savePolicy: .immediate)
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

    // MARK: - Slot controls

    public func setSlotEnabled(_ index: Int, enabled: Bool) async {
        await prepareIfNeeded()
        guard slotNodes.indices.contains(index) else { return }

        var s = currentState
        guard s.slots.indices.contains(index) else { return }

        s.slots[index].enabled = enabled
        s.updatedAt = Date()
        currentState = s

        slotNodes[index].setTargetEnabled(enabled)

        updateGeneratorTargets(from: s, savePolicy: .immediate)
        if s.wasPlaying {
            await startEngineIfNeeded()
        }
    }

    public func setSlotVolume(_ index: Int, volume: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard slotNodes.indices.contains(index) else { return }

        let v = volume.clamped(to: 0...1)

        var s = currentState
        guard s.slots.indices.contains(index) else { return }

        s.slots[index].volume = v
        s.updatedAt = Date()
        currentState = s

        slotNodes[index].setTargetVolume(v)

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotColour(_ index: Int, colour: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard slotNodes.indices.contains(index) else { return }

        let c = colour.clamped(to: 0...2)

        var s = currentState
        guard s.slots.indices.contains(index) else { return }

        s.slots[index].colour = c
        s.updatedAt = Date()
        currentState = s

        slotNodes[index].setTargetColour(c)

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotLowCut(_ index: Int, hz: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard slotNodes.indices.contains(index) else { return }

        let f = hz.clamped(to: 10...2000)

        var s = currentState
        guard s.slots.indices.contains(index) else { return }

        s.slots[index].lowCutHz = f
        if s.slots[index].lowCutHz >= s.slots[index].highCutHz {
            s.slots[index].highCutHz = min(20_000, s.slots[index].lowCutHz + 1000)
        }
        s.updatedAt = Date()
        currentState = s

        slotNodes[index].setTargetLowCutHz(s.slots[index].lowCutHz)

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotHighCut(_ index: Int, hz: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard slotNodes.indices.contains(index) else { return }

        let f = hz.clamped(to: 500...20_000)

        var s = currentState
        guard s.slots.indices.contains(index) else { return }

        s.slots[index].highCutHz = f
        if s.slots[index].lowCutHz >= s.slots[index].highCutHz {
            s.slots[index].lowCutHz = max(10, s.slots[index].highCutHz - 1000)
        }
        s.updatedAt = Date()
        currentState = s

        slotNodes[index].setTargetHighCutHz(s.slots[index].highCutHz)

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setSlotEQ(_ index: Int, eq: EQState, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()
        guard slotNodes.indices.contains(index) else { return }

        let eq = eq.sanitised()

        var s = currentState
        guard s.slots.indices.contains(index) else { return }

        s.slots[index].eq = eq
        s.updatedAt = Date()
        currentState = s

        slotNodes[index].setTargetEQ(eq)

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    public func setMasterVolume(_ volume: Float, savePolicy: SavePolicy = .immediate) async {
        await prepareIfNeeded()

        let v = volume.clamped(to: 0...1)

        var s = currentState
        s.masterVolume = v
        s.updatedAt = Date()
        currentState = s

        masterMixer?.outputVolume = v

        updateGeneratorTargets(from: s, savePolicy: savePolicy)
    }

    // MARK: - Persistence

    public func flushPersistence() async {
        store.flushPendingWrites()
    }

    // MARK: - Audio session / engine graph

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

    private func buildGraph() {
        let engine = AVAudioEngine()

        let outFormat = AVAudioFormat(standardFormatWithSampleRate: renderSampleRate, channels: 2)!

        let master = AVAudioMixerNode()
        master.outputVolume = currentState.masterVolume.clamped(to: 0...1)

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

            engine.attach(slot.outputNode)
            engine.attach(slot.eqNode)

            engine.connect(slot.outputNode, to: slot.eqNode, format: slot.outputFormat)
            engine.connect(slot.eqNode, to: master, format: slot.outputFormat)
        }

        engine.connect(master, to: limiter, format: outFormat)
        engine.connect(limiter, to: engine.outputNode, format: outFormat)

        self.engine = engine
        self.masterMixer = master
        self.limiter = limiter
        self.slotNodes = slots

        updateGeneratorTargets(from: currentState, savePolicy: .immediate)
    }

    private func installObservers() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            Task { await self.handleInterruption(note) }
        }

        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            Task { await self.handleRouteChange(note) }
        }

        center.addObserver(
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
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
        }

        if !shouldKeepPlaying {
            await stopEngineSoon()
        }
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
            slot.setTargetEnabled(false)
            slot.setTargetVolume(0)
        }

        updateGeneratorTargets(from: currentState, savePolicy: .immediate)

        try? await Task.sleep(nanoseconds: 60_000_000)

        engine.pause()
        isEngineRunning = false
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
        if slotNodes.count != NoiseMixState.slotCount { return }

        masterMixer?.outputVolume = state.masterVolume.clamped(to: 0...1)

        for idx in 0..<NoiseMixState.slotCount {
            guard state.slots.indices.contains(idx) else { continue }
            let slotState = state.slots[idx]

            let enabled = slotState.enabled && state.wasPlaying
            slotNodes[idx].setTargetEnabled(enabled)

            let vol = slotState.volume.clamped(to: 0...1)
            slotNodes[idx].setTargetVolume(vol)

            slotNodes[idx].setTargetColour(slotState.colour.clamped(to: 0...2))
            slotNodes[idx].setTargetLowCutHz(slotState.lowCutHz.clamped(to: 10...2000))
            slotNodes[idx].setTargetHighCutHz(slotState.highCutHz.clamped(to: 500...20_000))
            slotNodes[idx].setTargetEQ(slotState.eq.sanitised())
        }

        var toSave = state
        toSave.updatedAt = Date()

        switch savePolicy {
        case .immediate:
            store.saveImmediate(toSave)
        case .throttled:
            store.saveThrottled(toSave)
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

    private var targetEnabled: AtomicFloat = .init(0)
    private var targetVolume: AtomicFloat = .init(0)
    private var targetColour: AtomicFloat = .init(0)

    private var targetLowCut: AtomicFloat = .init(20)
    private var targetHighCut: AtomicFloat = .init(18_000)

    private var targetEQLow: AtomicFloat = .init(0)
    private var targetEQMid: AtomicFloat = .init(0)
    private var targetEQHigh: AtomicFloat = .init(0)

    private let gainSmoother = SmoothedParam(timeConstantSeconds: 0.04)
    private let colourSmoother = SmoothedParam(timeConstantSeconds: 0.12)
    private let cutSmoother = SmoothedParam(timeConstantSeconds: 0.18)

    init(index: Int, sampleRate: Double) {
        self.index = index
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        self.generator = NoiseGenerator(sampleRate: Float(sampleRate))

        self.eq = AVAudioUnitEQ(numberOfBands: 3)
        self.eq.globalGain = 0

        let low = self.eq.bands[0]
        low.filterType = .lowShelf
        low.frequency = 180
        low.bandwidth = 1.0
        low.gain = 0
        low.bypass = false

        let mid = self.eq.bands[1]
        mid.filterType = .parametric
        mid.frequency = 900
        mid.bandwidth = 0.9
        mid.gain = 0
        mid.bypass = false

        let high = self.eq.bands[2]
        high.filterType = .highShelf
        high.frequency = 6_000
        high.bandwidth = 1.0
        high.gain = 0
        high.bypass = false

        self.sourceNode = AVAudioSourceNode(format: self.format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            self.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }

        self.outputNode = sourceNode
        self.outputFormat = format
    }

    var eqNode: AVAudioUnitEQ { eq }

    func setTargetEnabled(_ enabled: Bool) {
        targetEnabled.store(enabled ? 1 : 0)
    }

    func setTargetVolume(_ volume: Float) {
        targetVolume.store(volume.clamped(to: 0...1))
    }

    func setTargetColour(_ colour: Float) {
        targetColour.store(colour.clamped(to: 0...2))
    }

    func setTargetLowCutHz(_ hz: Float) {
        targetLowCut.store(hz.clamped(to: 10...2000))
    }

    func setTargetHighCutHz(_ hz: Float) {
        targetHighCut.store(hz.clamped(to: 500...20_000))
    }

    func setTargetEQ(_ eq: EQState) {
        targetEQLow.store(eq.lowGainDB.clamped(to: -12...12))
        targetEQMid.store(eq.midGainDB.clamped(to: -12...12))
        targetEQHigh.store(eq.highGainDB.clamped(to: -12...12))
    }

    private func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let enabled = targetEnabled.load()
        let volume = targetVolume.load()
        let colour = targetColour.load()

        let lowCut = targetLowCut.load()
        let highCut = targetHighCut.load()

        let eqLow = targetEQLow.load()
        let eqMid = targetEQMid.load()
        let eqHigh = targetEQHigh.load()

        let rampEnabled = gainSmoother.process(target: enabled, sampleRate: Float(format.sampleRate))
        let rampVolume = gainSmoother.process(target: volume, sampleRate: Float(format.sampleRate))
        let rampColour = colourSmoother.process(target: colour, sampleRate: Float(format.sampleRate))

        let rampLowCut = cutSmoother.process(target: lowCut, sampleRate: Float(format.sampleRate))
        let rampHighCut = cutSmoother.process(target: highCut, sampleRate: Float(format.sampleRate))

        generator.setColour(rampColour)
        generator.setBandpass(lowCutHz: rampLowCut, highCutHz: rampHighCut)

        eq.bands[0].gain = eqLow
        eq.bands[1].gain = eqMid
        eq.bands[2].gain = eqHigh

        let overall = rampEnabled * rampVolume

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard buffers.count >= 2 else { return }

        let left = buffers[0]
        let right = buffers[1]

        guard let leftPtr = left.mData?.assumingMemoryBound(to: Float.self),
              let rightPtr = right.mData?.assumingMemoryBound(to: Float.self) else {
            return
        }

        generator.renderStereo(
            left: leftPtr,
            right: rightPtr,
            frameCount: frameCount,
            gain: overall
        )
    }
}

// MARK: - Noise generation

private final class NoiseGenerator {
    private var rng = SplitMix64(seed: UInt64.random(in: 1...UInt64.max))
    private let sampleRate: Float

    private var pink = PinkNoise()
    private var brown = BrownNoise()

    private var colour: Float = 0

    private var hp = OnePoleHighPass()
    private var lp = OnePoleLowPass()

    private var targetLowCut: Float = 20
    private var targetHighCut: Float = 18_000

    private let lowCutSmoother = SmoothedParam(timeConstantSeconds: 0.15)
    private let highCutSmoother = SmoothedParam(timeConstantSeconds: 0.15)

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        hp.reset()
        lp.reset()
    }

    func setColour(_ c: Float) {
        colour = c.clamped(to: 0...2)
    }

    func setBandpass(lowCutHz: Float, highCutHz: Float) {
        targetLowCut = lowCutHz
        targetHighCut = highCutHz
    }

    func renderStereo(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int, gain: Float) {
        if frameCount <= 0 { return }

        for i in 0..<frameCount {
            let lc = lowCutSmoother.process(target: targetLowCut, sampleRate: sampleRate)
            let hc = highCutSmoother.process(target: targetHighCut, sampleRate: sampleRate)

            hp.set(cutoffHz: lc, sampleRate: sampleRate)
            lp.set(cutoffHz: hc, sampleRate: sampleRate)

            let white = rng.nextFloatSigned()

            let pinkSample = pink.process(white)
            let brownSample = brown.process(white)

            let c = colour

            let x: Float
            if c <= 1 {
                let t = c
                x = lerp(white, pinkSample, t: t)
            } else {
                let t = c - 1
                x = lerp(pinkSample, brownSample, t: t)
            }

            let filtered = lp.process(hp.process(x))

            let y = softClip(filtered * gain)

            left[i] = y
            right[i] = y
        }
    }

    private func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    private func softClip(_ x: Float) -> Float {
        tanhf(x)
    }
}

// MARK: - Noise colour filters

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
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return pink * 0.11
    }
}

private struct BrownNoise {
    private var last: Float = 0

    mutating func process(_ white: Float) -> Float {
        last = (last + (0.02 * white)).clamped(to: -1...1)
        return last
    }
}

// MARK: - Simple filters

private struct OnePoleLowPass {
    private var a: Float = 0
    private var b: Float = 0
    private var z: Float = 0

    mutating func reset() {
        z = 0
    }

    mutating func set(cutoffHz: Float, sampleRate: Float) {
        let fc = max(10, min(cutoffHz, sampleRate * 0.45))
        let x = expf(-2 * Float.pi * fc / sampleRate)
        a = 1 - x
        b = x
    }

    mutating func process(_ x: Float) -> Float {
        z = a * x + b * z
        return z
    }
}

private struct OnePoleHighPass {
    private var lp = OnePoleLowPass()

    mutating func reset() {
        lp.reset()
    }

    mutating func set(cutoffHz: Float, sampleRate: Float) {
        lp.set(cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    mutating func process(_ x: Float) -> Float {
        x - lp.process(x)
    }
}

// MARK: - Parameter smoothing

private struct SmoothedParam {
    private let timeConstant: Float
    private var value: Float = 0

    init(timeConstantSeconds: Float) {
        timeConstant = max(0.001, timeConstantSeconds)
    }

    mutating func reset(to v: Float) {
        value = v
    }

    mutating func process(target: Float, sampleRate: Float) -> Float {
        let dt = 1 / sampleRate
        let alpha = dt / (timeConstant + dt)
        value += alpha * (target - value)
        return value
    }
}

// MARK: - RNG

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
        let u = next()
        let mantissa = u >> 40
        let f = Float(mantissa) / Float(1 << 24)
        return (f * 2) - 1
    }
}

// MARK: - Atomic float

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

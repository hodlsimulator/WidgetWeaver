//
//  NoiseSlotNode.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import AVFoundation
import AudioToolbox
import Foundation

final class NoiseSlotNode {
    enum VolumeBehaviour {
        case normal
        case force(Float)
        case preserve
    }

    let index: Int

    let sourceNode: AVAudioSourceNode
    let eqNode: AVAudioUnitEQ
    let slotMixer: AVAudioMixerNode

    let format: AVAudioFormat

    private let renderState: RenderState

    private var lastEnabled: Bool = false
    private var lastVolume: Float = 0.0

    init(index: Int, sampleRate: Double, channelCount: AVAudioChannelCount) {
        self.index = index

        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
        self.format = fmt

        self.eqNode = AVAudioUnitEQ(numberOfBands: 5)
        self.slotMixer = AVAudioMixerNode()
        self.slotMixer.outputVolume = 0.0

        let seed = UInt64(0xA1B2C3D4) ^ UInt64(index &* 991)
        let state = RenderState(seed: seed, channelCount: Int(channelCount), amplitude: 0.22)
        self.renderState = state

        self.sourceNode = AVAudioSourceNode(format: fmt) { isSilence, _, frameCount, audioBufferList -> OSStatus in
            isSilence.pointee = false
            state.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }

        configureEQBands()
    }

    func scheduleIfNeeded() {
        // No scheduling required for AVAudioSourceNode.
    }

    func playIfNeeded() {
        // AVAudioSourceNode has no explicit play/stop; the engine pulls samples when running.
    }

    func stop() {
        // No-op for AVAudioSourceNode.
        // Restore the mixer to its last applied state; apply(slot:volumeBehaviour:) will re-assert on next tick.
        slotMixer.outputVolume = lastEnabled ? lastVolume : 0
    }

    func apply(slot: NoiseSlotState, volumeBehaviour: VolumeBehaviour = .normal) {
        lastEnabled = slot.enabled
        lastVolume = slot.volume

        switch volumeBehaviour {
        case .normal:
            slotMixer.outputVolume = slot.enabled ? slot.volume : 0
        case .force(let v):
            slotMixer.outputVolume = slot.enabled ? v : 0
        case .preserve:
            break
        }

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
}

private final class RenderState {
    private var rngs: [SplitMix64]
    private let amplitude: Float
    private let channelCount: Int

    init(seed: UInt64, channelCount: Int, amplitude: Float) {
        self.channelCount = max(1, channelCount)
        self.amplitude = amplitude

        self.rngs = (0..<self.channelCount).map { idx in
            let mix = UInt64(truncatingIfNeeded: idx &* 0x9E3779B9)
            return SplitMix64(seed: seed ^ mix ^ 0xD1B54A32D192ED03)
        }

        for i in rngs.indices {
            _ = rngs[i].nextUInt64()
            _ = rngs[i].nextUInt64()
        }
    }

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let frames = max(0, frameCount)
        if frames == 0 { return }

        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)

        if abl.count == 1, channelCount > 1 {
            let buf = abl[0]
            guard let mData = buf.mData else { return }
            let ptr = mData.assumingMemoryBound(to: Float.self)
            let stride = channelCount

            for frame in 0..<frames {
                let base = frame * stride
                for ch in 0..<channelCount {
                    var r = rngs[ch]
                    ptr[base + ch] = r.nextFloatMinus1To1() * amplitude
                    rngs[ch] = r
                }
            }
            return
        }

        let actualChannels = min(channelCount, abl.count)
        for ch in 0..<actualChannels {
            let buf = abl[ch]
            guard let mData = buf.mData else { continue }
            let ptr = mData.assumingMemoryBound(to: Float.self)

            var r = rngs[ch]
            for i in 0..<frames {
                ptr[i] = r.nextFloatMinus1To1() * amplitude
            }
            rngs[ch] = r
        }
    }

    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0xDEADBEEF : seed
        }

        mutating func nextUInt64() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextFloatMinus1To1() -> Float {
            let u = Float(nextUInt64() >> 40) / Float(1 << 24)
            return (u * 2.0) - 1.0
        }
    }
}

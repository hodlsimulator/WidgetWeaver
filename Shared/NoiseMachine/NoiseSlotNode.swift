//
//  NoiseSlotNode.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import AVFoundation
import Foundation

final class NoiseSlotNode {
    let index: Int

    let playerNode: AVAudioPlayerNode
    let eqNode: AVAudioUnitEQ
    let slotMixer: AVAudioMixerNode

    let format: AVAudioFormat

    private var noiseBuffer: AVAudioPCMBuffer
    private var hasScheduled: Bool = false

    private var lastEnabled: Bool = false
    private var lastVolume: Float = 0.0

    init(index: Int, sampleRate: Double, channelCount: AVAudioChannelCount) {
        self.index = index

        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
        self.format = fmt

        self.playerNode = AVAudioPlayerNode()
        self.eqNode = AVAudioUnitEQ(numberOfBands: 5)
        self.slotMixer = AVAudioMixerNode()
        self.slotMixer.outputVolume = 0.0

        self.noiseBuffer = Self.makeNoiseBuffer(
            format: fmt,
            seconds: 0.25,
            seed: UInt64(0xA1B2C3D4) ^ UInt64(index &* 991)
        )

        configureEQBands()
    }

    func scheduleIfNeeded() {
        guard !hasScheduled else { return }
        hasScheduled = true

        playerNode.scheduleBuffer(
            noiseBuffer,
            at: nil,
            options: [.loops, .interruptsAtLoop],
            completionHandler: nil
        )
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

        // Restore mixer to its last applied state; apply(slot:) will re-assert on next tick.
        slotMixer.outputVolume = lastEnabled ? lastVolume : 0
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

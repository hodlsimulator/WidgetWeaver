//
//  NoiseMachineController+Graph.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import AVFoundation
import AudioToolbox
import Foundation

extension NoiseMachineController {
    // MARK: - Graph

    func buildGraph() {
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

            engine.attach(slot.sourceNode)
            engine.attach(slot.eqNode)
            engine.attach(slot.slotMixer)

            engine.connect(slot.sourceNode, to: slot.eqNode, format: slot.format)
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
    }
}

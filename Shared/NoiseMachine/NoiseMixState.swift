//
//  NoiseMixState.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation

public struct NoiseMixState: Codable, Hashable, Sendable {
    public static let slotCount: Int = 4

    public var wasPlaying: Bool
    public var masterVolume: Float
    public var slots: [NoiseSlotState]
    public var updatedAt: Date

    public init(
        wasPlaying: Bool,
        masterVolume: Float,
        slots: [NoiseSlotState],
        updatedAt: Date
    ) {
        self.wasPlaying = wasPlaying
        self.masterVolume = masterVolume
        self.slots = slots
        self.updatedAt = updatedAt
    }

    public static var `default`: NoiseMixState {
        let slots = (0..<slotCount).map { idx in
            NoiseSlotState(
                enabled: idx == 0,
                volume: idx == 0 ? 0.65 : 0.0,
                colour: 0.0,
                lowCutHz: idx == 0 ? 80 : 20,
                highCutHz: 18_000,
                eq: .default
            )
        }

        return NoiseMixState(
            wasPlaying: false,
            masterVolume: 0.8,
            slots: slots,
            updatedAt: Date()
        )
    }

    public func sanitised() -> NoiseMixState {
        var s = self
        if s.slots.count != Self.slotCount {
            s.slots = (0..<Self.slotCount).map { idx in
                if self.slots.indices.contains(idx) {
                    return self.slots[idx]
                }
                return NoiseSlotState.default
            }
        }

        s.masterVolume = s.masterVolume.clamped(to: 0...1)

        s.slots = s.slots.map { slot in
            var slot = slot
            slot.volume = slot.volume.clamped(to: 0...1)
            slot.colour = slot.colour.clamped(to: 0...2)

            slot.lowCutHz = slot.lowCutHz.clamped(to: 10...2000)
            slot.highCutHz = slot.highCutHz.clamped(to: 500...20_000)
            if slot.lowCutHz >= slot.highCutHz {
                slot.highCutHz = min(20_000, slot.lowCutHz + 1000)
            }

            slot.eq = slot.eq.sanitised()
            return slot
        }

        return s
    }
}

public struct NoiseSlotState: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var volume: Float
    public var colour: Float
    public var lowCutHz: Float
    public var highCutHz: Float
    public var eq: EQState

    public init(
        enabled: Bool,
        volume: Float,
        colour: Float,
        lowCutHz: Float,
        highCutHz: Float,
        eq: EQState
    ) {
        self.enabled = enabled
        self.volume = volume
        self.colour = colour
        self.lowCutHz = lowCutHz
        self.highCutHz = highCutHz
        self.eq = eq
    }

    public static var `default`: NoiseSlotState {
        NoiseSlotState(
            enabled: false,
            volume: 0.5,
            colour: 0.0,
            lowCutHz: 20,
            highCutHz: 18_000,
            eq: .default
        )
    }
}

public struct EQState: Codable, Hashable, Sendable {
    public var lowGainDB: Float
    public var midGainDB: Float
    public var highGainDB: Float

    public init(lowGainDB: Float, midGainDB: Float, highGainDB: Float) {
        self.lowGainDB = lowGainDB
        self.midGainDB = midGainDB
        self.highGainDB = highGainDB
    }

    public static var `default`: EQState {
        EQState(lowGainDB: 0, midGainDB: 0, highGainDB: 0)
    }

    public func sanitised() -> EQState {
        EQState(
            lowGainDB: lowGainDB.clamped(to: -12...12),
            midGainDB: midGainDB.clamped(to: -12...12),
            highGainDB: highGainDB.clamped(to: -12...12)
        )
    }
}

public enum NoiseMixPreset: String, CaseIterable, Identifiable, Sendable {
    case white
    case pink
    case brown
    case deepFocus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .white:
            return "White"
        case .pink:
            return "Pink"
        case .brown:
            return "Brown"
        case .deepFocus:
            return "Deep Focus"
        }
    }

    public func applying(to base: NoiseMixState, updatedAt: Date = Date()) -> NoiseMixState {
        var s = base
        s.updatedAt = updatedAt

        switch self {
        case .white:
            s.slots = [
                NoiseSlotState(enabled: true, volume: 0.65, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default)
            ]

        case .pink:
            s.slots = [
                NoiseSlotState(enabled: true, volume: 0.65, colour: 1.0, lowCutHz: 20, highCutHz: 16_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default)
            ]

        case .brown:
            s.slots = [
                NoiseSlotState(enabled: true, volume: 0.65, colour: 2.0, lowCutHz: 20, highCutHz: 10_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default)
            ]

        case .deepFocus:
            s.slots = [
                NoiseSlotState(enabled: true, volume: 0.55, colour: 2.0, lowCutHz: 80, highCutHz: 10_000, eq: .default),
                NoiseSlotState(enabled: true, volume: 0.20, colour: 1.0, lowCutHz: 20, highCutHz: 16_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default),
                NoiseSlotState(enabled: false, volume: 0.0, colour: 0.0, lowCutHz: 20, highCutHz: 18_000, eq: .default)
            ]
        }

        return s.sanitised()
    }
}

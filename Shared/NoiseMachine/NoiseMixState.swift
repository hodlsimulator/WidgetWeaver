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
        updatedAt: Date = Date()
    ) {
        self.wasPlaying = wasPlaying
        self.masterVolume = masterVolume
        self.slots = slots
        self.updatedAt = updatedAt
        normalise()
    }
    
    public static func `default`() -> NoiseMixState {
        NoiseMixState(
            wasPlaying: false,
            masterVolume: 0.8,
            slots: (0..<slotCount).map { NoiseSlotState.default(index: $0) },
            updatedAt: Date()
        )
    }
    
    public mutating func normalise() {
        masterVolume = masterVolume.clamped(to: 0...1)
        
        if slots.count < Self.slotCount {
            for i in slots.count..<Self.slotCount {
                slots.append(.default(index: i))
            }
        } else if slots.count > Self.slotCount {
            slots = Array(slots.prefix(Self.slotCount))
        }
        
        for i in 0..<slots.count {
            slots[i].normalise()
        }
    }
    
    public var normalisedWithUpdateTimestamp: NoiseMixState {
        var s = self
        s.updatedAt = Date()
        s.normalise()
        return s
    }
}

public struct NoiseSlotState: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var volume: Float
    
    /// 0 = white, 1 = pink, 2 = brown
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
        normalise()
    }
    
    public static func `default`(index: Int) -> NoiseSlotState {
        let defaults: [(Bool, Float, Float)] = [
            (true, 0.35, 1.0),
            (true, 0.30, 0.0),
            (false, 0.25, 2.0),
            (false, 0.25, 1.0)
        ]
        
        let tuple = defaults.indices.contains(index) ? defaults[index] : (false, 0.25, 1.0)
        
        return NoiseSlotState(
            enabled: tuple.0,
            volume: tuple.1,
            colour: tuple.2,
            lowCutHz: 20,
            highCutHz: 18_000,
            eq: .default()
        )
    }
    
    public mutating func normalise() {
        volume = volume.clamped(to: 0...1)
        colour = colour.clamped(to: 0...2)
        
        lowCutHz = lowCutHz.clamped(to: 10...10_000)
        highCutHz = highCutHz.clamped(to: 50...20_000)
        
        if lowCutHz > highCutHz {
            swap(&lowCutHz, &highCutHz)
        }
        
        eq.normalise()
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
        normalise()
    }
    
    public static func `default`() -> EQState {
        EQState(lowGainDB: 0, midGainDB: 0, highGainDB: 0)
    }
    
    public mutating func normalise() {
        lowGainDB = lowGainDB.clamped(to: -12...12)
        midGainDB = midGainDB.clamped(to: -12...12)
        highGainDB = highGainDB.clamped(to: -12...12)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

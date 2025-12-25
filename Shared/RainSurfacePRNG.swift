//
//  RainSurfacePRNG.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Deterministic pseudo-random generator used for stable rendering.
//

import Foundation

struct RainSurfacePRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble01() -> Double {
        Double(nextUInt64()) / Double(UInt64.max)
    }

    // Compatibility alias used by the surface drawing code.
    mutating func random01() -> Double {
        nextDouble01()
    }

    static func seed(sampleIndex: Int, saltA: Int, saltB: Int = 0) -> UInt64 {
        let a = UInt64(bitPattern: Int64(sampleIndex &* 0x1F123BB5 ^ saltA &* 0x6A09E667 ^ saltB &* 0x9E3779B9))
        var x = a &+ 0xD1B54A32D192ED03
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x = x ^ (x >> 31)
        return x
    }
}

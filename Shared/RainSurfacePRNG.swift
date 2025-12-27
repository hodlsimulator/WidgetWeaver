//
//  RainSurfacePRNG.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation

struct RainSurfacePRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func nextUInt64() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextFloat01() -> Double {
        // 53-bit precision in [0,1)
        let x = nextUInt64() >> 11
        return Double(x) * (1.0 / 9007199254740992.0)
    }

    mutating func nextSignedFloat() -> Double {
        nextFloat01() * 2.0 - 1.0
    }

    static func combine(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var x = a &+ 0x9E3779B97F4A7C15
        x ^= b &+ 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }

    static func float01(_ x: UInt64) -> Double {
        let y = x >> 11
        return Double(y) * (1.0 / 9007199254740992.0)
    }
}

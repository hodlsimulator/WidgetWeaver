//
//  RainSurfacePRNG.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Deterministic pseudo-random generator used for stable rendering.
//

import Foundation

/// SplitMix64-based deterministic PRNG.
/// Stable across redraws when initialised with a stable seed.
struct RainSurfacePRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = (seed == 0) ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        return Self.mix64(state)
    }

    mutating func nextDouble01() -> Double {
        // 53-bit mantissa -> [0, 1)
        let x = nextUInt64() >> 11
        return Double(x) / Double(1 << 53)
    }

    // MARK: - Hash / mixing

    /// SplitMix64 finaliser (good avalanche for seed mixing).
    static func mix64(_ x: UInt64) -> UInt64 {
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return z
    }

    /// Combines two 64-bit values into one mixed value.
    static func combine(_ a: UInt64, _ b: UInt64) -> UInt64 {
        // Offset + mix to avoid simple XOR collisions.
        let x = a ^ (b &+ 0x9E3779B97F4A7C15)
        return mix64(x)
    }

    /// FNV-1a 64-bit, then mixed for better bit diffusion.
    static func hashString64(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 0x100000001b3
        }
        return mix64(h)
    }

    /// Convenience seed builder used for per-sample streams.
    static func seed(sampleIndex: Int, saltA: Int, saltB: Int = 0) -> UInt64 {
        let i = UInt64(bitPattern: Int64(sampleIndex))
        let a = UInt64(bitPattern: Int64(saltA))
        let b = UInt64(bitPattern: Int64(saltB))
        return combine(combine(i, a), b)
    }
}

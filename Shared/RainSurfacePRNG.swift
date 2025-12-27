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

    /// Deterministic 2D hash (0...1), suitable for per-pixel dithering.
    static func hash2D01(x: Int, y: Int, seed: UInt64) -> Double {
        let ux = UInt64(bitPattern: Int64(x))
        let uy = UInt64(bitPattern: Int64(y))

        // Coordinate mixing with distinct odd constants to reduce correlation.
        var h = combine(seed, ux &* 0x9E3779B97F4A7C15)
        h = combine(h, uy &* 0xD6E8FEB86659FD93)

        // Map to [0, 1) using the top 53 bits (Double mantissa).
        return Double(h >> 11) / Double(1 << 53)
    }

    /// Low-frequency value noise (0...1) using bilinear interpolation between hashed lattice points.
    static func valueNoise2D01(x: Double, y: Double, cell: Double, seed: UInt64) -> Double {
        let c = max(1e-6, cell)
        let gx = x / c
        let gy = y / c

        let x0 = Int(floor(gx))
        let y0 = Int(floor(gy))
        let fx = gx - Double(x0)
        let fy = gy - Double(y0)

        let u = smoothstep01(fx)
        let v = smoothstep01(fy)

        let a = hash2D01(x: x0, y: y0, seed: seed)
        let b = hash2D01(x: x0 + 1, y: y0, seed: seed)
        let c0 = hash2D01(x: x0, y: y0 + 1, seed: seed)
        let d = hash2D01(x: x0 + 1, y: y0 + 1, seed: seed)

        let ab = lerp(a, b, u)
        let cd = lerp(c0, d, u)
        return lerp(ab, cd, v)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func smoothstep01(_ u: Double) -> Double {
        let x = max(0.0, min(1.0, u))
        return x * x * (3.0 - 2.0 * x)
    }
}

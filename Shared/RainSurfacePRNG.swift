//
//  RainSurfacePRNG.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Deterministic pseudo-random generator used for stable rendering.
//

import Foundation
import CoreGraphics

/// Deterministic pseudo-random generator for stable widget rendering.
struct RainSurfacePRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = (seed == 0) ? 0x9E3779B97F4A7C15 : seed
    }

    // MARK: - SplitMix64

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble01() -> Double {
        // [0, 1)
        let v = nextUInt64()
        return Double(v) / (Double(UInt64.max) + 1.0)
    }

    mutating func nextCGFloat01() -> CGFloat {
        CGFloat(nextDouble01())
    }

    mutating func random01() -> Double {
        nextDouble01()
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(upperBound))
    }

    // MARK: - Hashing / seeding

    static func hash64(_ x: UInt64) -> UInt64 {
        // SplitMix64 finaliser (pure hash, no state)
        var z = x &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    static func seed(sampleIndex: Int, saltA: Int, saltB: Int = 0) -> UInt64 {
        let mixed = Int64(sampleIndex &* 0x1F123BB5 ^ saltA &* 0x6A09E667 ^ saltB &* 0x9E3779B9)
        return hash64(UInt64(bitPattern: mixed))
    }

    static func hashString(_ s: String) -> UInt64 {
        // FNV-1a 64-bit, then mixed.
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 0x100000001b3
        }
        return hash64(h)
    }

    static func roundedTimestampSeconds(_ date: Date, roundingSeconds: Int) -> Int64 {
        let r = max(1, roundingSeconds)
        let t = Int64(date.timeIntervalSince1970)
        return (t / Int64(r)) * Int64(r)
    }

    static func seed(
        roundedTimestampSeconds: Int64,
        pixelWidth: Int,
        pixelHeight: Int,
        widgetFamilyRaw: Int,
        locationHash: UInt64 = 0,
        extra: UInt64 = 0
    ) -> UInt64 {
        var x: UInt64 = 0
        x ^= UInt64(bitPattern: roundedTimestampSeconds)
        x &*= 0x9E3779B97F4A7C15
        x ^= UInt64(pixelWidth &* 73856093)
        x ^= UInt64(pixelHeight &* 19349663) << 1
        x ^= UInt64(widgetFamilyRaw &* 83492791) << 2
        x ^= locationHash &* 0xD1B54A32D192ED03
        x ^= extra &* 0x94D049BB133111EB
        return hash64(x)
    }
}

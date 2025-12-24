//
//  RainSurfaceMath.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Small maths helpers used by the surface renderer.
//

import Foundation
import SwiftUI

enum RainSurfaceMath {

    static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }

    static func clamp(_ v: Double, min lo: Double, max hi: Double) -> Double {
        if lo >= hi { return lo }
        return max(lo, min(hi, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let tt = clamp01(t)
        return a + (b - a) * tt
    }

    static func smoothstep01(_ u: Double) -> Double {
        let x = clamp01(u)
        return x * x * (3.0 - 2.0 * x)
    }

    static func alignToPixelCenter(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (floor(value * displayScale) + 0.5) / displayScale
    }

    /// Rendering-only boundary easing intended for diffusion/glow alpha (not geometry).
    static func edgeFactors(
        sampleCount: Int,
        startEaseMinutes: Int,
        endFadeMinutes: Int,
        endFadeFloor: Double
    ) -> [Double] {
        guard sampleCount > 0 else { return [] }
        if sampleCount == 1 { return [1.0] }

        let startN = max(0, startEaseMinutes)
        let endN = max(0, endFadeMinutes)
        let floorClamped = clamp01(endFadeFloor)

        var out: [Double] = []
        out.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            var f = 1.0

            if startN > 0, i < startN {
                let t = Double(i) / Double(max(1, startN))
                f *= smoothstep01(t)
            }

            if endN > 0 {
                let remaining = (sampleCount - 1) - i
                if remaining < endN {
                    let t = Double(remaining) / Double(max(1, endN))
                    let fade = smoothstep01(t) // 0 at end, 1 at start of fade window
                    let endFactor = lerp(floorClamped, 1.0, fade)
                    f *= endFactor
                }
            }

            out.append(f)
        }

        return out
    }

    static func smooth(_ values: [CGFloat], passes: Int) -> [CGFloat] {
        guard values.count >= 3, passes > 0 else { return values }

        var out = values
        var tmp = values

        for _ in 0..<passes {
            tmp[0] = out[0]
            tmp[tmp.count - 1] = out[out.count - 1]

            if out.count > 2 {
                for i in 1..<(out.count - 1) {
                    // Mildly weighted 3-tap blur (stable shape, less shrink).
                    tmp[i] = (out[i - 1] * 0.25) + (out[i] * 0.50) + (out[i + 1] * 0.25)
                }
            }

            out = tmp
        }

        return out
    }

    static func smooth(_ values: [Double], passes: Int) -> [Double] {
        guard values.count >= 3, passes > 0 else { return values }

        var out = values
        var tmp = values

        for _ in 0..<passes {
            tmp[0] = out[0]
            tmp[tmp.count - 1] = out[out.count - 1]

            if out.count > 2 {
                for i in 1..<(out.count - 1) {
                    tmp[i] = (out[i - 1] * 0.25) + (out[i] * 0.50) + (out[i + 1] * 0.25)
                }
            }

            out = tmp
        }

        return out
    }
}

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

    static func clamp01(_ v: CGFloat) -> CGFloat {
        max(0.0, min(1.0, v))
    }

    static func clamp(_ v: Double, min lo: Double, max hi: Double) -> Double {
        if lo >= hi { return lo }
        return max(lo, min(hi, v))
    }

    static func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
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

    static func smoothstep01(_ u: CGFloat) -> CGFloat {
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

    // MARK: - Monotone cubic resampling (uniform spacing)

    private static func monotoneCubicTangents(_ y: [CGFloat]) -> [CGFloat] {
        let n = y.count
        guard n >= 2 else { return y }

        var d = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) { d[i] = y[i + 1] - y[i] }

        var m = [CGFloat](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]

        if n > 2 {
            for i in 1..<(n - 1) {
                let d0 = d[i - 1]
                let d1 = d[i]
                if d0 == 0 || d1 == 0 || (d0 > 0 && d1 < 0) || (d0 < 0 && d1 > 0) {
                    m[i] = 0
                } else {
                    m[i] = 2 * d0 * d1 / (d0 + d1) // harmonic mean
                }
            }
        }

        let eps: CGFloat = 1e-8
        if n >= 2 {
            for i in 0..<(n - 1) {
                let di = d[i]
                if abs(di) <= eps {
                    m[i] = 0
                    m[i + 1] = 0
                    continue
                }

                let a = m[i] / di
                let b = m[i + 1] / di
                let s = a * a + b * b

                if s > 9 {
                    let t = 3 / sqrt(s)
                    m[i] = t * a * di
                    m[i + 1] = t * b * di
                }
            }
        }

        return m
    }

    private static func evalMonotoneCubic(y: [CGFloat], m: [CGFloat], x: CGFloat) -> CGFloat {
        let n = y.count
        guard n >= 2 else { return y.first ?? 0 }
        if x <= 0 { return y[0] }

        let maxX = CGFloat(n - 1)
        if x >= maxX { return y[n - 1] }

        let i = Int(floor(x))
        let t = x - CGFloat(i)

        let y0 = y[i]
        let y1 = y[i + 1]
        let m0 = m[i]
        let m1 = m[i + 1]

        let t2 = t * t
        let t3 = t2 * t

        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        return h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
    }

    static func resampleMonotoneCubic(_ y: [CGFloat], targetCount: Int) -> [CGFloat] {
        let n = y.count
        let outCount = max(2, targetCount)
        guard n >= 2 else {
            return Array(repeating: y.first ?? 0, count: outCount)
        }

        let tangents = monotoneCubicTangents(y)
        let maxX = CGFloat(n - 1)

        var out = [CGFloat](repeating: 0, count: outCount)
        for j in 0..<outCount {
            let u = CGFloat(j) / CGFloat(outCount - 1)
            out[j] = evalMonotoneCubic(y: y, m: tangents, x: u * maxX)
        }

        return out
    }

    static func resampleMonotoneCubic(_ y: [Double], targetCount: Int) -> [Double] {
        let yy = y.map { CGFloat($0) }
        let out = resampleMonotoneCubic(yy, targetCount: targetCount)
        return out.map { Double($0) }
    }
}

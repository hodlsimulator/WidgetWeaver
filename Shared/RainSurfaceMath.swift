//
// RainSurfaceMath.swift
// WidgetWeaver
//
// Created by . . on 12/23/25.
//

import Foundation
import SwiftUI

enum RainSurfaceMath {

    // MARK: - Basic helpers

    @inline(__always)
    static func clamp01(_ x: Double) -> Double {
        guard x.isFinite else { return 0.0 }
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }

    @inline(__always)
    static func clamp01(_ x: CGFloat) -> CGFloat {
        guard x.isFinite else { return 0.0 }
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }

    @inline(__always)
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    @inline(__always)
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    static func alignToPixelCenter(_ y: CGFloat, displayScale: CGFloat) -> CGFloat {
        let s = max(1.0, displayScale)
        return (round(y * s) + 0.5) / s
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        if a == b { return x < a ? 0.0 : 1.0 }
        let t = clamp01((x - a) / (b - a))
        return t * t * (3.0 - 2.0 * t)
    }

    static func smoothstep01(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * (3.0 - 2.0 * t)
    }

    static func smoothstep01(_ x: CGFloat) -> CGFloat {
        let t = clamp01(x)
        return t * t * (3.0 - 2.0 * t)
    }

    // MARK: - Percentiles

    static func percentile(_ values: [Double], p: Double) -> Double {
        let finite = values.filter { $0.isFinite }
        guard !finite.isEmpty else { return 0.0 }
        let pp = clamp01(p)
        let sorted = finite.sorted()
        if sorted.count == 1 { return sorted[0] }

        let idx = pp * Double(sorted.count - 1)
        let i0 = Int(floor(idx))
        let i1 = min(sorted.count - 1, i0 + 1)
        let frac = idx - Double(i0)
        return sorted[i0] + (sorted[i1] - sorted[i0]) * frac
    }

    static func percentile(_ values: [CGFloat], p: CGFloat) -> CGFloat {
        let finite = values.filter { $0.isFinite }
        guard !finite.isEmpty else { return 0.0 }
        let pp = clamp01(p)
        let sorted = finite.sorted()
        if sorted.count == 1 { return sorted[0] }

        let idx = Double(pp) * Double(sorted.count - 1)
        let i0 = Int(floor(idx))
        let i1 = min(sorted.count - 1, i0 + 1)
        let frac = CGFloat(idx - Double(i0))
        return sorted[i0] + (sorted[i1] - sorted[i0]) * frac
    }

    // MARK: - Smoothing

    static func smooth(_ values: [CGFloat], windowRadius: Int, passes: Int) -> [CGFloat] {
        let sanitized = values.map { $0.isFinite ? $0 : 0.0 }
        guard sanitized.count > 2, windowRadius > 0, passes > 0 else {
            return sanitized
        }

        var v = sanitized
        let n = v.count
        let r = windowRadius

        for _ in 0..<passes {
            var out = Array(repeating: CGFloat(0.0), count: n)

            for i in 0..<n {
                let lo = max(0, i - r)
                let hi = min(n - 1, i + r)

                var acc: CGFloat = 0.0
                var wsum: CGFloat = 0.0

                // Triangular weights: closer neighbours contribute more.
                for j in lo...hi {
                    let dist = abs(j - i)
                    let w = CGFloat((r + 1) - dist)
                    acc += v[j] * w
                    wsum += w
                }

                let y = (wsum > 0.000_001) ? (acc / wsum) : 0.0
                out[i] = y.isFinite ? y : 0.0
            }

            v = out
        }

        return v
    }

    // MARK: - Edge easing

    static func applyEdgeEasing(to heights: inout [CGFloat], fraction: CGFloat, power: Double) {
        let n = heights.count
        guard n > 2 else { return }

        let f = max(0.0, min(0.49, fraction))
        guard f > 0.000_01 else { return }

        var ramp = Int(round(CGFloat(n) * f))
        ramp = max(1, min(ramp, (n - 1) / 2))
        guard ramp >= 1 else { return }

        let p = max(0.10, power)

        @inline(__always)
        func ease(_ t: CGFloat) -> CGFloat {
            let tt = clamp01(t)
            return CGFloat(pow(Double(tt), p))
        }

        for i in 0..<ramp {
            let t = CGFloat(i + 1) / CGFloat(ramp)
            let w = ease(t)

            heights[i] *= w
            heights[n - 1 - i] *= w
        }
    }

    // MARK: - Wet segment easing (ramps on/off at wet/dry boundaries)

    static func applyWetSegmentEasing(to heights: inout [CGFloat], threshold: CGFloat, fraction: CGFloat, power: Double) {
        let n = heights.count
        guard n > 4 else { return }

        let f = max(0.0, min(0.49, fraction))
        guard f > 0.000_01 else { return }

        var ramp = Int(round(CGFloat(n) * f))
        ramp = max(1, min(ramp, n - 1))
        guard ramp >= 1 else { return }

        let p = max(0.10, power)

        @inline(__always)
        func ease(_ t: CGFloat) -> CGFloat {
            let tt = clamp01(t)
            return CGFloat(pow(Double(tt), p))
        }

        for i in 0..<(n - 1) {
            let a = heights[i]
            let b = heights[i + 1]

            // Dry -> wet transition: ramp up starting at i+1
            if a <= threshold && b > threshold {
                for k in 0..<ramp {
                    let idx = i + 1 + k
                    if idx >= n { break }
                    let t = CGFloat(k + 1) / CGFloat(ramp)
                    heights[idx] *= ease(t)
                }
            }

            // Wet -> dry transition: ramp down ending at i
            if a > threshold && b <= threshold {
                for k in 0..<ramp {
                    let idx = i - k
                    if idx < 0 { break }
                    let t = CGFloat(k + 1) / CGFloat(ramp)
                    heights[idx] *= ease(t)
                }
            }
        }
    }

    // MARK: - Resampling (monotone cubic)

    static func resampleMonotoneCubic(_ values: [CGFloat], targetCount: Int) -> [CGFloat] {
        let v = values.map { $0.isFinite ? $0 : 0.0 }
        guard targetCount > 1 else { return v.isEmpty ? [] : [v[0]] }
        guard v.count > 1 else { return Array(repeating: v.first ?? 0.0, count: targetCount) }

        let n = v.count
        var d = Array(repeating: CGFloat(0.0), count: n - 1)
        for i in 0..<(n - 1) {
            d[i] = v[i + 1] - v[i]
        }

        // Initial tangents (harmonic mean inside, endpoint = secant)
        var m = Array(repeating: CGFloat(0.0), count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]

        if n > 2 {
            for i in 1..<(n - 1) {
                let a = d[i - 1]
                let b = d[i]
                if a == 0.0 || b == 0.0 || (a > 0.0) != (b > 0.0) {
                    m[i] = 0.0
                } else {
                    m[i] = (2.0 * a * b) / (a + b)
                }
            }
        }

        // Fritsch–Carlson monotonicity limiter
        for i in 0..<(n - 1) {
            let di = d[i]
            if abs(di) < 0.000_001 {
                m[i] = 0.0
                m[i + 1] = 0.0
                continue
            }

            let ai = Double(m[i] / di)
            let bi = Double(m[i + 1] / di)

            if ai < 0.0 || bi < 0.0 {
                m[i] = 0.0
                m[i + 1] = 0.0
                continue
            }

            let sumSq = ai * ai + bi * bi
            if sumSq > 9.0 {
                let t = 3.0 / sqrt(sumSq)
                m[i] = CGFloat(t * ai) * di
                m[i + 1] = CGFloat(t * bi) * di
            }
        }

        @inline(__always)
        func hermite(_ y0: CGFloat, _ y1: CGFloat, _ m0: CGFloat, _ m1: CGFloat, _ t: CGFloat) -> CGFloat {
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            let h10 = t3 - 2.0 * t2 + t
            let h01 = -2.0 * t3 + 3.0 * t2
            let h11 = t3 - t2
            return h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
        }

        var out: [CGFloat] = []
        out.reserveCapacity(targetCount)

        let denom = Double(targetCount - 1)
        let scale = Double(n - 1)

        for j in 0..<targetCount {
            let u = (denom > 0.0) ? (Double(j) / denom) * scale : 0.0
            let i0 = max(0, min(n - 2, Int(floor(u))))
            let t = CGFloat(u - Double(i0))

            let y = hermite(v[i0], v[i0 + 1], m[i0], m[i0 + 1], clamp01(t))
            out.append(y.isFinite ? y : 0.0)
        }

        return out
    }

    static func resampleMonotoneCubic(_ values: [Double], targetCount: Int) -> [Double] {
        let v = values.map { $0.isFinite ? $0 : 0.0 }
        guard targetCount > 1 else { return v.isEmpty ? [] : [v[0]] }
        guard v.count > 1 else { return Array(repeating: v.first ?? 0.0, count: targetCount) }

        let n = v.count
        var d = Array(repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) {
            d[i] = v[i + 1] - v[i]
        }

        var m = Array(repeating: 0.0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]

        if n > 2 {
            for i in 1..<(n - 1) {
                let a = d[i - 1]
                let b = d[i]
                if a == 0.0 || b == 0.0 || (a > 0.0) != (b > 0.0) {
                    m[i] = 0.0
                } else {
                    m[i] = (2.0 * a * b) / (a + b)
                }
            }
        }

        for i in 0..<(n - 1) {
            let di = d[i]
            if abs(di) < 0.000_001 {
                m[i] = 0.0
                m[i + 1] = 0.0
                continue
            }

            let a = m[i] / di
            let b = m[i + 1] / di

            if a < 0.0 || b < 0.0 {
                m[i] = 0.0
                m[i + 1] = 0.0
                continue
            }

            let sumSq = a * a + b * b
            if sumSq > 9.0 {
                let t = 3.0 / sqrt(sumSq)
                m[i] = (t * a) * di
                m[i + 1] = (t * b) * di
            }
        }

        @inline(__always)
        func hermite(_ y0: Double, _ y1: Double, _ m0: Double, _ m1: Double, _ t: Double) -> Double {
            let tt = clamp01(t)
            let t2 = tt * tt
            let t3 = t2 * tt
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            let h10 = t3 - 2.0 * t2 + tt
            let h01 = -2.0 * t3 + 3.0 * t2
            let h11 = t3 - t2
            return h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
        }

        var out: [Double] = []
        out.reserveCapacity(targetCount)

        let denom = Double(targetCount - 1)
        let scale = Double(n - 1)

        for j in 0..<targetCount {
            let u = (denom > 0.0) ? (Double(j) / denom) * scale : 0.0
            let i0 = max(0, min(n - 2, Int(floor(u))))
            let t = u - Double(i0)

            let y = hermite(v[i0], v[i0 + 1], m[i0], m[i0 + 1], t)
            out.append(y.isFinite ? y : 0.0)
        }

        return out
    }
}

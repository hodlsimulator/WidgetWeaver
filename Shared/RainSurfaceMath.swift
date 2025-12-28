//
//  RainSurfaceMath.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI

enum RainSurfaceMath {
    static func clamp01(_ x: Double) -> Double {
        guard x.isFinite else { return 0.0 }
        return max(0.0, min(1.0, x))
    }
    static func clamp01(_ x: CGFloat) -> CGFloat {
        guard x.isFinite else { return 0.0 }
        return max(0.0, min(1.0, x))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    static func alignToPixelCenter(_ y: CGFloat, displayScale: CGFloat) -> CGFloat {
        let s = max(1.0, displayScale)
        return (round(y * s) + 0.5) / s
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        if a == b { return x < a ? 0 : 1 }
        let t = clamp01((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    static func smoothstep01(_ x: Double) -> Double {
        smoothstep(0.0, 1.0, x)
    }

    static func smoothstep01(_ x: CGFloat) -> CGFloat {
        CGFloat(smoothstep(0.0, 1.0, Double(x)))
    }

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

    static func smooth(_ values: [CGFloat], windowRadius: Int, passes: Int) -> [CGFloat] {
        guard values.count > 2, windowRadius > 0, passes > 0 else { return values }
        var v = values
        for _ in 0..<passes {
            var out = v
            for i in 0..<v.count {
                var acc: CGFloat = 0
                var w: CGFloat = 0
                let lo = max(0, i - windowRadius)
                let hi = min(v.count - 1, i + windowRadius)
                for j in lo...hi {
                    let ww: CGFloat = (j == i) ? 2.0 : 1.0
                    acc += v[j] * ww
                    w += ww
                }
                out[i] = acc / max(0.000_001, w)
            }
            v = out
        }
        return v
    }

    static func applyEdgeEasing(to heights: inout [CGFloat], fraction: CGFloat, power: Double) {
        guard heights.count > 2 else { return }
        let f = max(0.0, min(0.49, fraction))
        let n = heights.count
        let k = max(1, Int(round(CGFloat(n) * f)))

        func ease(_ t: CGFloat) -> CGFloat {
            let tt = clamp01(t)
            return CGFloat(pow(Double(tt), max(0.10, power)))
        }

        for i in 0..<k {
            let t = CGFloat(i) / CGFloat(max(1, k - 1))
            let w = ease(t)
            heights[i] *= w
            heights[n - 1 - i] *= w
        }
    }

    static func applyWetSegmentEasing(to heights: inout [CGFloat], threshold: CGFloat, fraction: CGFloat, power: Double) {
        guard heights.count > 4 else { return }
        let n = heights.count
        let ramp = max(2, Int(round(CGFloat(n) * max(0.05, min(0.40, fraction)))))

        func ease(_ t: CGFloat) -> CGFloat {
            let tt = clamp01(t)
            return CGFloat(pow(Double(tt), max(0.10, power)))
        }

        // Detect transitions and apply ramps.
        for i in 0..<(n - 1) {
            let a = heights[i]
            let b = heights[i + 1]

            // Dry -> Wet
            if a <= threshold && b > threshold {
                for k in 0..<ramp {
                    let idx = i + 1 + k
                    if idx >= n { break }
                    let t = CGFloat(k + 1) / CGFloat(ramp)
                    let w = ease(t)
                    heights[idx] *= w
                }
            }

            // Wet -> Dry
            if a > threshold && b <= threshold {
                for k in 0..<ramp {
                    let idx = i - k
                    if idx < 0 { break }
                    let t = CGFloat(k + 1) / CGFloat(ramp)
                    let w = ease(1.0 - t)
                    heights[idx] *= w
                }
            }
        }
    }

    // Monotone cubic (Fritsch–Carlson) resampling.
    static func resampleMonotoneCubic(_ values: [CGFloat], targetCount: Int) -> [CGFloat] {
        let v = values.map { $0.isFinite ? $0 : 0 }

        guard targetCount > 1 else { return v.isEmpty ? [] : [v[0]] }
        guard v.count > 1 else { return Array(repeating: v.first ?? 0, count: targetCount) }

        let n = v.count
        var d = Array(repeating: CGFloat(0), count: n - 1)
        for i in 0..<(n - 1) { d[i] = v[i + 1] - v[i] }

        var m = Array(repeating: CGFloat(0), count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                let a = d[i - 1]
                let b = d[i]
                if a == 0 || b == 0 || (a > 0) != (b > 0) {
                    m[i] = 0
                } else {
                    m[i] = (2 * a * b) / (a + b)
                }
            }
        }

        func hermite(_ y0: CGFloat, _ y1: CGFloat, _ m0: CGFloat, _ m1: CGFloat, _ t: CGFloat) -> CGFloat {
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2 * t3 - 3 * t2 + 1
            let h10 = t3 - 2 * t2 + t
            let h01 = -2 * t3 + 3 * t2
            let h11 = t3 - t2
            return h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
        }

        var out: [CGFloat] = []
        out.reserveCapacity(targetCount)

        for j in 0..<targetCount {
            let u = Double(j) / Double(targetCount - 1) * Double(n - 1)
            let i0 = max(0, min(n - 2, Int(floor(u))))
            let t = CGFloat(u - Double(i0))
            out.append(hermite(v[i0], v[i0 + 1], m[i0], m[i0 + 1], t))
        }
        return out
    }

    static func resampleMonotoneCubic(_ values: [Double], targetCount: Int) -> [Double] {
        let v = values.map { $0.isFinite ? $0 : 0 }

        guard targetCount > 1 else { return v.isEmpty ? [] : [v[0]] }
        guard v.count > 1 else { return Array(repeating: v.first ?? 0, count: targetCount) }

        let n = v.count
        var d = Array(repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) { d[i] = v[i + 1] - v[i] }

        var m = Array(repeating: 0.0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                let a = d[i - 1]
                let b = d[i]
                if a == 0 || b == 0 || (a > 0) != (b > 0) {
                    m[i] = 0
                } else {
                    m[i] = (2 * a * b) / (a + b)
                }
            }
        }

        func hermite(_ y0: Double, _ y1: Double, _ m0: Double, _ m1: Double, _ t: Double) -> Double {
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2 * t3 - 3 * t2 + 1
            let h10 = t3 - 2 * t2 + t
            let h01 = -2 * t3 + 3 * t2
            let h11 = t3 - t2
            return h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
        }

        var out: [Double] = []
        out.reserveCapacity(targetCount)

        for j in 0..<targetCount {
            let u = Double(j) / Double(targetCount - 1) * Double(n - 1)
            let i0 = max(0, min(n - 2, Int(floor(u))))
            let t = u - Double(i0)
            out.append(hermite(v[i0], v[i0 + 1], m[i0], m[i0 + 1], t))
        }
        return out
    }
}

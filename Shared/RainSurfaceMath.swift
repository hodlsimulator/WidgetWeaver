//
//  RainSurfaceMath.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Small maths helpers used by the surface renderer.
//

import Foundation
import CoreGraphics

enum RainSurfaceMath {

    // MARK: - Clamp / Lerp

    static func clamp(_ x: Double, min lo: Double, max hi: Double) -> Double {
        if x < lo { return lo }
        if x > hi { return hi }
        return x
    }

    static func clamp01(_ x: Double) -> Double {
        clamp(x, min: 0.0, max: 1.0)
    }

    static func clamp(_ x: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        if x < lo { return lo }
        if x > hi { return hi }
        return x
    }

    static func clamp01(_ x: CGFloat) -> CGFloat {
        clamp(x, min: 0.0, max: 1.0)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    // MARK: - Smoothstep

    static func smoothstep01(_ t: Double) -> Double {
        let x = clamp01(t)
        return x * x * (3.0 - 2.0 * x)
    }

    static func smoothstep01(_ t: CGFloat) -> CGFloat {
        let x = clamp01(t)
        return x * x * (3.0 - 2.0 * x)
    }

    // MARK: - Pixel alignment

    /// Aligns a 1px stroke to the pixel centre for crisp lines.
    static func alignToPixelCenter(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        let s = max(1.0, displayScale)
        return (floor(value * s) + 0.5) / s
    }

    // MARK: - Percentile

    static func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let pp = clamp(p, min: 0.0, max: 1.0)
        if values.count == 1 { return values[0] }

        let sorted = values.sorted()
        let idx = pp * Double(sorted.count - 1)
        let i0 = Int(floor(idx))
        let i1 = min(sorted.count - 1, i0 + 1)
        let t = idx - Double(i0)
        return lerp(sorted[i0], sorted[i1], t)
    }

    // MARK: - Smoothing (moving average)

    static func smooth(_ input: [CGFloat], windowRadius: Int, passes: Int) -> [CGFloat] {
        guard input.count >= 3, windowRadius > 0, passes > 0 else { return input }
        var a = input
        var b = input

        for _ in 0..<passes {
            for i in 0..<a.count {
                var sum: CGFloat = 0
                var w: CGFloat = 0
                let lo = max(0, i - windowRadius)
                let hi = min(a.count - 1, i + windowRadius)
                for j in lo...hi {
                    let ww: CGFloat
                    if j == i { ww = 2.0 } else { ww = 1.0 }
                    sum += a[j] * ww
                    w += ww
                }
                b[i] = sum / max(0.000_001, w)
            }
            a = b
        }

        return a
    }

    static func smooth(_ input: [Double], windowRadius: Int, passes: Int) -> [Double] {
        guard input.count >= 3, windowRadius > 0, passes > 0 else { return input }
        var a = input
        var b = input

        for _ in 0..<passes {
            for i in 0..<a.count {
                var sum: Double = 0
                var w: Double = 0
                let lo = max(0, i - windowRadius)
                let hi = min(a.count - 1, i + windowRadius)
                for j in lo...hi {
                    let ww: Double
                    if j == i { ww = 2.0 } else { ww = 1.0 }
                    sum += a[j] * ww
                    w += ww
                }
                b[i] = sum / max(0.000_001, w)
            }
            a = b
        }

        return a
    }

    // MARK: - Monotone cubic resample (PCHIP style)

    static func resampleMonotoneCubicCenters(_ input: [CGFloat], targetCount: Int) -> [CGFloat] {
        guard targetCount > 0 else { return [] }
        guard input.count > 1 else {
            return Array(repeating: input.first ?? 0, count: targetCount)
        }

        let n = input.count
        let y = input.map { Double($0) }

        // Slopes between points.
        var d = [Double](repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) {
            d[i] = y[i + 1] - y[i]
        }

        // Tangents.
        var m = [Double](repeating: 0.0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                let d0 = d[i - 1]
                let d1 = d[i]
                if d0 == 0.0 || d1 == 0.0 || (d0 > 0.0) != (d1 > 0.0) {
                    m[i] = 0.0
                } else {
                    // Harmonic mean (equal spacing).
                    m[i] = 2.0 / (1.0 / d0 + 1.0 / d1)
                }
            }
        }

        func hermite(_ i: Int, _ t: Double) -> Double {
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            let h10 = t3 - 2.0 * t2 + t
            let h01 = -2.0 * t3 + 3.0 * t2
            let h11 = t3 - t2
            return h00 * y[i] + h10 * m[i] + h01 * y[i + 1] + h11 * m[i + 1]
        }

        var out = [CGFloat]()
        out.reserveCapacity(targetCount)

        // Map output samples across [0, n-1].
        let denom = Double(max(1, targetCount - 1))
        for j in 0..<targetCount {
            let pos = (Double(j) / denom) * Double(n - 1)
            let i = min(n - 2, max(0, Int(floor(pos))))
            let t = pos - Double(i)
            let v = hermite(i, t)
            out.append(CGFloat(v))
        }

        return out
    }

    static func resampleMonotoneCubicCenters(_ input: [Double], targetCount: Int) -> [Double] {
        guard targetCount > 0 else { return [] }
        guard input.count > 1 else {
            return Array(repeating: input.first ?? 0, count: targetCount)
        }

        let n = input.count
        let y = input

        var d = [Double](repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) {
            d[i] = y[i + 1] - y[i]
        }

        var m = [Double](repeating: 0.0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                let d0 = d[i - 1]
                let d1 = d[i]
                if d0 == 0.0 || d1 == 0.0 || (d0 > 0.0) != (d1 > 0.0) {
                    m[i] = 0.0
                } else {
                    m[i] = 2.0 / (1.0 / d0 + 1.0 / d1)
                }
            }
        }

        func hermite(_ i: Int, _ t: Double) -> Double {
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            let h10 = t3 - 2.0 * t2 + t
            let h01 = -2.0 * t3 + 3.0 * t2
            let h11 = t3 - t2
            return h00 * y[i] + h10 * m[i] + h01 * y[i + 1] + h11 * m[i + 1]
        }

        var out = [Double]()
        out.reserveCapacity(targetCount)

        let denom = Double(max(1, targetCount - 1))
        for j in 0..<targetCount {
            let pos = (Double(j) / denom) * Double(n - 1)
            let i = min(n - 2, max(0, Int(floor(pos))))
            let t = pos - Double(i)
            out.append(hermite(i, t))
        }

        return out
    }

    // MARK: - Edge easing (whole-chart)

    static func applyEdgeEasing(to heights: inout [CGFloat], fraction: Double, power: Double) {
        guard heights.count >= 6 else { return }
        let f = clamp(fraction, min: 0.0, max: 0.45)
        if f <= 0.0 { return }

        let n = heights.count
        let k = max(1, Int(round(Double(n) * f)))

        for i in 0..<n {
            let leftT = Double(i) / Double(max(1, k))
            let rightT = Double(n - 1 - i) / Double(max(1, k))
            let t = min(1.0, min(leftT, rightT))

            let eased = pow(smoothstep01(t), power)
            heights[i] = heights[i] * CGFloat(eased)
        }
    }

    // MARK: - Wet-segment easing (fix cliffs at start/stop of rain)

    static func applyWetSegmentEasing(to heights: inout [CGFloat], threshold: CGFloat, fraction: Double, power: Double) {
        guard heights.count >= 6 else { return }
        let n = heights.count
        let f = clamp(fraction, min: 0.0, max: 0.45)
        if f <= 0.0 { return }

        // Identify wet runs (>= threshold).
        var runs: [(start: Int, end: Int)] = []
        var i = 0
        while i < n {
            while i < n && heights[i] < threshold { i += 1 }
            if i >= n { break }
            let start = i
            while i < n && heights[i] >= threshold { i += 1 }
            let end = i - 1
            runs.append((start, end))
        }

        guard !runs.isEmpty else { return }

        for run in runs {
            let len = run.end - run.start + 1
            if len < 4 { continue }

            let k = max(1, Int(round(Double(len) * f)))

            // Start ramp.
            if k > 0 {
                for j in 0..<min(k, len) {
                    let t = Double(j) / Double(max(1, k))
                    let eased = pow(smoothstep01(t), power)
                    heights[run.start + j] = heights[run.start + j] * CGFloat(eased)
                }
            }

            // End ramp.
            if k > 0 {
                for j in 0..<min(k, len) {
                    let t = Double(j) / Double(max(1, k))
                    let eased = pow(smoothstep01(t), power)
                    heights[run.end - j] = heights[run.end - j] * CGFloat(eased)
                }
            }
        }
    }
}

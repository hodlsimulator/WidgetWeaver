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
    // MARK: - Clamp / lerp

    static func clamp01(_ v: Double) -> Double { max(0.0, min(1.0, v)) }
    static func clamp01(_ v: CGFloat) -> CGFloat { max(0.0, min(1.0, v)) }

    static func clamp(_ v: Double, min lo: Double, max hi: Double) -> Double {
        guard lo < hi else { return lo }
        return max(lo, min(hi, v))
    }

    static func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        guard lo < hi else { return lo }
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

    // MARK: - Sampling

    static func sampleLinear(_ values: [Double], t: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        if values.count == 1 { return values[0] }
        let tt = clamp01(t)
        let x = tt * Double(values.count - 1)
        let i0 = Int(floor(x))
        let i1 = min(values.count - 1, i0 + 1)
        let f = x - Double(i0)
        return lerp(values[i0], values[i1], f)
    }

    static func sampleLinear(_ values: [CGFloat], t: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0.0 }
        if values.count == 1 { return values[0] }
        let tt = clamp01(t)
        let x = tt * CGFloat(values.count - 1)
        let i0 = Int(floor(x))
        let i1 = min(values.count - 1, i0 + 1)
        let f = x - CGFloat(i0)
        return values[i0] + (values[i1] - values[i0]) * f
    }

    // MARK: - Percentile scaling

    static func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let pp = clamp01(p)
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let r = pp * Double(sorted.count - 1)
        let i0 = Int(floor(r))
        let i1 = Int(ceil(r))
        if i0 == i1 { return sorted[i0] }
        let t = r - Double(i0)
        return lerp(sorted[i0], sorted[i1], t)
    }

    // MARK: - Smoothing (low-pass)

    static func smooth(_ values: [CGFloat], passes: Int) -> [CGFloat] {
        guard values.count >= 3, passes > 0 else { return values }
        var out = values
        var tmp = values
        for _ in 0..<passes {
            tmp[0] = out[0]
            tmp[out.count - 1] = out[out.count - 1]
            for i in 1..<(out.count - 1) {
                // 1–2–1 kernel
                tmp[i] = (out[i - 1] + out[i] * 2.0 + out[i + 1]) * 0.25
            }
            swap(&out, &tmp)
        }
        return out
    }

    static func smooth(_ values: [Double], passes: Int) -> [Double] {
        guard values.count >= 3, passes > 0 else { return values }
        var out = values
        var tmp = values
        for _ in 0..<passes {
            tmp[0] = out[0]
            tmp[out.count - 1] = out[out.count - 1]
            for i in 1..<(out.count - 1) {
                tmp[i] = (out[i - 1] + out[i] * 2.0 + out[i + 1]) * 0.25
            }
            swap(&out, &tmp)
        }
        return out
    }

    // MARK: - Monotone cubic resampling (uniform spacing)

    private static func monotoneCubicTangents(_ y: [CGFloat]) -> [CGFloat] {
        let n = y.count
        guard n >= 2 else { return y }

        var d = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            d[i] = y[i + 1] - y[i]
        }

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
                    // Harmonic mean.
                    m[i] = 2 * d0 * d1 / (d0 + d1)
                }
            }
        }

        // Fritsch–Carlson limiter.
        let eps: CGFloat = 1e-8
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

        let h00: CGFloat = 2 * t3 - 3 * t2 + 1
        let h10: CGFloat = t3 - 2 * t2 + t
        let h01: CGFloat = -2 * t3 + 3 * t2
        let h11: CGFloat = t3 - t2

        return h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
    }

    /// Resamples across the full domain including endpoints
    /// (j = 0 maps to x = 0; j = last maps to x = n-1).
    static func resampleMonotoneCubicEdges(_ y: [CGFloat], targetCount: Int) -> [CGFloat] {
        let n = y.count
        let outCount = max(2, targetCount)
        guard n >= 2 else {
            return Array(repeating: y.first ?? 0, count: outCount)
        }

        let tangents = monotoneCubicTangents(y)
        let maxX = CGFloat(n - 1)

        var out = [CGFloat](repeating: 0, count: outCount)
        for j in 0..<outCount {
            let t = (outCount <= 1) ? 0 : (CGFloat(j) / CGFloat(outCount - 1))
            let x = t * maxX
            out[j] = evalMonotoneCubic(y: y, m: tangents, x: x)
        }
        return out
    }

    /// Resamples at evenly-spaced bin centres, avoiding hard edge anchoring.
    static func resampleMonotoneCubicCenters(_ y: [CGFloat], targetCount: Int) -> [CGFloat] {
        let n = y.count
        let outCount = max(1, targetCount)
        guard n >= 2 else {
            return Array(repeating: y.first ?? 0, count: outCount)
        }

        let tangents = monotoneCubicTangents(y)
        let maxX = CGFloat(n - 1)

        var out = [CGFloat](repeating: 0, count: outCount)
        for j in 0..<outCount {
            let u = (CGFloat(j) + 0.5) / CGFloat(outCount)
            let x = u * maxX
            out[j] = evalMonotoneCubic(y: y, m: tangents, x: x)
        }
        return out
    }

    static func resampleMonotoneCubicEdges(_ y: [Double], targetCount: Int) -> [Double] {
        let yy = y.map { CGFloat($0) }
        return resampleMonotoneCubicEdges(yy, targetCount: targetCount).map { Double($0) }
    }

    static func resampleMonotoneCubicCenters(_ y: [Double], targetCount: Int) -> [Double] {
        let yy = y.map { CGFloat($0) }
        return resampleMonotoneCubicCenters(yy, targetCount: targetCount).map { Double($0) }
    }

    // MARK: - Distance field (fast chamfer)

    /// 3–4 chamfer distance transform in units of 1/3 px.
    /// - sources: 1 for source pixels, 0 otherwise.
    /// - traversable: optional mask; if provided, only pixels with 1 participate.
    static func chamferDistance3_4(
        width: Int,
        height: Int,
        sources: [UInt8],
        traversable: [UInt8]?
    ) -> [UInt16] {
        let count = width * height
        guard width > 0, height > 0, sources.count == count else {
            return []
        }
        if let traversable, traversable.count != count {
            return []
        }

        let INF: UInt16 = 0x3FFF
        let orth: UInt16 = 3
        let diag: UInt16 = 4

        var dist = [UInt16](repeating: INF, count: count)

        if let traversable {
            for i in 0..<count {
                if traversable[i] == 0 {
                    dist[i] = INF
                } else if sources[i] != 0 {
                    dist[i] = 0
                }
            }
        } else {
            for i in 0..<count {
                if sources[i] != 0 { dist[i] = 0 }
            }
        }

        // Forward pass.
        if let traversable {
            for y in 0..<height {
                let row = y * width
                for x in 0..<width {
                    let idx = row + x
                    if traversable[idx] == 0 { continue }
                    var best = dist[idx]
                    if best == 0 { continue }

                    if x > 0 {
                        let d = dist[idx - 1]
                        if d != INF { best = min(best, d &+ orth) }
                    }
                    if y > 0 {
                        let up = idx - width
                        let dUp = dist[up]
                        if dUp != INF { best = min(best, dUp &+ orth) }

                        if x > 0 {
                            let d = dist[up - 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                        if x + 1 < width {
                            let d = dist[up + 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                    }

                    dist[idx] = best
                }
            }
        } else {
            for y in 0..<height {
                let row = y * width
                for x in 0..<width {
                    let idx = row + x
                    var best = dist[idx]
                    if best == 0 { continue }

                    if x > 0 {
                        let d = dist[idx - 1]
                        if d != INF { best = min(best, d &+ orth) }
                    }
                    if y > 0 {
                        let up = idx - width
                        let dUp = dist[up]
                        if dUp != INF { best = min(best, dUp &+ orth) }

                        if x > 0 {
                            let d = dist[up - 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                        if x + 1 < width {
                            let d = dist[up + 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                    }

                    dist[idx] = best
                }
            }
        }

        // Backward pass.
        if let traversable {
            for y in stride(from: height - 1, through: 0, by: -1) {
                let row = y * width
                for x in stride(from: width - 1, through: 0, by: -1) {
                    let idx = row + x
                    if traversable[idx] == 0 { continue }
                    var best = dist[idx]
                    if best == 0 { continue }

                    if x + 1 < width {
                        let d = dist[idx + 1]
                        if d != INF { best = min(best, d &+ orth) }
                    }
                    if y + 1 < height {
                        let dn = idx + width
                        let dDn = dist[dn]
                        if dDn != INF { best = min(best, dDn &+ orth) }

                        if x + 1 < width {
                            let d = dist[dn + 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                        if x > 0 {
                            let d = dist[dn - 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                    }

                    dist[idx] = best
                }
            }
        } else {
            for y in stride(from: height - 1, through: 0, by: -1) {
                let row = y * width
                for x in stride(from: width - 1, through: 0, by: -1) {
                    let idx = row + x
                    var best = dist[idx]
                    if best == 0 { continue }

                    if x + 1 < width {
                        let d = dist[idx + 1]
                        if d != INF { best = min(best, d &+ orth) }
                    }
                    if y + 1 < height {
                        let dn = idx + width
                        let dDn = dist[dn]
                        if dDn != INF { best = min(best, dDn &+ orth) }

                        if x + 1 < width {
                            let d = dist[dn + 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                        if x > 0 {
                            let d = dist[dn - 1]
                            if d != INF { best = min(best, d &+ diag) }
                        }
                    }

                    dist[idx] = best
                }
            }
        }

        return dist
    }
}

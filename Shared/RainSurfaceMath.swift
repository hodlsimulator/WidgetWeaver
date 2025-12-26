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

    // MARK: - Clamp / Lerp

    static func clamp01(_ v: Double) -> Double {
        if v < 0 { return 0 }
        if v > 1 { return 1 }
        return v
    }

    static func clamp01(_ v: CGFloat) -> CGFloat {
        if v < 0 { return 0 }
        if v > 1 { return 1 }
        return v
    }

    static func clamp(_ v: Double, min lo: Double, max hi: Double) -> Double {
        if v < lo { return lo }
        if v > hi { return hi }
        return v
    }

    static func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        if v < lo { return lo }
        if v > hi { return hi }
        return v
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    // MARK: - Smoothstep

    static func smoothstep01(_ u: Double) -> Double {
        let t = clamp01(u)
        return t * t * (3.0 - 2.0 * t)
    }

    static func smoothstep01(_ u: CGFloat) -> CGFloat {
        let t = clamp01(u)
        return t * t * (3.0 - 2.0 * t)
    }

    static func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
        if edge0 == edge1 { return x < edge0 ? 0 : 1 }
        let t = clamp01((x - edge0) / (edge1 - edge0))
        return smoothstep01(t)
    }

    // MARK: - Pixel alignment

    static func onePixel(displayScale: CGFloat) -> CGFloat {
        1.0 / max(displayScale, 1.0)
    }

    static func alignToPixelCenter(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        let s = max(displayScale, 1.0)
        return (floor(value * s) + 0.5) / s
    }

    // MARK: - Array smoothing (low-pass)

    static func smooth(_ values: [CGFloat], passes: Int) -> [CGFloat] {
        guard values.count >= 3 else { return values }
        let p = max(0, passes)
        guard p > 0 else { return values }

        var current = values
        var tmp = values

        for _ in 0..<p {
            tmp[0] = current[0]
            tmp[tmp.count - 1] = current[current.count - 1]

            for i in 1..<(current.count - 1) {
                tmp[i] = 0.25 * current[i - 1] + 0.5 * current[i] + 0.25 * current[i + 1]
            }

            current = tmp
        }

        return current
    }

    static func smooth(_ values: [Double], passes: Int) -> [Double] {
        guard values.count >= 3 else { return values }
        let p = max(0, passes)
        guard p > 0 else { return values }

        var current = values
        var tmp = values

        for _ in 0..<p {
            tmp[0] = current[0]
            tmp[tmp.count - 1] = current[current.count - 1]

            for i in 1..<(current.count - 1) {
                tmp[i] = 0.25 * current[i - 1] + 0.5 * current[i] + 0.25 * current[i + 1]
            }

            current = tmp
        }

        return current
    }

    // MARK: - Monotone cubic resampling (uniform spacing)

    static func monotoneCubicTangents(_ y: [CGFloat]) -> [CGFloat] {
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
                    m[i] = 2 * d0 * d1 / (d0 + d1) // harmonic mean
                }
            }
        }

        // Hyman filter to limit overshoot.
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

    static func evaluateMonotoneCubic(y: [CGFloat], m: [CGFloat], x: CGFloat) -> CGFloat {
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
        guard n >= 2 else { return Array(repeating: y.first ?? 0, count: max(0, targetCount)) }
        let outCount = max(2, targetCount)

        let tangents = monotoneCubicTangents(y)
        var out = [CGFloat](repeating: 0, count: outCount)
        let maxX = CGFloat(n - 1)

        for j in 0..<outCount {
            let u = CGFloat(j) / CGFloat(outCount - 1)
            out[j] = evaluateMonotoneCubic(y: y, m: tangents, x: u * maxX)
        }

        return out
    }

    static func resampleMonotoneCubic(_ y: [Double], targetCount: Int) -> [Double] {
        let yy = y.map { CGFloat($0) }
        let out = resampleMonotoneCubic(yy, targetCount: targetCount)
        return out.map { Double($0) }
    }

    // MARK: - Edge fade

    static func edgeFadeFactor(x: CGFloat, minX: CGFloat, maxX: CGFloat, fadeWidth: CGFloat) -> CGFloat {
        let w = max(fadeWidth, 0.0001)
        let d = min(x - minX, maxX - x)
        return smoothstep(edge0: 0, edge1: w, x: d)
    }

    // MARK: - Legacy helper (kept for compatibility)

    static func edgeFactors(sampleCount: Int, startEaseMinutes: Int, endFadeMinutes: Int, endFadeFloor: Double) -> [Double] {
        let n = max(0, sampleCount)
        guard n > 0 else { return [] }

        let startEase = max(0, startEaseMinutes)
        let endFade = max(0, endFadeMinutes)

        var factors = [Double](repeating: 1.0, count: n)

        if startEase > 0 {
            let denom = Double(max(1, startEase))
            for i in 0..<min(n, startEase) {
                let t = Double(i + 1) / denom
                factors[i] *= smoothstep01(t)
            }
        }

        if endFade > 0 {
            let denom = Double(max(1, endFade))
            for k in 0..<min(n, endFade) {
                let i = (n - 1) - k
                let t = Double(k) / denom
                let floorV = clamp(endFadeFloor, min: 0.0, max: 1.0)
                let fade = lerp(1.0, floorV, smoothstep01(t))
                factors[i] *= fade
            }
        }

        return factors
    }
}

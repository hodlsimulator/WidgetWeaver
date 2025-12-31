//
//  RainForecastSurfaceRenderer+Data.swift
//  WidgetWeaver
//
//  Created by . . on 12/31/25.
//

import Foundation
import CoreGraphics

// MARK: - Data shaping helpers

extension RainForecastSurfaceRenderer {
    static func fillMissingLinearHoldEnds(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return values }
        var out = values

        let firstFinite = out.firstIndex(where: { $0.isFinite })
        if firstFinite == nil {
            return Array(repeating: 0.0, count: out.count)
        }

        if let first = firstFinite {
            let v = out[first]
            for i in 0..<first { out[i] = v }
        }

        var lastFinite: Int? = nil
        for i in 0..<out.count {
            let v = out[i]
            guard v.isFinite else { continue }
            if let last = lastFinite {
                let gap = i - last
                if gap > 1 {
                    let a = out[last]
                    let b = v
                    for k in 1..<gap {
                        let t = Double(k) / Double(gap)
                        out[last + k] = a + (b - a) * t
                    }
                }
            }
            lastFinite = i
        }

        if let last = lastFinite {
            let v = out[last]
            if last + 1 < out.count {
                for i in (last + 1)..<out.count { out[i] = v }
            }
        }

        for i in 0..<out.count {
            if !out[i].isFinite { out[i] = 0.0 }
            if out[i] < 0.0 { out[i] = 0.0 }
        }

        return out
    }

    static func robustReferenceMaxMMPerHour(values: [Double], defaultMax: Double, percentile: Double) -> Double {
        let finite = values.filter { $0.isFinite && $0 >= 0.0 }
        guard !finite.isEmpty else { return max(0.001, defaultMax) }
        let sorted = finite.sorted()
        let p = clamp01(percentile)
        let idx = Int(round(p * Double(max(0, sorted.count - 1))))
        let v = sorted[min(sorted.count - 1, max(0, idx))]
        return max(0.001, max(defaultMax, v))
    }

    static func applyEdgeEasing(values: [CGFloat], fraction: Double, power: Double) -> [CGFloat] {
        guard values.count >= 2 else { return values }
        let f = clamp01(fraction)
        guard f > 0.0001 else { return values }

        var out = values
        let n = out.count

        for i in 0..<n {
            let t = Double(i) / Double(max(1, n - 1))
            var m = 1.0
            if t < f {
                m = pow(clamp01(t / f), max(0.01, power))
            } else if t > 1.0 - f {
                m = pow(clamp01((1.0 - t) / f), max(0.01, power))
            }
            out[i] = out[i] * CGFloat(m)
        }

        return out
    }

    static func denseSampleCount(sourceCount: Int, rectWidthPoints: Double, displayScale: Double, maxDense: Int) -> Int {
        let px = max(1.0, rectWidthPoints * max(1.0, displayScale))
        let target = Int(round(px * 0.90))
        return max(sourceCount, min(maxDense, max(120, target)))
    }

    static func makeMinuteCertainties(sourceCount: Int, certainties01: [Double]) -> [CGFloat] {
        guard sourceCount > 0 else { return [] }

        if certainties01.count == sourceCount {
            return certainties01.map { CGFloat(clamp01($0)) }
        }

        if certainties01.isEmpty {
            return Array(repeating: CGFloat(1.0), count: sourceCount)
        }

        let clamped: [CGFloat] = certainties01.map { CGFloat(clamp01($0)) }
        return resampleLinear(clamped, toCount: sourceCount)
    }

    static func resampleLinear(_ values: [CGFloat], toCount n: Int) -> [CGFloat] {
        guard n > 0 else { return [] }
        guard values.count >= 2 else { return Array(repeating: values.first ?? 0.0, count: n) }
        if values.count == n { return values }

        var out: [CGFloat] = []
        out.reserveCapacity(n)

        let m = values.count
        for i in 0..<n {
            let t = Double(i) / Double(max(1, n - 1))
            let x = t * Double(m - 1)
            let i0 = Int(floor(x))
            let i1 = min(m - 1, i0 + 1)
            let u = x - Double(i0)
            let a = Double(values[i0])
            let b = Double(values[i1])
            out.append(CGFloat(a + (b - a) * u))
        }

        return out
    }

    static func smooth(values: [CGFloat], radius: Int) -> [CGFloat] {
        guard values.count >= 3, radius > 0 else { return values }
        let r = min(radius, max(1, values.count / 12))

        var out = values
        for i in 0..<values.count {
            let a = max(0, i - r)
            let b = min(values.count - 1, i + r)
            var sum: CGFloat = 0.0
            var count: CGFloat = 0.0
            for j in a...b {
                sum += values[j]
                count += 1.0
            }
            out[i] = sum / max(1.0, count)
        }

        return out
    }
}

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

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let tt = max(0.0, min(1.0, t))
        return a + (b - a) * tt
    }

    static func smoothstep01(_ u: Double) -> Double {
        let x = max(0.0, min(1.0, u))
        return x * x * (3.0 - 2.0 * x)
    }

    static func alignToPixelCenter(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (floor(value * displayScale) + 0.5) / displayScale
    }

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
            let startEase: Double
            if startN <= 0 {
                startEase = 1.0
            } else if i >= startN {
                startEase = 1.0
            } else if startN == 1 {
                startEase = 1.0
            } else {
                let u = Double(i) / Double(max(1, startN - 1))
                startEase = smoothstep01(u)
            }

            let endFade: Double
            if endN <= 0 {
                endFade = 1.0
            } else {
                let startIndex = max(0, sampleCount - endN)
                if i < startIndex {
                    endFade = 1.0
                } else if endN == 1 {
                    endFade = floorClamped
                } else {
                    let u = Double(i - startIndex) / Double(max(1, endN - 1))
                    let s = smoothstep01(u)
                    endFade = max(1.0 - s, floorClamped)
                }
            }

            out.append(startEase * endFade)
        }

        return out
    }

    static func smooth(_ values: [CGFloat], passes: Int) -> [CGFloat] {
        guard values.count >= 3, passes > 0 else { return values }

        var out = values
        var tmp = values

        for _ in 0..<passes {
            tmp = out

            let last = tmp.count - 1
            out[0] = (tmp[0] + tmp[1]) * 0.5
            out[last] = (tmp[last - 1] + tmp[last]) * 0.5

            if last >= 2 {
                for i in 1..<(last) {
                    out[i] = (tmp[i - 1] + tmp[i] + tmp[i + 1]) / 3.0
                }
            }
        }

        return out
    }
}

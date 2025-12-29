//
//  RainSurfaceGeometry.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI

struct RainSurfaceGeometry {
    let chartRect: CGRect
    let baselineY: CGFloat
    let heights: [CGFloat]
    let certainties: [Double]
    let displayScale: CGFloat

    init(chartRect: CGRect, baselineY: CGFloat, heights: [CGFloat], certainties: [Double], displayScale: CGFloat) {
        self.chartRect = chartRect
        self.baselineY = baselineY.isFinite ? baselineY : chartRect.maxY
        self.displayScale = displayScale.isFinite ? displayScale : 1.0

        self.heights = heights.map { h in
            guard h.isFinite else { return 0.0 }
            return max(0.0, h)
        }

        self.certainties = certainties.map { c in
            guard c.isFinite else { return 0.0 }
            return RainSurfaceMath.clamp01(c)
        }
    }

    var sampleCount: Int { heights.count }

    var dx: CGFloat {
        guard sampleCount > 1 else { return 0.0 }
        let w = chartRect.width.isFinite ? chartRect.width : 0.0
        return w / CGFloat(sampleCount - 1)
    }

    func xAt(_ index: Int) -> CGFloat {
        chartRect.minX + CGFloat(index) * dx
    }

    func surfaceYAt(_ index: Int) -> CGFloat {
        guard index >= 0 && index < heights.count else { return baselineY }
        let h = heights[index]
        guard h.isFinite else { return baselineY }
        return baselineY - max(0.0, h)
    }

    func certaintyAt(_ index: Int) -> Double {
        guard index >= 0 && index < certainties.count else { return 1.0 }
        return RainSurfaceMath.clamp01(certainties[index])
    }

    func surfacePointAt(_ index: Int) -> CGPoint {
        CGPoint(x: xAt(index), y: surfaceYAt(index))
    }

    func sampleSurfaceY(atX x: CGFloat) -> CGFloat {
        guard sampleCount > 1 else { return baselineY }
        let denom = max(0.000_001, chartRect.width)
        let t = (x - chartRect.minX) / denom
        let u = RainSurfaceMath.clamp01(Double(t)) * Double(sampleCount - 1)

        let i0 = max(0, min(sampleCount - 2, Int(floor(u))))
        let frac = CGFloat(u - Double(i0))

        let y0 = surfaceYAt(i0)
        let y1 = surfaceYAt(i0 + 1)
        let y = y0 + (y1 - y0) * frac
        return y.isFinite ? y : baselineY
    }

    func sampleCertainty(atX x: CGFloat) -> Double {
        guard sampleCount > 1 else { return 1.0 }
        let denom = max(0.000_001, chartRect.width)
        let t = (x - chartRect.minX) / denom
        let u = RainSurfaceMath.clamp01(Double(t)) * Double(sampleCount - 1)

        let i0 = max(0, min(sampleCount - 2, Int(floor(u))))
        let frac = u - Double(i0)

        let c0 = certaintyAt(i0)
        let c1 = certaintyAt(i0 + 1)
        let c = c0 + (c1 - c0) * frac
        return c.isFinite ? RainSurfaceMath.clamp01(c) : 0.0
    }

    func surfacePolylinePath() -> Path {
        var p = Path()
        guard sampleCount > 0 else { return p }

        p.move(to: surfacePointAt(0))
        if sampleCount > 1 {
            for i in 1..<sampleCount {
                p.addLine(to: surfacePointAt(i))
            }
        }
        return p
    }

    func filledPath(usingInsetTopPoints insetTop: [CGPoint]? = nil) -> Path {
        var p = Path()
        guard sampleCount > 0 else { return p }

        let topPoints: [CGPoint] = {
            if let insetTop, insetTop.count == sampleCount { return insetTop }
            return (0..<sampleCount).map { surfacePointAt($0) }
        }()

        p.move(to: topPoints[0])
        if sampleCount > 1 {
            for i in 1..<sampleCount {
                p.addLine(to: topPoints[i])
            }
        }

        p.addLine(to: CGPoint(x: xAt(sampleCount - 1), y: baselineY))
        p.addLine(to: CGPoint(x: xAt(0), y: baselineY))
        p.closeSubpath()

        return p
    }
}

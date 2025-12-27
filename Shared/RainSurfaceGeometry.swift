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
        self.baselineY = baselineY
        self.heights = heights
        self.certainties = certainties
        self.displayScale = displayScale
    }

    var sampleCount: Int { heights.count }

    var dx: CGFloat {
        guard sampleCount > 1 else { return 0 }
        return chartRect.width / CGFloat(sampleCount - 1)
    }

    func xAt(_ index: Int) -> CGFloat {
        chartRect.minX + CGFloat(index) * dx
    }

    func surfaceYAt(_ index: Int) -> CGFloat {
        let h = max(0, heights[index])
        return baselineY - h
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
        let t = (x - chartRect.minX) / max(0.000_001, chartRect.width)
        let u = RainSurfaceMath.clamp01(Double(t)) * Double(sampleCount - 1)
        let i0 = max(0, min(sampleCount - 2, Int(floor(u))))
        let frac = CGFloat(u - Double(i0))
        let y0 = surfaceYAt(i0)
        let y1 = surfaceYAt(i0 + 1)
        return y0 + (y1 - y0) * frac
    }

    func sampleCertainty(atX x: CGFloat) -> Double {
        guard sampleCount > 1 else { return 1.0 }
        let t = (x - chartRect.minX) / max(0.000_001, chartRect.width)
        let u = RainSurfaceMath.clamp01(t) * Double(sampleCount - 1)
        let i0 = max(0, min(sampleCount - 2, Int(floor(u))))
        let frac = u - Double(i0)
        let c0 = certaintyAt(i0)
        let c1 = certaintyAt(i0 + 1)
        return c0 + (c1 - c0) * frac
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

        // Start at baseline left, go up to surface, trace surface, then back down to baseline.
        p.move(to: CGPoint(x: chartRect.minX, y: baselineY))
        p.addLine(to: topPoints[0])

        if sampleCount > 1 {
            for i in 1..<sampleCount {
                p.addLine(to: topPoints[i])
            }
        }

        p.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))
        p.closeSubpath()
        return p
    }
}

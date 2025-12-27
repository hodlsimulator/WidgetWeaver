//
//  RainSurfaceGeometry.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Path construction helpers for the rain surface.
//

import Foundation
import SwiftUI

enum RainSurfaceGeometry {

    static func makeCorePath(chartRect: CGRect, baselineY: CGFloat, stepX: CGFloat, heights: [CGFloat]) -> Path {
        var p = Path()
        guard !heights.isEmpty else { return p }

        let n = heights.count
        let y0 = baselineY - heights[0]
        let yN = baselineY - heights[n - 1]

        p.move(to: CGPoint(x: chartRect.minX, y: baselineY))
        p.addLine(to: CGPoint(x: chartRect.minX, y: y0))

        for i in 0..<n {
            let x = chartRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            p.addLine(to: CGPoint(x: x, y: y))
        }

        p.addLine(to: CGPoint(x: chartRect.maxX, y: yN))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))
        p.closeSubpath()

        return p
    }

    static func makeTopEdgePath(chartRect: CGRect, baselineY: CGFloat, stepX: CGFloat, heights: [CGFloat]) -> Path {
        var p = Path()
        guard !heights.isEmpty else { return p }

        let n = heights.count
        let y0 = baselineY - heights[0]
        let yN = baselineY - heights[n - 1]

        p.move(to: CGPoint(x: chartRect.minX, y: y0))

        for i in 0..<n {
            let x = chartRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            p.addLine(to: CGPoint(x: x, y: y))
        }

        p.addLine(to: CGPoint(x: chartRect.maxX, y: yN))

        return p
    }
}

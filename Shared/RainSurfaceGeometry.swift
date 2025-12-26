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
    /// Builds a single closed core area:
    /// baseline → smooth top curve → baseline → close.
    static func makeCorePath(
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        let n = heights.count
        guard n > 0 else {
            var p = Path()
            p.addRect(CGRect(x: chartRect.minX, y: baselineY, width: chartRect.width, height: 0))
            return p
        }

        let topPoints = makeTopPoints(chartRect: chartRect, baselineY: baselineY, stepX: stepX, heights: heights)

        var path = Path()
        path.move(to: CGPoint(x: chartRect.minX, y: baselineY))
        path.addLine(to: topPoints[0])
        addSmoothQuad(points: topPoints, to: &path)
        path.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))
        path.closeSubpath()
        return path
    }

    /// Builds the top edge only (smooth curve across the chart width).
    static func makeTopEdgePath(
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        let n = heights.count
        guard n > 0 else { return Path() }

        let topPoints = makeTopPoints(chartRect: chartRect, baselineY: baselineY, stepX: stepX, heights: heights)

        var path = Path()
        path.move(to: topPoints[0])
        addSmoothQuad(points: topPoints, to: &path)
        return path
    }

    /// Even-odd mask path: (clip rect) minus (core path).
    static func makeOutsideMaskPath(clipRect: CGRect, corePath: Path) -> Path {
        var p = Path()
        p.addRect(clipRect)
        p.addPath(corePath)
        return p
    }

    // MARK: - Helpers

    private static func makeTopPoints(
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> [CGPoint] {
        let n = heights.count
        let firstY = baselineY - (heights.first ?? 0)
        let lastY = baselineY - (heights.last ?? 0)

        var pts: [CGPoint] = []
        pts.reserveCapacity(n + 2)

        // Extend to edges without creating hard vertical walls (tail easing enforces heights≈0 at ends).
        pts.append(CGPoint(x: chartRect.minX, y: firstY))
        for i in 0..<n {
            let x = chartRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            pts.append(CGPoint(x: x, y: y))
        }
        pts.append(CGPoint(x: chartRect.maxX, y: lastY))

        return pts
    }

    /// Adds a quad-smoothed polyline passing through `points` to `path`.
    /// `path` is expected to already be moved/connected to `points[0]`.
    private static func addSmoothQuad(points: [CGPoint], to path: inout Path) {
        guard points.count >= 2 else { return }
        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        for i in 1..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            let mid = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
            path.addQuadCurve(to: mid, control: current)
        }

        if let secondLast = points.dropLast().last, let last = points.last {
            path.addQuadCurve(to: last, control: secondLast)
        }
    }
}

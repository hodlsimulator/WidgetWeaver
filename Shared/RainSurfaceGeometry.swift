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

        var pts: [CGPoint] = []
        pts.reserveCapacity(n + 2)

        // Baseline anchor at chart bottom.
        pts.append(CGPoint(x: chartRect.minX, y: baselineY))

        // Per-column centres.
        for i in 0..<n {
            let x = chartRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            pts.append(CGPoint(x: x, y: y))
        }

        pts.append(CGPoint(x: chartRect.maxX, y: baselineY))

        var path = Path()
        addSmoothQuadSegments(&path, points: pts)
        path.closeSubpath()
        return path
    }

    /// Top edge (open) used for gloss band and optional glints.
    static func makeTopEdgePath(
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        let n = heights.count
        guard n > 0 else { return Path() }

        var pts: [CGPoint] = []
        pts.reserveCapacity(n + 2)

        // Extend to edges without forcing the edge down to baseline.
        let firstY = baselineY - (heights.first ?? 0)
        let lastY = baselineY - (heights.last ?? 0)
        pts.append(CGPoint(x: chartRect.minX, y: firstY))

        for i in 0..<n {
            let x = chartRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            pts.append(CGPoint(x: x, y: y))
        }

        pts.append(CGPoint(x: chartRect.maxX, y: lastY))

        var path = Path()
        addSmoothQuadSegments(&path, points: pts)
        return path
    }

    /// Smooth quadratic chain through given points.
    static func addSmoothQuadSegments(_ path: inout Path, points: [CGPoint]) {
        guard points.count > 1 else {
            if let p0 = points.first { path.move(to: p0) }
            return
        }

        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        for i in 1..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            let mid = CGPoint(
                x: (current.x + next.x) * 0.5,
                y: (current.y + next.y) * 0.5
            )
            path.addQuadCurve(to: mid, control: current)
        }

        if let secondLast = points.dropLast().last, let last = points.last {
            path.addQuadCurve(to: last, control: secondLast)
        }
    }

    /// Even-odd mask path: (clip rect) minus (core path).
    static func makeOutsideMaskPath(clipRect: CGRect, corePath: Path) -> Path {
        var p = Path()
        p.addRect(clipRect)
        p.addPath(corePath)
        return p
    }
}

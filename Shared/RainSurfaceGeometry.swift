//
//  RainSurfaceGeometry.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Surface path construction helpers.
//

import SwiftUI

enum RainSurfaceGeometry {
    static func wetRanges(from mask: [Bool]) -> [Range<Int>] {
        guard !mask.isEmpty else { return [] }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(6)

        var start: Int? = nil
        for i in 0..<mask.count {
            if mask[i] {
                if start == nil { start = i }
            } else if let s = start {
                ranges.append(s..<i)
                start = nil
            }
        }

        if let s = start {
            ranges.append(s..<mask.count)
        }

        return ranges
    }

    static func makeSurfacePath(
        for range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var topPoints: [CGPoint] = []
        topPoints.reserveCapacity(range.count + 2)
        topPoints.append(CGPoint(x: startEdgeX, y: baselineY))

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            topPoints.append(CGPoint(x: x, y: y))
        }

        topPoints.append(CGPoint(x: endEdgeX, y: baselineY))

        var path = Path()
        addSmoothQuadSegments(&path, points: topPoints, moveToFirst: true)
        path.closeSubpath()
        return path
    }

    static func makeTopEdgePath(
        for range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        guard let first = range.first else { return Path() }

        let last = max(first, range.upperBound - 1)
        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var points: [CGPoint] = []
        points.reserveCapacity(range.count + 2)

        points.append(CGPoint(x: startEdgeX, y: baselineY - heights[first]))

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            points.append(CGPoint(x: x, y: y))
        }

        points.append(CGPoint(x: endEdgeX, y: baselineY - heights[last]))

        var path = Path()
        addSmoothQuadSegments(&path, points: points, moveToFirst: true)
        return path
    }

    static func addSmoothQuadSegments(_ path: inout Path, points: [CGPoint], moveToFirst: Bool) {
        guard points.count >= 2 else { return }

        if moveToFirst { path.move(to: points[0]) }

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

        path.addQuadCurve(to: points[points.count - 1], control: points[points.count - 2])
    }

    static func makeOutsideMaskPath(plotRect: CGRect, surfacePath: Path, padding: CGFloat) -> Path {
        let pad = max(0, padding)
        var p = Path()
        p.addRect(plotRect.insetBy(dx: -pad, dy: -pad))
        p.addPath(surfacePath)
        return p
    }
}

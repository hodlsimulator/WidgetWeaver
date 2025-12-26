//
//  RainSurfaceGeometry.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Surface path construction helpers.
//

import Foundation
import SwiftUI

enum RainSurfaceGeometry {

    struct SurfaceSegment {
        let range: Range<Int>
        let surfacePath: Path
        let topEdgePath: Path
        let peakIndex: Int
        let peakHeight: CGFloat
        let startX: CGFloat
        let endX: CGFloat
    }

    static func wetRanges(from heights: [CGFloat], threshold: CGFloat) -> [Range<Int>] {
        guard !heights.isEmpty else { return [] }

        var raw: [Range<Int>] = []
        var start: Int? = nil

        for i in 0..<heights.count {
            let wet = heights[i] > threshold
            if wet {
                if start == nil { start = i }
            } else if let s = start {
                raw.append(s..<i)
                start = nil
            }
        }

        if let s = start {
            raw.append(s..<heights.count)
        }

        if raw.isEmpty { return [] }

        // Expand by 1 on each side to avoid hard starts/ends, then merge overlaps.
        let expanded: [Range<Int>] = raw.map { r in
            let lo = max(0, r.lowerBound - 1)
            let hi = min(heights.count, r.upperBound + 1)
            return lo..<hi
        }.sorted { $0.lowerBound < $1.lowerBound }

        var merged: [Range<Int>] = []
        for r in expanded {
            if merged.isEmpty {
                merged.append(r)
                continue
            }

            let last = merged[merged.count - 1]
            if r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }

        return merged
    }

    static func buildSegments(
        plotRect: CGRect,
        baselineY: CGFloat,
        heights: [CGFloat],
        threshold: CGFloat
    ) -> [SurfaceSegment] {
        guard heights.count >= 2 else { return [] }

        let stepX = plotRect.width / CGFloat(max(1, heights.count - 1))
        let ranges = wetRanges(from: heights, threshold: threshold)

        var out: [SurfaceSegment] = []
        out.reserveCapacity(ranges.count)

        for r in ranges {
            let surface = makeSurfacePath(range: r, plotRect: plotRect, baselineY: baselineY, stepX: stepX, heights: heights)
            let top = makeTopEdgePath(range: r, plotRect: plotRect, baselineY: baselineY, stepX: stepX, heights: heights)

            var peakIndex = r.lowerBound
            var peakHeight: CGFloat = 0
            for i in r {
                let h = heights[i]
                if h > peakHeight {
                    peakHeight = h
                    peakIndex = i
                }
            }

            let startX = plotRect.minX + CGFloat(r.lowerBound) * stepX
            let endX = plotRect.minX + CGFloat(max(r.lowerBound, r.upperBound - 1)) * stepX

            out.append(
                SurfaceSegment(
                    range: r,
                    surfacePath: surface,
                    topEdgePath: top,
                    peakIndex: peakIndex,
                    peakHeight: peakHeight,
                    startX: startX,
                    endX: endX
                )
            )
        }

        return out
    }

    static func makeSurfacePath(
        range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        guard !range.isEmpty else { return Path() }

        let start = range.lowerBound
        let endInclusive = max(range.lowerBound, range.upperBound - 1)

        var path = Path()

        let xStart = plotRect.minX + CGFloat(start) * stepX
        path.move(to: CGPoint(x: xStart, y: baselineY))

        for i in start...endInclusive {
            let x = plotRect.minX + CGFloat(i) * stepX
            let y = baselineY - heights[i]
            path.addLine(to: CGPoint(x: x, y: y))
        }

        let xEnd = plotRect.minX + CGFloat(endInclusive) * stepX
        path.addLine(to: CGPoint(x: xEnd, y: baselineY))
        path.closeSubpath()

        return path
    }

    static func makeTopEdgePath(
        range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        guard !range.isEmpty else { return Path() }

        let start = range.lowerBound
        let endInclusive = max(range.lowerBound, range.upperBound - 1)

        var path = Path()

        let x0 = plotRect.minX + CGFloat(start) * stepX
        let y0 = baselineY - heights[start]
        path.move(to: CGPoint(x: x0, y: y0))

        if start < endInclusive {
            for i in (start + 1)...endInclusive {
                let x = plotRect.minX + CGFloat(i) * stepX
                let y = baselineY - heights[i]
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    static func unionCoreMaskPath(segments: [SurfaceSegment]) -> Path {
        var mask = Path()
        for s in segments {
            mask.addPath(s.surfacePath)
        }
        return mask
    }

    static func outsideMaskPath(clipRect: CGRect, coreMask: Path) -> Path {
        var p = Path()
        p.addRect(clipRect)
        p.addPath(coreMask)
        return p
    }
}

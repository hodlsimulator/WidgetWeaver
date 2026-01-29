//
//  SegmentedOuterRingRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI

/// Canvas renderer for the Segmented face outer ring.
///
/// The renderer is intentionally CoreGraphics-adjacent (CGPath first), then wrapped into SwiftUI `Path`
/// for `GraphicsContext` drawing. This keeps the geometry stable and avoids shape re-tessellation surprises
/// in WidgetKit snapshots.
struct SegmentedOuterRingRenderer {

    private static let segmentCount: Int = 12

    func render(
        into context: inout GraphicsContext,
        size: CGSize,
        style: SegmentedOuterRingStyle,
        scale: CGFloat
    ) {
        guard size.width > 1, size.height > 1 else { return }

        let centre = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

        renderBed(into: &context, size: size, centre: centre, style: style)
        renderBlocks(into: &context, size: size, centre: centre, style: style, scale: scale)
    }

    private func renderBed(
        into context: inout GraphicsContext,
        size: CGSize,
        centre: CGPoint,
        style: SegmentedOuterRingStyle
    ) {
        let bedPath = Path(
            AnnularSegmentCGPath.annulus(
                centre: centre,
                innerRadius: style.radii.bedInner,
                outerRadius: style.radii.bedOuter
            )
        )

        let start = CGPoint(x: centre.x - style.radii.bedOuter, y: centre.y - style.radii.bedOuter)
        let end = CGPoint(x: centre.x + style.radii.bedOuter, y: centre.y + style.radii.bedOuter)

        let shading = GraphicsContext.Shading.linearGradient(
            style.bedFillGradient,
            startPoint: start,
            endPoint: end
        )

        context.fill(
            bedPath,
            with: shading,
            style: FillStyle(eoFill: true, antialiased: true)
        )
    }

    private func renderBlocks(
        into context: inout GraphicsContext,
        size: CGSize,
        centre: CGPoint,
        style: SegmentedOuterRingStyle,
        scale: CGFloat
    ) {
        let fullSpan = CGFloat.pi * 2.0
        let segmentSpan = fullSpan / CGFloat(Self.segmentCount)
        let halfGap = style.gap.angular * 0.5

        let gradientStart = CGPoint(x: centre.x - style.radii.blockOuter, y: centre.y - style.radii.blockOuter)
        let gradientEnd = CGPoint(x: centre.x + style.radii.blockOuter, y: centre.y + style.radii.blockOuter)

        for idx in 0..<Self.segmentCount {
            // Centre at 12 o'clock for idx == 0.
            let centreAngle = (-CGFloat.pi * 0.5) + (CGFloat(idx) * segmentSpan)

            let startAngle = centreAngle - (segmentSpan * 0.5) + halfGap
            let endAngle = centreAngle + (segmentSpan * 0.5) - halfGap

            guard endAngle > startAngle else { continue }

            let cgPath = AnnularSegmentCGPath.segment(
                centre: centre,
                innerRadius: style.radii.blockInner,
                outerRadius: style.radii.blockOuter,
                startAngle: startAngle,
                endAngle: endAngle
            )

            let path = Path(cgPath)

            let gradient = (idx % 2 == 0) ? style.blockFillEvenGradient : style.blockFillOddGradient
            let shading = GraphicsContext.Shading.linearGradient(
                gradient,
                startPoint: gradientStart,
                endPoint: gradientEnd
            )

            context.fill(path, with: shading)

            if style.diagnostic.enabled {
                renderMarker(
                    into: &context,
                    centre: centre,
                    angle: centreAngle,
                    radius: style.radii.blockMid,
                    markerRadius: style.diagnostic.markerRadius,
                    colour: style.diagnostic.markerColour,
                    scale: scale
                )
            }
        }
    }

    private func renderMarker(
        into context: inout GraphicsContext,
        centre: CGPoint,
        angle: CGFloat,
        radius: CGFloat,
        markerRadius: CGFloat,
        colour: Color,
        scale: CGFloat
    ) {
        guard markerRadius > 0 else { return }

        var p = CGPoint(
            x: centre.x + cos(angle) * radius,
            y: centre.y + sin(angle) * radius
        )

        p = PixelSnapping.snap(p, scale: scale)

        let rect = CGRect(
            x: p.x - markerRadius,
            y: p.y - markerRadius,
            width: markerRadius * 2.0,
            height: markerRadius * 2.0
        )

        context.fill(Path(ellipseIn: rect), with: .color(colour))
    }
}

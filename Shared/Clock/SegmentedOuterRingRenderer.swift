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

        context.blendMode = .normal

        let centre = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

        renderBed(into: &context, size: size, centre: centre, style: style)
        renderBlocks(into: &context, size: size, centre: centre, style: style, scale: scale)

        context.blendMode = .normal
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

        renderBedContactOcclusion(into: &context, centre: centre, style: style)
        renderBedLips(into: &context, centre: centre, style: style)
    }

    private func renderBedContactOcclusion(
        into context: inout GraphicsContext,
        centre: CGPoint,
        style: SegmentedOuterRingStyle
    ) {
        context.blendMode = .multiply

        let outerBandInner = style.radii.blockOuter
        let outerBandOuter = style.radii.bedOuter

        if outerBandOuter > outerBandInner {
            let outerBandPath = Path(
                AnnularSegmentCGPath.annulus(
                    centre: centre,
                    innerRadius: outerBandInner,
                    outerRadius: outerBandOuter
                )
            )

            let outerBandShading = GraphicsContext.Shading.radialGradient(
                style.bedContactOcclusion.outerBandGradient,
                center: centre,
                startRadius: outerBandInner,
                endRadius: outerBandOuter
            )

            context.fill(
                outerBandPath,
                with: outerBandShading,
                style: FillStyle(eoFill: true, antialiased: true)
            )
        }

        let innerBandInner = style.radii.bedInner
        let innerBandOuter = style.radii.blockInner

        if innerBandOuter > innerBandInner {
            let innerBandPath = Path(
                AnnularSegmentCGPath.annulus(
                    centre: centre,
                    innerRadius: innerBandInner,
                    outerRadius: innerBandOuter
                )
            )

            let innerBandShading = GraphicsContext.Shading.radialGradient(
                style.bedContactOcclusion.innerBandGradient,
                center: centre,
                startRadius: innerBandInner,
                endRadius: innerBandOuter
            )

            context.fill(
                innerBandPath,
                with: innerBandShading,
                style: FillStyle(eoFill: true, antialiased: true)
            )
        }

        context.blendMode = .normal
    }

    private func renderBedLips(
        into context: inout GraphicsContext,
        centre: CGPoint,
        style: SegmentedOuterRingStyle
    ) {
        let w = style.bedLips.lineWidth
        guard w > 0 else { return }

        let outerR = max(0.0, style.radii.bedOuter - (w * 0.5))
        let innerR = max(0.0, style.radii.bedInner + (w * 0.5))

        guard outerR > 0.0, outerR > innerR else { return }

        let start = CGPoint(x: centre.x - style.radii.bedOuter, y: centre.y - style.radii.bedOuter)
        let end = CGPoint(x: centre.x + style.radii.bedOuter, y: centre.y + style.radii.bedOuter)

        let outerPath = Path(
            ellipseIn: CGRect(
                x: centre.x - outerR,
                y: centre.y - outerR,
                width: outerR * 2.0,
                height: outerR * 2.0
            )
        )

        let innerPath = Path(
            ellipseIn: CGRect(
                x: centre.x - innerR,
                y: centre.y - innerR,
                width: innerR * 2.0,
                height: innerR * 2.0
            )
        )

        let highlightOuter = GraphicsContext.Shading.linearGradient(
            style.bedLips.highlightGradient,
            startPoint: start,
            endPoint: end
        )

        let shadowOuter = GraphicsContext.Shading.linearGradient(
            style.bedLips.shadowGradient,
            startPoint: end,
            endPoint: start
        )

        let highlightInner = GraphicsContext.Shading.linearGradient(
            style.bedLips.highlightGradient,
            startPoint: end,
            endPoint: start
        )

        let shadowInner = GraphicsContext.Shading.linearGradient(
            style.bedLips.shadowGradient,
            startPoint: start,
            endPoint: end
        )

        let stroke = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)

        context.stroke(outerPath, with: highlightOuter, style: stroke)
        context.stroke(outerPath, with: shadowOuter, style: stroke)
        context.stroke(innerPath, with: shadowInner, style: stroke)
        context.stroke(innerPath, with: highlightInner, style: stroke)
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

        // Encode the gap in the block geometry itself.
        let halfGap = (style.gap.angular * 0.5) + style.gap.edgeTrimAngular

        let gradientStart = CGPoint(x: centre.x - style.radii.blockOuter, y: centre.y - style.radii.blockOuter)
        let gradientEnd = CGPoint(x: centre.x + style.radii.blockOuter, y: centre.y + style.radii.blockOuter)

        for idx in 0..<Self.segmentCount {
            // Centre at 12 o'clock for idx == 0.
            let centreAngle = (-CGFloat.pi * 0.5) + (CGFloat(idx) * segmentSpan)

            let startAngle = centreAngle - (segmentSpan * 0.5) + halfGap
            let endAngle = centreAngle + (segmentSpan * 0.5) - halfGap

            guard endAngle > startAngle else { continue }

            let cgPath = AnnularSegmentCGPath.chamferedSegment(
                centre: centre,
                innerRadius: style.radii.blockInner,
                outerRadius: style.radii.blockOuter,
                startAngle: startAngle,
                endAngle: endAngle,
                chamfer: style.chamfer.depth
            )

            let path = Path(cgPath)

            let gradient: Gradient
            if style.diagnostic.enabled {
                gradient = (idx % 2 == 0) ? style.blockFillEvenGradient : style.blockFillOddGradient
            } else {
                gradient = style.blockFillEvenGradient
            }

            let baseShading = GraphicsContext.Shading.linearGradient(
                gradient,
                startPoint: gradientStart,
                endPoint: gradientEnd
            )

            context.blendMode = .normal
            context.fill(path, with: baseShading)

            // Per-block isolation: bevel, rim, and clipped strokes are applied inside a drawLayer.
            // This avoids state bleed across segments and keeps all shading inside the block.
            context.drawLayer { layer in
                layer.clip(to: path)
                renderBlockBevel(
                    into: &layer,
                    blockPath: path,
                    centre: centre,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    gradientStart: gradientStart,
                    gradientEnd: gradientEnd,
                    style: style
                )
            }

            if style.diagnostic.enabled {
                // Segment centre marker.
                renderMarker(
                    into: &context,
                    centre: centre,
                    angle: centreAngle,
                    radius: style.radii.blockMid,
                    markerRadius: style.diagnostic.markerRadius,
                    colour: style.diagnostic.segmentMarkerColour,
                    scale: scale
                )

                // Gap centre marker (between segments).
                let gapAngle = centreAngle + (segmentSpan * 0.5)
                renderMarker(
                    into: &context,
                    centre: centre,
                    angle: gapAngle,
                    radius: style.radii.blockMid,
                    markerRadius: style.diagnostic.markerRadius * 0.85,
                    colour: style.diagnostic.gapMarkerColour,
                    scale: scale
                )
            }
        }

        context.blendMode = .normal
    }

    private func renderBlockBevel(
        into context: inout GraphicsContext,
        blockPath: Path,
        centre: CGPoint,
        startAngle: CGFloat,
        endAngle: CGFloat,
        gradientStart: CGPoint,
        gradientEnd: CGPoint,
        style: SegmentedOuterRingStyle
    ) {
        let bevel = style.blockBevel

        // Screen-space lighting: highlight top-left, shadow bottom-right.
        let highlightShading = GraphicsContext.Shading.linearGradient(
            bevel.highlightOverlayGradient,
            startPoint: gradientStart,
            endPoint: gradientEnd
        )

        let shadowShading = GraphicsContext.Shading.linearGradient(
            bevel.shadowOverlayGradient,
            startPoint: gradientEnd,
            endPoint: gradientStart
        )

        context.blendMode = .screen
        context.fill(blockPath, with: highlightShading)

        context.blendMode = .multiply
        context.fill(blockPath, with: shadowShading)

        // Rim strokes: draw only the inner/outer arcs (avoid strokes landing on the air-gap boundaries).
        renderPerimeterRimStrokes(
            into: &context,
            centre: centre,
            startAngle: startAngle,
            endAngle: endAngle,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            style: style
        )

        // Edge accents are inset so strokes never leak into the air gaps.
        let outerW = bevel.outerEdgeLineWidth
        if outerW > 0 {
            let r = max(0.0, style.radii.blockOuter - outerW)
            if r > 0 {
                let outerArc = arcPath(centre: centre, radius: r, startAngle: startAngle, endAngle: endAngle)

                let outerEdgeShading = GraphicsContext.Shading.linearGradient(
                    bevel.perimeterHighlightGradient,
                    startPoint: gradientStart,
                    endPoint: gradientEnd
                )

                context.blendMode = .screen
                context.stroke(
                    outerArc,
                    with: outerEdgeShading,
                    style: StrokeStyle(lineWidth: outerW, lineCap: .butt, lineJoin: .miter)
                )
            }
        }

        let innerW = bevel.innerEdgeLineWidth
        if innerW > 0 {
            let r = max(0.0, style.radii.blockInner + innerW)
            if r > 0 {
                let innerArc = arcPath(centre: centre, radius: r, startAngle: startAngle, endAngle: endAngle)

                let innerEdgeShading = GraphicsContext.Shading.linearGradient(
                    bevel.perimeterShadowGradient,
                    startPoint: gradientEnd,
                    endPoint: gradientStart
                )

                context.blendMode = .multiply
                context.stroke(
                    innerArc,
                    with: innerEdgeShading,
                    style: StrokeStyle(lineWidth: innerW, lineCap: .butt, lineJoin: .miter)
                )
            }
        }

        renderRadialEdgeAccents(
            into: &context,
            centre: centre,
            startAngle: startAngle,
            endAngle: endAngle,
            style: style
        )

        context.blendMode = .normal
    }

    private func renderPerimeterRimStrokes(
        into context: inout GraphicsContext,
        centre: CGPoint,
        startAngle: CGFloat,
        endAngle: CGFloat,
        gradientStart: CGPoint,
        gradientEnd: CGPoint,
        style: SegmentedOuterRingStyle
    ) {
        let bevel = style.blockBevel
        let w = bevel.perimeterRimStrokeWidth
        guard w > 0 else { return }

        let highlight = GraphicsContext.Shading.linearGradient(
            bevel.perimeterHighlightGradient,
            startPoint: gradientStart,
            endPoint: gradientEnd
        )

        let shadow = GraphicsContext.Shading.linearGradient(
            bevel.perimeterShadowGradient,
            startPoint: gradientEnd,
            endPoint: gradientStart
        )

        // Stroke only the outer and inner arcs so nothing lands on the gap boundaries.
        let outerR = max(0.0, style.radii.blockOuter - (w * 0.50))
        let innerR = max(0.0, style.radii.blockInner + (w * 0.50))

        if outerR > 0 {
            let outerArc = arcPath(centre: centre, radius: outerR, startAngle: startAngle, endAngle: endAngle)

            context.blendMode = .screen
            context.stroke(
                outerArc,
                with: highlight,
                style: StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .miter)
            )

            context.blendMode = .multiply
            context.stroke(
                outerArc,
                with: shadow,
                style: StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .miter)
            )
        }

        if innerR > 0 {
            let innerArc = arcPath(centre: centre, radius: innerR, startAngle: startAngle, endAngle: endAngle)

            context.blendMode = .screen
            context.stroke(
                innerArc,
                with: highlight,
                style: StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .miter)
            )

            context.blendMode = .multiply
            context.stroke(
                innerArc,
                with: shadow,
                style: StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .miter)
            )
        }

        context.blendMode = .normal
    }

    private func renderRadialEdgeAccents(
        into context: inout GraphicsContext,
        centre: CGPoint,
        startAngle: CGFloat,
        endAngle: CGFloat,
        style: SegmentedOuterRingStyle
    ) {
        let bevel = style.blockBevel

        let w = bevel.radialEdgeStrokeWidth
        guard w > 0 else { return }

        let span = endAngle - startAngle
        guard span > 0 else { return }

        // Chamfer geometry: the block ends are diagonal faces between the inner/outer arc endpoints.
        let maxTrim = span * 0.25
        let chamfer = max(0.0, style.chamfer.depth)

        let outerTrim = min(maxTrim, max(0.0, chamfer / max(style.radii.blockOuter, 0.001)))
        let innerTrim = min(maxTrim, max(0.0, chamfer / max(style.radii.blockInner, 0.001)))

        let startOuterAngle = startAngle + outerTrim
        let startInnerAngle = startAngle + innerTrim
        let endOuterAngle = endAngle - outerTrim
        let endInnerAngle = endAngle - innerTrim

        let innerR = style.radii.blockInner + bevel.radialEdgeEndInset
        let outerR = style.radii.blockOuter - bevel.radialEdgeEndInset
        guard outerR > innerR else { return }

        // Fixed screen-space light direction (top-left).
        let light = CGPoint(x: -0.70710678, y: -0.70710678)

        let interiorSampleAngle = (startAngle + endAngle) * 0.5
        let interiorSample = CGPoint(
            x: centre.x + cos(interiorSampleAngle) * style.radii.blockMid,
            y: centre.y + sin(interiorSampleAngle) * style.radii.blockMid
        )

        // Start face.
        drawChamferEdgeAccent(
            into: &context,
            innerPoint: CGPoint(x: centre.x + cos(startInnerAngle) * innerR, y: centre.y + sin(startInnerAngle) * innerR),
            outerPoint: CGPoint(x: centre.x + cos(startOuterAngle) * outerR, y: centre.y + sin(startOuterAngle) * outerR),
            interiorSample: interiorSample,
            light: light,
            style: style
        )

        // End face.
        drawChamferEdgeAccent(
            into: &context,
            innerPoint: CGPoint(x: centre.x + cos(endInnerAngle) * innerR, y: centre.y + sin(endInnerAngle) * innerR),
            outerPoint: CGPoint(x: centre.x + cos(endOuterAngle) * outerR, y: centre.y + sin(endOuterAngle) * outerR),
            interiorSample: interiorSample,
            light: light,
            style: style
        )

        context.blendMode = .normal
    }

    private func drawChamferEdgeAccent(
        into context: inout GraphicsContext,
        innerPoint: CGPoint,
        outerPoint: CGPoint,
        interiorSample: CGPoint,
        light: CGPoint,
        style: SegmentedOuterRingStyle
    ) {
        let bevel = style.blockBevel

        let v = CGPoint(x: outerPoint.x - innerPoint.x, y: outerPoint.y - innerPoint.y)
        let len = max(0.0001, sqrt((v.x * v.x) + (v.y * v.y)))

        let u = CGPoint(x: v.x / len, y: v.y / len)

        // Candidate normals (perpendicular to the face line).
        let n1 = CGPoint(x: -u.y, y: u.x)
        let n2 = CGPoint(x: u.y, y: -u.x)

        // Pick the normal that points towards the block interior.
        let toSample = CGPoint(x: interiorSample.x - innerPoint.x, y: interiorSample.y - innerPoint.y)
        let dot1 = (toSample.x * n1.x) + (toSample.y * n1.y)
        let interiorNormal = (dot1 >= 0.0) ? n1 : n2
        let outwardNormal = CGPoint(x: -interiorNormal.x, y: -interiorNormal.y)

        // Shift the accent fully inside the block so it never "prints" into the air gap.
        let shift = CGPoint(
            x: interiorNormal.x * bevel.radialEdgeInset,
            y: interiorNormal.y * bevel.radialEdgeInset
        )

        let p0 = CGPoint(x: innerPoint.x + shift.x, y: innerPoint.y + shift.y)
        let p1 = CGPoint(x: outerPoint.x + shift.x, y: outerPoint.y + shift.y)

        // Light test: highlight faces that point towards the light.
        let dot = (outwardNormal.x * light.x) + (outwardNormal.y * light.y)
        let isLit = dot >= 0.0

        let cg = CGMutablePath()
        cg.move(to: p0)
        cg.addLine(to: p1)

        let path = Path(cg)
        let stroke = StrokeStyle(lineWidth: bevel.radialEdgeStrokeWidth, lineCap: .butt, lineJoin: .miter)

        if isLit {
            context.blendMode = .screen
            context.stroke(path, with: .color(bevel.radialEdgeHighlightColour), style: stroke)
        } else {
            context.blendMode = .multiply
            context.stroke(path, with: .color(bevel.radialEdgeShadowColour), style: stroke)
        }

        context.blendMode = .normal
    }

    private func arcPath(
        centre: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) -> Path {
        let p = CGMutablePath()

        let start = CGPoint(
            x: centre.x + cos(startAngle) * radius,
            y: centre.y + sin(startAngle) * radius
        )

        p.move(to: start)

        // Positive-angle direction in iOS screen space is clockwise.
        p.addArc(
            center: centre,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        return Path(p)
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

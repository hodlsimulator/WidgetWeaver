//
//  AnnularSegmentCGPath.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import CoreGraphics

enum AnnularSegmentCGPath {

    static func annulus(
        centre: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> CGPath {
        let p = CGMutablePath()

        p.addArc(
            center: centre,
            radius: outerRadius,
            startAngle: 0,
            endAngle: CGFloat.pi * 2.0,
            clockwise: false
        )

        p.addArc(
            center: centre,
            radius: innerRadius,
            startAngle: CGFloat.pi * 2.0,
            endAngle: 0,
            clockwise: true
        )

        p.closeSubpath()
        return p
    }

    static func segment(
        centre: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) -> CGPath {
        let p = CGMutablePath()

        let start = CGPoint(
            x: centre.x + cos(startAngle) * outerRadius,
            y: centre.y + sin(startAngle) * outerRadius
        )

        p.move(to: start)

        // Positive-angle direction in iOS screen space is clockwise.
        p.addArc(
            center: centre,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        let innerEnd = CGPoint(
            x: centre.x + cos(endAngle) * innerRadius,
            y: centre.y + sin(endAngle) * innerRadius
        )

        p.addLine(to: innerEnd)

        p.addArc(
            center: centre,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        p.closeSubpath()
        return p
    }

    /// Creates a chamfered annular segment (ring slice) from startAngle to endAngle.
    ///
    /// The chamfer is applied as an arc-length trim at both ends:
    /// - Outer arc trim = chamfer / outerRadius.
    /// - Inner arc trim = chamfer / innerRadius.
    ///
    /// This yields diagonal end faces that read as "machined" at small widget sizes.
    static func chamferedSegment(
        centre: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        chamfer: CGFloat
    ) -> CGPath {
        guard chamfer > 0 else {
            return segment(
                centre: centre,
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                startAngle: startAngle,
                endAngle: endAngle
            )
        }

        guard outerRadius > 0 else { return CGMutablePath() }
        guard innerRadius >= 0 else { return CGMutablePath() }
        guard outerRadius > innerRadius else { return CGMutablePath() }
        guard endAngle > startAngle else { return CGMutablePath() }

        let span = endAngle - startAngle
        guard span > 0 else { return CGMutablePath() }

        // Prevent the chamfer from collapsing the segment at very small spans.
        let maxTrim = span * 0.25

        let outerTrim = min(maxTrim, max(0.0, chamfer / max(outerRadius, 0.001)))
        let innerTrim = min(maxTrim, max(0.0, chamfer / max(innerRadius, 0.001)))

        let outerStartAngle = startAngle + outerTrim
        let outerEndAngle = endAngle - outerTrim
        let innerStartAngle = startAngle + innerTrim
        let innerEndAngle = endAngle - innerTrim

        guard outerEndAngle > outerStartAngle else { return CGMutablePath() }
        guard innerEndAngle > innerStartAngle else { return CGMutablePath() }

        let p = CGMutablePath()

        let outerStart = CGPoint(
            x: centre.x + cos(outerStartAngle) * outerRadius,
            y: centre.y + sin(outerStartAngle) * outerRadius
        )

        p.move(to: outerStart)

        // Positive-angle direction in iOS screen space is clockwise.
        p.addArc(
            center: centre,
            radius: outerRadius,
            startAngle: outerStartAngle,
            endAngle: outerEndAngle,
            clockwise: false
        )

        let innerEnd = CGPoint(
            x: centre.x + cos(innerEndAngle) * innerRadius,
            y: centre.y + sin(innerEndAngle) * innerRadius
        )

        // End-face chamfer (diagonal).
        p.addLine(to: innerEnd)

        p.addArc(
            center: centre,
            radius: innerRadius,
            startAngle: innerEndAngle,
            endAngle: innerStartAngle,
            clockwise: true
        )

        // Start-face chamfer (diagonal) back to the outer arc start.
        p.addLine(to: outerStart)

        p.closeSubpath()
        return p
    }
}

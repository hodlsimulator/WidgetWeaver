//
//  AnnularSegmentCGPath.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import CoreGraphics

/// CGPath builders for annular geometry (ring segments).
///
/// Angle conventions:
/// - Radians.
/// - 0 points to the right (+X).
/// - Positive angles advance clockwise in the default iOS coordinate space (Y increases down).
enum AnnularSegmentCGPath {

    /// Creates an annulus path (outer and inner circles) suitable for even-odd filling.
    static func annulus(
        centre: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()

        let outerRect = CGRect(
            x: centre.x - outerRadius,
            y: centre.y - outerRadius,
            width: outerRadius * 2.0,
            height: outerRadius * 2.0
        )

        let innerRect = CGRect(
            x: centre.x - innerRadius,
            y: centre.y - innerRadius,
            width: innerRadius * 2.0,
            height: innerRadius * 2.0
        )

        path.addEllipse(in: outerRect)
        path.addEllipse(in: innerRect)
        return path
    }

    /// Creates an annular segment (ring slice) from startAngle to endAngle.
    ///
    /// - The path is closed and suitable for normal filling.
    /// - The caller is responsible for applying any angular gap trimming.
    static func segment(
        centre: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) -> CGPath {
        guard outerRadius > 0 else { return CGMutablePath() }
        guard innerRadius >= 0 else { return CGMutablePath() }
        guard outerRadius > innerRadius else { return CGMutablePath() }
        guard endAngle > startAngle else { return CGMutablePath() }

        let p = CGMutablePath()

        let outerStart = CGPoint(
            x: centre.x + cos(startAngle) * outerRadius,
            y: centre.y + sin(startAngle) * outerRadius
        )

        p.move(to: outerStart)

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
}

//
//  WWClockAnnularSectorShape.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

/// An annular sector (ring segment) bounded by two radii and two angles.
///
/// The shape is centred in its rect. `innerRadius` and `outerRadius` are in points,
/// measured from the rect centre.
///
/// `angularGap` trims the sector symmetrically at both ends, producing a crisp separator
/// when multiple sectors are laid out around a ring.
struct WWClockAnnularSectorShape: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    var startAngle: Angle
    var endAngle: Angle

    var angularGap: Angle = .zero

    func path(in rect: CGRect) -> Path {
        guard outerRadius > 0 else { return Path() }
        guard innerRadius >= 0 else { return Path() }
        guard outerRadius > innerRadius else { return Path() }

        let centre = CGPoint(x: rect.midX, y: rect.midY)

        let halfGap = angularGap.radians * 0.5
        let adjustedStart = Angle.radians(startAngle.radians + halfGap)
        let adjustedEnd = Angle.radians(endAngle.radians - halfGap)

        guard adjustedEnd.radians > adjustedStart.radians else { return Path() }

        var p = Path()

        let outerStart = CGPoint(
            x: centre.x + (CGFloat(cos(adjustedStart.radians)) * outerRadius),
            y: centre.y + (CGFloat(sin(adjustedStart.radians)) * outerRadius)
        )

        p.move(to: outerStart)
        p.addArc(center: centre, radius: outerRadius, startAngle: adjustedStart, endAngle: adjustedEnd, clockwise: false)

        let innerEnd = CGPoint(
            x: centre.x + (CGFloat(cos(adjustedEnd.radians)) * innerRadius),
            y: centre.y + (CGFloat(sin(adjustedEnd.radians)) * innerRadius)
        )

        p.addLine(to: innerEnd)
        p.addArc(center: centre, radius: innerRadius, startAngle: adjustedEnd, endAngle: adjustedStart, clockwise: true)
        p.closeSubpath()

        return p
    }
}

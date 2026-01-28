//
//  WWClockAnnularSectorShape.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

/// Annular sector (ring slice) used by the Segmented face outer ring.
///
/// `angularGap` trims the slice symmetrically at both ends so neighbouring sectors leave a crisp separator.
struct WWClockAnnularSectorShape: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startAngle: Angle
    let endAngle: Angle
    let angularGap: Angle

    init(
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: Angle,
        endAngle: Angle,
        angularGap: Angle = .zero
    ) {
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.angularGap = angularGap
    }

    func path(in rect: CGRect) -> Path {
        guard outerRadius > 0 else { return Path() }
        guard innerRadius >= 0 else { return Path() }
        guard outerRadius > innerRadius else { return Path() }

        let centre = CGPoint(x: rect.midX, y: rect.midY)

        // Trim symmetrically for the separator gap.
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

        // UIKit / SwiftUI coordinate space uses a downward Y axis, so positive angles advance clockwise.
        // Tracing the outer arc with `clockwise: false` follows the positive-angle direction without wraparound.
        p.addArc(
            center: centre,
            radius: outerRadius,
            startAngle: adjustedStart,
            endAngle: adjustedEnd,
            clockwise: false
        )

        let innerEnd = CGPoint(
            x: centre.x + (CGFloat(cos(adjustedEnd.radians)) * innerRadius),
            y: centre.y + (CGFloat(sin(adjustedEnd.radians)) * innerRadius)
        )

        p.addLine(to: innerEnd)

        // Return along the inner radius in the opposite direction.
        p.addArc(
            center: centre,
            radius: innerRadius,
            startAngle: adjustedEnd,
            endAngle: adjustedStart,
            clockwise: true
        )

        p.closeSubpath()
        return p
    }
}

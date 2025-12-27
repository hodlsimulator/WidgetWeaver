//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let containerSide = min(proxy.size.width, proxy.size.height)
            let dialDiameter = WWClockIconMetrics.dialDiameter(forContainerSide: containerSide, scale: displayScale)

            let faceNow = WidgetWeaverRenderClock.now
            let faceAngles = WidgetWeaverClockAngles(now: faceNow)

            let secondHandAnchor = WidgetWeaverClockSecondHandAnchor.minuteAlignedAnchor(reference: Date())

            ZStack(alignment: .center) {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(faceAngles.hourDegrees),
                    minuteAngle: .degrees(faceAngles.minuteDegrees),
                    secondAngle: .degrees(faceAngles.secondDegrees),
                    showsSecondHand: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(secondHandAnchor, style: .timer)
                    .font(WWClockSecondHandFont.font(size: dialDiameter))
                    .foregroundStyle(palette.accent)
                    .frame(width: dialDiameter, height: dialDiameter, alignment: Alignment.center)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                #if DEBUG
                if WWClockWidgetLiveTuning.showDebugOverlay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(secondHandAnchor, style: .timer)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary.opacity(0.75))

                        Text(faceNow, format: .dateTime.hour().minute().second())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary.opacity(0.60))
                    }
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum WWClockIconMetrics {
    static func dialDiameter(forContainerSide side: CGFloat, scale: CGFloat) -> CGFloat {
        let outerDiameter = WWClock.pixel(side * 0.925, scale: scale)
        let outerRadius = outerDiameter * 0.5

        let metalThicknessRatio: CGFloat = 0.062
        let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

        let ringA = WWClock.pixel(provisionalR * 0.010, scale: scale)
        let ringC = WWClock.pixel(
            WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
            scale: scale
        )

        let minB = WWClock.px(scale: scale)
        let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: scale)

        let R = outerRadius - ringA - ringB - ringC
        return R * 2.0
    }
}

private enum WidgetWeaverClockSecondHandAnchor {
    static func minuteAlignedAnchor(reference: Date) -> Date {
        let t = reference.timeIntervalSince1970
        let aligned = floor(t / 60.0) * 60.0
        return Date(timeIntervalSince1970: aligned)
    }
}

private struct WidgetWeaverClockAngles {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(now: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: now))
        let local = now.timeIntervalSince1970 + tz

        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}

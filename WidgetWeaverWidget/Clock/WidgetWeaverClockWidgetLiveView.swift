//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI
import WidgetKit

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPlaceholder = redactionReasons.contains(.placeholder)
            let isPrivacy = redactionReasons.contains(.privacy)

            let showLive = !(isPlaceholder || isPrivacy)
            let handsOpacity: Double = showLive ? 1.0 : 0.85

            // README strategy:
            // - Hour/minute use minute-boundary timeline entries (stable, reliable).
            // - Seconds avoid 1 Hz WidgetKit timelines; instead use a ProgressView(timerInterval:)
            //   driven wedge mask to reveal one of 60 pre-rotated second hands.
            let base = WWClockBaseAngles(date: entryDate)

            ZStack {
                // Base clock (no seconds in the main tree).
                // Centre hub is drawn after the seconds overlay so the seconds needle sits underneath it.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: false,
                    handsOpacity: handsOpacity
                )

                // Seconds overlay: ticking/sweeping without TimelineView.
                WWClockSecondsTickOverlay(
                    palette: palette,
                    minuteAnchor: entryDate,
                    showLive: showLive,
                    handsOpacity: handsOpacity
                )
            }
            .privacySensitive(isPrivacy)
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Minute-boundary angles (tick)

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)

        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.minute = minuteInt * 6.0
        self.hour = (hour12 + (minuteInt / 60.0)) * 30.0
    }
}

// MARK: - Seconds overlay (ProgressView(timerInterval:) wedge mask)

private struct WWClockSecondsTickOverlay: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showLive: Bool
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                if showLive {
                    WWClockSecondHandSheet(
                        palette: palette,
                        dialDiameter: layout.dialDiameter,
                        scale: displayScale
                    )
                    .mask(
                        WWClockSecondWedgeMask(
                            minuteAnchor: minuteAnchor,
                            dialDiameter: layout.dialDiameter
                        )
                    )
                    .opacity(handsOpacity)
                }

                WidgetWeaverClockCentreHubView(
                    palette: palette,
                    baseRadius: layout.hubBaseRadius,
                    capRadius: layout.hubCapRadius,
                    scale: displayScale
                )
                .opacity(handsOpacity)
            }
            .frame(width: layout.dialDiameter, height: layout.dialDiameter)
            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
            .clipShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct WWClockSecondHandSheet: View {
    let palette: WidgetWeaverClockPalette
    let dialDiameter: CGFloat
    let scale: CGFloat

    var body: some View {
        let R = dialDiameter * 0.5

        let secondLength = WWClock.pixel(
            WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
            scale: scale
        )

        let secondWidth = WWClock.pixel(
            WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
            scale: scale
        )

        let secondTipSide = WWClock.pixel(
            WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
            scale: scale
        )

        ZStack {
            ForEach(0..<60, id: \.self) { i in
                WidgetWeaverClockSecondHandView(
                    colour: palette.accent,
                    width: secondWidth,
                    length: secondLength,
                    angle: .degrees(Double(i) * 6.0),
                    tipSide: secondTipSide,
                    scale: scale
                )
            }
        }
        .frame(width: dialDiameter, height: dialDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockSecondWedgeMask: View {
    let minuteAnchor: Date
    let dialDiameter: CGFloat

    // The raw “A minus B” wedge is centred between second marks; rotating by +3° centres it on the
    // current second hand (multiples of 6°), avoiding the “needle sits on the mask boundary” issue.
    private let wedgeRotation: Angle = .degrees(3.0)

    var body: some View {
        let aStart = minuteAnchor
        let aEnd = minuteAnchor.addingTimeInterval(60.0)

        let bStart = minuteAnchor.addingTimeInterval(1.0)
        let bEnd = minuteAnchor.addingTimeInterval(61.0)

        ZStack {
            progressMask(timer: aStart...aEnd)

            progressMask(timer: bStart...bEnd)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .rotationEffect(wedgeRotation)
        .frame(width: dialDiameter, height: dialDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func progressMask(timer: ClosedRange<Date>) -> some View {
        // Small seed size so the circular stroke becomes “thick” when scaled up.
        // This helps the wedge cover the dial area (not just a thin ring).
        let seed: CGFloat = 2.0
        let s = dialDiameter / seed

        ProgressView(timerInterval: timer, countsDown: false)
            .progressViewStyle(.circular)
            .tint(.white)
            .frame(width: seed, height: seed)
            .scaleEffect(s)
            .frame(width: dialDiameter, height: dialDiameter)
            .background(Color.black)
            .compositingGroup()
            .luminanceToAlpha()
    }
}

// MARK: - Dial layout (matches WidgetWeaverClockIconView)

private struct WWClockDialLayout {
    let dialDiameter: CGFloat
    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    init(size: CGSize, scale: CGFloat) {
        let s = min(size.width, size.height)

        let outerDiameter = WWClock.pixel(s * 0.925, scale: scale)
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
        self.dialDiameter = R * 2.0

        self.hubBaseRadius = WWClock.pixel(
            WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
            scale: scale
        )

        self.hubCapRadius = WWClock.pixel(
            WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
            scale: scale
        )
    }
}

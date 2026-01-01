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

            // Hour/minute: minute-boundary timeline entries (stable, reliable).
            let minuteAnchor = Self.floorToMinute(entryDate)
            let base = WWClockBaseAngles(date: minuteAnchor)

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

                // Seconds overlay:
                //
                // On iOS 26 Home Screen hosting, `TimelineView(.periodic)` can be paused and stop firing,
                // even while provider minute-boundary updates continue to land.
                //
                // This overlay avoids high-frequency provider timelines and instead uses a CoreAnimation-
                // backed infinite rotation (SwiftUI `repeatForever`) plus a tiny timer-style `Text` heartbeat
                // to encourage the host to keep the widget in a “live” rendering mode.
                //
                // This remains best-effort: the host can still freeze animations in some conditions,
                // but this path has proven more resilient than relying on `TimelineView` alone.
                WWClockSecondsHandOverlay(
                    palette: palette,
                    minuteAnchor: minuteAnchor,
                    showLive: showLive,
                    handsOpacity: handsOpacity
                )
            }
            .privacySensitive(isPrivacy)
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
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

// MARK: - Seconds overlay (CoreAnimation-backed sweep)

private struct WWClockSecondsHandOverlay: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showLive: Bool
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    @State private var baseDate: Date
    @State private var secPhase: Double = 0
    @State private var started: Bool = false

    init(
        palette: WidgetWeaverClockPalette,
        minuteAnchor: Date,
        showLive: Bool,
        handsOpacity: Double
    ) {
        self.palette = palette
        self.minuteAnchor = minuteAnchor
        self.showLive = showLive
        self.handsOpacity = handsOpacity
        _baseDate = State(initialValue: minuteAnchor)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)
            let R = layout.dialDiameter * 0.5

            let secondLength = WWClock.pixel(
                WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
                scale: displayScale
            )
            let secondWidth = WWClock.pixel(
                WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
                scale: displayScale
            )
            let secondTipSide = WWClock.pixel(
                WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
                scale: displayScale
            )

            let animatedAngle = Angle.degrees(Self.secondDegrees(date: baseDate) + secPhase * 360.0)

            ZStack {
                if showLive {
                    WidgetWeaverClockSecondHandView(
                        colour: palette.accent,
                        width: secondWidth,
                        length: secondLength,
                        angle: animatedAngle,
                        tipSide: secondTipSide,
                        scale: displayScale
                    )
                    .opacity(handsOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onAppear {
                        DispatchQueue.main.async {
                            syncAndStartIfNeeded()
                        }
                    }
                    .task {
                        // Some widget hosting paths can skip onAppear.
                        DispatchQueue.main.async {
                            syncAndStartIfNeeded()
                        }
                    }

                    // Heartbeat:
                    // A tiny timer-style Text keeps the widget host in a “live” rendering mode.
                    // This can help CoreAnimation-backed repeatForever rotations keep running.
                    WWClockWidgetHeartbeat(start: baseDate)
                } else {
                    // Placeholder/privacy: deterministic static position (12 o'clock).
                    WidgetWeaverClockSecondHandView(
                        colour: palette.accent,
                        width: secondWidth,
                        length: secondLength,
                        angle: .degrees(0.0),
                        tipSide: secondTipSide,
                        scale: displayScale
                    )
                    .opacity(handsOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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

    private func syncAndStartIfNeeded() {
        guard showLive else { return }

        let now = Date()

        // Start once per view lifetime, but also re-sync if the anchor is stale.
        let shouldResync = (!started) || (abs(now.timeIntervalSince(baseDate)) > 1.0)
        guard shouldResync else { return }

        started = true
        baseDate = now

        withAnimation(.none) {
            secPhase = 0
        }

        withAnimation(.linear(duration: 60.0).repeatForever(autoreverses: false)) {
            secPhase = 1
        }
    }

    private static func secondDegrees(date: Date) -> Double {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.second, .nanosecond], from: date)

        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        return sec * 6.0
    }
}

private struct WWClockWidgetHeartbeat: View {
    let start: Date

    var body: some View {
        // Keeping this extremely cheap:
        // - very small font
        // - clipped to a 1x1 region
        // - almost transparent
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(.system(size: 1))
            .foregroundStyle(Color.primary.opacity(0.001))
            .frame(width: 1, height: 1)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

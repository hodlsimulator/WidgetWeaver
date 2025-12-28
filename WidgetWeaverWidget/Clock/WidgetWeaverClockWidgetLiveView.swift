//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import SwiftUI
import Foundation

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Deterministic anchor for WidgetKit pre-rendering.
    /// The view re-syncs itself to `Date()` when it appears on screen.
    let startDate: Date

    @State private var baseDate: Date
    @State private var started: Bool = false

    @State private var secPhase: Double = 0
    @State private var minPhase: Double = 0
    @State private var hourPhase: Double = 0

    init(palette: WidgetWeaverClockPalette, startDate: Date) {
        self.palette = palette
        self.startDate = startDate
        _baseDate = State(initialValue: startDate)
    }

    var body: some View {
        let baseAngles = WWClockBaseAngles(date: baseDate)

        let hourAngle = Angle.degrees(baseAngles.hour + hourPhase * 360.0)
        let minuteAngle = Angle.degrees(baseAngles.minute + minPhase * 360.0)
        let secondAngle = Angle.degrees(baseAngles.second + secPhase * 360.0)

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle,
                showsSecondHand: true,
                handsOpacity: 1.0
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Keeps the widget in a time-aware hosting path (offscreen stops; onscreen catches up).
            WWClockHeartbeatDriver(baseDate: baseDate)
        }
        .onAppear {
            DispatchQueue.main.async { syncAndStartIfNeeded() }
        }
        .task {
            DispatchQueue.main.async { syncAndStartIfNeeded() }
        }
    }

    private func syncAndStartIfNeeded() {
        let now = Date()

        let shouldResync = (!started) || (abs(now.timeIntervalSince(baseDate)) > 1.0)
        guard shouldResync else { return }

        started = true
        baseDate = now

        withAnimation(.none) {
            secPhase = 0
            minPhase = 0
            hourPhase = 0
        }

        withAnimation(.linear(duration: 60.0).repeatForever(autoreverses: false)) {
            secPhase = 1
        }
        withAnimation(.linear(duration: 3600.0).repeatForever(autoreverses: false)) {
            minPhase = 1
        }
        withAnimation(.linear(duration: 43200.0).repeatForever(autoreverses: false)) {
            hourPhase = 1
        }
    }
}

private struct WWClockHeartbeatDriver: View {
    let baseDate: Date

    var body: some View {
        Text(timerInterval: baseDate...Date.distantFuture, countsDown: false)
            .font(.system(size: 1).monospacedDigit())
            .opacity(0.001)
            .frame(width: 1, height: 1, alignment: .bottomTrailing)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + tz

        let sec = local.truncatingRemainder(dividingBy: 60.0)
        let minTotal = (local / 60.0).truncatingRemainder(dividingBy: 60.0)
        let hourTotal = (local / 3600.0).truncatingRemainder(dividingBy: 12.0)

        second = sec * 6.0
        minute = (minTotal + sec / 60.0) * 6.0
        hour = (hourTotal + minTotal / 60.0 + sec / 3600.0) * 30.0
    }
}

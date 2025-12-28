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

    /// Deterministic anchor for WidgetKit pre-rendering. The view re-syncs to real time when visible.
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

        ZStack(alignment: .topLeading) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle,
                showsSecondHand: true,
                handsOpacity: 1.0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Hidden time-aware view to encourage “live” hosting paths.
            Text(timerInterval: baseDate...Date.distantFuture, countsDown: false)
                .font(.system(size: 1))
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            syncAndStartIfNeeded()
            DispatchQueue.main.async { syncAndStartIfNeeded() }
        }
        .task {
            syncAndStartIfNeeded()
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

        let secondDeg = sec * 6.0
        let minuteDeg = (minTotal + sec / 60.0) * 6.0
        let hourDeg = (hourTotal + minTotal / 60.0 + sec / 3600.0) * 30.0

        self.second = secondDeg
        self.minute = minuteDeg
        self.hour = hourDeg
    }
}

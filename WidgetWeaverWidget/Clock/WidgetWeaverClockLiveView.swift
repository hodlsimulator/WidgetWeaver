//
//  WidgetWeaverClockLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import SwiftUI
import Foundation

struct WidgetWeaverClockLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Used only as a deterministic anchor for WidgetKit pre-rendering.
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
        let baseAngles = WidgetWeaverClockBaseAngles(date: baseDate)

        let hourAngle = Angle.degrees(baseAngles.hour + hourPhase * 360.0)
        let minuteAngle = Angle.degrees(baseAngles.minute + minPhase * 360.0)
        let secondAngle = Angle.degrees(baseAngles.second + secPhase * 360.0)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: hourAngle,
            minuteAngle: minuteAngle,
            secondAngle: secondAngle
        )
        .onAppear {
            syncAndStartIfNeeded()
        }
    }

    private func syncAndStartIfNeeded() {
        let now = Date()

        // Start once per view lifetime, but also re-sync if the anchor is stale.
        // This covers cases where WidgetKit reuses a previously rendered snapshot and then the view becomes visible later.
        let shouldResync = (!started) || (abs(now.timeIntervalSince(baseDate)) > 1.0)
        guard shouldResync else { return }

        started = true
        baseDate = now

        secPhase = 0
        minPhase = 0
        hourPhase = 0

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

private struct WidgetWeaverClockBaseAngles {
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

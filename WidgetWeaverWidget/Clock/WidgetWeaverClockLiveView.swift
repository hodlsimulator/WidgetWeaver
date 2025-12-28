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
    @State private var appeared: Bool = false

    @State private var secPhase: Double = 0
    @State private var minPhase: Double = 0
    @State private var hourPhase: Double = 0

    @State private var debugPulse: Double = 0

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

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle
            )

            #if DEBUG
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .frame(width: 6, height: 6)
                        .opacity(0.15 + debugPulse * 0.85)

                    // Counts up from the last re-sync. This should tick if the widget host is live.
                    Text(timerInterval: baseDate...Date.distantFuture, countsDown: false)
                }

                Text(appeared ? "APPEAR ✅" : "APPEAR ❌")
                Text(started ? "RUN ✅" : "RUN ❌")

                Text("base: \(baseDate, format: .dateTime.hour().minute().second())")
                    .opacity(0.6)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary.opacity(0.70))
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            #endif
        }
        .onAppear {
            appeared = true
            // Start on the next runloop tick so CoreAnimation gets a clean “from” state.
            DispatchQueue.main.async {
                syncAndStartIfNeeded()
            }
        }
        .task {
            // Some WidgetKit hosting paths reuse snapshots in ways that can skip onAppear.
            // Running the same guarded start logic here is harmless.
            DispatchQueue.main.async {
                syncAndStartIfNeeded()
            }
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

        // Reset phases without animation.
        withAnimation(.none) {
            secPhase = 0
            minPhase = 0
            hourPhase = 0
            debugPulse = 0
        }

        // CoreAnimation-backed infinite sweeps.
        withAnimation(.linear(duration: 60.0).repeatForever(autoreverses: false)) {
            secPhase = 1
        }
        withAnimation(.linear(duration: 3600.0).repeatForever(autoreverses: false)) {
            minPhase = 1
        }
        withAnimation(.linear(duration: 43200.0).repeatForever(autoreverses: false)) {
            hourPhase = 1
        }

        #if DEBUG
        withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: true)) {
            debugPulse = 1
        }
        #endif
    }
}

private struct WidgetWeaverClockBaseAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.second = sec * 6.0
        self.minute = (minuteInt + sec / 60.0) * 6.0
        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
    }
}

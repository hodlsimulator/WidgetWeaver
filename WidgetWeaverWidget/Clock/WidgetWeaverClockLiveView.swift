//
//  WidgetWeaverClockLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import SwiftUI
import Foundation

struct WidgetWeaverClockLiveView: View {
    let face: WidgetWeaverClockFaceToken
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

    #if DEBUG
    @State private var debugPulse: Double = 0
    #endif

    init(
        face: WidgetWeaverClockFaceToken = .ceramic,
        palette: WidgetWeaverClockPalette,
        startDate: Date
    ) {
        self.face = face
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
            WidgetWeaverClockFaceView(
                face: face,
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle
            )

            // Heartbeat:
            // A tiny timer-style Text keeps the widget host in a “live” rendering mode.
            // This helps CoreAnimation-backed repeatForever rotations keep running on the Home Screen.
            WWClockWidgetHeartbeat(start: baseDate)

            #if DEBUG
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .frame(width: 6, height: 6)
                        .opacity(0.15 + debugPulse * 0.85)

                    // Counts up from the last re-sync.
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
    }

    private func syncAndStartIfNeeded() {
        let now = Date()

        // Start once per view lifetime, but also re-sync if the anchor is stale.
        let shouldResync = (!started) || (abs(now.timeIntervalSince(baseDate)) > 1.0)
        guard shouldResync else { return }

        started = true
        baseDate = now

        withAnimation(.none) {
            secPhase = 0
            minPhase = 0
            hourPhase = 0
            #if DEBUG
            debugPulse = 0
            #endif
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

//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    static let tickSeconds: TimeInterval = 1.0

    /// A missed-tick threshold. If the widget host pauses updates (off-screen, power, etc),
    /// the next visible update snaps to the correct time instead of spinning rapidly.
    static let animateOnlyWhenDeltaSecondsIsExactlyOne: Bool = true

    /// Keeps the heartbeat view “rendered” but effectively invisible.
    /// Avoids using `.hidden()` so the host is less likely to optimise it away.
    static let heartbeatOpacity: Double = 0.001

    /// Off by default. Flip to true for on-device verification.
    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Provided for deterministic WidgetKit pre-rendering.
    /// The view re-syncs to real time when it becomes visible.
    let anchorDate: Date

    @State private var heartbeatBaseDate: Date

    init(palette: WidgetWeaverClockPalette, anchorDate: Date) {
        self.palette = palette
        self.anchorDate = anchorDate

        let now = Date()
        let safeBase = (anchorDate <= now) ? anchorDate : now
        _heartbeatBaseDate = State(initialValue: safeBase)
    }

    var body: some View {
        // The “heartbeat” is a system-updating timer Text.
        // The clock is placed in its overlay so it is recomputed whenever the heartbeat updates.
        Text(timerInterval: heartbeatBaseDate...Date.distantFuture, countsDown: false)
            .font(.system(size: 1).monospacedDigit())
            .opacity(WWClockWidgetLiveTuning.heartbeatOpacity)
            .frame(width: 28, height: 12, alignment: .topLeading)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityHidden(true)
            .overlay {
                WidgetWeaverClockWidgetLiveDriverView(
                    palette: palette,
                    anchorDate: anchorDate
                )
            }
            .onAppear { resyncHeartbeatIfNeeded() }
            .task { resyncHeartbeatIfNeeded() }
    }

    private func resyncHeartbeatIfNeeded() {
        let now = Date()

        if heartbeatBaseDate > now {
            heartbeatBaseDate = now
            return
        }

        // Avoid moving the base date every render; only re-anchor if it is stale.
        if abs(now.timeIntervalSince(heartbeatBaseDate)) > 10.0 {
            heartbeatBaseDate = now
        }
    }
}

private struct WidgetWeaverClockWidgetLiveDriverView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date

    @State private var rendered: WWClockHandDegrees
    @State private var lastTick: Int?

    init(palette: WidgetWeaverClockPalette, anchorDate: Date) {
        self.palette = palette
        self.anchorDate = anchorDate
        _rendered = State(initialValue: WWClockHandDegrees(date: anchorDate))
        _lastTick = State(initialValue: Int(anchorDate.timeIntervalSince1970))
    }

    var body: some View {
        let now = Date()
        let tick = Int(floor(now.timeIntervalSince1970))

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(rendered.hourDegrees),
                minuteAngle: .degrees(rendered.minuteDegrees),
                secondAngle: .degrees(rendered.secondDegrees)
            )

            #if DEBUG
            if WWClockWidgetLiveTuning.showDebugOverlay {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(now, format: .dateTime.hour().minute().second())
                    Text("tick: \(tick)")
                    Text("last: \(lastTick.map(String.init) ?? "nil")")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.70))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #endif
        }
        .onAppear { syncToNow() }
        .task { syncToNow() }
        .onChange(of: tick) { _, newTick in
            applyTick(newTick)
        }
    }

    private func syncToNow() {
        let now = Date()
        let tick = Int(floor(now.timeIntervalSince1970))
        let quantised = Date(timeIntervalSince1970: Double(tick))
        let target = WWClockHandDegrees(date: quantised)

        lastTick = tick
        withAnimation(.none) {
            rendered = target
        }
    }

    private func applyTick(_ newTick: Int) {
           _ = newTick
       }
}

private struct WWClockHandDegrees: Equatable {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + tz

        // Monotonic degrees keep direction stable across wrap boundaries.
        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}

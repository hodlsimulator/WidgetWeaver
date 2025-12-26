//
//  WidgetWeaverHomeScreenClockWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/23/25.
//

import Foundation
import WidgetKit
import SwiftUI
import AppIntents

private enum WWClockTimelineTuning {
    // Home Screen widgets do not guarantee 1 Hz redraws.
    // Keep the WidgetKit timeline modest and avoid relying on frequent delivery.
    static let tickSeconds: TimeInterval = 60.0 * 15.0

    // Long-running CoreAnimation sweep. This avoids depending on frequent timeline delivery.
    static let sweepSeconds: TimeInterval = 60.0 * 60.0

    // 96 @ 15 minutes = 24 hours.
    static let maxEntries: Int = 96
}

// MARK: - Configuration

public enum WidgetWeaverClockColourScheme: String, AppEnum, CaseIterable {
    case classic
    case ocean
    case mint
    case orchid
    case sunset
    case ember
    case graphite

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Colour Scheme")
    }

    public static var caseDisplayRepresentations: [WidgetWeaverClockColourScheme: DisplayRepresentation] {
        [
            .classic: DisplayRepresentation(title: "Classic"),
            .ocean: DisplayRepresentation(title: "Ocean"),
            .mint: DisplayRepresentation(title: "Mint"),
            .orchid: DisplayRepresentation(title: "Orchid"),
            .sunset: DisplayRepresentation(title: "Sunset"),
            .ember: DisplayRepresentation(title: "Ember"),
            .graphite: DisplayRepresentation(title: "Graphite")
        ]
    }
}

public struct WidgetWeaverClockConfigurationIntent: AppIntent, WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Clock" }

    public static var description: IntentDescription {
        IntentDescription("Select the colour scheme for the clock widget.")
    }

    @Parameter(title: "Colour Scheme")
    public var colourScheme: WidgetWeaverClockColourScheme?

    public init() {
        self.colourScheme = .classic
    }
}

// MARK: - Timeline

public struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    public let date: Date
    public let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), colourScheme: .classic)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        Entry(date: Date(), colourScheme: configuration.colourScheme ?? .classic)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let scheme = configuration.colourScheme ?? .classic
        let base = Date()

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineTuning.maxEntries)

        for i in 0..<WWClockTimelineTuning.maxEntries {
            let d = base.addingTimeInterval(Double(i) * WWClockTimelineTuning.tickSeconds)
            entries.append(Entry(date: d, colourScheme: scheme))
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Widget

struct WidgetWeaverHomeScreenClockWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.homeScreenClock

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            WidgetWeaverRenderClock.withNow(entry.date) {
                WidgetWeaverHomeScreenClockView(entry: entry)
            }
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Time maths

private struct WWClockHandDegrees {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date, timeZone: TimeZone) {
        // Monotonic angles (no mod 360) so interpolation never runs backwards at wrap boundaries.
        let tz = TimeInterval(timeZone.secondsFromGMT(for: date))
        let localT = date.timeIntervalSinceReferenceDate + tz

        self.secondDegrees = localT * (360.0 / 60.0)
        self.minuteDegrees = localT * (360.0 / 3600.0)
        self.hourDegrees = localT * (360.0 / 43200.0)
    }
}

// MARK: - View

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: mode
        )

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverHomeScreenClockFaceView(
                palette: palette,
                date: entry.date
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if DEBUG
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.date, format: .dateTime.hour().minute().second())
                Text(entry.date, style: .timer)
                Text("CLK V5")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary.opacity(0.75))
            .padding(6)
            #endif
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}

// MARK: - Face (dial static, hands sweep via long-running animation)

private struct WidgetWeaverHomeScreenClockFaceView: View {
    let palette: WidgetWeaverClockPalette
    let date: Date

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let s = min(size.width, size.height)

            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: displayScale
            )

            let minB = WWClock.px(scale: displayScale)
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: displayScale)

            let R = outerRadius - ringA - ringB - ringC
            let dialDiameter = R * 2.0

            let occlusionWidth = WWClock.pixel(
                WWClock.clamp(R * 0.013, min: R * 0.010, max: R * 0.015),
                scale: displayScale
            )

            let dotRadius = WWClock.pixel(
                WWClock.clamp(R * 0.922, min: R * 0.910, max: R * 0.930),
                scale: displayScale
            )
            let dotDiameter = WWClock.pixel(
                WWClock.clamp(R * 0.010, min: R * 0.009, max: R * 0.011),
                scale: displayScale
            )

            let batonCentreRadius = WWClock.pixel(
                WWClock.clamp(R * 0.815, min: R * 0.780, max: R * 0.830),
                scale: displayScale
            )
            let batonLength = WWClock.pixel(
                WWClock.clamp(R * 0.155, min: R * 0.135, max: R * 0.170),
                scale: displayScale
            )
            let batonWidth = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.038),
                scale: displayScale
            )
            let capLength = WWClock.pixel(
                WWClock.clamp(R * 0.026, min: R * 0.020, max: R * 0.030),
                scale: displayScale
            )

            let pipSide = WWClock.pixel(
                WWClock.clamp(R * 0.016, min: R * 0.014, max: R * 0.018),
                scale: displayScale
            )
            let pipInset = WWClock.pixel(1.5, scale: displayScale)
            let pipRadius = dotRadius - pipInset

            let numeralsRadius = WWClock.pixel(
                WWClock.clamp(R * 0.70, min: R * 0.66, max: R * 0.74),
                scale: displayScale
            )
            let numeralsSize = WWClock.pixel(R * 0.32, scale: displayScale)

            let hourLength = WWClock.pixel(
                WWClock.clamp(R * 0.50, min: R * 0.46, max: R * 0.54),
                scale: displayScale
            )
            let hourWidth = WWClock.pixel(
                WWClock.clamp(R * 0.18, min: R * 0.16, max: R * 0.20),
                scale: displayScale
            )

            let minuteLength = WWClock.pixel(
                WWClock.clamp(R * 0.84, min: R * 0.80, max: R * 0.86),
                scale: displayScale
            )
            let minuteWidth = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.038),
                scale: displayScale
            )

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

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: displayScale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: displayScale
            )

            ZStack {
                // Dial (static)
                ZStack {
                    WidgetWeaverClockDialFaceView(
                        palette: palette,
                        radius: R,
                        occlusionWidth: occlusionWidth
                    )

                    WidgetWeaverClockMinuteDotsView(
                        count: 60,
                        radius: dotRadius,
                        dotDiameter: dotDiameter,
                        dotColour: palette.minuteDot,
                        scale: displayScale
                    )

                    WidgetWeaverClockHourIndicesView(
                        palette: palette,
                        dialDiameter: dialDiameter,
                        centreRadius: batonCentreRadius,
                        length: batonLength,
                        width: batonWidth,
                        capLength: capLength,
                        capColour: palette.accent,
                        scale: displayScale
                    )

                    WidgetWeaverClockCardinalPipsView(
                        pipColour: palette.accent,
                        side: pipSide,
                        radius: pipRadius
                    )

                    WidgetWeaverClockNumeralsView(
                        palette: palette,
                        radius: numeralsRadius,
                        fontSize: numeralsSize,
                        scale: displayScale
                    )
                }
                .frame(width: dialDiameter, height: dialDiameter)
                .clipShape(Circle())
                .compositingGroup()

                // Hands (long-running sweep; re-syncs when the host delivers a new entry)
                WidgetWeaverClockSweepHandsLayer(
                    palette: palette,
                    anchorDate: date,
                    sweepSeconds: WWClockTimelineTuning.sweepSeconds,
                    dialDiameter: dialDiameter,
                    hourLength: hourLength,
                    hourWidth: hourWidth,
                    minuteLength: minuteLength,
                    minuteWidth: minuteWidth,
                    secondLength: secondLength,
                    secondWidth: secondWidth,
                    secondTipSide: secondTipSide,
                    hubBaseRadius: hubBaseRadius,
                    hubCapRadius: hubCapRadius,
                    scale: displayScale
                )
                .frame(width: dialDiameter, height: dialDiameter)
                .allowsHitTesting(false)

                // Bezel (static)
                WidgetWeaverClockBezelView(
                    palette: palette,
                    outerDiameter: outerDiameter,
                    ringA: ringA,
                    ringB: ringB,
                    ringC: ringC,
                    scale: displayScale
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Hands sweep driver

private struct WidgetWeaverClockSweepHandsLayer: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date
    let sweepSeconds: TimeInterval

    let dialDiameter: CGFloat

    let hourLength: CGFloat
    let hourWidth: CGFloat

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    let scale: CGFloat

    @State private var baseDate: Date
    @State private var phase: Double = 0
    @State private var started: Bool = false

    init(
        palette: WidgetWeaverClockPalette,
        anchorDate: Date,
        sweepSeconds: TimeInterval,
        dialDiameter: CGFloat,
        hourLength: CGFloat,
        hourWidth: CGFloat,
        minuteLength: CGFloat,
        minuteWidth: CGFloat,
        secondLength: CGFloat,
        secondWidth: CGFloat,
        secondTipSide: CGFloat,
        hubBaseRadius: CGFloat,
        hubCapRadius: CGFloat,
        scale: CGFloat
    ) {
        self.palette = palette
        self.anchorDate = anchorDate
        self.sweepSeconds = sweepSeconds

        self.dialDiameter = dialDiameter

        self.hourLength = hourLength
        self.hourWidth = hourWidth

        self.minuteLength = minuteLength
        self.minuteWidth = minuteWidth

        self.secondLength = secondLength
        self.secondWidth = secondWidth
        self.secondTipSide = secondTipSide

        self.hubBaseRadius = hubBaseRadius
        self.hubCapRadius = hubCapRadius

        self.scale = scale

        _baseDate = State(initialValue: anchorDate)
    }

    var body: some View {
        let effectiveNow = baseDate.addingTimeInterval(phase * sweepSeconds)
        let deg = WWClockHandDegrees(date: effectiveNow, timeZone: .autoupdatingCurrent)

        return ZStack {
            WidgetWeaverClockHandsView(
                palette: palette,
                dialDiameter: dialDiameter,
                hourAngle: .degrees(deg.hourDegrees),
                minuteAngle: .degrees(deg.minuteDegrees),
                secondAngle: .degrees(deg.secondDegrees),
                hourLength: hourLength,
                hourWidth: hourWidth,
                minuteLength: minuteLength,
                minuteWidth: minuteWidth,
                secondLength: secondLength,
                secondWidth: secondWidth,
                secondTipSide: secondTipSide,
                scale: scale
            )

            WidgetWeaverClockCentreHubView(
                palette: palette,
                baseRadius: hubBaseRadius,
                capRadius: hubCapRadius,
                scale: scale
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                resyncAndStartIfNeeded()
            }
        }
        .task {
            DispatchQueue.main.async {
                resyncAndStartIfNeeded()
            }
        }
        .onChange(of: anchorDate) { _, newAnchor in
            started = false
            baseDate = newAnchor
            DispatchQueue.main.async {
                resyncAndStartIfNeeded()
            }
        }
    }

    private func resyncAndStartIfNeeded() {
        let now = Date()

        // WidgetKit can reuse an older snapshot and then show it later.
        // When that happens, align the sweep to the current wall-clock time.
        let shouldResync = (!started) || (abs(now.timeIntervalSince(baseDate)) > 1.0)
        guard shouldResync else { return }

        started = true

        let t = now.timeIntervalSince1970
        let alignedT = ceil(t)
        baseDate = Date(timeIntervalSince1970: alignedT)

        withAnimation(.none) {
            phase = 0
        }

        withAnimation(.linear(duration: sweepSeconds)) {
            phase = 1
        }
    }
}

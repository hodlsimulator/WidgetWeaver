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
    // WidgetKit may coalesce updates; targeting 2s matches the README’s observed behaviour.
    static let tickSeconds: TimeInterval = 2.0

    // README guidance: keep the entry count modest (≈180).
    static let maxEntries: Int = 180
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
            .graphite: DisplayRepresentation(title: "Graphite"),
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
        // Monotonic (no mod 360) to avoid reverse interpolation at wrap boundaries.
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

    @Environment(\.colorScheme)
    private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: mode
        )

        let deg = WWClockHandDegrees(
            date: entry.date,
            timeZone: .autoupdatingCurrent
        )

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverHomeScreenClockFaceView(
                palette: palette,
                hourAngle: .degrees(deg.hourDegrees),
                minuteAngle: .degrees(deg.minuteDegrees),
                secondAngle: .degrees(deg.secondDegrees),
                animationKeyDegrees: deg.secondDegrees,
                tickSeconds: WWClockTimelineTuning.tickSeconds
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if DEBUG
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.35))
                .padding(6)
            #endif
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}

// MARK: - Face (dial + hands + bezel)

private struct WidgetWeaverHomeScreenClockFaceView: View {
    let palette: WidgetWeaverClockPalette
    let hourAngle: Angle
    let minuteAngle: Angle
    let secondAngle: Angle

    // A single animating key is enough to animate all three hands together.
    let animationKeyDegrees: Double
    let tickSeconds: TimeInterval

    @Environment(\.displayScale)
    private var displayScale

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

                // Hands (animated between timeline entries)
                ZStack {
                    WidgetWeaverClockHandsView(
                        palette: palette,
                        dialDiameter: dialDiameter,
                        hourAngle: hourAngle,
                        minuteAngle: minuteAngle,
                        secondAngle: secondAngle,
                        hourLength: hourLength,
                        hourWidth: hourWidth,
                        minuteLength: minuteLength,
                        minuteWidth: minuteWidth,
                        secondLength: secondLength,
                        secondWidth: secondWidth,
                        secondTipSide: secondTipSide,
                        scale: displayScale
                    )

                    WidgetWeaverClockCentreHubView(
                        palette: palette,
                        baseRadius: hubBaseRadius,
                        capRadius: hubCapRadius,
                        scale: displayScale
                    )
                }
                .frame(width: dialDiameter, height: dialDiameter)
                .animation(.linear(duration: tickSeconds), value: animationKeyDegrees)
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

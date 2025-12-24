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

// MARK: - Intent + Enum

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

struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    let date: Date
    let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetWeaverHomeScreenClockEntry {
        WidgetWeaverHomeScreenClockEntry(date: Date(), colourScheme: .classic)
    }

    func snapshot(for configuration: WidgetWeaverClockConfigurationIntent, in context: Context) async -> WidgetWeaverHomeScreenClockEntry {
        WidgetWeaverHomeScreenClockEntry(
            date: Date(),
            colourScheme: configuration.colourScheme ?? .classic
        )
    }

    func timeline(for configuration: WidgetWeaverClockConfigurationIntent, in context: Context) async -> Timeline<WidgetWeaverHomeScreenClockEntry> {
        let scheme = configuration.colourScheme ?? .classic
        let now = Date()

        // Minute entries keep the clock from “freezing” entirely even when iOS suppresses
        // high-frequency view updates. This matches the general WidgetKit model.
        let calendar = Calendar.current
        let nextMinute = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? now.addingTimeInterval(60)

        var entries: [WidgetWeaverHomeScreenClockEntry] = []
        entries.reserveCapacity(61)

        // Immediate entry.
        entries.append(.init(date: now, colourScheme: scheme))

        // Next hour, at minute boundaries.
        var cursor = nextMinute
        for _ in 0..<60 {
            entries.append(.init(date: cursor, colourScheme: scheme))
            cursor = calendar.date(byAdding: .minute, value: 1, to: cursor) ?? cursor.addingTimeInterval(60)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Widget

struct WidgetWeaverHomeScreenClockWidget: Widget {
    let kind = WidgetWeaverWidgetKinds.homeScreenClock

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            WidgetWeaverHomeScreenClockView(entry: entry)
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A beautiful clock icon-style widget.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Root View

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(scheme: entry.colourScheme, mode: colorScheme)

        // Keep the schedule aligned to whole seconds for nicer sweep maths.
        let alignedStart = Date(
            timeIntervalSinceReferenceDate: floor(entry.date.timeIntervalSinceReferenceDate)
        )

        TimelineView(.periodic(from: alignedStart, by: 1.0)) { context in
            WidgetWeaverClockIconView(
                now: context.date,
                palette: palette,
                colourScheme: entry.colourScheme
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .wwWidgetContainerBackground {
                WidgetWeaverClockBackgroundView(palette: palette)
            }
        }
        .id(entry.colourScheme.rawValue)
    }
}

// MARK: - Palette

private struct WidgetWeaverClockPalette {
    enum Mode { case dark, light }

    let mode: Mode

    let backgroundTop: Color
    let backgroundBottom: Color

    let bezelHighlight: Color
    let bezelMid: Color
    let bezelShadow: Color

    let faceTop: Color
    let faceBottom: Color
    let faceRimHighlight: Color
    let faceRimShadow: Color

    let dot: Color

    let tickTop: Color
    let tickBottom: Color
    let tickShadow: Color

    let numeralsBase: Color
    let numeralsShadow: Color

    let accent: Color
    let accentSecondary: Color

    static func resolve(scheme: WidgetWeaverClockColourScheme, mode: ColorScheme) -> WidgetWeaverClockPalette {
        let isDark = (mode == .dark)

        let common = (
            faceTop: isDark ? wwColor(0x1B1D21) : wwColor(0xF7F7F6),
            faceBottom: isDark ? wwColor(0x0B0D11) : wwColor(0xE9E9E7),
            faceRimHighlight: isDark ? wwColor(0xFFFFFF, alpha: 0.25) : wwColor(0xFFFFFF, alpha: 0.65),
            faceRimShadow: isDark ? wwColor(0x000000, alpha: 0.55) : wwColor(0x000000, alpha: 0.12),
            dot: isDark ? wwColor(0xE6E6E6, alpha: 0.35) : wwColor(0x000000, alpha: 0.16),
            tickTop: isDark ? wwColor(0xF2F3F5) : wwColor(0xF7F7F8),
            tickBottom: isDark ? wwColor(0x9FA6B0) : wwColor(0xB1B7C0),
            tickShadow: isDark ? wwColor(0x000000, alpha: 0.55) : wwColor(0x000000, alpha: 0.20),
            numeralsBase: isDark ? wwColor(0xE9EEF6) : wwColor(0x8A8F98),
            numeralsShadow: isDark ? wwColor(0x000000, alpha: 0.65) : wwColor(0x000000, alpha: 0.18),
            bezelHighlight: isDark ? wwColor(0xF4F6F9) : wwColor(0xFFFFFF),
            bezelMid: isDark ? wwColor(0x8E949D) : wwColor(0xC9CDD3),
            bezelShadow: isDark ? wwColor(0x14161A) : wwColor(0x8E939B)
        )

        let background: (Color, Color)
        let accentPair: (Color, Color)

        switch scheme {
        case .classic:
            background = isDark
                ? (wwColor(0x15171B), wwColor(0x0B0D10))
                : (wwColor(0xFAFAFA), wwColor(0xEDEDED))
            accentPair = (wwColor(0x2BC0FD), wwColor(0x6CEAFF))

        case .ocean:
            background = isDark
                ? (wwColor(0x0E1A2A), wwColor(0x08101A))
                : (wwColor(0xF2F8FF), wwColor(0xE6F2FF))
            accentPair = (wwColor(0x00A9FF), wwColor(0x66D6FF))

        case .mint:
            background = isDark
                ? (wwColor(0x0F1F1B), wwColor(0x07110E))
                : (wwColor(0xF1FFFB), wwColor(0xE4FFF5))
            accentPair = (wwColor(0x2EF2C6), wwColor(0x7CFFD8))

        case .orchid:
            background = isDark
                ? (wwColor(0x1B1124), wwColor(0x0D0812))
                : (wwColor(0xFBF2FF), wwColor(0xF2E6FF))
            accentPair = (wwColor(0xC77DFF), wwColor(0xE3B4FF))

        case .sunset:
            background = isDark
                ? (wwColor(0x22150F), wwColor(0x120B08))
                : (wwColor(0xFFF6EF), wwColor(0xFFE9D9))
            accentPair = (wwColor(0xFF8A00), wwColor(0xFFD29A))

        case .ember:
            background = isDark
                ? (wwColor(0x230C0C), wwColor(0x110606))
                : (wwColor(0xFFF2F2), wwColor(0xFFE1E1))
            accentPair = (wwColor(0xFF3B30), wwColor(0xFF9A93))

        case .graphite:
            background = isDark
                ? (wwColor(0x1C1D1F), wwColor(0x101113))
                : (wwColor(0xF7F7F7), wwColor(0xE6E7E9))
            accentPair = (wwColor(0x9AA0A6), wwColor(0xC4C7CC))
        }

        return WidgetWeaverClockPalette(
            mode: isDark ? .dark : .light,
            backgroundTop: background.0,
            backgroundBottom: background.1,
            bezelHighlight: common.bezelHighlight,
            bezelMid: common.bezelMid,
            bezelShadow: common.bezelShadow,
            faceTop: common.faceTop,
            faceBottom: common.faceBottom,
            faceRimHighlight: common.faceRimHighlight,
            faceRimShadow: common.faceRimShadow,
            dot: common.dot,
            tickTop: common.tickTop,
            tickBottom: common.tickBottom,
            tickShadow: common.tickShadow,
            numeralsBase: common.numeralsBase,
            numeralsShadow: common.numeralsShadow,
            accent: accentPair.0,
            accentSecondary: accentPair.1
        )
    }
}

// MARK: - Background

private struct WidgetWeaverClockBackgroundView: View {
    let palette: WidgetWeaverClockPalette

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let corner = s * 0.224

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.backgroundTop, palette.backgroundBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(palette.mode == .dark ? 0.18 : 0.65),
                                    Color.black.opacity(palette.mode == .dark ? 0.65 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1, s * 0.012)
                        )
                        .blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(palette.mode == .dark ? 0.05 : 0.20),
                            lineWidth: max(1, s * 0.004)
                        )
                        .blur(radius: s * 0.004)
                        .offset(x: -s * 0.002, y: -s * 0.002)
                        .mask(
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                        )
                )
        }
    }
}

// MARK: - Icon

private struct WidgetWeaverClockIconView: View {
    let now: Date
    let palette: WidgetWeaverClockPalette
    let colourScheme: WidgetWeaverClockColourScheme

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = s * 0.94
            let bezelWidth = s * 0.043

            let innerDiameter = outerDiameter - (bezelWidth * 2)
            let innerRadius = innerDiameter / 2

            let storageKey = "WidgetWeaver.ClockIcon.lastRendered.\(colourScheme.rawValue)"

            ZStack {
                // Ambient depth behind the clock face.
                Circle()
                    .fill(Color.black.opacity(palette.mode == .dark ? 0.55 : 0.18))
                    .frame(width: outerDiameter, height: outerDiameter)
                    .blur(radius: s * 0.040)
                    .offset(y: s * 0.022)

                WidgetWeaverClockBezelView(
                    palette: palette,
                    diameter: outerDiameter,
                    bezelWidth: bezelWidth
                )

                WidgetWeaverClockFaceView(
                    palette: palette,
                    diameter: innerDiameter
                )

                WidgetWeaverClockMinuteDotsView(
                    palette: palette,
                    count: 60,
                    dotSize: max(1, s * 0.0055),
                    radius: innerRadius * 0.93
                )

                WidgetWeaverClockHourTicksView(
                    palette: palette,
                    tickWidth: s * 0.022,
                    tickLength: s * 0.118,
                    radius: innerRadius * 0.80
                )

                WidgetWeaverClockMajorGlowSquaresView(
                    palette: palette,
                    squareSize: s * 0.024,
                    radius: innerRadius * 0.93
                )

                WidgetWeaverClockNumeralsView(
                    palette: palette,
                    fontSize: s * 0.235,
                    radius: innerRadius * 0.64
                )

                WidgetWeaverClockHandsView(
                    now: now,
                    palette: palette,
                    innerRadius: innerRadius,
                    storageKey: storageKey
                )

                WidgetWeaverClockHubView(
                    palette: palette,
                    diameter: s * 0.092
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

// MARK: - Bezel + Face

private struct WidgetWeaverClockBezelView: View {
    let palette: WidgetWeaverClockPalette
    let diameter: CGFloat
    let bezelWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelHighlight, location: 0.00),
                            .init(color: palette.bezelMid, location: 0.18),
                            .init(color: palette.bezelShadow, location: 0.48),
                            .init(color: palette.bezelMid, location: 0.80),
                            .init(color: palette.bezelHighlight, location: 1.00)
                        ]),
                        center: .center,
                        startAngle: .degrees(-110),
                        endAngle: .degrees(250)
                    ),
                    lineWidth: bezelWidth
                )
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: Color.black.opacity(palette.mode == .dark ? 0.55 : 0.18),
                    radius: bezelWidth * 0.45,
                    x: 0,
                    y: bezelWidth * 0.25
                )

            // Outer crisp edge.
            Circle()
                .strokeBorder(
                    Color.white.opacity(palette.mode == .dark ? 0.18 : 0.55),
                    lineWidth: max(1, bezelWidth * 0.10)
                )
                .frame(width: diameter, height: diameter)
                .blendMode(.overlay)

            // Inner rim edge.
            Circle()
                .strokeBorder(
                    Color.black.opacity(palette.mode == .dark ? 0.75 : 0.15),
                    lineWidth: max(1, bezelWidth * 0.10)
                )
                .frame(width: diameter - bezelWidth, height: diameter - bezelWidth)
        }
    }
}

private struct WidgetWeaverClockFaceView: View {
    let palette: WidgetWeaverClockPalette
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        palette.faceTop,
                        palette.faceBottom
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: diameter * 0.70
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [palette.faceRimHighlight, palette.faceRimShadow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1, diameter * 0.018)
                    )
            )
            .overlay(
                // Subtle vignette to match the mockups.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(palette.mode == .dark ? 0.35 : 0.10)
                            ],
                            center: .center,
                            startRadius: diameter * 0.15,
                            endRadius: diameter * 0.55
                        )
                    )
                    .blendMode(.multiply)
            )
    }
}

// MARK: - Markers

private struct WidgetWeaverClockMinuteDotsView: View {
    let palette: WidgetWeaverClockPalette
    let count: Int
    let dotSize: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(palette.dot)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(i) * (360.0 / Double(count))))
            }
        }
    }
}

private struct WidgetWeaverClockHourTicksView: View {
    let palette: WidgetWeaverClockPalette
    let tickWidth: CGFloat
    let tickLength: CGFloat
    let radius: CGFloat

    private var hoursWithTicks: [Int] { [1, 2, 4, 5, 7, 8, 10, 11] }

    var body: some View {
        ZStack {
            ForEach(hoursWithTicks, id: \.self) { hour in
                WidgetWeaverClockHourTickView(
                    palette: palette,
                    tickWidth: tickWidth,
                    tickLength: tickLength
                )
                .offset(y: -(radius - tickLength / 2))
                .rotationEffect(.degrees(Double(hour) * 30.0))
            }
        }
    }
}

private struct WidgetWeaverClockHourTickView: View {
    let palette: WidgetWeaverClockPalette
    let tickWidth: CGFloat
    let tickLength: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: tickWidth * 0.55, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [palette.tickTop, palette.tickBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: tickWidth * 0.55, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(palette.mode == .dark ? 0.35 : 0.55),
                        lineWidth: max(1, tickWidth * 0.10)
                    )
                    .blendMode(.overlay)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: tickWidth * 0.40, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.accentSecondary.opacity(palette.mode == .dark ? 0.95 : 0.65),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: tickWidth * 1.35, height: tickLength * 0.35)
                    .blur(radius: tickWidth * 0.60)
                    .offset(y: -tickLength * 0.02)
                    .blendMode(.screen)
            }
            .shadow(
                color: palette.tickShadow,
                radius: tickWidth * 0.60,
                x: 0,
                y: tickWidth * 0.40
            )
            .frame(width: tickWidth, height: tickLength)
    }
}

private struct WidgetWeaverClockMajorGlowSquaresView: View {
    let palette: WidgetWeaverClockPalette
    let squareSize: CGFloat
    let radius: CGFloat

    private var angles: [Double] { [90, 180, 270] } // 3, 6, 9

    var body: some View {
        ZStack {
            ForEach(angles, id: \.self) { degrees in
                RoundedRectangle(cornerRadius: squareSize * 0.18, style: .continuous)
                    .fill(palette.accent)
                    .frame(width: squareSize, height: squareSize)
                    .shadow(
                        color: palette.accent.opacity(palette.mode == .dark ? 0.75 : 0.35),
                        radius: squareSize * 0.65,
                        x: 0,
                        y: squareSize * 0.15
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: squareSize * 0.18, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(palette.mode == .dark ? 0.35 : 0.55),
                                lineWidth: max(1, squareSize * 0.08)
                            )
                            .blendMode(.overlay)
                    )
                    .offset(y: -radius)
                    .rotationEffect(.degrees(degrees))
            }
        }
    }
}

// MARK: - Numerals

private struct WidgetWeaverClockNumeralsView: View {
    let palette: WidgetWeaverClockPalette
    let fontSize: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            numeral("12", angle: 0)
            numeral("3", angle: 90)
            numeral("6", angle: 180)
            numeral("9", angle: 270)
        }
    }

    @ViewBuilder
    private func numeral(_ text: String, angle: Double) -> some View {
        WidgetWeaverClockEmbossedText(
            text: text,
            fontSize: fontSize,
            base: palette.numeralsBase,
            shadow: palette.numeralsShadow,
            mode: palette.mode
        )
        .offset(y: -radius)
        .rotationEffect(.degrees(angle))
    }
}

private struct WidgetWeaverClockEmbossedText: View {
    let text: String
    let fontSize: CGFloat
    let base: Color
    let shadow: Color
    let mode: WidgetWeaverClockPalette.Mode

    var body: some View {
        ZStack {
            Text(text)
                .font(.system(size: fontSize, weight: .light, design: .rounded))
                .foregroundStyle(Color.black.opacity(mode == .dark ? 0.55 : 0.22))
                .offset(x: 0, y: fontSize * 0.030)
                .blur(radius: fontSize * 0.020)

            Text(text)
                .font(.system(size: fontSize, weight: .light, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(mode == .dark ? 0.85 : 0.75),
                            base
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: shadow,
                    radius: fontSize * 0.06,
                    x: 0,
                    y: fontSize * 0.025
                )

            Text(text)
                .font(.system(size: fontSize, weight: .light, design: .rounded))
                .foregroundStyle(Color.white.opacity(mode == .dark ? 0.18 : 0.28))
                .blendMode(.overlay)
                .offset(x: -fontSize * 0.018, y: -fontSize * 0.018)
        }
    }
}

// MARK: - Hands (Smooth sweep + catch-up)

private struct WidgetWeaverClockHandsView: View {
    let now: Date
    let palette: WidgetWeaverClockPalette
    let innerRadius: CGFloat
    let storageKey: String

    @State private var hasStarted: Bool = false

    @State private var hourAngle: Double = 0
    @State private var minuteAngle: Double = 0
    @State private var secondAngle: Double = 0

    private var secondSweep: Animation { .linear(duration: 60).repeatForever(autoreverses: false) }
    private var minuteSweep: Animation { .linear(duration: 3600).repeatForever(autoreverses: false) }
    private var hourSweep: Animation { .linear(duration: 43200).repeatForever(autoreverses: false) }

    var body: some View {
        let hourLength = innerRadius * 0.50
        let minuteLength = innerRadius * 0.78
        let secondLength = innerRadius * 0.86

        let hourWidth = innerRadius * 0.24
        let minuteWidth = innerRadius * 0.085
        let secondWidth = max(1, innerRadius * 0.022)

        ZStack {
            WidgetWeaverClockHourHandView(
                palette: palette,
                width: hourWidth,
                length: hourLength,
                angleDegrees: hourAngle
            )

            WidgetWeaverClockMinuteHandView(
                palette: palette,
                width: minuteWidth,
                length: minuteLength,
                angleDegrees: minuteAngle
            )

            WidgetWeaverClockSecondHandView(
                palette: palette,
                width: secondWidth,
                length: secondLength,
                angleDegrees: secondAngle
            )
        }
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            startAnimations(targetDate: now)
        }
        .onChange(of: minuteKey(for: now)) { _, _ in
            restartAnimations(targetDate: now)
        }
    }

    private func minuteKey(for date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / 60.0)
    }

    private func startAnimations(targetDate: Date) {
        let previous = loadLastRenderedDate()
        storeLastRenderedDate(targetDate)

        let targetAngles = WidgetWeaverClockAngles.from(date: targetDate)

        // Hour + minute jump to correct position first, then sweep continuously.
        withTransaction(Transaction(animation: nil)) {
            hourAngle = targetAngles.hour
            minuteAngle = targetAngles.minute
        }

        DispatchQueue.main.async {
            withAnimation(hourSweep) { hourAngle = targetAngles.hour + 360.0 }
            withAnimation(minuteSweep) { minuteAngle = targetAngles.minute + 360.0 }
        }

        // Second hand: graceful catch-up if a prior render exists.
        if let previous {
            let gap = targetDate.timeIntervalSince(previous)
            if gap > 2.0 {
                let previousAngles = WidgetWeaverClockAngles.from(date: previous)

                withTransaction(Transaction(animation: nil)) {
                    secondAngle = previousAngles.second
                }

                let catchUpDuration = min(0.95, max(0.35, 0.35 + (log(gap + 1) * 0.12)))

                var targetSecondForward = targetAngles.second
                while targetSecondForward < previousAngles.second {
                    targetSecondForward += 360.0
                }

                let extraTurns = min(3, Int(gap / 60.0))
                targetSecondForward += Double(extraTurns) * 360.0

                withAnimation(.easeOut(duration: catchUpDuration)) {
                    secondAngle = targetSecondForward
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + catchUpDuration) {
                    withAnimation(secondSweep) {
                        secondAngle = targetSecondForward + 360.0
                    }
                }
                return
            }
        }

        // No catch-up path.
        withTransaction(Transaction(animation: nil)) {
            secondAngle = targetAngles.second
        }
        DispatchQueue.main.async {
            withAnimation(secondSweep) {
                secondAngle = targetAngles.second + 360.0
            }
        }
    }

    private func restartAnimations(targetDate: Date) {
        // Use the stored value as the “previous” marker for catch-up.
        startAnimations(targetDate: targetDate)
    }

    private func loadLastRenderedDate() -> Date? {
        if AppGroup.userDefaults.object(forKey: storageKey) == nil {
            return nil
        }
        let ts = AppGroup.userDefaults.double(forKey: storageKey)
        return Date(timeIntervalSinceReferenceDate: ts)
    }

    private func storeLastRenderedDate(_ date: Date) {
        AppGroup.userDefaults.set(date.timeIntervalSinceReferenceDate, forKey: storageKey)
    }
}

private struct WidgetWeaverClockAngles {
    let hour: Double
    let minute: Double
    let second: Double

    static func from(date: Date) -> WidgetWeaverClockAngles {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let h = Double((comps.hour ?? 0) % 12)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0) + (Double(comps.nanosecond ?? 0) / 1_000_000_000.0)

        let minuteFloat = m + (s / 60.0)
        let hourFloat = h + (minuteFloat / 60.0)

        let secondDeg = (s / 60.0) * 360.0
        let minuteDeg = (minuteFloat / 60.0) * 360.0
        let hourDeg = (hourFloat / 12.0) * 360.0

        return WidgetWeaverClockAngles(hour: hourDeg, minute: minuteDeg, second: secondDeg)
    }
}

// MARK: - Hand Views

private struct WidgetWeaverClockHourHandView: View {
    let palette: WidgetWeaverClockPalette
    let width: CGFloat
    let length: CGFloat
    let angleDegrees: Double

    var body: some View {
        WidgetWeaverClockHourHandShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(palette.mode == .dark ? 0.95 : 0.75),
                        wwColor(0xC9CED6),
                        wwColor(0x7D838D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                WidgetWeaverClockHourHandShape()
                    .stroke(
                        Color.white.opacity(palette.mode == .dark ? 0.22 : 0.35),
                        style: StrokeStyle(
                            lineWidth: max(1, width * 0.06),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .blendMode(.overlay)
            }
            .shadow(
                color: Color.black.opacity(palette.mode == .dark ? 0.55 : 0.18),
                radius: width * 0.40,
                x: 0,
                y: width * 0.25
            )
            .frame(width: width, height: length)
            .rotationEffect(.degrees(angleDegrees), anchor: .bottom)
            .offset(y: -length * 0.02)
    }
}

private struct WidgetWeaverClockMinuteHandView: View {
    let palette: WidgetWeaverClockPalette
    let width: CGFloat
    let length: CGFloat
    let angleDegrees: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.55, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.mode == .dark ? 0.98 : 0.80),
                            wwColor(0xC6CBD3),
                            wwColor(0x7A808A)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Accent edge glow
            RoundedRectangle(cornerRadius: width * 0.55, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.accent.opacity(palette.mode == .dark ? 0.95 : 0.55),
                            Color.clear
                        ],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .blendMode(.screen)
                .blur(radius: width * 0.55)
                .offset(x: width * 0.22)
        }
        .shadow(
            color: Color.black.opacity(palette.mode == .dark ? 0.55 : 0.18),
            radius: width * 0.55,
            x: 0,
            y: width * 0.32
        )
        .frame(width: width, height: length)
        .rotationEffect(.degrees(angleDegrees), anchor: .bottom)
        .offset(y: -length * 0.02)
    }
}

private struct WidgetWeaverClockSecondHandView: View {
    let palette: WidgetWeaverClockPalette
    let width: CGFloat
    let length: CGFloat
    let angleDegrees: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.55, style: .continuous)
                .fill(palette.accent)
                .frame(width: width, height: length)
                .offset(y: -length / 2)

            RoundedRectangle(cornerRadius: width * 0.25, style: .continuous)
                .fill(palette.accentSecondary)
                .frame(width: width * 1.25, height: width * 1.25)
                .offset(y: -length)
                .shadow(
                    color: palette.accent.opacity(palette.mode == .dark ? 0.75 : 0.35),
                    radius: width * 1.10,
                    x: 0,
                    y: width * 0.25
                )
        }
        .shadow(
            color: palette.accent.opacity(palette.mode == .dark ? 0.55 : 0.20),
            radius: width * 1.40,
            x: 0,
            y: width * 0.40
        )
        .rotationEffect(.degrees(angleDegrees))
    }
}

private struct WidgetWeaverClockHourHandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let tipY: CGFloat = 0
        let baseY: CGFloat = h

        let tipHalfWidth = w * 0.16
        let midHalfWidth = w * 0.36
        let baseHalfWidth = w * 0.46

        let tipX = w / 2.0
        let midY = h * 0.18
        let baseCorner = w * 0.22

        var p = Path()

        // Tip
        p.move(to: CGPoint(x: tipX - tipHalfWidth, y: tipY))
        p.addLine(to: CGPoint(x: tipX + tipHalfWidth, y: tipY))

        // Right shoulder
        p.addQuadCurve(
            to: CGPoint(x: tipX + midHalfWidth, y: midY),
            control: CGPoint(x: tipX + tipHalfWidth * 1.10, y: midY * 0.30)
        )

        // Right edge down to base
        p.addLine(to: CGPoint(x: tipX + baseHalfWidth, y: baseY - baseCorner))
        p.addQuadCurve(
            to: CGPoint(x: tipX + baseHalfWidth - baseCorner, y: baseY),
            control: CGPoint(x: tipX + baseHalfWidth, y: baseY)
        )

        // Base
        p.addLine(to: CGPoint(x: tipX - baseHalfWidth + baseCorner, y: baseY))
        p.addQuadCurve(
            to: CGPoint(x: tipX - baseHalfWidth, y: baseY - baseCorner),
            control: CGPoint(x: tipX - baseHalfWidth, y: baseY)
        )

        // Left edge back to tip
        p.addLine(to: CGPoint(x: tipX - midHalfWidth, y: midY))
        p.addQuadCurve(
            to: CGPoint(x: tipX - tipHalfWidth, y: tipY),
            control: CGPoint(x: tipX - tipHalfWidth * 1.10, y: midY * 0.30)
        )

        p.closeSubpath()
        return p
    }
}

// MARK: - Hub

private struct WidgetWeaverClockHubView: View {
    let palette: WidgetWeaverClockPalette
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(palette.mode == .dark ? 0.95 : 0.75),
                            wwColor(0xC2C7CF),
                            wwColor(0x747A84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(
                    Color.white.opacity(palette.mode == .dark ? 0.25 : 0.40),
                    lineWidth: max(1, diameter * 0.10)
                )
                .blendMode(.overlay)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            wwColor(0xFFFFFF, alpha: palette.mode == .dark ? 0.35 : 0.22),
                            wwColor(0x000000, alpha: palette.mode == .dark ? 0.40 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diameter * 0.42, height: diameter * 0.42)
        }
        .frame(width: diameter, height: diameter)
        .shadow(
            color: Color.black.opacity(palette.mode == .dark ? 0.55 : 0.18),
            radius: diameter * 0.12,
            x: 0,
            y: diameter * 0.06
        )
    }
}

// MARK: - Widget background helper

private extension View {
    @ViewBuilder
    func wwWidgetContainerBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                background()
            }
        } else {
            self.background(background())
        }
    }
}

// MARK: - Colour helper

private func wwColor(_ hex: UInt32, alpha: Double = 1.0) -> Color {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
}

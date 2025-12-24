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

        // Tick the second hand by stepping through a dense timeline.
        // The system may still throttle updates, but providing frequent entries is the only
        // reliable way to animate non-text content in a Home Screen widget.
        let now = Date()

        let tickSeconds: TimeInterval = 1.0
        let maxEntries: Int = 360  // ~6 minutes at 1s/tick (keeps the timeline reasonably small)

        // Align to whole seconds so hands don’t “wobble” due to sub-second render timing.
        let base = Date(timeIntervalSinceReferenceDate: floor(now.timeIntervalSinceReferenceDate))

        var entries: [Entry] = []
        entries.reserveCapacity(maxEntries)

        for i in 0..<maxEntries {
            let d = base.addingTimeInterval(TimeInterval(i) * tickSeconds)
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
            WidgetWeaverHomeScreenClockView(entry: entry)
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - View

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry
    @Environment(\.colorScheme) private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(scheme: entry.colourScheme, mode: mode)
        let now = entry.date

        ZStack {
            WidgetWeaverClockIconView(date: now, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
        .transaction { t in
            t.animation = nil
        }
    }
}

// MARK: - Palette

private struct WidgetWeaverClockPalette {
    let accent: Color

    let backgroundTop: Color
    let backgroundBottom: Color

    let bezelHighlight: Color
    let bezelMid: Color
    let bezelShadow: Color

    let faceTop: Color
    let faceBottom: Color

    let numerals: Color
    let numeralsShadow: Color

    let minuteDot: Color

    let tickTop: Color
    let tickBottom: Color
    let tickShadow: Color

    let hourHandTop: Color
    let hourHandBottom: Color
    let minuteHandTop: Color
    let minuteHandBottom: Color
    let handShadow: Color

    let hubOuter: Color
    let hubInner: Color
    let hubShadow: Color

    let rimInnerShadow: Color

    static func resolve(scheme: WidgetWeaverClockColourScheme, mode: ColorScheme) -> WidgetWeaverClockPalette {
        let isDark = (mode == .dark)

        let accent: Color = {
            switch scheme {
            case .classic:
                return isDark ? wwColor(0x429FD0) : wwColor(0x7EFCD8)
            case .ocean:
                return isDark ? wwColor(0x4FA9FF) : wwColor(0x4AAEF6)
            case .mint:
                return isDark ? wwColor(0x4BE3B4) : wwColor(0x4BE3B4)
            case .orchid:
                return isDark ? wwColor(0xB08CFF) : wwColor(0xB08CFF)
            case .sunset:
                return isDark ? wwColor(0xFFAA5C) : wwColor(0xFF9F4E)
            case .ember:
                return isDark ? wwColor(0xFF5A56) : wwColor(0xFF4D4A)
            case .graphite:
                return isDark ? wwColor(0xC8C8C8) : wwColor(0xC8C8C8)
            }
        }()

        let backgroundTop: Color = {
            switch scheme {
            case .classic:
                return isDark ? wwColor(0x0A0F18) : wwColor(0xE8F2FA)
            case .ocean:
                return isDark ? wwColor(0x050B12) : wwColor(0xE7F4FF)
            case .mint:
                return isDark ? wwColor(0x06120E) : wwColor(0xE6FFF3)
            case .orchid:
                return isDark ? wwColor(0x0C0712) : wwColor(0xF3ECFF)
            case .sunset:
                return isDark ? wwColor(0x120A05) : wwColor(0xFFF2E8)
            case .ember:
                return isDark ? wwColor(0x160707) : wwColor(0xFFF0F0)
            case .graphite:
                return isDark ? wwColor(0x0A0A0A) : wwColor(0xF2F2F2)
            }
        }()

        let backgroundBottom: Color = {
            switch scheme {
            case .classic:
                return isDark ? wwColor(0x1A2433) : wwColor(0xCFE8FF)
            case .ocean:
                return isDark ? wwColor(0x0D2238) : wwColor(0xCFEAFF)
            case .mint:
                return isDark ? wwColor(0x0D2B20) : wwColor(0xCFFFEA)
            case .orchid:
                return isDark ? wwColor(0x241235) : wwColor(0xE6DAFF)
            case .sunset:
                return isDark ? wwColor(0x2E1408) : wwColor(0xFFE0C9)
            case .ember:
                return isDark ? wwColor(0x2B0C0C) : wwColor(0xFFD7D7)
            case .graphite:
                return isDark ? wwColor(0x1B1B1B) : wwColor(0xD9D9D9)
            }
        }()

        let bezelHighlight = isDark ? wwColor(0xFFFFFF, 0.18) : wwColor(0xFFFFFF, 0.62)
        let bezelMid = isDark ? wwColor(0xFFFFFF, 0.10) : wwColor(0xFFFFFF, 0.28)
        let bezelShadow = isDark ? wwColor(0x000000, 0.46) : wwColor(0x000000, 0.18)

        let faceTop = isDark ? wwColor(0x10131A) : wwColor(0xFFFFFF)
        let faceBottom = isDark ? wwColor(0x0A0C10) : wwColor(0xEDEFF6)

        let numerals = isDark ? wwColor(0xE9EEF8, 0.85) : wwColor(0x1B2230, 0.75)
        let numeralsShadow = isDark ? wwColor(0x000000, 0.55) : wwColor(0x000000, 0.12)

        let minuteDot = isDark ? wwColor(0xFFFFFF, 0.10) : wwColor(0x000000, 0.10)

        let tickTop = isDark ? wwColor(0xFFFFFF, 0.16) : wwColor(0xFFFFFF, 0.70)
        let tickBottom = isDark ? wwColor(0xFFFFFF, 0.06) : wwColor(0xFFFFFF, 0.30)
        let tickShadow = isDark ? wwColor(0x000000, 0.55) : wwColor(0x000000, 0.20)

        let hourHandTop = isDark ? wwColor(0xFFFFFF, 0.80) : wwColor(0x1E2330, 0.85)
        let hourHandBottom = isDark ? wwColor(0xFFFFFF, 0.35) : wwColor(0x1E2330, 0.55)

        let minuteHandTop = isDark ? wwColor(0xFFFFFF, 0.88) : wwColor(0x202738, 0.90)
        let minuteHandBottom = isDark ? wwColor(0xFFFFFF, 0.44) : wwColor(0x202738, 0.62)

        let handShadow = isDark ? wwColor(0x000000, 0.62) : wwColor(0x000000, 0.20)

        let hubOuter = isDark ? wwColor(0xFFFFFF, 0.22) : wwColor(0xFFFFFF, 0.75)
        let hubInner = isDark ? wwColor(0xFFFFFF, 0.10) : wwColor(0xFFFFFF, 0.40)
        let hubShadow = isDark ? wwColor(0x000000, 0.60) : wwColor(0x000000, 0.22)

        let rimInnerShadow = isDark ? wwColor(0x000000, 0.65) : wwColor(0x000000, 0.18)

        return WidgetWeaverClockPalette(
            accent: accent,
            backgroundTop: backgroundTop,
            backgroundBottom: backgroundBottom,
            bezelHighlight: bezelHighlight,
            bezelMid: bezelMid,
            bezelShadow: bezelShadow,
            faceTop: faceTop,
            faceBottom: faceBottom,
            numerals: numerals,
            numeralsShadow: numeralsShadow,
            minuteDot: minuteDot,
            tickTop: tickTop,
            tickBottom: tickBottom,
            tickShadow: tickShadow,
            hourHandTop: hourHandTop,
            hourHandBottom: hourHandBottom,
            minuteHandTop: minuteHandTop,
            minuteHandBottom: minuteHandBottom,
            handShadow: handShadow,
            hubOuter: hubOuter,
            hubInner: hubInner,
            hubShadow: hubShadow,
            rimInnerShadow: rimInnerShadow
        )
    }
}

// MARK: - Background

private struct WidgetWeaverClockBackgroundView: View {
    let palette: WidgetWeaverClockPalette

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let corner = s * 0.205

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [palette.backgroundTop, palette.backgroundBottom]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: max(1, s * 0.003))
                        .blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.00),
                                    Color.black.opacity(0.22)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.overlay)
                )
        }
    }
}

// MARK: - Clock Icon

private struct WidgetWeaverClockIconView: View {
    let date: Date
    let palette: WidgetWeaverClockPalette

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = s * 0.925
            let bezelWidth = s * 0.040
            let innerDiameter = outerDiameter - (bezelWidth * 2.0)
            let innerRadius = innerDiameter * 0.5

            let dotsRadius = innerRadius * 0.93
            let ticksRadius = innerRadius * 0.80
            let squaresRadius = innerRadius * 0.93
            let numeralsRadius = innerRadius * 0.64

            let tickWidth = s * 0.022
            let tickLength = s * 0.112

            let hubDiameter = s * 0.085

            ZStack {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.bezelHighlight, location: 0.0),
                                .init(color: palette.bezelMid, location: 0.48),
                                .init(color: palette.bezelShadow, location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: bezelWidth
                    )
                    .frame(width: outerDiameter, height: outerDiameter)
                    .shadow(color: palette.rimInnerShadow.opacity(0.30), radius: s * 0.012, x: 0, y: s * 0.006)

                Circle()
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: max(1, s * 0.002))
                    .frame(width: outerDiameter - bezelWidth * 0.18, height: outerDiameter - bezelWidth * 0.18)

                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.faceTop, location: 0.0),
                                .init(color: palette.faceBottom, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: outerDiameter * 0.55
                        )
                    )
                    .frame(width: innerDiameter, height: innerDiameter)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.10), lineWidth: max(1, s * 0.0015))
                            .blur(radius: s * 0.001)
                    )

                WidgetWeaverClockMinuteDotsView(
                    count: 60,
                    dotColor: palette.minuteDot,
                    dotSize: max(1, s * 0.0060),
                    radius: dotsRadius
                )

                WidgetWeaverClockHourTicksView(
                    palette: palette,
                    tickWidth: tickWidth,
                    tickLength: tickLength,
                    radius: ticksRadius
                )

                WidgetWeaverClockMajorGlowSquaresView(
                    glowColor: palette.accent,
                    size: max(2, s * 0.020),
                    radius: squaresRadius
                )

                WidgetWeaverClockNumeralsView(
                    color: palette.numerals,
                    shadow: palette.numeralsShadow,
                    fontSize: s * 0.22,
                    radius: numeralsRadius
                )

                WidgetWeaverClockHandsView(
                    date: date,
                    palette: palette,
                    innerRadius: innerRadius
                )

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [palette.hubOuter, palette.hubInner]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: hubDiameter, height: hubDiameter)
                        .shadow(color: palette.hubShadow, radius: s * 0.010, x: 0, y: s * 0.004)

                    Circle()
                        .fill(Color.black.opacity(0.10))
                        .frame(width: hubDiameter * 0.62, height: hubDiameter * 0.62)

                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: max(1, s * 0.002))
                        .frame(width: hubDiameter * 0.92, height: hubDiameter * 0.92)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WidgetWeaverClockMinuteDotsView: View {
    let count: Int
    let dotColor: Color
    let dotSize: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: -radius)
                    .rotationEffect(.degrees((Double(i) / Double(count)) * 360.0))
            }
        }
    }
}

private struct WidgetWeaverClockHourTicksView: View {
    let palette: WidgetWeaverClockPalette
    let tickWidth: CGFloat
    let tickLength: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: tickWidth * 0.45, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [palette.tickTop, palette.tickBottom]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: tickWidth, height: tickLength)
                    .shadow(color: palette.tickShadow, radius: tickWidth * 0.70, x: 0, y: tickWidth * 0.35)
                    .offset(y: -radius)
                    .rotationEffect(.degrees((Double(i) / 12.0) * 360.0))
            }
        }
    }
}

private struct WidgetWeaverClockMajorGlowSquaresView: View {
    let glowColor: Color
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach([3, 6, 9], id: \.self) { i in
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(glowColor)
                    .frame(width: size, height: size)
                    .shadow(color: glowColor.opacity(0.85), radius: size * 1.6, x: 0, y: 0)
                    .offset(y: -radius)
                    .rotationEffect(.degrees((Double(i) / 12.0) * 360.0))
            }
        }
    }
}

private struct WidgetWeaverClockNumeralsView: View {
    let color: Color
    let shadow: Color
    let fontSize: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            Group {
                Text("12").offset(x: 0, y: -radius)
                Text("3").offset(x: radius, y: 0)
                Text("6").offset(x: 0, y: radius)
                Text("9").offset(x: -radius, y: 0)
            }
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: shadow, radius: fontSize * 0.05, x: 0, y: fontSize * 0.03)
        }
    }
}

// MARK: - Hands

private struct WidgetWeaverClockHandsView: View {
    let date: Date
    let palette: WidgetWeaverClockPalette
    let innerRadius: CGFloat

    var body: some View {
        let tickDate = Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate))
        let a = WidgetWeaverClockAngles(date: tickDate)

        ZStack {
            WidgetWeaverClockHourHandView(
                palette: palette,
                width: innerRadius * 0.30,
                length: innerRadius * 0.56,
                angle: a.hour
            )

            WidgetWeaverClockMinuteHandView(
                palette: palette,
                width: innerRadius * 0.13,
                length: innerRadius * 0.86,
                angle: a.minute
            )

            WidgetWeaverClockSecondHandView(
                palette: palette,
                width: max(1, innerRadius * 0.012),
                length: innerRadius * 0.92,
                angleDegrees: a.secondDegrees
            )
        }
    }
}

private struct WidgetWeaverClockAngles {
    let hour: Angle
    let minute: Angle
    let secondDegrees: Double

    init(date: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: date)

        let h = Double((comps.hour ?? 0) % 12)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0)

        let hourValue = h + (m / 60.0)
        let minuteValue = m

        self.hour = .degrees((hourValue / 12.0) * 360.0)
        self.minute = .degrees((minuteValue / 60.0) * 360.0)
        self.secondDegrees = (s / 60.0) * 360.0
    }
}

private struct WidgetWeaverClockHourHandView: View {
    let palette: WidgetWeaverClockPalette
    let width: CGFloat
    let length: CGFloat
    let angle: Angle

    var body: some View {
        WidgetWeaverClockHourHandShape()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [palette.hourHandTop, palette.hourHandBottom]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                WidgetWeaverClockHourHandShape()
                    .stroke(Color.black.opacity(0.16), lineWidth: max(1, width * 0.03))
            )
            .shadow(color: palette.handShadow, radius: width * 0.22, x: 0, y: width * 0.12)
            .frame(width: width, height: length)
            .rotationEffect(angle, anchor: .bottom)
            .offset(y: -length / 2.0)
    }
}

private struct WidgetWeaverClockHourHandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let tipWidth = w * 0.72
        let baseWidth = w
        let tipInsetY = h * 0.03

        let tipLeft = CGPoint(x: rect.midX - tipWidth * 0.5, y: rect.minY + tipInsetY)
        let tipRight = CGPoint(x: rect.midX + tipWidth * 0.5, y: rect.minY + tipInsetY)
        let baseRight = CGPoint(x: rect.midX + baseWidth * 0.5, y: rect.maxY)
        let baseLeft = CGPoint(x: rect.midX - baseWidth * 0.5, y: rect.maxY)

        var p = Path()
        p.move(to: baseLeft)
        p.addLine(to: tipLeft)
        p.addQuadCurve(to: tipRight, control: CGPoint(x: rect.midX, y: rect.minY - (w * 0.10)))
        p.addLine(to: baseRight)
        p.closeSubpath()
        return p
    }
}

private struct WidgetWeaverClockMinuteHandView: View {
    let palette: WidgetWeaverClockPalette
    let width: CGFloat
    let length: CGFloat
    let angle: Angle

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.48, style: .continuous)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [palette.minuteHandTop, palette.minuteHandBottom]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.48, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: max(1, width * 0.05))
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(palette.accent.opacity(0.95))
                    .frame(width: max(1, width * 0.12))
                    .blur(radius: width * 0.22)
                    .shadow(color: palette.accent.opacity(0.75), radius: width * 1.0, x: 0, y: 0)
                    .blendMode(.screen)
            }
            .shadow(color: palette.handShadow, radius: width * 0.18, x: 0, y: width * 0.12)
            .shadow(color: palette.accent.opacity(0.30), radius: width * 1.7, x: width * 0.45, y: width * 0.55)
            .frame(width: width, height: length)
            .rotationEffect(angle, anchor: .bottom)
            .offset(y: -length / 2.0)
    }
}

private struct WidgetWeaverClockSecondHandView: View {
    let palette: WidgetWeaverClockPalette
    let width: CGFloat
    let length: CGFloat
    let angleDegrees: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.60, style: .continuous)
                .fill(palette.accent.opacity(0.92))
                .frame(width: width, height: length)
                .shadow(color: palette.accent.opacity(0.55), radius: width * 2.5, x: 0, y: 0)
                .shadow(color: palette.accent.opacity(0.20), radius: width * 6.0, x: 0, y: 0)
                .offset(y: -length / 2.0)

            RoundedRectangle(cornerRadius: width * 1.2, style: .continuous)
                .fill(palette.accent)
                .frame(width: width * 2.4, height: width * 2.4)
                .shadow(color: palette.accent.opacity(0.85), radius: width * 2.0, x: 0, y: 0)
                .offset(y: -length)
        }
        .rotationEffect(.degrees(angleDegrees))
    }
}

// MARK: - Colour helper

private func wwColor(_ hex: UInt32, _ alpha: Double = 1.0) -> Color {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
}

private struct WidgetWeaverPerSecondInvalidator: View {
    private let start: Date

    init(startDate: Date) {
        self.start = Date(timeIntervalSinceReferenceDate: floor(startDate.timeIntervalSinceReferenceDate))
    }

    var body: some View {
        Text(start, style: .timer)
            .font(.system(size: 1, weight: .regular, design: .default))
            .opacity(0.01)
            .frame(width: 1, height: 1)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func wwWidgetContainerBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { background() }
        } else {
            self.background(background())
        }
    }
}

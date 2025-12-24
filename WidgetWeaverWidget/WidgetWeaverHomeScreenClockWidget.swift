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
        let now = Date()
        let scheme = configuration.colourScheme ?? .classic

        // One timeline entry per second.
        //
        // WidgetKit displays each entry at its date, allowing the second hand to advance
        // without relying on in-view timers.
        let start = Date(timeIntervalSinceReferenceDate: floor(now.timeIntervalSinceReferenceDate))

        let horizonSeconds: Int = 180
        var entries: [Entry] = []
        entries.reserveCapacity(horizonSeconds)

        for i in 0..<horizonSeconds {
            let date = start.addingTimeInterval(TimeInterval(i))
            entries.append(Entry(date: date, colourScheme: scheme))
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

        WidgetWeaverClockIconView(date: entry.date, palette: palette)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                WidgetWeaverClockBackgroundView(palette: palette)
            }
            .id(entry.colourScheme.rawValue)
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
                return isDark ? wwColor(0x7EFCD8) : wwColor(0x43E0C2)
            case .orchid:
                return isDark ? wwColor(0xC9A0FF) : wwColor(0xB684FF)
            case .sunset:
                return isDark ? wwColor(0xFF9B6B) : wwColor(0xFF7C4D)
            case .ember:
                return isDark ? wwColor(0xFF5E5E) : wwColor(0xFF3B3B)
            case .graphite:
                return isDark ? wwColor(0xB8BBC0) : wwColor(0x8A8D92)
            }
        }()

        if isDark {
            return WidgetWeaverClockPalette(
                accent: accent,

                backgroundTop: wwColor(0x2D2E34),
                backgroundBottom: wwColor(0x050609),

                bezelHighlight: wwColor(0xE5E6E9),
                bezelMid: wwColor(0xC9CBD1),
                bezelShadow: wwColor(0x6A6D75),

                faceTop: wwColor(0x2A2C31),
                faceBottom: wwColor(0x0A0C11),

                numerals: wwColor(0xD9DADE),
                numeralsShadow: wwColor(0x000000, 0.55),

                minuteDot: wwColor(0x9EA1A7, 0.85),

                tickTop: wwColor(0xF6F7F8),
                tickBottom: wwColor(0xC9CBD0),
                tickShadow: wwColor(0x000000, 0.55),

                hourHandTop: wwColor(0xFFFFFF),
                hourHandBottom: wwColor(0xC9CBD0),
                minuteHandTop: wwColor(0xFFFFFF),
                minuteHandBottom: wwColor(0xD0D2D6),
                handShadow: wwColor(0x000000, 0.45),

                hubOuter: wwColor(0xD6D8DC),
                hubInner: wwColor(0x8E9196),
                hubShadow: wwColor(0x000000, 0.35),

                rimInnerShadow: wwColor(0x000000, 0.35)
            )
        } else {
            return WidgetWeaverClockPalette(
                accent: accent,

                backgroundTop: wwColor(0xF4F4F3),
                backgroundBottom: wwColor(0xD8D8D7),

                bezelHighlight: wwColor(0xFFFFFF),
                bezelMid: wwColor(0xE1E2E3),
                bezelShadow: wwColor(0xA6A8AC),

                faceTop: wwColor(0xF9F8F5),
                faceBottom: wwColor(0xECECE9),

                numerals: wwColor(0xA5AAAF),
                numeralsShadow: wwColor(0x000000, 0.14),

                minuteDot: wwColor(0xB6B9BE, 0.75),

                tickTop: wwColor(0xFFFFFF),
                tickBottom: wwColor(0xD3D5D9),
                tickShadow: wwColor(0x000000, 0.18),

                hourHandTop: wwColor(0xFFFFFF),
                hourHandBottom: wwColor(0xD6D8DC),
                minuteHandTop: wwColor(0xFFFFFF),
                minuteHandBottom: wwColor(0xD6D8DC),
                handShadow: wwColor(0x000000, 0.18),

                hubOuter: wwColor(0xD6D8DC),
                hubInner: wwColor(0xB5B8BD),
                hubShadow: wwColor(0x000000, 0.18),

                rimInnerShadow: wwColor(0x000000, 0.12)
            )
        }
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
                                    Color.black.opacity(0.22),
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
                                .init(color: palette.bezelShadow, location: 1.0),
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
                                .init(color: palette.faceBottom, location: 1.0),
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

// MARK: - Markers & Numerals

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
                    .opacity(i % 5 == 0 ? 0.35 : 1.0)
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
                if i == 0 || i == 3 || i == 6 || i == 9 {
                    EmptyView()
                } else {
                    RoundedRectangle(cornerRadius: tickWidth * 0.35, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [palette.tickTop, palette.tickBottom]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: tickWidth, height: tickLength)
                        .overlay(
                            RoundedRectangle(cornerRadius: tickWidth * 0.35, style: .continuous)
                                .stroke(Color.black.opacity(0.10), lineWidth: max(1, tickWidth * 0.08))
                        )
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: tickWidth * 0.35, style: .continuous)
                                .fill(palette.accent)
                                .frame(width: tickWidth, height: max(1, tickLength * 0.12))
                                .shadow(color: palette.accent.opacity(0.85), radius: tickWidth * 1.9, x: 0, y: 0)
                                .opacity(0.85)
                                .padding(.top, max(1, tickLength * 0.05))
                                .blendMode(.screen)
                        }
                        .shadow(color: palette.tickShadow, radius: tickWidth * 0.70, x: 0, y: tickWidth * 0.35)
                        .offset(y: -radius)
                        .rotationEffect(.degrees((Double(i) / 12.0) * 360.0))
                }
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

    @State private var displayedSecondAngleDegrees: Double = 0
    @State private var hasInitialisedSecond = false

    var body: some View {
        let angles = WidgetWeaverClockAngles(date: date)

        ZStack {
            WidgetWeaverClockHourHandView(
                palette: palette,
                width: innerRadius * 0.30,
                length: innerRadius * 0.56,
                angle: angles.hour
            )

            WidgetWeaverClockMinuteHandView(
                palette: palette,
                width: innerRadius * 0.13,
                length: innerRadius * 0.86,
                angle: angles.minute
            )

            WidgetWeaverClockSecondHandView(
                palette: palette,
                width: max(1, innerRadius * 0.012),
                length: innerRadius * 0.92,
                angleDegrees: displayedSecondAngleDegrees
            )
        }
        .onAppear {
            setSecondAngle(date: date, animated: false)
            hasInitialisedSecond = true
        }
        .onChange(of: Int(date.timeIntervalSinceReferenceDate)) { _, _ in
            if hasInitialisedSecond {
                setSecondAngle(date: date, animated: true)
            } else {
                setSecondAngle(date: date, animated: false)
                hasInitialisedSecond = true
            }
        }
    }

    private func setSecondAngle(date: Date, animated: Bool) {
        let tickSeconds = floor(date.timeIntervalSinceReferenceDate)
        let target = tickSeconds * 6.0

        let delta = abs(target - displayedSecondAngleDegrees)

        // Only animate the normal 1-second step.
        // Any missed ticks snap to the correct time, then resume 1-second ticks.
        let shouldAnimate = animated && (delta <= 6.1)

        if shouldAnimate {
            withAnimation(.linear(duration: 0.16)) {
                displayedSecondAngleDegrees = target
            }
        } else {
            displayedSecondAngleDegrees = target
        }
    }
}

private struct WidgetWeaverClockAngles {
    let hour: Angle
    let minute: Angle

    init(date: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: date)

        let h = Double((comps.hour ?? 0) % 12)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0)

        let hourValue = h + (m / 60.0) + (s / 3600.0)
        let minuteValue = m + (s / 60.0)

        self.hour = .degrees((hourValue / 12.0) * 360.0)
        self.minute = .degrees((minuteValue / 60.0) * 360.0)
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

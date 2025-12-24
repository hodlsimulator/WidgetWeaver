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

// MARK: - Timeline tuning

private enum WWClockTimelineTuning {
    // WidgetKit aggressively budgets timeline refresh.
    static let widgetKitRefreshAfter: TimeInterval = 60 * 60 * 6 // 6 hours
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
        let now = Date()

        let entry = Entry(date: now, colourScheme: scheme)
        let nextRefresh = now.addingTimeInterval(WWClockTimelineTuning.widgetKitRefreshAfter)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
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

        ZStack {
            WidgetWeaverClockIconView(entryDate: entry.date, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
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
    let bezelInnerShadow: Color

    let separatorRing: Color

    let dialCenter: Color
    let dialMid: Color
    let dialEdge: Color
    let dialVignette: Color
    let dialDomeHighlight: Color

    let minuteDot: Color

    let indexHighlight: Color
    let indexMid: Color
    let indexShadow: Color

    let numeralMetalLight: Color
    let numeralMetalMid: Color
    let numeralMetalDark: Color
    let numeralHighlight: Color
    let numeralShadow: Color

    let handMetalLight: Color
    let handMetalMid: Color
    let handMetalDark: Color
    let handEdgeStroke: Color
    let handShadow: Color

    let hubBase: Color
    let hubCapLight: Color
    let hubCapMid: Color
    let hubCapDark: Color
    let hubShadow: Color

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
                return isDark ? wwColor(0xB7C3D6) : wwColor(0x90A0B8)
            }
        }()

        let backgroundTop: Color = isDark ? wwColor(0x141A22) : wwColor(0xECF1F8)
        let backgroundBottom: Color = isDark ? wwColor(0x0B0F15) : wwColor(0xC7D2E5)

        // Silver metallic bezel.
        let bezelHighlight: Color = wwColor(0xF6FAFF, isDark ? 0.92 : 0.90)
        let bezelMid: Color = wwColor(0xB8C4D6, isDark ? 0.88 : 0.92)
        let bezelShadow: Color = wwColor(0x5B6677, isDark ? 0.92 : 0.88)
        let bezelInnerShadow: Color = wwColor(0x000000, isDark ? 0.55 : 0.25)

        // Near-black separator, slightly lighter than the dial’s darkest tone.
        let separatorRing: Color = wwColor(0x0E1218, isDark ? 1.0 : 1.0)

        // Dark graphite dial.
        let dialCenter: Color = wwColor(0x1A222E)
        let dialMid: Color = wwColor(0x10161F)
        let dialEdge: Color = wwColor(0x07090C)
        let dialVignette: Color = wwColor(0x000000, 0.30)
        let dialDomeHighlight: Color = wwColor(0xFFFFFF, 0.06)

        let minuteDot: Color = wwColor(0xB7C3D6, 0.38)

        let indexHighlight: Color = wwColor(0xF2F6FB, 0.92)
        let indexMid: Color = wwColor(0xC4D0E0, 0.86)
        let indexShadow: Color = wwColor(0x6B7A92, 0.92)

        let numeralMetalLight: Color = wwColor(0xE7EFF9, 0.86)
        let numeralMetalMid: Color = wwColor(0xB8C4D6, 0.84)
        let numeralMetalDark: Color = wwColor(0x7D8CA3, 0.86)
        let numeralHighlight: Color = wwColor(0xFFFFFF, 0.26)
        let numeralShadow: Color = wwColor(0x000000, 0.55)

        let handMetalLight: Color = wwColor(0xE2EAF4, 0.90)
        let handMetalMid: Color = wwColor(0xB2BED0, 0.86)
        let handMetalDark: Color = wwColor(0x5F6E86, 0.92)
        let handEdgeStroke: Color = wwColor(0x000000, 0.22)
        let handShadow: Color = wwColor(0x000000, isDark ? 0.52 : 0.28)

        let hubBase: Color = wwColor(0x121A24, 1.0)
        let hubCapLight: Color = wwColor(0xF4F8FF, 0.92)
        let hubCapMid: Color = wwColor(0xB9C5D6, 0.86)
        let hubCapDark: Color = wwColor(0x5C697D, 0.92)
        let hubShadow: Color = wwColor(0x000000, isDark ? 0.60 : 0.30)

        return WidgetWeaverClockPalette(
            accent: accent,
            backgroundTop: backgroundTop,
            backgroundBottom: backgroundBottom,
            bezelHighlight: bezelHighlight,
            bezelMid: bezelMid,
            bezelShadow: bezelShadow,
            bezelInnerShadow: bezelInnerShadow,
            separatorRing: separatorRing,
            dialCenter: dialCenter,
            dialMid: dialMid,
            dialEdge: dialEdge,
            dialVignette: dialVignette,
            dialDomeHighlight: dialDomeHighlight,
            minuteDot: minuteDot,
            indexHighlight: indexHighlight,
            indexMid: indexMid,
            indexShadow: indexShadow,
            numeralMetalLight: numeralMetalLight,
            numeralMetalMid: numeralMetalMid,
            numeralMetalDark: numeralMetalDark,
            numeralHighlight: numeralHighlight,
            numeralShadow: numeralShadow,
            handMetalLight: handMetalLight,
            handMetalMid: handMetalMid,
            handMetalDark: handMetalDark,
            handEdgeStroke: handEdgeStroke,
            handShadow: handShadow,
            hubBase: hubBase,
            hubCapLight: hubCapLight,
            hubCapMid: hubCapMid,
            hubCapDark: hubCapDark,
            hubShadow: hubShadow
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
    let entryDate: Date
    let palette: WidgetWeaverClockPalette

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            // Coordinate system: centre C, radius R (outer edge of the dial bezel).
            let outerDiameter = s * 0.925
            let R = outerDiameter * 0.5

            let bezelWidth = wwPixel(wwClamp(R * 0.062, min: R * 0.055, max: R * 0.070), scale: displayScale)
            let separatorWidth = wwPixel(wwClamp(R * 0.012, min: R * 0.010, max: R * 0.015), scale: displayScale)

            let dialRadius = R - bezelWidth - separatorWidth
            let dialDiameter = dialRadius * 2.0

            let minuteDotRadius = wwPixel(wwClamp(R * 0.918, min: R * 0.905, max: R * 0.930), scale: displayScale)
            let minuteDotDiameter = wwPixel(wwClamp(R * 0.010, min: R * 0.008, max: R * 0.012), scale: displayScale)

            let markerCenterRadius = wwPixel(wwClamp(R * 0.80, min: R * 0.78, max: R * 0.82), scale: displayScale)
            let markerLength = wwPixel(wwClamp(R * 0.12, min: R * 0.10, max: R * 0.14), scale: displayScale)
            let markerWidth = wwPixel(wwClamp(R * 0.026, min: R * 0.020, max: R * 0.030), scale: displayScale)
            let capLength = wwPixel(wwClamp(R * 0.025, min: R * 0.020, max: R * 0.030), scale: displayScale)

            let pipSide = wwPixel(wwClamp(R * 0.015, min: R * 0.012, max: R * 0.018), scale: displayScale)
            let pipRadius = wwPixel(R * 0.904, scale: displayScale)

            let numeralsRadius = wwPixel(R * 0.60, scale: displayScale)
            let numeralsFontSize = wwPixel(R * 0.32, scale: displayScale)

            // Fixed target pose.
            let hourAngle = Angle.degrees(310.0)   // ~10:20
            let minuteAngle = Angle.degrees(120.0) // 20 minutes
            let secondAngleDegrees = 180.0         // 30 seconds

            let hourHandLength = wwPixel(wwClamp(R * 0.45, min: R * 0.42, max: R * 0.48), scale: displayScale)
            let hourHandBaseWidth = wwPixel(wwClamp(R * 0.15, min: R * 0.12, max: R * 0.18), scale: displayScale)

            let minuteHandLength = wwPixel(wwClamp(R * 0.82, min: R * 0.78, max: R * 0.84), scale: displayScale)
            let minuteHandWidth = wwPixel(wwClamp(R * 0.028, min: R * 0.020, max: R * 0.035), scale: displayScale)

            let secondHandLength = wwPixel(wwClamp(R * 0.90, min: R * 0.84, max: R * 0.92), scale: displayScale)
            let secondHandWidth = wwPixel(wwClamp(R * 0.006, min: R * 0.004, max: R * 0.008), scale: displayScale)
            let secondTipSide = wwPixel(wwClamp(R * 0.013, min: R * 0.010, max: R * 0.016), scale: displayScale)

            let hubBaseRadius = wwPixel(wwClamp(R * 0.043, min: R * 0.035, max: R * 0.050), scale: displayScale)
            let hubCapRadius = wwPixel(wwClamp(R * 0.025, min: R * 0.020, max: R * 0.030), scale: displayScale)

            ZStack {
                // Dial shading (base)
                WidgetWeaverClockDialFaceView(
                    palette: palette,
                    radius: dialRadius
                )
                .frame(width: dialDiameter, height: dialDiameter)

                // Bezel + separator rings
                WidgetWeaverClockBezelView(
                    palette: palette,
                    outerDiameter: outerDiameter,
                    bezelWidth: bezelWidth,
                    separatorWidth: separatorWidth,
                    dialDiameter: dialDiameter
                )

                // Minute dots
                WidgetWeaverClockMinuteDotsView(
                    count: 60,
                    dotColor: palette.minuteDot,
                    dotDiameter: minuteDotDiameter,
                    radius: minuteDotRadius
                )

                // Hour indices + their caps (no glow here)
                WidgetWeaverClockHourIndicesView(
                    palette: palette,
                    capColor: palette.accent,
                    markerCenterRadius: markerCenterRadius,
                    markerLength: markerLength,
                    markerWidth: markerWidth,
                    capLength: capLength
                )

                // Cardinal luminous pips (no glow here)
                WidgetWeaverClockCardinalPipsView(
                    pipColor: palette.accent,
                    side: pipSide,
                    radius: pipRadius
                )

                // Numerals
                WidgetWeaverClockNumeralsView(
                    palette: palette,
                    fontSize: numeralsFontSize,
                    radius: numeralsRadius
                )

                // Hand shadows
                WidgetWeaverClockHandShadowsView(
                    palette: palette,
                    hourAngle: hourAngle,
                    minuteAngle: minuteAngle,
                    hourWidth: hourHandBaseWidth,
                    hourLength: hourHandLength,
                    minuteWidth: minuteHandWidth,
                    minuteLength: minuteHandLength
                )

                // Hands
                WidgetWeaverClockHandsForegroundView(
                    palette: palette,
                    hourAngle: hourAngle,
                    minuteAngle: minuteAngle,
                    secondAngleDegrees: secondAngleDegrees,
                    hourWidth: hourHandBaseWidth,
                    hourLength: hourHandLength,
                    minuteWidth: minuteHandWidth,
                    minuteLength: minuteHandLength,
                    secondWidth: secondHandWidth,
                    secondLength: secondHandLength,
                    secondTipSide: secondTipSide
                )

                // Centre hub (base + metallic cap)
                WidgetWeaverClockCentreHubView(
                    palette: palette,
                    baseRadius: hubBaseRadius,
                    capRadius: hubCapRadius
                )

                // Blue glows (local overlays only)
                WidgetWeaverClockGlowsOverlayView(
                    glowColor: palette.accent,
                    markerCenterRadius: markerCenterRadius,
                    markerLength: markerLength,
                    markerWidth: markerWidth,
                    capLength: capLength,
                    pipSide: pipSide,
                    pipRadius: pipRadius,
                    minuteAngle: minuteAngle,
                    minuteWidth: minuteHandWidth,
                    minuteLength: minuteHandLength,
                    secondAngleDegrees: secondAngleDegrees,
                    secondWidth: secondHandWidth,
                    secondLength: secondHandLength,
                    secondTipSide: secondTipSide,
                    hubCutoutRadius: hubBaseRadius + hubCapRadius * 0.20
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Dial face

private struct WidgetWeaverClockDialFaceView: View {
    let palette: WidgetWeaverClockPalette
    let radius: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.dialCenter, location: 0.0),
                        .init(color: palette.dialMid, location: 0.58),
                        .init(color: palette.dialEdge, location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.03), location: 0.0),
                                .init(color: Color.clear, location: 0.50),
                                .init(color: palette.dialVignette, location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            )
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialDomeHighlight, location: 0.0),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: radius * 1.15
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: Color.clear, location: 0.40),
                                .init(color: wwColor(0x000000, 0.20), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.multiply)
            )
    }
}

// MARK: - Bezel

private struct WidgetWeaverClockBezelView: View {
    let palette: WidgetWeaverClockPalette
    let outerDiameter: CGFloat
    let bezelWidth: CGFloat
    let separatorWidth: CGFloat
    let dialDiameter: CGFloat

    var body: some View {
        ZStack {
            // Metallic ring.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelShadow, location: 0.00),
                            .init(color: palette.bezelMid, location: 0.18),
                            .init(color: palette.bezelHighlight, location: 0.32),
                            .init(color: palette.bezelMid, location: 0.60),
                            .init(color: palette.bezelShadow, location: 1.00)
                        ]),
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    ),
                    lineWidth: bezelWidth
                )
                .frame(width: outerDiameter, height: outerDiameter)

            // Angle-dependent highlight/shadow bias.
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelHighlight.opacity(0.55), location: 0.00),
                            .init(color: palette.bezelHighlight.opacity(0.00), location: 0.14),
                            .init(color: palette.bezelShadow.opacity(0.00), location: 0.62),
                            .init(color: palette.bezelShadow.opacity(0.45), location: 0.80),
                            .init(color: palette.bezelHighlight.opacity(0.55), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-45)
                    ),
                    lineWidth: bezelWidth
                )
                .frame(width: outerDiameter, height: outerDiameter)
                .blendMode(.overlay)

            // Thin dark separator ring immediately inside the bezel.
            Circle()
                .strokeBorder(palette.separatorRing, lineWidth: separatorWidth)
                .frame(width: outerDiameter - (bezelWidth * 2.0), height: outerDiameter - (bezelWidth * 2.0))

            // Subtle inner shadow at the bezel’s inner edge, offset toward lower-right.
            Circle()
                .stroke(palette.bezelInnerShadow, lineWidth: separatorWidth * 2.4)
                .frame(width: dialDiameter + (separatorWidth * 2.4), height: dialDiameter + (separatorWidth * 2.4))
                .blur(radius: separatorWidth * 0.70)
                .offset(x: separatorWidth * 0.55, y: separatorWidth * 0.55)
                .mask(
                    Circle()
                        .frame(width: dialDiameter, height: dialDiameter)
                )
        }
    }
}

// MARK: - Minute dots

private struct WidgetWeaverClockMinuteDotsView: View {
    let count: Int
    let dotColor: Color
    let dotDiameter: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(dotColor)
                    .frame(width: dotDiameter, height: dotDiameter)
                    .offset(y: -radius)
                    .rotationEffect(.degrees((Double(i) / Double(count)) * 360.0))
            }
        }
    }
}

// MARK: - Hour indices

private struct WidgetWeaverClockHourIndicesView: View {
    let palette: WidgetWeaverClockPalette
    let capColor: Color

    let markerCenterRadius: CGFloat
    let markerLength: CGFloat
    let markerWidth: CGFloat
    let capLength: CGFloat

    private let hourIndices: [Int] = [1, 2, 4, 5, 7, 8, 10, 11]

    var body: some View {
        ZStack {
            ForEach(hourIndices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                // Metallic baton.
                WidgetWeaverClockBatonView(
                    palette: palette,
                    width: markerWidth,
                    length: markerLength
                )
                .offset(y: -markerCenterRadius)
                .rotationEffect(.degrees(degrees))

                // Luminous cap (base only, glow is in the overlay layer).
                Rectangle()
                    .fill(capColor)
                    .frame(width: markerWidth, height: capLength)
                    .offset(y: -(markerCenterRadius + (markerLength * 0.5) - (capLength * 0.5)))
                    .rotationEffect(.degrees(degrees))
            }
        }
    }
}

private struct WidgetWeaverClockBatonView: View {
    let palette: WidgetWeaverClockPalette
    let width: CGFloat
    let length: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)

        shape
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.indexHighlight, location: 0.0),
                        .init(color: palette.indexMid, location: 0.55),
                        .init(color: palette.indexShadow, location: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.indexShadow.opacity(0.16), location: 0.0),
                                .init(color: Color.white.opacity(0.28), location: 0.50),
                                .init(color: palette.indexShadow.opacity(0.18), location: 1.0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(width * 0.14)
                    .mask(shape)
            )
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.42), location: 0.0),
                                .init(color: Color.clear, location: 0.55),
                                .init(color: Color.black.opacity(0.45), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1, width * 0.08)
                    )
            )
            .frame(width: width, height: length)
    }
}

// MARK: - Cardinal pips

private struct WidgetWeaverClockCardinalPipsView: View {
    let pipColor: Color
    let side: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach([3, 6, 9], id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                Rectangle()
                    .fill(pipColor)
                    .frame(width: side, height: side)
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
            WidgetWeaverEmbossedNumeral(
                text: "12",
                palette: palette,
                fontSize: fontSize
            )
            .offset(x: 0, y: -radius)

            WidgetWeaverEmbossedNumeral(
                text: "3",
                palette: palette,
                fontSize: fontSize
            )
            .offset(x: radius, y: 0)

            WidgetWeaverEmbossedNumeral(
                text: "6",
                palette: palette,
                fontSize: fontSize
            )
            .offset(x: 0, y: radius)

            WidgetWeaverEmbossedNumeral(
                text: "9",
                palette: palette,
                fontSize: fontSize
            )
            .offset(x: -radius, y: 0)
        }
    }
}

private struct WidgetWeaverEmbossedNumeral: View {
    let text: String
    let palette: WidgetWeaverClockPalette
    let fontSize: CGFloat

    var body: some View {
        let highlightOffset = max(1, fontSize * 0.018)
        let shadowOffset = max(1, fontSize * 0.020)
        let blurRadius = fontSize * 0.020

        let base = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.numeralMetalLight, location: 0.0),
                .init(color: palette.numeralMetalMid, location: 0.52),
                .init(color: palette.numeralMetalDark, location: 1.0)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        ZStack {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.numeralShadow)
                .offset(x: shadowOffset, y: shadowOffset)
                .blur(radius: blurRadius)

            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.numeralHighlight)
                .offset(x: -highlightOffset, y: -highlightOffset)
                .blur(radius: blurRadius)

            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(base)
        }
        .compositingGroup()
    }
}

// MARK: - Hands

private struct WidgetWeaverClockHandShadowsView: View {
    let palette: WidgetWeaverClockPalette

    let hourAngle: Angle
    let minuteAngle: Angle

    let hourWidth: CGFloat
    let hourLength: CGFloat

    let minuteWidth: CGFloat
    let minuteLength: CGFloat

    var body: some View {
        let shadowOffset = max(1, hourWidth * 0.06)
        let shadowBlur = max(1, hourWidth * 0.08)

        ZStack {
            WidgetWeaverClockHourWedgeShape()
                .fill(palette.handShadow.opacity(0.55))
                .frame(width: hourWidth, height: hourLength)
                .rotationEffect(hourAngle, anchor: .bottom)
                .offset(y: -hourLength / 2.0)
                .offset(x: shadowOffset, y: shadowOffset)
                .blur(radius: shadowBlur)

            WidgetWeaverClockMinuteNeedleShape()
                .fill(palette.handShadow.opacity(0.45))
                .frame(width: minuteWidth, height: minuteLength)
                .rotationEffect(minuteAngle, anchor: .bottom)
                .offset(y: -minuteLength / 2.0)
                .offset(x: shadowOffset * 0.75, y: shadowOffset * 0.75)
                .blur(radius: shadowBlur * 0.75)
        }
    }
}

private struct WidgetWeaverClockHandsForegroundView: View {
    let palette: WidgetWeaverClockPalette

    let hourAngle: Angle
    let minuteAngle: Angle
    let secondAngleDegrees: Double

    let hourWidth: CGFloat
    let hourLength: CGFloat

    let minuteWidth: CGFloat
    let minuteLength: CGFloat

    let secondWidth: CGFloat
    let secondLength: CGFloat
    let secondTipSide: CGFloat

    var body: some View {
        ZStack {
            // Hour hand (metal wedge).
            WidgetWeaverClockHourWedgeShape()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.handMetalLight, location: 0.0),
                            .init(color: palette.handMetalMid, location: 0.56),
                            .init(color: palette.handMetalDark, location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    WidgetWeaverClockHourWedgeShape()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.black.opacity(0.12), location: 0.0),
                                    .init(color: Color.white.opacity(0.32), location: 0.50),
                                    .init(color: Color.black.opacity(0.14), location: 1.0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(hourWidth * 0.10)
                        .mask(WidgetWeaverClockHourWedgeShape())
                )
                .overlay(
                    WidgetWeaverClockHourWedgeShape()
                        .stroke(palette.handEdgeStroke, lineWidth: max(1, hourWidth * 0.05))
                )
                .frame(width: hourWidth, height: hourLength)
                .rotationEffect(hourAngle, anchor: .bottom)
                .offset(y: -hourLength / 2.0)

            // Minute hand (metal needle).
            WidgetWeaverClockMinuteNeedleShape()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.handMetalLight, location: 0.0),
                            .init(color: palette.handMetalMid, location: 0.52),
                            .init(color: palette.handMetalDark, location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    WidgetWeaverClockMinuteNeedleShape()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.black.opacity(0.12), location: 0.0),
                                    .init(color: Color.white.opacity(0.30), location: 0.50),
                                    .init(color: Color.black.opacity(0.14), location: 1.0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(minuteWidth * 0.22)
                        .mask(WidgetWeaverClockMinuteNeedleShape())
                )
                .overlay(
                    WidgetWeaverClockMinuteNeedleShape()
                        .stroke(palette.handEdgeStroke, lineWidth: max(1, minuteWidth * 0.08))
                )
                .frame(width: minuteWidth, height: minuteLength)
                .rotationEffect(minuteAngle, anchor: .bottom)
                .offset(y: -minuteLength / 2.0)

            // Second hand (thin cyan line to 6 o’clock).
            WidgetWeaverClockSecondHandView(
                color: palette.accent,
                width: secondWidth,
                length: secondLength,
                angleDegrees: secondAngleDegrees,
                tipSide: secondTipSide
            )
        }
    }
}

private struct WidgetWeaverClockHourWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width

        let baseInset = w * 0.03
        let baseLeft = CGPoint(x: rect.minX + baseInset, y: rect.maxY)
        let baseRight = CGPoint(x: rect.maxX - baseInset, y: rect.maxY)

        let tip = CGPoint(x: rect.midX, y: rect.minY)

        var p = Path()
        p.move(to: baseLeft)
        p.addLine(to: tip)
        p.addLine(to: baseRight)
        p.closeSubpath()
        return p
    }
}

private struct WidgetWeaverClockMinuteNeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width

        let tipHeight = max(1, w * 0.95)
        let shaftTopY = rect.minY + tipHeight
        let shaftInset = w * 0.10

        let bottomLeft = CGPoint(x: rect.minX + shaftInset, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX - shaftInset, y: rect.maxY)

        let shaftTopLeft = CGPoint(x: rect.minX + shaftInset, y: shaftTopY)
        let shaftTopRight = CGPoint(x: rect.maxX - shaftInset, y: shaftTopY)

        let tip = CGPoint(x: rect.midX, y: rect.minY)

        var p = Path()
        p.move(to: bottomLeft)
        p.addLine(to: shaftTopLeft)
        p.addLine(to: tip)
        p.addLine(to: shaftTopRight)
        p.addLine(to: bottomRight)
        p.closeSubpath()
        return p
    }
}

private struct WidgetWeaverClockSecondHandView: View {
    let color: Color
    let width: CGFloat
    let length: CGFloat
    let angleDegrees: Double
    let tipSide: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color.opacity(0.92))
                .frame(width: width, height: length)
                .offset(y: -length / 2.0)

            Rectangle()
                .fill(color)
                .frame(width: tipSide, height: tipSide)
                .offset(y: -length)
        }
        .rotationEffect(.degrees(angleDegrees))
    }
}

// MARK: - Centre hub

private struct WidgetWeaverClockCentreHubView: View {
    let palette: WidgetWeaverClockPalette
    let baseRadius: CGFloat
    let capRadius: CGFloat

    var body: some View {
        let baseDiameter = baseRadius * 2.0
        let capDiameter = capRadius * 2.0

        ZStack {
            Circle()
                .fill(palette.hubBase)
                .frame(width: baseDiameter, height: baseDiameter)
                .shadow(color: palette.hubShadow, radius: baseRadius * 0.28, x: baseRadius * 0.12, y: baseRadius * 0.18)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.hubCapLight, location: 0.0),
                            .init(color: palette.hubCapMid, location: 0.55),
                            .init(color: palette.hubCapDark, location: 1.0)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: capRadius * 1.25
                    )
                )
                .frame(width: capDiameter, height: capDiameter)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.20), lineWidth: max(1, capRadius * 0.10))
                )
        }
    }
}

// MARK: - Glows overlay

private struct WidgetWeaverClockGlowsOverlayView: View {
    let glowColor: Color

    let markerCenterRadius: CGFloat
    let markerLength: CGFloat
    let markerWidth: CGFloat
    let capLength: CGFloat

    let pipSide: CGFloat
    let pipRadius: CGFloat

    let minuteAngle: Angle
    let minuteWidth: CGFloat
    let minuteLength: CGFloat

    let secondAngleDegrees: Double
    let secondWidth: CGFloat
    let secondLength: CGFloat
    let secondTipSide: CGFloat

    let hubCutoutRadius: CGFloat

    private let hourIndices: [Int] = [1, 2, 4, 5, 7, 8, 10, 11]

    var body: some View {
        let capGlowBlur = max(1, capLength * 0.38)
        let pipGlowBlur = max(1, pipSide * 0.55)

        let minuteGlowWidth = max(1, minuteWidth * 0.24)
        let minuteGlowBlur = max(1, minuteWidth * 0.35)

        let secondGlowBlur = max(1, secondWidth * 1.2)

        ZStack {
            // Baton cap glows.
            ForEach(hourIndices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                Rectangle()
                    .fill(glowColor.opacity(0.70))
                    .frame(width: markerWidth, height: capLength)
                    .offset(y: -(markerCenterRadius + (markerLength * 0.5) - (capLength * 0.5)))
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: capGlowBlur)
                    .blendMode(.screen)
            }

            // Cardinal pip glows.
            ForEach([3, 6, 9], id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                Rectangle()
                    .fill(glowColor.opacity(0.75))
                    .frame(width: pipSide, height: pipSide)
                    .offset(y: -pipRadius)
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: pipGlowBlur)
                    .blendMode(.screen)
            }

            // Minute-hand edge emission (one side only), intensity increases toward the tip.
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: glowColor.opacity(0.00), location: 0.0),
                            .init(color: glowColor.opacity(0.10), location: 0.55),
                            .init(color: glowColor.opacity(0.65), location: 1.0)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: minuteGlowWidth, height: minuteLength)
                .offset(x: minuteWidth * 0.50, y: 0)
                .frame(width: minuteWidth, height: minuteLength)
                .rotationEffect(minuteAngle, anchor: .bottom)
                .offset(y: -minuteLength / 2.0)
                .blur(radius: minuteGlowBlur)
                .blendMode(.screen)

            // Second-hand glow (tight).
            ZStack {
                Rectangle()
                    .fill(glowColor.opacity(0.55))
                    .frame(width: secondWidth, height: secondLength)
                    .offset(y: -secondLength / 2.0)

                Rectangle()
                    .fill(glowColor.opacity(0.75))
                    .frame(width: secondTipSide, height: secondTipSide)
                    .offset(y: -secondLength)
            }
            .rotationEffect(.degrees(secondAngleDegrees))
            .blur(radius: secondGlowBlur)
            .blendMode(.screen)

            // Cut out the hub region so glows do not paint over the centre cap.
            Circle()
                .fill(Color.black)
                .frame(width: hubCutoutRadius * 2.0, height: hubCutoutRadius * 2.0)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

// MARK: - Helpers

private func wwClamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, min), max)
}

private func wwPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
    guard scale > 0 else { return value }
    return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
}

private func wwColor(_ hex: UInt32, _ alpha: Double = 1.0) -> Color {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
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

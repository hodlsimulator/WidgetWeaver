//
//  WidgetWeaverClockSegmentedFaceView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

private enum WWClockSegmentedFaceConstants {
    static let segmentIndices: [Int] = Array(0..<12)
}

/// Clock face renderer for Face = "segmented".
///
/// Step 2 scaffold:
/// - Uses a dedicated view so routing and geometry are stable.
/// - Renders bezel + dial placeholders.
///
/// Step 3:
/// - Adds the segmented outer ring geometry (12 sectors).
///
/// Step 4:
/// - Adds segment material shading (bevel + highlights + separation).
///
/// Step 5:
/// - Adds embossed, upright numerals on the segment ring.
///
/// Step 6:
/// - Adds inner tick marks with quarter/five/minute hierarchy.
///
/// Step 7:
/// - Adds Segmented-specific hands (bar-like hour/minute + yellow seconds).
///
/// Segmented-specific centre hub is implemented in later steps.
struct WidgetWeaverClockSegmentedFaceView: View {
    let palette: WidgetWeaverClockPalette

    let hourAngle: Angle
    let minuteAngle: Angle
    let secondAngle: Angle

    let showsSecondHand: Bool
    let showsMinuteHand: Bool
    let showsHandShadows: Bool
    let showsGlows: Bool
    let showsCentreHub: Bool

    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    init(
        palette: WidgetWeaverClockPalette,
        hourAngle: Angle = .degrees(310.0),
        minuteAngle: Angle = .degrees(120.0),
        secondAngle: Angle = .degrees(180.0),
        showsSecondHand: Bool = true,
        showsMinuteHand: Bool = true,
        showsHandShadows: Bool = true,
        showsGlows: Bool = true,
        showsCentreHub: Bool = true,
        handsOpacity: Double = 1.0
    ) {
        self.palette = palette
        self.hourAngle = hourAngle
        self.minuteAngle = minuteAngle
        self.secondAngle = secondAngle
        self.showsSecondHand = showsSecondHand
        self.showsMinuteHand = showsMinuteHand
        self.showsHandShadows = showsHandShadows
        self.showsGlows = showsGlows
        self.showsCentreHub = showsCentreHub
        self.handsOpacity = handsOpacity
    }

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = WWClock.outerBezelDiameter(containerSide: s, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            // Mirror existing face geometry conventions so widget sizes remain stable.
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

            // Hand sizes tuned for the Segmented face geometry.
            let hourLength = WWClock.pixel(
                WWClock.clamp(R * 0.52, min: R * 0.48, max: R * 0.56),
                scale: displayScale
            )
            let hourWidth = WWClock.pixel(
                WWClock.clamp(R * 0.18, min: R * 0.16, max: R * 0.20),
                scale: displayScale
            )

            let minuteLength = WWClock.pixel(
                WWClock.clamp(R * 0.78, min: R * 0.74, max: R * 0.82),
                scale: displayScale
            )
            let minuteWidth = WWClock.pixel(
                WWClock.clamp(R * 0.060, min: R * 0.052, max: R * 0.068),
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

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.040),
                scale: displayScale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: displayScale
            )

            ZStack {
                ZStack {
                    // Dark dial base (placeholder).
                    WidgetWeaverClockDialFaceView(
                        palette: palette,
                        radius: R,
                        occlusionWidth: occlusionWidth
                    )

                    // Segmented outer ring sectors (Steps 3–5).
                    WidgetWeaverClockSegmentedOuterRingSectorsView(
                        palette: palette,
                        dialRadius: R,
                        scale: displayScale
                    )

                    // Segmented inner tick marks (Step 6).
                    WidgetWeaverClockSegmentedTickMarksView(
                        palette: palette,
                        dialRadius: R,
                        scale: displayScale
                    )

                    ZStack {
                        let usedSecondLength = showsSecondHand ? secondLength : 0.0
                        let usedSecondWidth = showsSecondHand ? secondWidth : 0.0
                        let usedMinuteLength = showsMinuteHand ? minuteLength : 0.0
                        let usedMinuteWidth = showsMinuteHand ? minuteWidth : 0.0

                        if showsHandShadows {
                            WidgetWeaverClockSegmentedHandShadowsView(
                                palette: palette,
                                dialDiameter: dialDiameter,
                                hourAngle: hourAngle,
                                minuteAngle: minuteAngle,
                                hourLength: hourLength,
                                hourWidth: hourWidth,
                                minuteLength: usedMinuteLength,
                                minuteWidth: usedMinuteWidth,
                                scale: displayScale
                            )
                        }

                        WidgetWeaverClockSegmentedHandsView(
                            palette: palette,
                            dialDiameter: dialDiameter,
                            hourAngle: hourAngle,
                            minuteAngle: minuteAngle,
                            secondAngle: secondAngle,
                            hourLength: hourLength,
                            hourWidth: hourWidth,
                            minuteLength: usedMinuteLength,
                            minuteWidth: usedMinuteWidth,
                            secondLength: usedSecondLength,
                            secondWidth: usedSecondWidth,
                            scale: displayScale
                        )

                        if showsCentreHub {
                            WidgetWeaverClockCentreHubView(
                                palette: palette,
                                baseRadius: hubBaseRadius,
                                capRadius: hubCapRadius,
                                scale: displayScale
                            )
                        }
                    }
                    .opacity(handsOpacity)
                }
                .frame(width: dialDiameter, height: dialDiameter)
                .clipShape(Circle())

                // Dark bezel + inner separator ring (placeholder).
                WidgetWeaverClockSegmentedBezelPlaceholderView(
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

private struct WidgetWeaverClockSegmentedOuterRingSectorsView: View {
    let palette: WidgetWeaverClockPalette
    let dialRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Layout tuned to the mock: outer inset, thickness, and gap are expressed in pixels to remain stable
        // at 60pt / 44pt widget sizes.
        let outerInset = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.010, min: px, max: dialRadius * 0.018),
            scale: scale
        )

        let outerR = WWClock.pixel(max(px, dialRadius - outerInset), scale: scale)

        let targetThickness = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.185, min: px * 6.0, max: dialRadius * 0.205),
            scale: scale
        )

        let innerR = WWClock.pixel(max(px, outerR - targetThickness), scale: scale)
        let thickness = max(px, outerR - innerR)

        // Linear gap size converted to an angular gap at the mid radius.
        let linearGap = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.012, min: px * 1.4, max: dialRadius * 0.020),
            scale: scale
        )

        let midR = max(px, (outerR + innerR) * 0.5)
        let angularGapRadians = max(0.0, linearGap / midR)
        let angularGap = Angle.radians(Double(angularGapRadians))

        let baseRingThickness = WWClock.pixel(max(px, thickness + (px * 1.0)), scale: scale)

        // Base ring under segments so separators read as crisp black.
        Circle()
            .fill(Color.black.opacity(0.88))
            .frame(width: outerR * 2.0, height: outerR * 2.0)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.92), lineWidth: baseRingThickness)
                    .frame(width: (outerR + innerR) * 2.0, height: (outerR + innerR) * 2.0)
            )
            .accessibilityHidden(true)

        ZStack {
            SwiftUI.ForEach(WWClockSegmentedFaceConstants.segmentIndices, id: \.self) { (idx: Int) in
                let startDeg = Double(idx) * 30.0
                let endDeg = startDeg + 30.0

                // Segment body material.
                let bodyFill = LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: WWClock.colour(0x3A3A21).opacity(0.98), location: 0.00),
                        .init(color: WWClock.colour(0x2A2B18).opacity(0.96), location: 0.55),
                        .init(color: WWClock.colour(0x16170E).opacity(0.98), location: 1.00)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                let bevelOverlay = LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.22), location: 0.00),
                        .init(color: Color.white.opacity(0.00), location: 0.35),
                        .init(color: Color.black.opacity(0.28), location: 1.00)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                let specularOverlay = LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.22), location: 0.00),
                        .init(color: Color.white.opacity(0.00), location: 0.50),
                        .init(color: Color.black.opacity(0.20), location: 1.00)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                let liftShadowRadius = WWClock.pixel(max(px, thickness * 0.10), scale: scale)
                let liftShadowY = WWClock.pixel(max(0.0, thickness * 0.08), scale: scale)

                let edgeHighlightWidth = WWClock.pixel(max(px, thickness * 0.065), scale: scale)
                let edgeShadowWidth = WWClock.pixel(max(px, thickness * 0.065), scale: scale)

                let innerEdgeShadow = LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.black.opacity(0.45), location: 0.00),
                        .init(color: Color.black.opacity(0.00), location: 1.00)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )

                let outerEdgeHighlight = LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.28), location: 0.00),
                        .init(color: Color.white.opacity(0.00), location: 1.00)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                let sector = WWClockAnnularSectorShape(
                    innerRadius: innerR,
                    outerRadius: outerR,
                    startAngle: .degrees(startDeg),
                    endAngle: .degrees(endDeg),
                    angularGap: angularGap
                )

                sector
                    .fill(bodyFill)
                    .overlay(
                        sector
                            .fill(bevelOverlay)
                            .blendMode(.overlay)
                            .opacity(0.90)
                    )
                    .overlay(
                        sector
                            .fill(specularOverlay)
                            .blendMode(.screen)
                            .opacity(0.22)
                    )
                    .overlay(
                        sector
                            .stroke(Color.black.opacity(0.55), lineWidth: px)
                            .blendMode(.multiply)
                            .opacity(0.90)
                    )
                    .overlay(
                        // Inner edge shadow (towards dial).
                        sector
                            .stroke(innerEdgeShadow, lineWidth: edgeShadowWidth)
                            .opacity(0.88)
                    )
                    .overlay(
                        // Outer edge highlight (towards bezel).
                        sector
                            .stroke(outerEdgeHighlight, lineWidth: edgeHighlightWidth)
                            .opacity(0.82)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: liftShadowRadius, x: 0, y: liftShadowY)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: dialRadius * 2.0, height: dialRadius * 2.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay(
            // Numerals on the segments (Step 5).
            WidgetWeaverClockSegmentedNumeralsOnRingView(
                dialRadius: dialRadius,
                innerRadius: innerR,
                thickness: thickness,
                scale: scale
            )
        )
    }
}

private struct WidgetWeaverClockSegmentedNumeralsOnRingView: View {
    let dialRadius: CGFloat
    let innerRadius: CGFloat
    let thickness: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Place numerals biased towards the segment's outer edge.
        let placement = WWClock.pixel(
            WWClock.clamp(thickness * 0.64, min: thickness * 0.58, max: thickness * 0.70),
            scale: scale
        )

        let r = WWClock.pixel(innerRadius + placement, scale: scale)

        let fontSizeBase = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.18, min: dialRadius * 0.16, max: dialRadius * 0.20),
            scale: scale
        )

        ZStack {
            SwiftUI.ForEach(WWClockSegmentedFaceConstants.segmentIndices, id: \.self) { (idx: Int) in
                let numeral = idx == 0 ? 12 : idx
                let angle = Angle.degrees(Double(idx) * 30.0)

                // Optical nudges for better perceived centring.
                let xNudge: CGFloat = {
                    switch numeral {
                    case 12: return -px * 0.6
                    case 10: return -px * 0.3
                    case 11: return -px * 0.2
                    default: return 0.0
                    }
                }()

                let yNudge: CGFloat = {
                    switch numeral {
                    case 12: return -px * 0.2
                    default: return 0.0
                    }
                }()

                WidgetWeaverClockSegmentedNumeralGlyphView(
                    text: String(numeral),
                    fontSize: fontSizeBase,
                    scale: scale
                )
                .frame(width: fontSizeBase * 1.20, height: fontSizeBase * 1.10)
                .offset(x: xNudge, y: yNudge)
                .rotationEffect(-angle)
                .offset(y: -r)
                .rotationEffect(angle)
                .accessibilityHidden(true)
            }
        }
        .frame(width: dialRadius * 2.0, height: dialRadius * 2.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WidgetWeaverClockSegmentedBezelPlaceholderView: View {
    let palette: WidgetWeaverClockPalette
    let outerDiameter: CGFloat

    let ringA: CGFloat
    let ringB: CGFloat
    let ringC: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Dark bezel ring.
        Circle()
            .fill(Color.black.opacity(0.70))
            .frame(width: outerDiameter, height: outerDiameter)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: max(px, ringA))
                    .blendMode(.overlay)
            )

        // Inner separator ring (thin bright ring between bezel and dial).
        Circle()
            .stroke(Color.white.opacity(0.08), lineWidth: max(px, ringC))
            .frame(
                width: outerDiameter - (ringA * 2.0) - (ringB * 2.0) - ringC,
                height: outerDiameter - (ringA * 2.0) - (ringB * 2.0) - ringC
            )
            .blendMode(.screen)
            .accessibilityHidden(true)
    }
}

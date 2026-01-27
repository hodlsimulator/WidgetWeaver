//
//  WidgetWeaverClockSegmentedFaceView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

/// Clock face renderer for Face = "segmented".
///
/// Step 2 scaffold:
/// - Uses a dedicated view so routing and geometry are stable.
/// - Renders bezel + dial placeholders and reuses the existing hands + centre hub.
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
/// Segmented-specific hands and centre hub are implemented in later steps.
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

            // Placeholder hand sizes (final segmented hands are added in a later step).
            let hourLength = WWClock.pixel(
                WWClock.clamp(R * 0.52, min: R * 0.48, max: R * 0.56),
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
            let secondTipSide = WWClock.pixel(
                WWClock.clamp(R * 0.016, min: R * 0.012, max: R * 0.020),
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

                    // Segmented outer ring sectors (Step 3).
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
                        let usedSecondTipSide = showsSecondHand ? secondTipSide : 0.0

                        let usedMinuteLength = showsMinuteHand ? minuteLength : 0.0
                        let usedMinuteWidth = showsMinuteHand ? minuteWidth : 0.0

                        if showsHandShadows {
                            WidgetWeaverClockHandShadowsView(
                                palette: palette,
                                dialDiameter: dialDiameter,
                                hourAngle: hourAngle,
                                minuteAngle: minuteAngle,
                                hourLength: hourLength,
                                hourWidth: hourWidth,
                                hourHandStyle: .icon,
                                minuteLength: usedMinuteLength,
                                minuteWidth: usedMinuteWidth,
                                scale: displayScale
                            )
                        }

                        WidgetWeaverClockHandsView(
                            palette: palette,
                            dialDiameter: dialDiameter,
                            hourAngle: hourAngle,
                            minuteAngle: minuteAngle,
                            secondAngle: secondAngle,
                            hourLength: hourLength,
                            hourWidth: hourWidth,
                            hourHandStyle: .icon,
                            minuteLength: usedMinuteLength,
                            minuteWidth: usedMinuteWidth,
                            secondLength: usedSecondLength,
                            secondWidth: usedSecondWidth,
                            secondTipSide: usedSecondTipSide,
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

        // Base ring radii (under the segments).
        let outerInset = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.010, min: px, max: dialRadius * 0.018),
            scale: scale
        )

        let baseOuterRadius = WWClock.pixel(max(1.0, dialRadius - outerInset), scale: scale)

        let targetThickness = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.185, min: px * 6.0, max: dialRadius * 0.205),
            scale: scale
        )

        let baseInnerRadius = WWClock.pixel(max(1.0, baseOuterRadius - targetThickness), scale: scale)
        let baseThickness = max(px, baseOuterRadius - baseInnerRadius)
        let midRadius = max(px, (baseInnerRadius + baseOuterRadius) * 0.5)

        // Compute angular gap from a pixel-snapped linear gap.
        let gapLinear = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.020, min: px * 2.0, max: dialRadius * 0.028),
            scale: scale
        )
        let gapAngle = Angle.radians(Double(gapLinear / midRadius))

        // A small radial inset helps the separators read as crisp black grooves.
        let maxInset = baseThickness * 0.28
        let radialInset = WWClock.pixel(min(maxInset, max(px, dialRadius * 0.004)), scale: scale)

        let segmentOuterRadius = baseOuterRadius - radialInset
        let segmentInnerRadius = baseInnerRadius + radialInset

        let segmentThickness = max(px, segmentOuterRadius - segmentInnerRadius)

        // Numerals sit slightly towards the outer edge of each segment (Step 5).
        let numeralRadius = WWClock.pixel(
            segmentInnerRadius + (segmentThickness * 0.64),
            scale: scale
        )

        let numeralFontSize = WWClock.pixel(
            WWClock.clamp(segmentThickness * 0.78, min: px * 4.0, max: segmentThickness * 0.84),
            scale: scale
        )


        let baseRingFill = palette.separatorRing.opacity(1.0)

        ZStack {
            Circle()
                .strokeBorder(baseRingFill, lineWidth: baseThickness)
                .frame(width: baseOuterRadius * 2.0, height: baseOuterRadius * 2.0)

            ForEach(0..<12, id: \.self) { i in
                // 12 at the top; sectors centred on hour positions.
                let centreDeg = -90.0 + (Double(i) * 30.0)
                let start = Angle.degrees(centreDeg - 15.0)
                let end = Angle.degrees(centreDeg + 15.0)

                WidgetWeaverClockSegmentedRingSegmentView(
                    innerRadius: segmentInnerRadius,
                    outerRadius: segmentOuterRadius,
                    startAngle: start,
                    endAngle: end,
                    angularGap: gapAngle,
                    dialRadius: dialRadius,
                    scale: scale
                )
            }

            WidgetWeaverClockSegmentedOuterRingNumeralsView(
                radius: numeralRadius,
                fontSize: numeralFontSize,
                scale: scale
            )
        }
        .frame(width: dialRadius * 2.0, height: dialRadius * 2.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WidgetWeaverClockSegmentedOuterRingNumeralsView: View {
    let radius: CGFloat
    let fontSize: CGFloat
    let scale: CGFloat

    private func text(for numeral: Int) -> String {
        numeral == 12 ? "12" : String(numeral)
    }

    private func offset(for numeral: Int) -> (x: CGFloat, y: CGFloat) {
        let stepDegrees = Double(numeral % 12) * 30.0
        let radians = stepDegrees * Double.pi / 180.0

        let x = radius * CGFloat(sin(radians))
        let y = -radius * CGFloat(cos(radians))

        return (x, y)
    }

    private func fineTuning(for numeral: Int, px: CGFloat) -> (x: CGFloat, y: CGFloat) {
        switch numeral {
        case 12:
            return (x: CGFloat(-0.45) * px, y: CGFloat(0.35) * px)
        case 10:
            return (x: CGFloat(-0.20) * px, y: 0.0)
        case 11:
            return (x: CGFloat(-0.12) * px, y: 0.0)
        default:
            return (x: 0.0, y: 0.0)
        }
    }

    var body: some View {
        let px = WWClock.px(scale: scale)

        ZStack {
            SwiftUI.ForEach(Array(1...12), id: \.self) { numeral in
                let p = offset(for: numeral)
                let t = fineTuning(for: numeral, px: px)

                WidgetWeaverClockSegmentedNumeralGlyphView(
                    text: text(for: numeral),
                    fontSize: fontSize,
                    scale: scale
                )
                .offset(x: p.x + t.x, y: p.y + t.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .unredacted()
    }
}

private struct WidgetWeaverClockSegmentedRingSegmentView: View {
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    let startAngle: Angle
    let endAngle: Angle

    let angularGap: Angle

    let dialRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let thickness = max(px, outerRadius - innerRadius)

        // Bevel widths are proportional but capped to stay crisp at small widget sizes.
        let outerBevelWidth = WWClock.pixel(
            WWClock.clamp(thickness * 0.16, min: px, max: px * 3.0),
            scale: scale
        )
        let innerBevelWidth = WWClock.pixel(
            WWClock.clamp(thickness * 0.18, min: px, max: px * 3.0),
            scale: scale
        )

        let dropShadowRadius = WWClock.pixel(
            WWClock.clamp(thickness * 0.045, min: px, max: px * 2.0),
            scale: scale
        )
        let dropShadowYOffset = WWClock.pixel(
            WWClock.clamp(thickness * 0.020, min: 0.0, max: px * 1.5),
            scale: scale
        )

        let baseFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: WWClock.colour(0x4B4A26, alpha: 1.0), location: 0.00),
                .init(color: WWClock.colour(0x3B3A1E, alpha: 1.0), location: 0.55),
                .init(color: WWClock.colour(0x252412, alpha: 1.0), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bodyBevelOverlay = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.20), location: 0.00),
                .init(color: Color.black.opacity(0.00), location: 0.42),
                .init(color: Color.white.opacity(0.08), location: 1.00)
            ]),
            center: .center,
            startRadius: innerRadius,
            endRadius: outerRadius
        )

        let specularOverlay = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.12), location: 0.00),
                .init(color: Color.white.opacity(0.02), location: 0.44),
                .init(color: Color.black.opacity(0.18), location: 1.00)
            ]),
            center: .topLeading,
            startRadius: 0,
            endRadius: dialRadius * 1.30
        )

        let outerEdgeHighlight = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.00), location: 0.00),
                .init(color: Color.white.opacity(0.22), location: 1.00)
            ]),
            center: .center,
            startRadius: max(0.0, outerRadius - outerBevelWidth),
            endRadius: outerRadius
        )

        let innerEdgeShadow = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.50), location: 0.00),
                .init(color: Color.black.opacity(0.00), location: 1.00)
            ]),
            center: .center,
            startRadius: innerRadius,
            endRadius: innerRadius + innerBevelWidth
        )

        let segmentShape = WWClockAnnularSectorShape(
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            angularGap: angularGap
        )

        let outerEdgeShape = WWClockAnnularSectorShape(
            innerRadius: max(innerRadius, outerRadius - outerBevelWidth),
            outerRadius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            angularGap: angularGap
        )

        let innerEdgeShape = WWClockAnnularSectorShape(
            innerRadius: innerRadius,
            outerRadius: min(outerRadius, innerRadius + innerBevelWidth),
            startAngle: startAngle,
            endAngle: endAngle,
            angularGap: angularGap
        )

        ZStack {
            segmentShape
                .fill(baseFill, style: FillStyle(eoFill: false, antialiased: true))
                .shadow(color: Color.black.opacity(0.30), radius: dropShadowRadius, x: 0, y: dropShadowYOffset)

            segmentShape
                .fill(bodyBevelOverlay, style: FillStyle(eoFill: false, antialiased: true))
                .opacity(0.95)

            segmentShape
                .fill(specularOverlay, style: FillStyle(eoFill: false, antialiased: true))
                .opacity(0.90)
                .blendMode(.overlay)

            outerEdgeShape
                .fill(outerEdgeHighlight, style: FillStyle(eoFill: false, antialiased: true))
                .opacity(0.90)

            innerEdgeShape
                .fill(innerEdgeShadow, style: FillStyle(eoFill: false, antialiased: true))
                .opacity(0.95)
        }
        .compositingGroup()
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

        let bezelThickness = ringA + ringB
        let separatorThickness = ringC
        let separatorDiameter = max(1, outerDiameter - (bezelThickness * 2.0))

        // Dark, slightly lifted bezel placeholder.
        let bezelFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.dialMid.opacity(0.98), location: 0.00),
                .init(color: palette.dialEdge.opacity(1.00), location: 0.60),
                .init(color: Color.black.opacity(0.96), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bezelHighlight = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.14), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.55),
                .init(color: Color.black.opacity(0.22), location: 1.00)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )

        let separatorStroke = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.separatorRing.opacity(0.92), location: 0.00),
                .init(color: palette.separatorRing.opacity(0.65), location: 0.55),
                .init(color: Color.black.opacity(0.92), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bezelShadowRadius = max(px, bezelThickness * 0.90)

        ZStack {
            Circle()
                .strokeBorder(bezelFill, lineWidth: bezelThickness)
                .frame(width: outerDiameter, height: outerDiameter)
                .shadow(color: Color.black.opacity(0.60), radius: bezelShadowRadius, x: 0, y: bezelShadowRadius * 0.30)

            Circle()
                .strokeBorder(bezelHighlight, lineWidth: max(px, bezelThickness * 0.24))
                .frame(width: outerDiameter, height: outerDiameter)
                .blendMode(.overlay)

            Circle()
                .strokeBorder(separatorStroke, lineWidth: separatorThickness)
                .frame(width: separatorDiameter, height: separatorDiameter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

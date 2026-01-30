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
/// Step 8:
/// - Adds a Segmented-specific centre hub (stacked discs + specular).
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

            let px = WWClock.px(scale: displayScale)

            // 11A: Bezel chunkiness via ring redistribution, dial radius locked (segmented ring must not move).
            let rings = SegmentedBezelStyle.rings(outerRadius: outerRadius, scale: displayScale)

            let ringA = rings.ringA
            let ringC = rings.ringC

            let ringB = rings.ringB
            let R = rings.dialRadius
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
                WWClock.clamp(R * 0.13, min: R * 0.11, max: R * 0.15),
                scale: displayScale
            )

            let secondLength = WWClock.pixel(
                WWClock.clamp(R * 0.76, min: R * 0.70, max: R * 0.80),
                scale: displayScale
            )
            let secondWidth = WWClock.pixel(
                WWClock.clamp(R * 0.010, min: WWClock.px(scale: displayScale), max: R * 0.016),
                scale: displayScale
            )

            let centreHubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.085, min: R * 0.070, max: R * 0.095),
                scale: displayScale
            )
            let centreHubCapRadius = WWClock.pixel(
                WWClock.clamp(
                    centreHubBaseRadius * 0.50,
                    min: centreHubBaseRadius * 0.42,
                    max: centreHubBaseRadius * 0.58
                ),
                scale: displayScale
            )

            // 11A: Dial radius lock + bezel chunk + gap lock.
            // Gutter inner edge is derived from the segmented ring outer boundary so widget and in-app stay locked.
            let segmentedOuterBoundaryRadius = SegmentedOuterRingStyle.segmentedOuterBoundaryRadius(
                dialRadius: R,
                scale: displayScale
            )

            let rimInnerRadius = max(px, outerRadius - ringA)
            let baselineRimInnerRadius = max(px, outerRadius - rings.baselineRingA)

            let gutterLock = SegmentedBezelStyle.lockedGutter(
                rimInnerRadius: rimInnerRadius,
                baselineRimInnerRadius: baselineRimInnerRadius,
                segmentedOuterBoundaryRadius: segmentedOuterBoundaryRadius,
                scale: displayScale
            )

            #if DEBUG
            let _ = SegmentedBezelStyle.debugValidateGutterLock(
                containerSide: s,
                scale: displayScale,
                gutter: gutterLock
            )
            #endif

            let gutterWidth = gutterLock.width

            let bezelGutterInnerRadius = segmentedOuterBoundaryRadius
            let bezelGutterOuterRadius = segmentedOuterBoundaryRadius + gutterWidth

            ZStack {
                // Bezel placeholder ring (A/B/C rings) – annular only (transparent centre).
                WidgetWeaverClockSegmentedBezelPlaceholderView(
                    palette: palette,
                    outerDiameter: outerDiameter,
                    ringA: ringA,
                    ringB: ringB,
                    ringC: ringC,
                    scale: displayScale
                )
                .frame(width: outerDiameter, height: outerDiameter)

                // Dial.
                WidgetWeaverClockDialFaceView(
                    palette: palette,
                    radius: R,
                    occlusionWidth: occlusionWidth
                )
                .frame(width: dialDiameter, height: dialDiameter)

                // Raised inner shelf (covers most of the rim→segment band, stopping at the gutter).
                WidgetWeaverClockSegmentedBezelShelfOverlayView(
                    outerRadius: rimInnerRadius,
                    innerRadius: bezelGutterOuterRadius,
                    scale: displayScale
                )

                // Recessed gutter (narrow groove immediately before the segmented ring).
                WidgetWeaverClockSegmentedBezelGutterOverlayView(
                    innerRadius: bezelGutterInnerRadius,
                    outerRadius: bezelGutterOuterRadius,
                    scale: displayScale
                )

                // Segmented outer ring (Canvas/CGPath renderer).
                SegmentedOuterRingView(
                    dialRadius: R,
                    scale: displayScale
                )

                // Inner tick marks.
                WidgetWeaverClockSegmentedTickMarksView(
                    palette: palette,
                    dialRadius: R,
                    scale: displayScale
                )

                // Hand shadows (optional).
                if showsHandShadows {
                    WidgetWeaverClockSegmentedHandShadowsView(
                        palette: palette,
                        dialDiameter: dialDiameter,
                        hourAngle: hourAngle,
                        minuteAngle: minuteAngle,
                        hourLength: hourLength,
                        hourWidth: hourWidth,
                        minuteLength: minuteLength,
                        minuteWidth: minuteWidth,
                        scale: displayScale
                    )
                }

                // Hands (optional seconds, optional minute).
                WidgetWeaverClockSegmentedHandsView(
                    palette: palette,
                    dialDiameter: dialDiameter,
                    hourAngle: hourAngle,
                    minuteAngle: showsMinuteHand ? minuteAngle : .degrees(0.0),
                    secondAngle: showsSecondHand ? secondAngle : .degrees(0.0),
                    hourLength: hourLength,
                    hourWidth: hourWidth,
                    minuteLength: showsMinuteHand ? minuteLength : 0.0,
                    minuteWidth: showsMinuteHand ? minuteWidth : 0.0,
                    secondLength: showsSecondHand ? secondLength : 0.0,
                    secondWidth: showsSecondHand ? secondWidth : 0.0,
                    scale: displayScale
                )
                .opacity(handsOpacity)

                // Centre hub (optional).
                if showsCentreHub {
                    WidgetWeaverClockSegmentedCentreHubView(
                        palette: palette,
                        baseRadius: centreHubBaseRadius,
                        capRadius: centreHubCapRadius,
                        scale: displayScale
                    )
                }

                #if DEBUG
                if WidgetWeaverFeatureFlags.segmentedBezelDiagnosticsEnabled {
                    WidgetWeaverClockSegmentedBezelDiagnosticsOverlayView(
                        containerSide: s,
                        rings: rings,
                        rimInnerRadius: rimInnerRadius,
                        baselineRimInnerRadius: baselineRimInnerRadius,
                        segmentedOuterBoundaryRadius: segmentedOuterBoundaryRadius,
                        gutterOuterRadius: bezelGutterOuterRadius,
                        gutterLock: gutterLock,
                        scale: displayScale
                    )
                }
                #endif
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Bezel placeholder (annular)

private struct WidgetWeaverClockSegmentedBezelPlaceholderView: View {
    let palette: WidgetWeaverClockPalette
    let outerDiameter: CGFloat

    let ringA: CGFloat
    let ringB: CGFloat
    let ringC: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let rimCrispW = WWClock.pixel(
            WWClock.clamp(ringA + (px * 2.0), min: px * 3.0, max: px * 6.0),
            scale: scale
        )
        let rimGrooveW = WWClock.pixel(px, scale: scale)
        let rimOuterEdgeW = WWClock.pixel(px, scale: scale)

        let outerA = outerDiameter
        let outerB = max(1.0, outerA - (ringA * 2.0))
        let outerC = max(1.0, outerA - ((ringA + ringB) * 2.0))

        let outerBR = outerB * 0.5
        let innerBR = max(0.0, outerBR - ringB)
        let innerFractionB: CGFloat = (outerBR > 0.0) ? (innerBR / outerBR) : 0.01

        // 11A2: Lighter bezel tone (neutral gunmetal).
        let bezelDark = SegmentedBezelStyle.bezelDark
        let bezelMid = SegmentedBezelStyle.bezelMid
        let bezelBright = SegmentedBezelStyle.bezelBright

        let bodyFill = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: bezelDark, location: 0.00),
                .init(color: bezelMid, location: 0.64),
                .init(color: bezelBright, location: 1.00)
            ]),
            center: .center,
            startRadius: innerBR,
            endRadius: outerBR
        )

        // Broad overlays are kept lower-energy to avoid haze on light wallpapers.
        let angularHighlight = AngularGradient(
            gradient: Gradient(stops: [
                .init(color: bezelBright.opacity(0.50), location: 0.000),
                .init(color: bezelBright.opacity(0.50), location: 0.055),
                .init(color: bezelMid.opacity(0.18), location: 0.190),
                .init(color: bezelMid.opacity(0.05), location: 0.330),
                .init(color: bezelDark.opacity(0.14), location: 0.560),
                .init(color: bezelDark.opacity(0.44), location: 0.740),
                .init(color: bezelMid.opacity(0.14), location: 0.885),
                .init(color: bezelBright.opacity(0.32), location: 1.000)
            ]),
            center: .center,
            angle: .degrees(-135.0)
        )

        let outerRimRadius = outerA * 0.5

        // Rim highlight is kept inside the rim and the outermost edge is kept dark to avoid halo.
        let outerRimMachining = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.78), location: 0.00),
                .init(color: Color.black.opacity(0.18), location: 0.64),
                .init(color: Color.white.opacity(0.28), location: 0.88),
                .init(color: Color.black.opacity(0.70), location: 1.00)
            ]),
            center: .center,
            startRadius: max(0.0, outerRimRadius - ringA),
            endRadius: outerRimRadius
        )

        let outerRimDirectional = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.22), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.44),
                .init(color: Color.black.opacity(0.34), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let innerRidge = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.28), location: 0.00),
                .init(color: Color.white.opacity(0.04), location: 0.44),
                .init(color: Color.black.opacity(0.44), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let innerChamfer = AngularGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.34), location: 0.000),
                .init(color: Color.white.opacity(0.18), location: 0.090),
                .init(color: Color.white.opacity(0.00), location: 0.240),
                .init(color: Color.black.opacity(0.20), location: 0.460),
                .init(color: Color.black.opacity(0.58), location: 0.690),
                .init(color: Color.black.opacity(0.30), location: 0.840),
                .init(color: Color.white.opacity(0.22), location: 1.000)
            ]),
            center: .center,
            angle: .degrees(-135.0)
        )

        return ZStack {
            // B) Main bezel ring (gunmetal).
            WWClockSegmentedAnnulus(innerRadiusFraction: innerFractionB)
                .fill(bodyFill, style: FillStyle(eoFill: true, antialiased: true))
                .frame(width: outerB, height: outerB)
                .overlay(
                    WWClockSegmentedAnnulus(innerRadiusFraction: innerFractionB)
                        .fill(angularHighlight, style: FillStyle(eoFill: true, antialiased: true))
                        .frame(width: outerB, height: outerB)
                        .blendMode(.overlay)
                        .opacity(0.74)
                )

            // A) Raised outer rim.
            Circle()
                .strokeBorder(outerRimMachining, lineWidth: max(px, ringA))
                .frame(width: outerA, height: outerA)
                .opacity(0.98)

            Circle()
                .strokeBorder(outerRimDirectional, lineWidth: max(px, ringA * 0.92))
                .frame(width: outerA, height: outerA)
                .blendMode(.overlay)
                .opacity(0.52)

            // Crisp outer edge (keeps the rim from blooming on light wallpapers).
            Circle()
                .strokeBorder(Color.black.opacity(0.82), lineWidth: max(px, rimOuterEdgeW))
                .frame(width: outerA, height: outerA)
                .opacity(0.92)

            // Inner rim shadow to increase perceived thickness.
            Circle()
                .strokeBorder(Color.black.opacity(0.74), lineWidth: max(px, rimCrispW))
                .frame(width: outerB, height: outerB)
                .blendMode(.multiply)
                .opacity(0.90)

            Circle()
                .strokeBorder(Color.black.opacity(0.60), lineWidth: max(px, rimGrooveW))
                .frame(width: outerB, height: outerB)
                .blendMode(.multiply)
                .opacity(0.90)

            Circle()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: max(px, rimGrooveW))
                .frame(width: outerB, height: outerB)
                .blendMode(.screen)
                .opacity(0.66)

            // C) Inner ridge / separator between bezel and dial.
            Circle()
                .strokeBorder(innerRidge, lineWidth: max(px, ringC))
                .frame(width: outerC, height: outerC)
                .blendMode(.overlay)
                .opacity(0.92)

            Circle()
                .strokeBorder(innerChamfer, lineWidth: max(px, ringC * 0.92))
                .frame(width: outerC, height: outerC)
                .blendMode(.overlay)
                .opacity(0.92)

            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: max(px, ringC * 0.22))
                .frame(
                    width: max(1.0, outerC - (ringC * 0.55)),
                    height: max(1.0, outerC - (ringC * 0.55))
                )
                .blendMode(.screen)
                .opacity(0.80)

            Circle()
                .strokeBorder(Color.black.opacity(0.62), lineWidth: max(px, ringC * 0.52))
                .frame(width: outerC, height: outerC)
                .blendMode(.multiply)
                .opacity(0.78)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bezel shelf + gutter overlays (10A)

private struct WidgetWeaverClockSegmentedBezelShelfOverlayView: View {
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let outerR = max(px, outerRadius)
        let innerR = max(0.0, min(innerRadius, outerR - px))
        let innerFraction: CGFloat = (outerR > 0.0) ? (innerR / outerR) : 0.01

        let band = max(px, outerR - innerR)

        // Clamp broad gradients to narrow, physical-pixel ramps.
        let innerRamp = WWClock.pixel(min(band, px * 2.0), scale: scale)
        let outerRamp = WWClock.pixel(min(band, px * 3.0), scale: scale)

        let innerLoc = Double(WWClock.clamp(innerRamp / band, min: 0.0, max: 0.35))
        let outerLoc = Double(WWClock.clamp(outerRamp / band, min: 0.0, max: 0.35))
        let plateauStart = max(0.0, 1.0 - outerLoc)

        // 11A2: Lighter shelf metal (neutral gunmetal).
        let bezelDark = SegmentedBezelStyle.bezelDark
        let bezelMid = SegmentedBezelStyle.bezelMid
        let bezelBright = SegmentedBezelStyle.bezelBright

        let shelfFill = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: bezelDark.opacity(0.98), location: 0.00),
                .init(color: bezelMid.opacity(1.00), location: innerLoc),
                .init(color: bezelMid.opacity(1.00), location: plateauStart),
                .init(color: bezelBright.opacity(0.92), location: 1.00)
            ]),
            center: .center,
            startRadius: innerR,
            endRadius: outerR
        )

        // Narrow specular band, confined to the rim-side edge to avoid "misty" overlays.
        let specularBand = WWClock.pixel(min(band, px * 3.0), scale: scale)
        let specularInnerFraction: CGFloat = (outerR > 0.0) ? max(0.0, (outerR - specularBand) / outerR) : 0.01

        let shelfSpecular = AngularGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.24), location: 0.000),
                .init(color: Color.white.opacity(0.08), location: 0.120),
                .init(color: Color.white.opacity(0.00), location: 0.260),
                .init(color: Color.black.opacity(0.22), location: 0.560),
                .init(color: Color.black.opacity(0.46), location: 0.720),
                .init(color: Color.black.opacity(0.18), location: 0.860),
                .init(color: Color.white.opacity(0.14), location: 1.000)
            ]),
            center: .center,
            angle: .degrees(-135.0)
        )

        let shelfInnerShadowBand = WWClock.pixel(min(band, px * 2.0), scale: scale)
        let shadowOuterR = innerR + shelfInnerShadowBand
        let shadowInnerFraction: CGFloat = (shadowOuterR > 0.0) ? (innerR / shadowOuterR) : 0.01

        let shelfInnerShadow = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.50), location: 0.00),
                .init(color: Color.black.opacity(0.00), location: 1.00)
            ]),
            center: .center,
            startRadius: innerR,
            endRadius: shadowOuterR
        )

        let outerD = outerR * 2.0
        let grooveLineW = WWClock.pixel(px, scale: scale)

        return ZStack {
            WWClockSegmentedAnnulus(innerRadiusFraction: innerFraction)
                .fill(shelfFill, style: FillStyle(eoFill: true, antialiased: true))
                .frame(width: outerD, height: outerD)

            // Rim→shelf step groove line (crisp, 1px).
            Circle()
                .strokeBorder(Color.black.opacity(0.72), lineWidth: max(px, grooveLineW))
                .frame(width: outerD, height: outerD)
                .blendMode(.multiply)
                .opacity(0.92)

            WWClockSegmentedAnnulus(innerRadiusFraction: specularInnerFraction)
                .fill(shelfSpecular, style: FillStyle(eoFill: true, antialiased: true))
                .frame(width: outerD, height: outerD)
                .blendMode(.overlay)
                .opacity(0.62)

            WWClockSegmentedAnnulus(innerRadiusFraction: shadowInnerFraction)
                .fill(shelfInnerShadow, style: FillStyle(eoFill: true, antialiased: true))
                .frame(width: shadowOuterR * 2.0, height: shadowOuterR * 2.0)
                .blendMode(.multiply)
                .opacity(0.78)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WidgetWeaverClockSegmentedBezelGutterOverlayView: View {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let outerR = max(px, outerRadius)
        let innerR = max(0.0, min(innerRadius, outerR - px))
        let innerFraction: CGFloat = (outerR > 0.0) ? (innerR / outerR) : 0.01

        let band = max(px, outerR - innerR)
        let ramp = WWClock.pixel(min(band, px * 1.0), scale: scale)

        let rampLoc = Double(WWClock.clamp(ramp / band, min: 0.0, max: 0.45))
        let plateauStart = max(0.0, 1.0 - rampLoc)

        // 11A3: Gutter reads as a recessed cut (neutral, crisp).
        let gutterBase = SegmentedBezelStyle.gutterBase
        let gutterHi = SegmentedBezelStyle.gutterHi

        let gutterFill = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: gutterHi.opacity(0.98), location: 0.00),
                .init(color: gutterBase.opacity(1.00), location: rampLoc),
                .init(color: gutterBase.opacity(1.00), location: plateauStart),
                .init(color: Color.black.opacity(0.92), location: 1.00)
            ]),
            center: .center,
            startRadius: innerR,
            endRadius: outerR
        )

        let outerD = outerR * 2.0
        let innerD = max(1.0, innerR * 2.0)

        let grooveLineW = WWClock.pixel(px, scale: scale)

        return ZStack {
            WWClockSegmentedAnnulus(innerRadiusFraction: innerFraction)
                .fill(gutterFill, style: FillStyle(eoFill: true, antialiased: true))
                .frame(width: outerD, height: outerD)

            // Shelf→gutter groove line (crisp, 1px).
            Circle()
                .strokeBorder(Color.black.opacity(0.86), lineWidth: max(px, grooveLineW))
                .frame(width: outerD, height: outerD)
                .blendMode(.multiply)
                .opacity(0.95)

            // A subtle outer-edge highlight that stays inside the groove.
            Circle()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: max(px, grooveLineW))
                .frame(width: outerD, height: outerD)
                .blendMode(.screen)
                .opacity(0.56)

            // Inner lip highlight at gutter→ring boundary.
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: max(px, grooveLineW))
                .frame(width: innerD, height: innerD)
                .blendMode(.screen)
                .opacity(0.86)

            // Inner lip shadow (depth cue).
            Circle()
                .strokeBorder(Color.black.opacity(0.54), lineWidth: max(px, grooveLineW))
                .frame(width: innerD, height: innerD)
                .blendMode(.multiply)
                .opacity(0.72)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
private struct WidgetWeaverClockSegmentedBezelDiagnosticsOverlayView: View {
    let containerSide: CGFloat
    let rings: SegmentedBezelStyle.Rings

    let rimInnerRadius: CGFloat
    let baselineRimInnerRadius: CGFloat

    let segmentedOuterBoundaryRadius: CGFloat
    let gutterOuterRadius: CGFloat

    let gutterLock: SegmentedBezelStyle.GutterLock
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)
        let lineW = WWClock.pixel(px, scale: scale)

        let rimD = WWClock.pixel(rimInnerRadius * 2.0, scale: scale)
        let ringD = WWClock.pixel(segmentedOuterBoundaryRadius * 2.0, scale: scale)
        let gutterD = WWClock.pixel(gutterOuterRadius * 2.0, scale: scale)

        let baselineSegmentedOuterBoundaryRadius = SegmentedOuterRingStyle.segmentedOuterBoundaryRadius(
            dialRadius: rings.baselineDialRadius,
            scale: scale
        )

        func pxCount(_ value: CGFloat) -> Int {
            Int((value / max(px, 0.0001)).rounded())
        }

        let rPx = pxCount(rings.dialRadius)
        let baseRPx = pxCount(rings.baselineDialRadius)
        let rDeltaPx = rPx - baseRPx

        let segPx = pxCount(segmentedOuterBoundaryRadius)
        let baseSegPx = pxCount(baselineSegmentedOuterBoundaryRadius)
        let segDeltaPx = segPx - baseSegPx

        let gutterPx = pxCount(gutterLock.width)
        let baseGutterPx = pxCount(gutterLock.baselineWidth)
        let gutterDeltaPx = gutterPx - baseGutterPx

        let ringAPx = pxCount(rings.ringA)
        let ringBPx = pxCount(rings.ringB)
        let ringCPx = pxCount(rings.ringC)

        let baseRingAPx = pxCount(rings.baselineRingA)
        let baseRingBPx = pxCount(rings.baselineRingB)
        let baseRingCPx = pxCount(rings.baselineRingC)

        let ringADeltaPx = ringAPx - baseRingAPx
        let ringBDeltaPx = ringBPx - baseRingBPx
        let ringCDeltaPx = ringCPx - baseRingCPx

        let rimInnerPx = pxCount(rimInnerRadius)
        let baseRimInnerPx = pxCount(baselineRimInnerRadius)
        let rimInnerDeltaPx = rimInnerPx - baseRimInnerPx

        let shelfBandPx = pxCount(gutterLock.availableShelfBand)

        let metrics = VStack(alignment: .leading, spacing: 2.0) {
            Text("s \(containerSide, specifier: "%.1f")  scale \(scale, specifier: "%.2f")")
            Text("R \(rPx)px  Δ\(rDeltaPx)px")
            Text("segOut \(segPx)px  Δ\(segDeltaPx)px")
            Text("gutter \(gutterPx)px  Δ\(gutterDeltaPx)px")
            Text("ringA \(ringAPx)px  Δ\(ringADeltaPx)px")
            Text("ringB \(ringBPx)px  Δ\(ringBDeltaPx)px")
            Text("ringC \(ringCPx)px  Δ\(ringCDeltaPx)px")
            Text("rimIn \(rimInnerPx)px  Δ\(rimInnerDeltaPx)px")
            Text("shelfBand \(shelfBandPx)px")

            if gutterLock.didClampDueToBand {
                Text("gutter clamped")
                    .fontWeight(.bold)
                    .foregroundStyle(WWClock.colour(0xFF2D55, alpha: 0.92))
            }
        }
        .font(.system(size: 10.0, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(6.0)
        .background(Color.black.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 6.0, style: .continuous))
        .padding(4.0)

        return ZStack(alignment: .topLeading) {
            // Rim→shelf step (rim inner edge).
            Circle()
                .stroke(Color.yellow.opacity(0.90), lineWidth: max(px, lineW))
                .frame(width: rimD, height: rimD)

            // Segmented ring outer boundary (style helper, bedOuter).
            Circle()
                .stroke(WWClock.colour(0xFF2D55, alpha: 0.92), lineWidth: max(px, lineW))
                .frame(width: ringD, height: ringD)

            // Gutter outer edge / shelf inner edge.
            Circle()
                .stroke(WWClock.colour(0x32D7FF, alpha: 0.92), lineWidth: max(px, lineW))
                .frame(width: gutterD, height: gutterD)

            metrics
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

// MARK: - Shapes

private struct WWClockSegmentedAnnulus: Shape {
    var innerRadiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.5
        let innerR = max(0.0, r * innerRadiusFraction)
        let c = CGPoint(x: rect.midX, y: rect.midY)

        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2.0, height: r * 2.0))
        p.addEllipse(in: CGRect(x: c.x - innerR, y: c.y - innerR, width: innerR * 2.0, height: innerR * 2.0))
        return p
    }
}

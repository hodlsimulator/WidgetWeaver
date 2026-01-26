//
//  ClockFaceTokens.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import SwiftUI

/// Centralised styling tokens for the clock face renderers.
///
/// Notes:
/// - Scheme/palette remain the source of truth for dial and background fills.
/// - Tokens cover material styling knobs (numerals / rings / ticks / hands) so future tuning stays local.
enum WidgetWeaverClockFaceTokens {

    // MARK: - Numerals

    struct Numerals {

        enum FillStyle {
            case palette
            case fixed(light: Color, mid: Color, dark: Color)
        }

        /// Controls the main numeral fill colouring.
        ///
        /// Default is `.palette` to preserve the existing scheme appearance.
        let fillStyle: FillStyle = .palette

        // Depth shadow (embossed feel).
        let depthShadowOpacity: Double = 0.42
        let depthShadowOffsetXInPx: CGFloat = 1.2
        let depthShadowOffsetYInPx: CGFloat = 1.4
        let depthShadowBlurInPx: CGFloat = 0.30

        // Inner bevel highlight + shade.
        let innerHighlightOffsetXInPx: CGFloat = -0.9
        let innerHighlightOffsetYInPx: CGFloat = -1.0
        let innerHighlightBlurInPx: CGFloat = 0.24

        let innerShadeOffsetXInPx: CGFloat = 0.9
        let innerShadeOffsetYInPx: CGFloat = 1.0
        let innerShadeBlurInPx: CGFloat = 0.26

        // Outer shadow.
        let outerShadowRadiusFactor: CGFloat = 0.045
        let outerShadowYOffsetFactor: CGFloat = 0.020

        func fillGradient(palette: WidgetWeaverClockPalette) -> LinearGradient {
            let (light, mid, dark): (Color, Color, Color) = {
                switch fillStyle {
                case .palette:
                    return (palette.numeralLight, palette.numeralMid, palette.numeralDark)
                case .fixed(let l, let m, let d):
                    return (l, m, d)
                }
            }()

            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: light, location: 0.00),
                    .init(color: mid, location: 0.56),
                    .init(color: dark, location: 1.00)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static let numerals = Numerals()

    // MARK: - Dial

    struct Dial {
        let domeHighlightOpacity: Double = 0.60

        let occlusionRingStartOpacity: Double = 0.58
        let occlusionRingEndOpacity: Double = 0.92
    }

    static let dial = Dial()

    struct IconDial {
        let separatorStrokeOpacity: Double = 0.22
        let separatorStrokeWidthFactor: CGFloat = 0.25
    }

    static let iconDial = IconDial()

    // MARK: - Tick marks

    struct TickMarks {
        let majorFillOpacity: Double = 0.82
        let minorFillOpacity: Double = 0.62

        let majorShadowOpacity: Double = 0.18
        let minorShadowOpacity: Double = 0.14

        /// Size-driven minor tick opacity.
        ///
        /// Default is flat to preserve the existing baseline. Future tuning can fade earlier at tiny sizes.
        func minorOpacity(dialDiameter: CGFloat) -> Double {
            minorFillOpacity
        }
    }

    static let tickMarks = TickMarks()

    // MARK: - Ceramic bezel

    struct CeramicBezel {
        // Outer rim highlight intensity.
        let outerRimHighlightMidOpacity: Double = 0.72
        let outerRimHighlightPeakOpacity: Double = 0.90

        // Outer drop shadow.
        let outerShadowOpacity: Double = 0.30
        let outerShadowRadiusInPx: CGFloat = 1.4
        let outerShadowYOffsetInPx: CGFloat = 1.0
    }

    static let ceramicBezel = CeramicBezel()

    // MARK: - Icon bezel

    struct IconBezel {
        // Outer metal rim colouring.
        let metalHi: Color = WWClock.colour(0xF6FAFF, alpha: 1.0)
        let metalMid: Color = WWClock.colour(0xD6DEEA, alpha: 1.0)
        let metalLo: Color = WWClock.colour(0x9AA8BA, alpha: 1.0)

        // Rim definition.
        let rimInnerTopOpacity: Double = 0.18
        let rimInnerBottomOpacity: Double = 0.18

        // Matte ring fill.
        let matteRingTop: Color = WWClock.colour(0x0A0E14, alpha: 1.0)
        let matteRingMid: Color = WWClock.colour(0x0B0F15, alpha: 1.0)
        let matteRingBottom: Color = WWClock.colour(0x05080C, alpha: 1.0)

        // Inner metal ring.
        let innerMetalTopOpacity: Double = 0.22
        let innerMetalMidOpacity: Double = 0.06
        let innerMetalBottomOpacity: Double = 0.22

        // Shadows.
        let rimShadowOpacity: Double = 0.20
        let matteRingShadowOpacity: Double = 0.32
        let innerMetalShadowOpacity: Double = 0.22

        // Outer gloss.
        let glossMidOpacity: Double = 0.08
        let glossPeakOpacity: Double = 0.16
        let glossLineWidthFactor: CGFloat = 0.26
        let glossBlurFactor: CGFloat = 0.12

        let glossTrimFrom: CGFloat = 0.06
        let glossTrimTo: CGFloat = 0.42
        let glossRotationDegrees: Double = -14.0
    }

    static let iconBezel = IconBezel()

    // MARK: - Icon second hand

    struct IconSecondHand {
        let stemOpacity: Double = 0.92
        let tipStrokeOpacity: Double = 0.12
        let tipStrokeWidthFactor: CGFloat = 0.14
    }

    static let iconSecondHand = IconSecondHand()
}

//
//  WidgetWeaverClockPalette.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockPalette {
    let accent: Color

    let backgroundTop: Color
    let backgroundBottom: Color

    // Bezel metal
    let bezelBright: Color
    let bezelMid: Color
    let bezelDark: Color
    let bezelOcclusion: Color

    // Dark separator / occlusion ring
    let separatorRing: Color

    // Dial
    let dialCenter: Color
    let dialMid: Color
    let dialEdge: Color
    let dialVignette: Color
    let dialDomeHighlight: Color

    // Icon face dial (uniform fill)
    let iconDialFill: Color

    // Icon face seconds hand (baseline)
    let iconSecondHand: Color

    // Tracks / markers
    let minuteDot: Color

    let batonBright: Color
    let batonMid: Color
    let batonDark: Color
    let batonEdgeLight: Color
    let batonEdgeDark: Color
    let batonShadow: Color

    // Numerals
    let numeralLight: Color
    let numeralMid: Color
    let numeralDark: Color
    let numeralInnerHighlight: Color
    let numeralInnerShade: Color
    let numeralShadow: Color

    // Hands
    let handLight: Color
    let handMid: Color
    let handDark: Color
    let handEdge: Color
    let handShadow: Color

    // Hub
    let hubBase: Color
    let hubCapLight: Color
    let hubCapMid: Color
    let hubCapDark: Color
    let hubShadow: Color

    static func resolve(scheme: WidgetWeaverClockColourScheme, mode: ColorScheme) -> WidgetWeaverClockPalette {
        let isDark = (mode == .dark)

        let accent: Color = {
            switch scheme {
            // Use high-contrast, clearly-distinct accents so scheme changes are obvious
            // both in-widget and in the in-app preview.
            case .classic: return WWClock.colour(0xFF9F0A)   // system-like orange
            case .ocean: return WWClock.colour(0x339CFF)     // lighter blue (Ocean)
            case .mint: return WWClock.colour(0x34C759)      // system-like green
            case .orchid: return WWClock.colour(0xAF52DE)    // system-like purple
            case .sunset: return WWClock.colour(0xFF2D55)    // system-like pink
            case .ember: return WWClock.colour(0xFF3B30)     // system-like red
            case .graphite: return WWClock.colour(0x8E8E93)  // system-like gray
            }
        }()

        // Widget background (outside dial)
        let backgroundTop: Color = isDark ? WWClock.colour(0x141A22) : WWClock.colour(0xECF1F8)
        let backgroundBottom: Color = isDark ? WWClock.colour(0x0B0F15) : WWClock.colour(0xC7D2E5)

        // Bezel: stronger metal range; keep highlight controlled.
        let bezelBright: Color = WWClock.colour(0xF6FAFF, alpha: 0.96)
        let bezelMid: Color = WWClock.colour(0xB9C7DB, alpha: 0.92)
        let bezelDark: Color = WWClock.colour(0x2C3442, alpha: 0.96)
        let bezelOcclusion: Color = WWClock.colour(0x000000, alpha: isDark ? 0.86 : 0.66)

        // Ring D / separator: near-black but not pure black.
        let separatorRing: Color = WWClock.colour(0x0B0F15, alpha: 1.0)

        // Dial: lifted off pure-black to better match the icon mock.
        let dialCenter: Color = WWClock.colour(0x101722, alpha: 1.0)
        let dialMid: Color = WWClock.colour(0x0E141E, alpha: 1.0)
        let dialEdge: Color = WWClock.colour(0x0B0F15, alpha: 1.0)

        let dialVignette: Color = WWClock.colour(0x000000, alpha: 0.22)
        let dialDomeHighlight: Color = WWClock.colour(0xFFFFFF, alpha: 0.040)

        // Icon face dial: a calmer, flatter slate-blue field.
        let iconDialFill: Color = isDark ? WWClock.colour(0x22364B, alpha: 1.0) : WWClock.colour(0x2A4158, alpha: 1.0)

        // Icon face baseline seconds hand colour (red).
        let iconSecondHand: Color = WWClock.colour(0xF53842, alpha: 1.0)

        // Minute dots: more visible, uniform.
        let minuteDot: Color = WWClock.colour(0xD0DBEE, alpha: 0.80)

        // Batons: crisp bevel range.
        let batonBright: Color = WWClock.colour(0xF2F6FB, alpha: 0.96)
        let batonMid: Color = WWClock.colour(0xC3D0E2, alpha: 0.92)
        let batonDark: Color = WWClock.colour(0x5E6E89, alpha: 0.96)
        let batonEdgeLight: Color = WWClock.colour(0xFFFFFF, alpha: 0.52)
        let batonEdgeDark: Color = WWClock.colour(0x000000, alpha: 0.55)
        let batonShadow: Color = WWClock.colour(0x000000, alpha: 0.18)

        // Numerals: brighter silver-grey, minimal outer shadow.
        let numeralLight: Color = WWClock.colour(0xEEF5FF, alpha: 0.92)
        let numeralMid: Color = WWClock.colour(0xC2D0E4, alpha: 0.90)
        let numeralDark: Color = WWClock.colour(0x7E8EA9, alpha: 0.92)
        let numeralInnerHighlight: Color = WWClock.colour(0xFFFFFF, alpha: 0.28)
        let numeralInnerShade: Color = WWClock.colour(0x000000, alpha: 0.32)
        let numeralShadow: Color = WWClock.colour(0x000000, alpha: isDark ? 0.18 : 0.12)

        // Hands: clear metal separation + consistent lighting.
        let handLight: Color = WWClock.colour(0xF1F7FF, alpha: 0.94)
        let handMid: Color = WWClock.colour(0xBCCADF, alpha: 0.92)
        let handDark: Color = WWClock.colour(0x55657F, alpha: 0.95)
        let handEdge: Color = WWClock.colour(0x000000, alpha: 0.22)
        let handShadow: Color = WWClock.colour(0x000000, alpha: isDark ? 0.62 : 0.30)

        // Hub: two discs with tight spec highlight.
        let hubBase: Color = WWClock.colour(0x0C121B, alpha: 1.0)
        let hubCapLight: Color = WWClock.colour(0xF7FBFF, alpha: 0.96)
        let hubCapMid: Color = WWClock.colour(0xC2D0E2, alpha: 0.92)
        let hubCapDark: Color = WWClock.colour(0x5B6A82, alpha: 0.96)
        let hubShadow: Color = WWClock.colour(0x000000, alpha: isDark ? 0.65 : 0.32)

        return WidgetWeaverClockPalette(
            accent: accent,
            backgroundTop: backgroundTop,
            backgroundBottom: backgroundBottom,
            bezelBright: bezelBright,
            bezelMid: bezelMid,
            bezelDark: bezelDark,
            bezelOcclusion: bezelOcclusion,
            separatorRing: separatorRing,
            dialCenter: dialCenter,
            dialMid: dialMid,
            dialEdge: dialEdge,
            dialVignette: dialVignette,
            dialDomeHighlight: dialDomeHighlight,
            iconDialFill: iconDialFill,
            iconSecondHand: iconSecondHand,
            minuteDot: minuteDot,
            batonBright: batonBright,
            batonMid: batonMid,
            batonDark: batonDark,
            batonEdgeLight: batonEdgeLight,
            batonEdgeDark: batonEdgeDark,
            batonShadow: batonShadow,
            numeralLight: numeralLight,
            numeralMid: numeralMid,
            numeralDark: numeralDark,
            numeralInnerHighlight: numeralInnerHighlight,
            numeralInnerShade: numeralInnerShade,
            numeralShadow: numeralShadow,
            handLight: handLight,
            handMid: handMid,
            handDark: handDark,
            handEdge: handEdge,
            handShadow: handShadow,
            hubBase: hubBase,
            hubCapLight: hubCapLight,
            hubCapMid: hubCapMid,
            hubCapDark: hubCapDark,
            hubShadow: hubShadow
        )
    }
}

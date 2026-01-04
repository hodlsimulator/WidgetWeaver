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
            case .classic: return WWClock.colour(0x3FC0F0)
            case .ocean: return WWClock.colour(0x4FA9FF)
            case .mint: return WWClock.colour(0x4BE3B4)
            case .orchid: return WWClock.colour(0xB08CFF)
            case .sunset: return WWClock.colour(0xFF9F4E)
            case .ember: return WWClock.colour(0xFF4D4A)
            case .graphite: return WWClock.colour(0x93A7C2)
            }
        }()

        // Widget background (outside dial)
        // Match the mock: a slightly lifted dark graphite rather than near-black.
        let backgroundTop: Color = isDark ? WWClock.colour(0x1A202A) : WWClock.colour(0xECF1F8)
        let backgroundBottom: Color = isDark ? WWClock.colour(0x0A0E14) : WWClock.colour(0xC7D2E5)

        // Bezel: stronger metal range; keep highlight controlled.
        let bezelBright: Color = WWClock.colour(0xF6FAFF, alpha: 0.96)
        let bezelMid: Color = WWClock.colour(0xB9C7DB, alpha: 0.92)
        let bezelDark: Color = WWClock.colour(0x2C3442, alpha: 0.96)
        let bezelOcclusion: Color = WWClock.colour(0x000000, alpha: isDark ? 0.86 : 0.66)

        // Ring D / separator: near-black but not pure black.
        let separatorRing: Color = WWClock.colour(0x0B0F15, alpha: 1.0)

        // Dial: lifted dark grey (avoid pure black).
        // The mock dial reads as dark graphite with a soft centre glow.
        let dialCenter: Color = WWClock.colour(0x1B212B, alpha: 1.0)
        let dialMid: Color = WWClock.colour(0x0F141C, alpha: 1.0)
        let dialEdge: Color = WWClock.colour(0x070A0F, alpha: 1.0)

        let dialVignette: Color = WWClock.colour(0x000000, alpha: 0.58)
        let dialDomeHighlight: Color = WWClock.colour(0xFFFFFF, alpha: 0.060)

        // Minute dots: slightly softer than the hands/indices.
        let minuteDot: Color = WWClock.colour(0xB8C4D8, alpha: 0.62)

        // Batons: crisp bevel range.
        let batonBright: Color = WWClock.colour(0xF2F6FB, alpha: 0.96)
        let batonMid: Color = WWClock.colour(0xC3D0E2, alpha: 0.92)
        let batonDark: Color = WWClock.colour(0x5E6E89, alpha: 0.96)
        let batonEdgeLight: Color = WWClock.colour(0xFFFFFF, alpha: 0.52)
        let batonEdgeDark: Color = WWClock.colour(0x000000, alpha: 0.55)
        let batonShadow: Color = WWClock.colour(0x000000, alpha: 0.18)

        // Numerals: metal gradient + visible bevel (emboss).
        let numeralLight: Color = WWClock.colour(0xF3F8FF, alpha: 0.96)
        let numeralMid: Color = WWClock.colour(0xC5D2E6, alpha: 0.94)
        let numeralDark: Color = WWClock.colour(0x6D7E99, alpha: 0.96)
        let numeralInnerHighlight: Color = WWClock.colour(0xFFFFFF, alpha: 0.38)
        let numeralInnerShade: Color = WWClock.colour(0x000000, alpha: 0.38)
        let numeralShadow: Color = WWClock.colour(0x000000, alpha: isDark ? 0.24 : 0.16)

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

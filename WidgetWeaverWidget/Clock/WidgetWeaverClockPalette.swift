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

    // Bezel
    let bezelBright: Color
    let bezelMid: Color
    let bezelDark: Color
    let bezelOcclusion: Color

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
            case .classic:
                return WWClock.colour(0x43A7D8)
            case .ocean:
                return WWClock.colour(0x4FA9FF)
            case .mint:
                return WWClock.colour(0x4BE3B4)
            case .orchid:
                return WWClock.colour(0xB08CFF)
            case .sunset:
                return WWClock.colour(0xFF9F4E)
            case .ember:
                return WWClock.colour(0xFF4D4A)
            case .graphite:
                return WWClock.colour(0x9FB2CC)
            }
        }()

        // Widget background (outside dial)
        let backgroundTop: Color = isDark ? WWClock.colour(0x141A22) : WWClock.colour(0xECF1F8)
        let backgroundBottom: Color = isDark ? WWClock.colour(0x0B0F15) : WWClock.colour(0xC7D2E5)

        // Bezel: increase value range so it reads as metal.
        let bezelBright: Color = WWClock.colour(0xFAFCFF, alpha: 0.95)
        let bezelMid: Color = WWClock.colour(0xB9C6D8, alpha: 0.92)
        let bezelDark: Color = WWClock.colour(0x4E5B6C, alpha: 0.95)
        let bezelOcclusion: Color = WWClock.colour(0x000000, alpha: isDark ? 0.78 : 0.55)

        // Separator ring: slightly stronger than before.
        let separatorRing: Color = WWClock.colour(0x0B0F15, alpha: 1.0)

        // Dial: near-black, controlled highlight + vignette.
        let dialCenter: Color = WWClock.colour(0x0C121A, alpha: 1.0)
        let dialMid: Color = WWClock.colour(0x05070B, alpha: 1.0)
        let dialEdge: Color = WWClock.colour(0x010203, alpha: 1.0)
        let dialVignette: Color = WWClock.colour(0x000000, alpha: 0.62)
        let dialDomeHighlight: Color = WWClock.colour(0xFFFFFF, alpha: 0.055)

        // Minute dots: uniform, slightly higher opacity.
        let minuteDot: Color = WWClock.colour(0xC4D0E0, alpha: 0.56)

        // Batons: stronger bevel range.
        let batonBright: Color = WWClock.colour(0xF2F7FF, alpha: 0.92)
        let batonMid: Color = WWClock.colour(0xC1CEE0, alpha: 0.88)
        let batonDark: Color = WWClock.colour(0x55667D, alpha: 0.96)
        let batonEdgeLight: Color = WWClock.colour(0xFFFFFF, alpha: 0.46)
        let batonEdgeDark: Color = WWClock.colour(0x000000, alpha: 0.46)
        let batonShadow: Color = WWClock.colour(0x000000, alpha: 0.22)

        // Numerals: brighten substantially (silver-grey), crisp emboss.
        let numeralLight: Color = WWClock.colour(0xF0F6FF, alpha: 0.86)
        let numeralMid: Color = WWClock.colour(0xC1CEE0, alpha: 0.84)
        let numeralDark: Color = WWClock.colour(0x7B8EA8, alpha: 0.86)
        let numeralInnerHighlight: Color = WWClock.colour(0xFFFFFF, alpha: 0.26)
        let numeralInnerShade: Color = WWClock.colour(0x000000, alpha: 0.36)
        let numeralShadow: Color = WWClock.colour(0x000000, alpha: isDark ? 0.28 : 0.18)

        // Hands: separate clearly from dial.
        let handLight: Color = WWClock.colour(0xEEF5FF, alpha: 0.92)
        let handMid: Color = WWClock.colour(0xC0CEE0, alpha: 0.88)
        let handDark: Color = WWClock.colour(0x46566D, alpha: 0.96)
        let handEdge: Color = WWClock.colour(0x000000, alpha: 0.20)
        let handShadow: Color = WWClock.colour(0x000000, alpha: isDark ? 0.55 : 0.28)

        // Hub: simple layered metal.
        let hubBase: Color = WWClock.colour(0x121A24, alpha: 1.0)
        let hubCapLight: Color = WWClock.colour(0xFAFCFF, alpha: 0.92)
        let hubCapMid: Color = WWClock.colour(0xC0CEE0, alpha: 0.88)
        let hubCapDark: Color = WWClock.colour(0x4C5A6C, alpha: 0.95)
        let hubShadow: Color = WWClock.colour(0x000000, alpha: isDark ? 0.60 : 0.30)

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

//
//  WidgetWeaverClockSegmentedCentreHubView.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI

/// Centre hub used by the Segmented clock face.
///
/// Matches the mock's stacked-disc look:
/// - Dark base disc with a tight shadow.
/// - Subtle inner ring highlight.
/// - Lighter cap disc with a specular highlight.
struct WidgetWeaverClockSegmentedCentreHubView: View {
    let palette: WidgetWeaverClockPalette
    let baseRadius: CGFloat
    let capRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let baseD = baseRadius * 2.0
        let capD = capRadius * 2.0

        let baseShadowRadius = WWClock.pixel(
            WWClock.clamp(baseRadius * 0.20, min: px * 0.70, max: baseRadius * 0.32),
            scale: scale
        )
        let baseShadowX = WWClock.pixel(WWClock.clamp(baseRadius * 0.10, min: 0.0, max: baseRadius * 0.18), scale: scale)
        let baseShadowY = WWClock.pixel(WWClock.clamp(baseRadius * 0.14, min: 0.0, max: baseRadius * 0.22), scale: scale)

        let ringWidth = WWClock.pixel(
            WWClock.clamp(baseRadius * 0.22, min: px, max: baseRadius * 0.36),
            scale: scale
        )
        let ringInset = WWClock.pixel(
            WWClock.clamp(baseRadius * 0.22, min: px * 0.50, max: baseRadius * 0.34),
            scale: scale
        )

        let capShadowRadius = WWClock.pixel(
            WWClock.clamp(capRadius * 0.12, min: px * 0.70, max: capRadius * 0.22),
            scale: scale
        )
        let capShadowOffset = WWClock.pixel(max(0.0, capRadius * 0.06), scale: scale)

        let capHighlightBlur = WWClock.pixel(
            WWClock.clamp(capRadius * 0.10, min: px * 0.60, max: capRadius * 0.16),
            scale: scale
        )

        let baseFill = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: palette.hubBase.opacity(0.90), location: 0.00),
                .init(color: palette.hubBase.opacity(1.00), location: 0.64),
                .init(color: Color.black.opacity(0.92), location: 1.00)
            ]),
            center: .topLeading,
            startRadius: 0,
            endRadius: baseRadius * 1.35
        )

        let ringHighlight = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.18), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.46),
                .init(color: Color.black.opacity(0.22), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let capFill = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: palette.hubCapLight.opacity(0.96), location: 0.00),
                .init(color: palette.hubCapMid.opacity(0.92), location: 0.58),
                .init(color: palette.hubCapDark.opacity(0.96), location: 1.00)
            ]),
            center: .topLeading,
            startRadius: 0,
            endRadius: capRadius * 1.20
        )

        ZStack {
            // Base disc.
            Circle()
                .fill(baseFill)
                .frame(width: baseD, height: baseD)
                .shadow(color: palette.hubShadow.opacity(0.85), radius: baseShadowRadius, x: baseShadowX, y: baseShadowY)
                .overlay(
                    // Subtle inner ring highlight to separate the stack.
                    Circle()
                        .strokeBorder(ringHighlight, lineWidth: ringWidth)
                        .frame(width: max(0.0, baseD - (ringInset * 2.0)), height: max(0.0, baseD - (ringInset * 2.0)))
                        .blendMode(.overlay)
                        .opacity(0.85)
                )
                .overlay(
                    // Crisp outer edge so the base does not bloom at small sizes.
                    Circle()
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: max(px, baseRadius * 0.06))
                        .blendMode(.screen)
                )

            // Cap disc.
            Circle()
                .fill(capFill)
                .frame(width: capD, height: capD)
                .shadow(color: Color.black.opacity(0.22), radius: capShadowRadius, x: capShadowOffset, y: capShadowOffset)
                .overlay(
                    // Tight specular highlight (upper-left bias).
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: capD * 0.46, height: capD * 0.46)
                        .offset(x: -capRadius * 0.18, y: -capRadius * 0.22)
                        .blur(radius: capHighlightBlur)
                        .blendMode(.screen)
                )
                .overlay(
                    // Rim highlight to keep the cap edge readable.
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: max(px, capRadius * 0.07))
                        .blendMode(.overlay)
                        .opacity(0.70)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

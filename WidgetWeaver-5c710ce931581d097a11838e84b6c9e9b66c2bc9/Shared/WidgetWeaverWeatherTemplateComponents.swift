//
//  WidgetWeaverWeatherTemplateComponents.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  UI components for the weather template.
//
//  NOTE ABOUT MINUTE-BY-MINUTE CONSISTENCY
//  --------------------------------------
//  The chart must not invent “wet” pixels when the nowcast model says it is dry.
//  Rendering must be driven by `WeatherNowcast.isWet(...)` to keep the chart aligned
//  with the headline text as the widget ticks every minute.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Render context environment

private struct WidgetWeaverRenderContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: WidgetWeaverRenderContext = .preview
}

extension EnvironmentValues {
    var wwRenderContext: WidgetWeaverRenderContext {
        get { self[WidgetWeaverRenderContextEnvironmentKey.self] }
        set { self[WidgetWeaverRenderContextEnvironmentKey.self] = newValue }
    }
}

// MARK: - Widget-safe “glass” background
//
// WidgetKit can render Material as black on the Home Screen (especially after snapshotting).
// This view uses a stable translucent fill for `.widget` and keeps Material for previews.

struct WeatherGlassBackground: View {
    let cornerRadius: CGFloat

    @Environment(\.wwRenderContext) private var renderContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch renderContext {
        case .widget:
            shape.fill(fallbackFill)
        case .preview, .simulator:
            shape.fill(.ultraThinMaterial)
        }
    }

    private var fallbackFill: Color {
        // Light mode: a little dark tint.
        // Dark mode: a little light tint.
        if colorScheme == .dark {
            return Color.white.opacity(0.11)
        } else {
            return Color.black.opacity(0.07)
        }
    }
}

// MARK: - Building Blocks

struct WeatherGlassContainer<Content: View>: View {
    let metrics: WeatherMetrics
    let content: () -> Content

    init(metrics: WeatherMetrics, @ViewBuilder content: @escaping () -> Content) {
        self.metrics = metrics
        self.content = content
    }

    var body: some View {
        content()
            .padding(metrics.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                WeatherGlassBackground(cornerRadius: metrics.containerCornerRadius)
            }
            .overlay {
                RoundedRectangle(cornerRadius: metrics.containerCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .compositingGroup()
    }
}

struct WeatherSectionCard<Content: View>: View {
    let metrics: WeatherMetrics
    let content: () -> Content

    init(metrics: WeatherMetrics, @ViewBuilder content: @escaping () -> Content) {
        self.metrics = metrics
        self.content = content
    }

    var body: some View {
        content()
            .padding(metrics.sectionPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                Color.black.opacity(0.16),
                in: RoundedRectangle(cornerRadius: metrics.sectionCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.sectionCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct WeatherAttributionLink: View {
    let accent: Color

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared
        if let url = store.attributionLegalURL() {
            Link(destination: url) {
                // Removes the redundant info icon and stays out of the “Now” axis label area.
                Text("Weather")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.18), in: Capsule())
            }
            .accessibilityLabel("Apple Weather attribution")
        }
    }
}

// MARK: - Metrics

struct WeatherMetrics {
    let family: WidgetFamily
    let style: StyleSpec
    let layout: LayoutSpec

    var scale: CGFloat {
        max(0.85, min(1.35, CGFloat(style.weatherScale)))
    }

    var contentPadding: CGFloat {
        let base = CGFloat(style.padding)
        let familyMultiplier: CGFloat
        switch family {
        case .systemSmall:
            familyMultiplier = 0.85
        case .systemMedium:
            familyMultiplier = 0.90
        default:
            familyMultiplier = 1.00
        }
        return max(10, min(18, base * familyMultiplier)) * scale
    }

    var containerCornerRadius: CGFloat {
        max(14, min(26, CGFloat(style.cornerRadius)))
    }

    var sectionCornerRadius: CGFloat {
        max(12, min(22, CGFloat(style.cornerRadius) - 4))
    }

    var sectionPadding: CGFloat {
        max(10, min(16, CGFloat(style.padding) * 0.75)) * scale
    }

    var sectionSpacing: CGFloat {
        max(8, min(14, CGFloat(layout.spacing))) * scale
    }

    // Font sizes
    var locationFontSize: CGFloat { 12 * scale }
    var locationFontSizeLarge: CGFloat { 13 * scale }

    var nowcastPrimaryFontSizeSmall: CGFloat { 16 * scale }
    var nowcastPrimaryFontSizeMedium: CGFloat { 18 * scale }
    var nowcastPrimaryFontSizeLarge: CGFloat { 20 * scale }

    var detailsFontSize: CGFloat { 12 * scale }
    var detailsFontSizeLarge: CGFloat { 13 * scale }

    var updatedFontSize: CGFloat { 11 * scale }

    var temperatureFontSizeSmall: CGFloat { 28 * scale }
    var temperatureFontSizeMedium: CGFloat { 30 * scale }
    var temperatureFontSizeLarge: CGFloat { 34 * scale }

    var sectionTitleFontSize: CGFloat { 12 * scale }

    // Chart heights
    var nowcastChartHeightSmall: CGFloat { 54 * scale }
    var nowcastChartHeightMedium: CGFloat { 62 * scale }
    var nowcastChartHeightLarge: CGFloat { 92 * scale }

    // Hourly strip
    var hourlyStripFontSize: CGFloat { 11 * scale }
    var hourlyStripFontSizeLarge: CGFloat { 12 * scale }
}

// MARK: - Background

struct WeatherPalette: Hashable {
    let top: Color
    let bottom: Color
    let glow: Color
    let rainAccent: Color

    static func fallback(accent: Color) -> WeatherPalette {
        WeatherPalette(
            top: Color.black.opacity(0.55),
            bottom: Color.black.opacity(0.75),
            glow: accent.opacity(0.25),
            rainAccent: accent
        )
    }

    static func forSnapshot(_ snapshot: WidgetWeaverWeatherSnapshot, now: Date, accent: Color) -> WeatherPalette {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)
        let hasRain =
            (nowcast.peakIntensityMMPerHour >= WeatherNowcast.wetIntensityThresholdMMPerHour) ||
            ((nowcast.startOffsetMinutes ?? 999) <= 60)

        if hasRain {
            return WeatherPalette(
                top: Color.black.opacity(0.40),
                bottom: Color.black.opacity(0.78),
                glow: accent.opacity(0.35),
                rainAccent: accent
            )
        }

        return WeatherPalette(
            top: Color.black.opacity(0.45),
            bottom: Color.black.opacity(0.82),
            glow: Color.white.opacity(0.08),
            rainAccent: accent
        )
    }
}

struct WeatherBackdropView: View {
    let palette: WeatherPalette
    let family: WidgetFamily

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(palette.glow)
                .frame(width: glowSize, height: glowSize)
                .blur(radius: glowBlur)
                .offset(x: glowOffsetX, y: glowOffsetY)
        }
        .ignoresSafeArea()
    }

    private var glowSize: CGFloat {
        switch family {
        case .systemSmall: return 110
        case .systemMedium: return 150
        default: return 220
        }
    }

    private var glowBlur: CGFloat {
        switch family {
        case .systemSmall: return 28
        case .systemMedium: return 34
        default: return 44
        }
    }

    private var glowOffsetX: CGFloat {
        switch family {
        case .systemSmall: return 45
        case .systemMedium: return 85
        default: return 110
        }
    }

    private var glowOffsetY: CGFloat {
        switch family {
        case .systemSmall: return -30
        case .systemMedium: return -46
        default: return -65
        }
    }
}

// MARK: - Colour blending helpers

private extension Color {
    func wwBlended(with other: Color, amount: CGFloat) -> Color {
        let t = max(0, min(1, amount))
        guard t > 0 else { return self }
        guard let a = wwRGBA(), let b = other.wwRGBA() else { return self }

        let r = a.r + (b.r - a.r) * t
        let g = a.g + (b.g - a.g) * t
        let bl = a.b + (b.b - a.b) * t
        let al = a.a + (b.a - a.a) * t

        return Color(red: Double(r), green: Double(g), blue: Double(bl), opacity: Double(al))
    }

    func wwRGBA() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (r, g, b, a)
        }

        if let cs = CGColorSpace(name: CGColorSpace.sRGB),
           let cg = ui.cgColor.converted(to: cs, intent: .defaultIntent, options: nil),
           let comps = cg.components
        {
            if comps.count >= 4 { return (comps[0], comps[1], comps[2], comps[3]) }
            if comps.count == 2 { return (comps[0], comps[0], comps[0], comps[1]) }
        }
        return nil
        #elseif canImport(AppKit)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return nil }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
        #else
        return nil
        #endif
    }
}

//
//  WidgetWeaverSpecView.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit

public enum WidgetWeaverRenderContext: String, Codable, Sendable {
    case widget
    case preview
    case simulator
}

public struct WidgetWeaverSpecView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily
    public let context: WidgetWeaverRenderContext

    @AppStorage(WidgetWeaverWeatherStore.Keys.snapshotData, store: AppGroup.userDefaults)
    private var weatherSnapshotData: Data = Data()

    @AppStorage(WidgetWeaverWeatherStore.Keys.attributionData, store: AppGroup.userDefaults)
    private var weatherAttributionData: Data = Data()

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        let _ = weatherSnapshotData
        let _ = weatherAttributionData

        let resolved = spec.resolved(for: family).resolvingVariables()
        let style = resolved.style
        let layout = resolved.layout
        let accent = style.accent.swiftUIColor
        let frameAlignment: Alignment = layout.alignment.swiftUIAlignment

        ZStack(alignment: .topLeading) {
            backgroundView(spec: resolved, layout: layout, style: style, accent: accent)

            VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
                switch layout.template {
                case .classic:
                    classicTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                case .hero:
                    heroTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                case .poster:
                    posterTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                case .weather:
                    weatherTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                case .nextUpCalendar:
                    nextUpCalendarTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                }
            }
            .padding(layout.template == .poster || layout.template == .weather ? 0 : style.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        }
        .modifier(
            WidgetWeaverBackgroundModifier(
                cornerRadius: layout.template == .poster ? 0 : style.cornerRadius,
                family: family,
                context: context
            )
        )
    }

    // MARK: - Templates

    private func classicTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)
            contentStackClassic(spec: spec, layout: layout, style: style)
            if let symbol = spec.symbol {
                imageRowClassic(symbol: symbol, style: style, accent: accent)
            }
            if layout.showsAccentBar {
                accentBar(accent: accent, style: style)
            }
        }
    }

    private func heroTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)
            HStack(alignment: .top, spacing: layout.spacing) {
                VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
                    contentStackHero(spec: spec, layout: layout, style: style)
                    if layout.showsAccentBar {
                        accentBar(accent: accent, style: style)
                    }
                }

                if let symbol = spec.symbol {
                    Image(systemName: symbol.name)
                        .font(.system(size: style.symbolSize))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(0.85)
                }
            }
        }
        .padding(style.padding)
    }

    private func posterTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                if !spec.name.isEmpty {
                    Text(spec.name)
                        .font(style.nameTextStyle.font(fallback: .caption))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }

                if !spec.primaryText.isEmpty {
                    Text(spec.primaryText)
                        .font(style.primaryTextStyle.font(fallback: .title3))
                        .foregroundStyle(.white)
                        .lineLimit(layout.primaryLineLimit)
                }

                if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(style.secondaryTextStyle.font(fallback: .caption2))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(layout.secondaryLineLimit)
                }
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.10),
                        Color.clear,
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
    }

    private func weatherTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        WeatherTemplateView(
            spec: spec,
            family: family,
            context: context,
            accent: accent
        )
    }

    private func nextUpCalendarTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        NextUpCalendarTemplateView(
            spec: spec,
            family: family,
            context: context,
            accent: accent
        )
    }

    // MARK: - Building Blocks

    private func headerRow(spec: WidgetSpec, style: StyleSpec, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if !spec.name.isEmpty {
                Text(spec.name)
                    .font(style.nameTextStyle.font(fallback: .caption))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func contentStackClassic(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: 6) {
            if !spec.primaryText.isEmpty {
                Text(spec.primaryText)
                    .font(style.primaryTextStyle.font(fallback: .title3))
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)
            }
            if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? layout.secondaryLineLimitSmall : layout.secondaryLineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top))
    }

    private func contentStackHero(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: 6) {
            if !spec.primaryText.isEmpty {
                Text(spec.primaryText)
                    .font(style.primaryTextStyle.font(fallback: .title3))
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)
            }
            if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(style.secondaryTextStyle.font)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? layout.secondaryLineLimitSmall : layout.secondaryLineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top))
    }

    private func imageRowClassic(symbol: WidgetSymbol, style: StyleSpec, accent: Color) -> some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: symbol.name)
                .font(.system(size: style.symbolSize))
                .foregroundStyle(accent)
                .opacity(0.85)
        }
    }

    private func accentBar(accent: Color, style: StyleSpec) -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(accent)
            .frame(height: 5)
            .opacity(0.9)
    }

    // MARK: - Background

    private func backgroundView(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        ZStack {
            Color(uiColor: .systemBackground)

            if layout.template == .weather {
                Color.clear
            } else if layout.template == .poster,
                      let image = spec.image,
                      let uiImage = image.loadUIImageFromAppGroup() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)
            } else {
                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)

                backgroundEffects(style: style, accent: accent)
            }
        }
    }

    private func backgroundEffects(style: StyleSpec, accent: Color) -> some View {
        ZStack {
            if style.backgroundGlowEnabled {
                Circle()
                    .fill(accent)
                    .blur(radius: 70)
                    .opacity(0.18)
                    .offset(x: -120, y: -120)

                Circle()
                    .fill(accent)
                    .blur(radius: 90)
                    .opacity(0.12)
                    .offset(x: 140, y: 160)
            }
        }
    }
}

// MARK: - Background Modifier

private struct WidgetWeaverBackgroundModifier: ViewModifier {
    let cornerRadius: Double
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    func body(content: Content) -> some View {
        // iOS controls the outer widget mask.
        // Widget designs cannot change the widget’s shape.
        // The preview uses a stable approximation for the outer mask so sliders do not appear
        // to change the widget’s outer corners.

        let outerCornerRadius = Self.systemWidgetCornerRadius()

        switch context {
        case .widget:
            content
                .containerBackground(for: .widget) { Color.clear }
                .clipShape(ContainerRelativeShape())

        case .preview, .simulator:
            content
                .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        }
    }

    private static func systemWidgetCornerRadius() -> CGFloat {
        // The system widget corner radius is not exposed publicly.
        // Values are tuned to look close to iOS on iPhone and iPad.
        if UIDevice.current.userInterfaceIdiom == .pad { return 24 }
        return 22
    }
}

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
import AppIntents

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

    // Forces a re-render when the saved spec store changes (so Home Screen widgets update).
    @AppStorage("widgetweaver.specs.v1", store: AppGroup.userDefaults)
    private var specsData: Data = Data()

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        let _ = weatherSnapshotData
        let _ = weatherAttributionData
        let _ = specsData

        let baseSpec: WidgetSpec = {
            guard context == .widget else { return spec }
            // Prefer the latest saved version of the same design ID when rendering in WidgetKit.
            // This prevents stale timeline entries from keeping an old design on the Home Screen.
            return WidgetSpecStore.shared.load(id: spec.id) ?? spec
        }()

        let resolved = baseSpec.resolved(for: family).resolvingVariables()
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

            actionBarIfNeeded(spec: spec, accent: accent)

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

            actionBarIfNeeded(spec: spec, accent: accent)
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
        .frame(
            maxWidth: .infinity,
            alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top)
        )
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
        .frame(
            maxWidth: .infinity,
            alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top)
        )
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

    // MARK: - Quick Actions (interactive widget buttons)

    private func actionBarIfNeeded(spec: WidgetSpec, accent: Color) -> some View {
        Group {
            if WidgetWeaverEntitlements.isProUnlocked,
               let bar = spec.actionBar,
               !bar.actions.isEmpty {
                actionBar(bar: bar, accent: accent)
                    .allowsHitTesting(context == .widget)
                    .opacity(context == .widget ? 1.0 : 0.85)
            }
        }
    }

    private func actionBar(bar: WidgetActionBarSpec, accent: Color) -> some View {
        HStack(spacing: 10) {
            ForEach(bar.actions) { action in
                widgetActionButton(action: action, barStyle: bar.style, accent: accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func widgetActionButton(action: WidgetActionSpec, barStyle: WidgetActionButtonStyleToken, accent: Color) -> some View {
        switch action.kind {
        case .incrementVariable:
            Button(intent: WidgetWeaverIncrementVariableIntent(key: action.variableKey, amount: action.incrementAmount)) {
                actionButtonLabel(action: action, barStyle: barStyle, accent: accent)
            }
            .buttonStyle(.plain)

        case .setVariableToNow:
            Button(intent: WidgetWeaverSetVariableToNowIntent(key: action.variableKey, format: mapNowFormat(action.nowFormat))) {
                actionButtonLabel(action: action, barStyle: barStyle, accent: accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func mapNowFormat(_ token: WidgetNowFormatToken) -> WidgetWeaverNowValueFormat {
        switch token {
        case .iso8601:
            return .iso8601
        case .unixSeconds:
            return .unixSeconds
        case .unixMilliseconds:
            return .unixSeconds
        case .dateOnly:
            return .dateOnly
        case .timeOnly:
            return .timeOnly
        }
    }

    private func actionButtonLabel(action: WidgetActionSpec, barStyle: WidgetActionButtonStyleToken, accent: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let backgroundOpacity: Double = (barStyle == .prominent) ? 0.20 : 0.12
        let borderOpacity: Double = (barStyle == .prominent) ? 0.30 : 0.16
        let minHeight: CGFloat = 44

        return HStack(spacing: 8) {
            if let systemImage = action.systemImage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !systemImage.isEmpty {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(action.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 12)
        .background { shape.fill(accent.opacity(backgroundOpacity)) }
        .overlay { shape.strokeBorder(accent.opacity(borderOpacity), lineWidth: 1) }
        .contentShape(shape)
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

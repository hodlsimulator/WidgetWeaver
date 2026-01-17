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

    @AppStorage(WidgetWeaverRemindersStore.Keys.snapshotData, store: AppGroup.userDefaults)
    private var remindersSnapshotData: Data = Data()

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastUpdatedAt, store: AppGroup.userDefaults)
    private var remindersLastUpdatedAt: Double = 0

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastErrorKind, store: AppGroup.userDefaults)
    private var remindersLastErrorKind: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastErrorMessage, store: AppGroup.userDefaults)
    private var remindersLastErrorMessage: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastErrorAt, store: AppGroup.userDefaults)
    private var remindersLastErrorAt: Double = 0

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastActionKind, store: AppGroup.userDefaults)
    private var remindersLastActionKind: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastActionMessage, store: AppGroup.userDefaults)
    private var remindersLastActionMessage: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastActionAt, store: AppGroup.userDefaults)
    private var remindersLastActionAt: Double = 0


    // Forces a re-render when the saved spec store changes (so Home Screen widgets update).
    @AppStorage("widgetweaver.specs.v1", store: AppGroup.userDefaults)
    private var specsData: Data = Data()

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        // Touch AppStorage so WidgetKit redraws when these change.
        let _ = weatherSnapshotData
        let _ = weatherAttributionData
        let _ = specsData
        let _ = remindersSnapshotData
        let _ = remindersLastUpdatedAt
        let _ = remindersLastErrorKind
        let _ = remindersLastErrorMessage
        let _ = remindersLastErrorAt
        let _ = remindersLastActionKind
        let _ = remindersLastActionMessage
        let _ = remindersLastActionAt

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

        let background = backgroundView(spec: resolved, layout: layout, style: style, accent: accent)

        return VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
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
            case .reminders:
                WidgetWeaverRemindersTemplateView(spec: resolved, family: family, context: context, layout: layout, style: style, accent: accent)
            case .clockIcon:
                clockIconTemplatePlaceholder(spec: resolved, layout: layout, style: style, accent: accent)
            }
        }
        .padding(layout.template == .poster || layout.template == .weather ? 0 : style.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        .modifier(
            WidgetWeaverBackgroundModifier(
                family: family,
                context: context,
                background: background
            )
        )
    }

    // MARK: - Templates

    private func classicTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)
            contentStackClassic(spec: spec, layout: layout, style: style, accent: accent)

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
                    contentStackHero(spec: spec, layout: layout, style: style, accent: accent)

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

    @ViewBuilder
    private func posterTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        switch layout.posterOverlayMode {
        case .none:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .caption:
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

    private func clockIconTemplatePlaceholder(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let stroke = max(2, side * 0.05)

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))

                Circle()
                    .strokeBorder(accent.opacity(0.70), lineWidth: stroke)

                // Hour hand (placeholder geometry).
                RoundedRectangle(cornerRadius: max(1, side * 0.02), style: .continuous)
                    .fill(accent.opacity(0.90))
                    .frame(width: max(2, side * 0.05), height: side * 0.24)
                    .offset(y: -side * 0.12)
                    .rotationEffect(.degrees(-65))

                // Minute hand (placeholder geometry).
                RoundedRectangle(cornerRadius: max(1, side * 0.02), style: .continuous)
                    .fill(accent.opacity(0.80))
                    .frame(width: max(2, side * 0.04), height: side * 0.34)
                    .offset(y: -side * 0.17)
                    .rotationEffect(.degrees(18))

                Circle()
                    .fill(accent)
                    .frame(width: side * 0.09, height: side * 0.09)

                Text("Clock (Placeholder)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, side * 0.85)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

}

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

    @Environment(\.colorScheme)
    private var colorScheme

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

        // Widgets are clipped to the system container shape.
        // The main widget disables the system's default content margins (`.contentMarginsDisabled()`),
        // so a design can legitimately request 0 padding.
        //
        // Some content (notably the Reminders template's header + footer) sits flush against the
        // container mask when padding is small and can look uncomfortably tight or even get clipped.
        //
        // Respect the user's configured padding, but enforce a small per-template minimum so text
        // never touches the outer mask.
        let needsOuterPadding = (layout.template != .poster && layout.template != .weather)

        let minimumSafePadding: Double = {
            guard needsOuterPadding else { return 0 }
            switch layout.template {
            case .reminders:
                // The Reminders template has a header at the very top and an optional status line
                // at the very bottom; it needs a larger minimum to avoid top/bottom clipping.
                return 10
            default:
                return 2
            }
        }()

        let resolvedPadding = needsOuterPadding ? max(minimumSafePadding, style.padding) : 0.0
        let horizontalPadding = resolvedPadding
        let verticalPadding = resolvedPadding

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
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
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
        let theme = (spec.clockConfig?.theme ?? WidgetWeaverClockDesignConfig.defaultTheme)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let scheme: WidgetWeaverClockColourScheme = {
            switch theme {
            case "ocean":
                return .ocean
            case "graphite":
                return .graphite
            default:
                return .classic
            }
        }()

        let palette = WidgetWeaverClockPalette.resolve(scheme: scheme, mode: colorScheme)

        let label: String? = {
            guard context == .preview else { return nil }

            switch scheme {
            case .ocean:
                return "Ocean"
            case .graphite:
                return "Graphite"
            default:
                return "Classic"
            }
        }()

        let showsSecondsHand = (context == .simulator)

        return GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            let now = WidgetWeaverRenderClock.now
            let cal = Calendar.autoupdatingCurrent
            let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: now)

            let hour = Double((comps.hour ?? 0) % 12)
            let minute = Double(comps.minute ?? 0)
            let second = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000.0

            let hourAngle = Angle.degrees((hour + (minute / 60.0) + (second / 3600.0)) / 12.0 * 360.0)
            let minuteAngle = Angle.degrees((minute + (second / 60.0)) / 60.0 * 360.0)
            let secondAngle = Angle.degrees(second / 60.0 * 360.0)

            ZStack(alignment: .bottom) {
                ZStack {
                    WidgetWeaverClockBackgroundView(palette: palette)

                    WidgetWeaverClockIconView(
                        palette: palette,
                        hourAngle: hourAngle,
                        minuteAngle: minuteAngle,
                        secondAngle: secondAngle,
                        showsSecondHand: showsSecondsHand,
                        showsMinuteHand: true,
                        showsHandShadows: true,
                        showsGlows: true,
                        showsCentreHub: true,
                        handsOpacity: 1.0
                    )
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if let label {
                    Text("Clock • \(label)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, max(6, side * 0.04))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

}

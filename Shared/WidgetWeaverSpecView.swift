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
    public let renderDate: Date

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

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext, now: Date = Date()) {
        self.spec = spec
        self.family = family
        self.context = context
        self.renderDate = now
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

        let familySpec = baseSpec.resolved(for: family)
        let resolved = familySpec.resolvingVariables(now: renderDate)
        let style = resolved.style
        let layout = resolved.layout
        let accent = style.accent.swiftUIColor
        let frameAlignment: Alignment = layout.alignment.swiftUIAlignment

        let background = backgroundView(spec: resolved, layout: layout, style: style, accent: accent)

        // Widgets are clipped to the system container shape.
        // The main widget disables the system's default content margins (`.contentMarginsDisabled()`),
        // so a design can legitimately request 0 padding.
        //
        // Respect the user's configured padding, but enforce a small per-template minimum so text
        // never touches the outer mask.
        let needsOuterPadding = (layout.template != .poster && layout.template != .weather)

        let minimumSafePadding: Double = {
            guard needsOuterPadding else { return 0 }

            switch layout.template {
            case .reminders:
                // Lists mode in medium can feel especially tight (header + footer sit near the
                // system mask). Clamp to the app's default padding so it matches the other
                // Reminders widgets even when a design's padding slider is set lower.
                let mode = (resolved.remindersConfig?.mode ?? .today)
                if family == .systemMedium && mode == .list {
                    return 16
                }

                // General Reminders safety padding.
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
                posterTemplate(templateSpec: familySpec, spec: resolved, layout: layout, style: style, accent: accent)
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
    private func posterTemplate(templateSpec: WidgetSpec, spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        switch layout.posterOverlayMode {
        case .none:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .caption:
            WidgetWeaverPosterCaptionOverlayView(
                templateSpec: templateSpec,
                staticSpec: spec,
                entryDate: renderDate,
                family: family,
                context: context,
                layout: layout,
                style: style
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let clockConfig = (spec.clockConfig ?? WidgetWeaverClockDesignConfig.default).normalised()
        let appearance = WidgetWeaverClockAppearanceResolver.resolve(config: clockConfig, mode: colorScheme)
        let palette = appearance.palette

        let label: String? = {
            guard context == .preview else { return nil }

            return appearance.schemeDisplayName
        }()

        let showsSecondsHand = (context == .simulator)

        return GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            let now = renderDate
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

                    WidgetWeaverClockFaceView(
                        face: clockConfig.faceToken,
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

// MARK: - Poster caption overlay (time-dependent)

/// Poster caption overlay that can tick at minute granularity.
///
/// Photo-based posters (e.g. Photo Clock) are expensive to re-render every minute because WidgetKit
/// would repeatedly decode the poster image. This view keeps the *text* fresh via a lightweight
/// view-level heartbeat while leaving the photo background untouched.
private struct WidgetWeaverPosterCaptionOverlayView: View {
    @Environment(\.wwLowGraphicsBudget)
    private var lowGraphicsBudget

    /// The poster spec with variable templates intact.
    ///
    /// This should be resolved for the target family (matched sets dropped) but NOT have variables applied.
    let templateSpec: WidgetSpec

    /// The spec resolved for the target family and with variables applied using the widget entry date.
    ///
    /// Used for WidgetKit pre-render/snapshot contexts where live ticking is undesirable.
    let staticSpec: WidgetSpec

    /// The widget entry's date (pinned to the timeline entry when available).
    ///
    /// Used as a stable lower bound when ticking live so WidgetKit pre-rendered future
    /// entries remain distinct.
    let entryDate: Date

    let family: WidgetFamily
    let context: WidgetWeaverRenderContext
    let layout: LayoutSpec
    let style: StyleSpec

    var body: some View {
        tickingOverlay
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tickingOverlay: some View {
        switch context {
        case .widget:
            // WidgetKit: opt in to a lightweight view-level heartbeat in the final rendered view,
            // but keep pre-rendered snapshots deterministic.
            //
            // Approach:
            // - If WidgetKit is pre-rendering a future timeline entry, treat `entryDate` as the "now"
            //   and do not tick.
            // - Otherwise, tick at minute granularity, with `entryDate` as a lower bound so each
            //   timeline entry remains distinct.
            //
            // Implementation detail:
            // - Use a hidden `ProgressView(timerInterval:)` as the minute heartbeat. This avoids
            //   triggering body recomputation every second.
            //
            // This forces SwiftUI to re-evaluate the overlay at minute granularity while leaving
            // the (expensive) poster image background untouched.
            let entryNow = Self.floorToMinute(entryDate)

            // Wall clock minute anchor (drives the heartbeat when live).
            let wallNow = Date()
            let wallMinuteAnchor = Self.floorToMinute(wallNow)

            // Pre-render detection: if the entry date is meaningfully ahead of the wall clock,
            // avoid any live heartbeat so snapshots remain deterministic.
            let leadSeconds = entryNow.timeIntervalSince(wallNow)
            let isPrerender = (leadSeconds > 5.0) || (entryNow > wallMinuteAnchor)

            // Live: wall clock (but never earlier than the entry date).
            // Pre-render: pinned entry date.
            let now = isPrerender ? entryNow : maxDate(entryNow, wallMinuteAnchor)
            let minuteID = Int(now.timeIntervalSince1970 / 60.0)

            ZStack(alignment: .topLeading) {
                if !isPrerender {
                    let heartbeatRange = wallMinuteAnchor...wallMinuteAnchor.addingTimeInterval(60.0)
                    ProgressView(timerInterval: heartbeatRange, countsDown: false)
                        .id(wallMinuteAnchor)
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                let dynamicSpec = templateSpec
                    .resolvingVariables(now: now)
                    .normalised()

                overlayBody(spec: dynamicSpec)
                    .id(minuteID)
            }

        case .simulator:
            // Simulator-only: live ticking inside the running app.
            let scheduleStart = WidgetWeaverRenderClock.alignedTimelineStartDate(interval: 60, now: Date())

            TimelineView(.periodic(from: scheduleStart, by: 60)) { timeline in
                let now = Self.floorToMinute(timeline.date)
                let minuteID = Int(now.timeIntervalSinceReferenceDate / 60.0)

                let dynamicSpec = templateSpec
                    .resolvingVariables(now: now)
                    .normalised()

                overlayBody(spec: dynamicSpec)
                    .id(minuteID)
            }

        case .preview:
            overlayBody(spec: staticSpec)
        }
    }



    @ViewBuilder
    private func overlayText(
        resolved: String,
        font: Font,
        foreground: Color,
        lineLimit: Int
    ) -> some View {
        // The resolved string is produced by the widget's variable renderer.
        // For poster clocks, the minute heartbeat in `tickingOverlay` keeps this fresh on the Home Screen.
        Text(resolved)
            .font(font)
            .foregroundStyle(foreground)
            .lineLimit(lineLimit)
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
    }

    private var wantsGlassCaptionStrip: Bool {
        guard !lowGraphicsBudget else { return false }

        // Reuse an existing style knob (no schema change).
        // When the background overlay token is Subtle Material, treat the poster caption overlay as a
        // distinct glass style (a floating frosted card) rather than the default scrim.
        guard style.backgroundOverlay == .subtleMaterial else { return false }

        // Be conservative: only treat this as an opt-in when the full-screen overlay is effectively off.
        // This keeps existing posters stable when Subtle Material is used as a global overlay.
        return style.backgroundOverlayOpacity <= 0.0001
    }

    private var wantsTopAnchoredCaption: Bool {
        // Layout alignment is reused as a poster-only opt-in token (no schema change).
        // Only `top*` values anchor the caption at the top; existing values remain bottom-anchored.
        return layout.alignment.isPosterCaptionTopAligned
    }

    private var captionBackdropStartPoint: UnitPoint {
        wantsTopAnchoredCaption ? .top : .bottom
    }

    private var captionBackdropEndPoint: UnitPoint {
        wantsTopAnchoredCaption ? .bottom : .top
    }

    private var normalBackdropGradientStops: [Gradient.Stop] {
        // Default poster caption treatment: a soft scrim that fades away from the caption edge.
        // This should never look like a hard rectangular panel.
        return [
            .init(color: Color.black.opacity(0.72), location: 0.00),
            .init(color: Color.black.opacity(0.46), location: 0.18),
            .init(color: Color.black.opacity(0.18), location: 0.45),
            .init(color: Color.black.opacity(0.06), location: 0.70),
            .init(color: Color.black.opacity(0.02), location: 0.85),
            .init(color: Color.clear, location: 1.00),
        ]
    }

    @ViewBuilder
    private var posterBackdropScrim: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: normalBackdropGradientStops),
                    startPoint: captionBackdropStartPoint,
                    endPoint: captionBackdropEndPoint
                )
            )
    }

    private var glassCardOuterPadding: Double {
        switch family {
        case .systemSmall:
            return 12
        case .systemMedium:
            return 16
        case .systemLarge:
            return 18
        default:
            return 12
        }
    }

    private var glassCardCornerRadius: Double {
        switch family {
        case .systemSmall:
            return 20
        case .systemMedium:
            return 22
        case .systemLarge:
            return 24
        default:
            return 20
        }
    }

    private var glassCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: glassCardCornerRadius, style: .continuous)
    }

    private var glassCardTintGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.28), location: 0.00),
                .init(color: Color.black.opacity(0.14), location: 0.35),
                .init(color: Color.black.opacity(0.06), location: 0.70),
                .init(color: Color.clear, location: 1.00),
            ]),
            startPoint: captionBackdropStartPoint,
            endPoint: captionBackdropEndPoint
        )
    }

    private var glassCardBackground: some View {
        let shape = glassCardShape

        return shape
            .fill(.thinMaterial)
            .overlay(shape.fill(glassCardTintGradient))
            .overlay(
                shape
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .overlay(
                shape
                    .stroke(Color.black.opacity(0.20), lineWidth: 0.5)
            )
    }

    private func overlayBody(spec: WidgetSpec) -> some View {
        ZStack {
            if !wantsGlassCaptionStrip {
                posterBackdropScrim
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                if wantsTopAnchoredCaption {
                    captionPanel(spec: spec)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    captionPanel(spec: spec)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func captionPanel(spec: WidgetSpec) -> some View {
        Group {
            if wantsGlassCaptionStrip {
                captionContent(spec: spec)
                    .padding(style.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { glassCardBackground }
                    .clipShape(glassCardShape)
                    .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 12)
                    .padding(.horizontal, glassCardOuterPadding)
                    .padding(wantsTopAnchoredCaption ? .top : .bottom, glassCardOuterPadding)
            } else {
                captionContent(spec: spec)
                    .padding(style.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func captionContent(spec: WidgetSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !spec.name.isEmpty {
                Text(spec.name)
                    .font(style.nameTextStyle.font(fallback: .caption))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
            }

            if !spec.primaryText.isEmpty {
                overlayText(
                    resolved: spec.primaryText,
                    font: style.primaryTextStyle.font(fallback: .title3),
                    foreground: .white,
                    lineLimit: layout.primaryLineLimit
                )
            }

            if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                overlayText(
                    resolved: secondaryText,
                    font: style.secondaryTextStyle.font(fallback: .caption2),
                    foreground: .white.opacity(0.85),
                    lineLimit: layout.secondaryLineLimit
                )
            }
        }
    }

    private func maxDate(_ a: Date, _ b: Date) -> Date {
        if a >= b { return a }
        return b
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

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

#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Renderer

public enum WidgetWeaverRenderContext: String, Codable, Hashable {
    case widget
    case preview
    case simulator
}

public struct WidgetWeaverSpecView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily
    public let context: WidgetWeaverRenderContext

    public init(
        spec: WidgetSpec,
        family: WidgetFamily,
        context: WidgetWeaverRenderContext = .widget
    ) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        let resolved = spec
            .resolved(for: family)
            .resolvingVariables()

        let layout = resolved.layout
        let style = resolved.style
        let accent = style.accent.swiftUIColor

        let bg = AnyView(backgroundView(spec: resolved, layout: layout, style: style, accent: accent))

        Group {
            switch layout.template {
            case .classic:
                classicTemplate(spec: resolved, layout: layout, style: style, accent: accent)

            case .hero:
                heroTemplate(spec: resolved, layout: layout, style: style, accent: accent)

            case .poster:
                posterTemplate(spec: resolved, layout: layout, style: style, accent: accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.alignment.swiftUIAlignment)
        .padding(layout.template == .poster ? 0 : style.padding)
        .modifier(
            WidgetWeaverBackgroundModifier(
                context: context,
                backgroundView: bg,
                cornerRadius: style.cornerRadius
            )
        )
    }

    // MARK: - Templates

    @ViewBuilder
    private func classicTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        if layout.axis == .horizontal {
            HStack(alignment: .top, spacing: layout.spacing) {
                accentBar(isHorizontal: true, accent: accent, show: layout.showsAccentBar)
                contentStackClassic(spec: spec, layout: layout, style: style, accent: accent)
            }
        } else {
            VStack(alignment: .leading, spacing: layout.spacing) {
                accentBar(isHorizontal: false, accent: accent, show: layout.showsAccentBar)
                contentStackClassic(spec: spec, layout: layout, style: style, accent: accent)
            }
        }
    }

    @ViewBuilder
    private func heroTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        ZStack(alignment: .topLeading) {
            if let sym = spec.symbol {
                heroWatermark(sym, accent: accent)
            }

            VStack(alignment: .leading, spacing: max(8, layout.spacing)) {
                let trimmedName = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty {
                    Text(trimmedName)
                        .font(style.nameTextStyle.font(fallback: .footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(spec.primaryText)
                    .font(style.primaryTextStyle.font(fallback: heroPrimaryFont()))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(primaryLineLimit(layout: layout))
                    .minimumScaleFactor(0.60)

                if let secondary = spec.secondaryText, !secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(secondary)
                        .font(style.secondaryTextStyle.font(fallback: .footnote))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(layout.secondaryLineLimit)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                actionBar(spec: spec, accent: accent)
            }
            .padding(style.padding)
        }
    }

    @ViewBuilder
    private func posterTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                if spec.symbol != nil || !spec.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        if let sym = spec.symbol {
                            Image(systemName: sym.name)
                                .symbolRenderingMode(sym.renderingMode.swiftUISymbolRenderingMode)
                                .foregroundStyle(sym.tint == .accent ? accent : sym.tint.swiftUIColor)
                                .font(.system(size: 16, weight: sym.weight.swiftUIFontWeight))
                                .accessibilityHidden(true)
                        }

                        let trimmedName = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedName.isEmpty {
                            Text(trimmedName)
                                .font(style.nameTextStyle.font(fallback: .headline))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                }

                Text(spec.primaryText)
                    .font(style.primaryTextStyle.font(fallback: .title2))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(primaryLineLimit(layout: layout))
                    .minimumScaleFactor(0.60)

                if let secondary = spec.secondaryText, !secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(secondary)
                        .font(style.secondaryTextStyle.font(fallback: .footnote))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(layout.secondaryLineLimit)
                        .minimumScaleFactor(0.75)
                }

                actionBar(spec: spec, accent: accent)
            }
            .padding(14)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: max(12, style.cornerRadius * 0.75),
                    style: .continuous
                )
            )
            .padding(style.padding)
        }
    }

    // MARK: - Building Blocks

    private func contentStackClassic(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: layout.spacing) {
            if let img = spec.image {
                bannerImage(img, style: style)
            }

            header(spec: spec, style: style, accent: accent)

            Text(spec.primaryText)
                .font(style.primaryTextStyle.font(fallback: defaultPrimaryFont(for: family)))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(primaryLineLimit(layout: layout))
                .minimumScaleFactor(0.85)

            if let secondary = spec.secondaryText, shouldShowSecondary(layout: layout) {
                Text(secondary)
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(layout.secondaryLineLimit)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)

            actionBar(spec: spec, accent: accent)
        }
    }

    private func header(spec: WidgetSpec, style: StyleSpec, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let sym = spec.symbol, sym.placement == .beforeName {
                symbolView(sym, accent: accent)
            }

            Text(spec.name)
                .font(style.nameTextStyle.font(fallback: .caption2))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .overlay(alignment: .topLeading) {
            if let sym = spec.symbol, sym.placement == .aboveName {
                symbolView(sym, accent: accent)
                    .offset(y: -6)
            }
        }
    }

    private func symbolView(_ sym: SymbolSpec, accent: Color) -> some View {
        Image(systemName: sym.name)
            .symbolRenderingMode(sym.renderingMode.swiftUISymbolRenderingMode)
            .foregroundStyle(sym.tint == .accent ? accent : sym.tint.swiftUIColor)
            .font(.system(size: sym.size, weight: sym.weight.swiftUIFontWeight))
            .accessibilityHidden(true)
    }

    private func bannerImage(_ image: ImageSpec, style: StyleSpec) -> some View {
        let requested = image.height.normalised().clamped(to: 40...240)

        let maxH: Double
        switch family {
        case .systemSmall: maxH = 110
        case .systemMedium: maxH = 130
        case .systemLarge: maxH = 160
        default: maxH = 120
        }

        let h = min(requested, maxH)

        return Group {
            if let uiImage = AppGroup.loadUIImage(fileName: image.fileName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: image.contentMode.swiftUIContentMode)
                    .frame(maxWidth: .infinity)
                    .frame(height: h)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: image.cornerRadius, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func accentBar(isHorizontal: Bool, accent: Color, show: Bool) -> some View {
        if show {
            let barThickness: Double = 4
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.9))
                .frame(
                    width: isHorizontal ? barThickness : nil,
                    height: isHorizontal ? nil : barThickness
                )
                .padding(.top, isHorizontal ? 0 : 2)
        }
    }

    private func heroWatermark(_ sym: SymbolSpec, accent: Color) -> some View {
        let size: CGFloat
        switch family {
        case .systemSmall: size = 92
        case .systemMedium: size = 120
        case .systemLarge: size = 160
        default: size = 120
        }

        return Image(systemName: sym.name)
            .font(.system(size: size, weight: .heavy))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(accent.opacity(0.22))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(-12)
            .accessibilityHidden(true)
    }

    private func backgroundView(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        ZStack {
            Color(uiColor: .systemBackground)

            if layout.template == .poster,
               let img = spec.image,
               let ui = AppGroup.loadUIImage(fileName: img.fileName)
            {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.00),
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))

                backgroundOverlay(style.background, accent: accent)
            }
        }
    }

    @ViewBuilder
    private func backgroundOverlay(_ token: BackgroundToken, accent: Color) -> some View {
        switch token {
        case .aurora:
            RadialGradient(
                colors: [Color.cyan.opacity(0.20), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 260
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.22), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 340
            )

        case .sunset:
            RadialGradient(
                colors: [Color.orange.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 280
            )
            RadialGradient(
                colors: [Color.pink.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 360
            )

        case .candy:
            RadialGradient(
                colors: [Color.yellow.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 260
            )

        case .midnight:
            RadialGradient(
                colors: [Color.white.opacity(0.08), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 320
            )

        default:
            EmptyView()
        }
    }

    // MARK: - Actions (interactive widgets)

    @ViewBuilder
    private func actionBar(spec: WidgetSpec, accent: Color) -> some View {
        if let bar = spec.actionBar?.normalisedOrNil() {
            let maxButtons = (family == .systemSmall) ? 1 : WidgetActionBarSpec.maxActions
            let actions = Array(bar.actions.prefix(maxButtons))

            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        actionButton(action: action, buttonStyle: bar.style, accent: accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func actionButton(action: WidgetActionSpec, buttonStyle: WidgetActionButtonStyleToken, accent: Color) -> some View {
        let titleTrimmed = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = titleTrimmed.isEmpty ? action.kind.displayName : titleTrimmed
        let sys = action.systemImage?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Group {
            #if canImport(AppIntents)
            if #available(iOS 17.0, *), (context == .widget || context == .simulator) {
                switch action.kind {
                case .incrementVariable:
                    Button(intent: WidgetWeaverQuickIncrementVariableIntent(key: action.variableKey, amount: action.incrementAmount)) {
                        actionButtonLabel(title: displayTitle, systemImage: sys)
                    }

                case .setVariableToNow:
                    Button(intent: WidgetWeaverQuickSetNowVariableIntent(key: action.variableKey, formatRawValue: action.nowFormat.rawValue)) {
                        actionButtonLabel(title: displayTitle, systemImage: sys)
                    }
                }
            } else {
                Button(action: {}) {
                    actionButtonLabel(title: displayTitle, systemImage: sys)
                }
                .allowsHitTesting(false)
            }
            #else
            Button(action: {}) {
                actionButtonLabel(title: displayTitle, systemImage: sys)
            }
            .allowsHitTesting(false)
            #endif
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .widgetWeaverActionButtonStyle(buttonStyle)
        .tint(accent)
    }

    @ViewBuilder
    private func actionButtonLabel(title: String, systemImage: String?) -> some View {
        if let systemImage, !systemImage.isEmpty {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        } else {
            Text(title)
        }
    }

    // MARK: - Fonts / Limits

    private func heroPrimaryFont() -> Font {
        switch family {
        case .systemSmall: return .title3
        case .systemMedium: return .title2
        case .systemLarge: return .largeTitle
        default: return .title2
        }
    }

    private func defaultPrimaryFont(for family: WidgetFamily) -> Font {
        switch family {
        case .systemSmall: return .subheadline
        case .systemMedium: return .headline
        case .systemLarge: return .title3
        default: return .subheadline
        }
    }

    private func primaryLineLimit(layout: LayoutSpec) -> Int {
        switch family {
        case .systemSmall: return layout.primaryLineLimitSmall
        default: return layout.primaryLineLimit
        }
    }

    private func shouldShowSecondary(layout: LayoutSpec) -> Bool {
        switch family {
        case .systemSmall: return false
        default: return true
        }
    }
}

// MARK: - Background Modifier

private struct WidgetWeaverBackgroundModifier: ViewModifier {
    let context: WidgetWeaverRenderContext
    let backgroundView: AnyView
    let cornerRadius: Double

    func body(content: Content) -> some View {
        switch context {
        case .widget:
            if #available(iOS 17.0, *) {
                content.containerBackground(for: .widget) { backgroundView }
            } else {
                content.background(backgroundView)
            }

        case .preview, .simulator:
            content
                .background(backgroundView)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Button Styling

private extension View {
    @ViewBuilder
    func widgetWeaverActionButtonStyle(_ token: WidgetActionButtonStyleToken) -> some View {
        switch token {
        case .prominent:
            self.buttonStyle(.borderedProminent)
        case .subtle:
            self.buttonStyle(.bordered)
        }
    }
}

#if canImport(AppIntents)

// MARK: - Quick Action Intents (used by interactive widgets)

@available(iOS 17.0, *)
struct WidgetWeaverQuickIncrementVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "WidgetWeaver Quick Increment"
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Amount") var amount: Int

    init() {
        self.key = ""
        self.amount = 1
    }

    init(key: String, amount: Int) {
        self.key = key
        self.amount = amount
    }

    func perform() async throws -> some IntentResult {
        guard WidgetWeaverEntitlements.isProUnlocked else { return .result() }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result() }

        let existingRaw = WidgetWeaverVariableStore.shared.value(for: canonical) ?? "0"
        let existing = Int(existingRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let newValue = existing + amount

        WidgetWeaverVariableStore.shared.setValue(String(newValue), for: canonical)
        return .result()
    }
}

@available(iOS 17.0, *)
struct WidgetWeaverQuickSetNowVariableIntent: AppIntent {
    static let title: LocalizedStringResource = "WidgetWeaver Quick Set Now"
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Key") var key: String
    @Parameter(title: "Format") var formatRawValue: String

    init() {
        self.key = ""
        self.formatRawValue = WidgetNowFormatToken.iso8601.rawValue
    }

    init(key: String, formatRawValue: String) {
        self.key = key
        self.formatRawValue = formatRawValue
    }

    func perform() async throws -> some IntentResult {
        guard WidgetWeaverEntitlements.isProUnlocked else { return .result() }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result() }

        let now = Date()
        let format = WidgetNowFormatToken(rawValue: formatRawValue) ?? .iso8601

        let value: String
        switch format {
        case .iso8601:
            value = WidgetWeaverVariableTemplate.iso8601String(now)

        case .unixSeconds:
            value = String(Int64(now.timeIntervalSince1970))

        case .unixMilliseconds:
            value = String(Int64(now.timeIntervalSince1970 * 1000.0))

        case .dateOnly:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = Calendar.autoupdatingCurrent.timeZone
            df.dateFormat = "yyyy-MM-dd"
            value = df.string(from: now)

        case .timeOnly:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = Calendar.autoupdatingCurrent.timeZone
            df.dateFormat = "HH:mm"
            value = df.string(from: now)
        }

        WidgetWeaverVariableStore.shared.setValue(value, for: canonical)
        return .result()
    }
}

#endif

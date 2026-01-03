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

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext = .widget) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        let s = spec.resolved(for: family)
        ZStack {
            backgroundView(spec: s)

            HStack(spacing: 0) {
                if s.layout.showsAccentBar {
                    Rectangle()
                        .fill(s.style.accentColor.colorValue)
                        .frame(width: 6)
                }

                contentView(spec: s)
                    .padding(.leading, s.layout.showsAccentBar ? 10 : 0)
                    .padding(.trailing, 12)
            }
            .padding(.vertical, 12)
        }
        .containerBackgroundIfNeeded(spec: s, context: context)
    }

    @ViewBuilder
    private func backgroundView(spec: WidgetSpec) -> some View {
        switch spec.layout.template {
        case .none:
            spec.style.backgroundColor.colorValue
        case .poster:
            let bg = spec.style.backgroundColor.colorValue
            ZStack {
                bg
                if let image = spec.image {
                    let uiImage = image.loadUIImageFromAppGroup(for: family)
                    if let uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: image.contentMode == .fit ? .fit : .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        .black.opacity(0.50),
                                        .black.opacity(0.10),
                                        .black.opacity(0.00)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                    }
                }
            }
        case .weather:
            WeatherBackgroundView(style: spec.style)
        case .nextUpCalendar:
            NextUpBackgroundView(style: spec.style)
        case .checklist:
            ChecklistBackgroundView(style: spec.style)
        }
    }

    @ViewBuilder
    private func contentView(spec: WidgetSpec) -> some View {
        switch spec.layout.template {
        case .none:
            BasicLayoutView(spec: spec, family: family, context: context)
        case .poster:
            PosterLayoutView(spec: spec, family: family, context: context)
        case .weather:
            WeatherLayoutView(spec: spec, family: family, context: context)
        case .nextUpCalendar:
            NextUpLayoutView(spec: spec, family: family, context: context)
        case .checklist:
            ChecklistLayoutView(spec: spec, family: family, context: context)
        }
    }
}

private extension View {
    @ViewBuilder
    func containerBackgroundIfNeeded(spec: WidgetSpec, context: WidgetWeaverRenderContext) -> some View {
        switch context {
        case .widget:
            self.containerBackground(for: .widget) { spec.style.backgroundColor.colorValue }
        case .preview:
            self.background(spec.style.backgroundColor.colorValue)
        case .simulator:
            self.background(spec.style.backgroundColor.colorValue)
        }
    }
}

// MARK: - Basic Layout

private struct BasicLayoutView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    var body: some View {
        let axis = spec.layout.axis
        let spacing = spec.layout.spacing
        let alignment = spec.layout.alignment

        if axis == .horizontal {
            HStack(alignment: alignment.horizontalStackAlignment, spacing: spacing) {
                symbolView
                textStack
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: alignment.verticalStackAlignment, spacing: spacing) {
                symbolView
                textStack
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var symbolView: some View {
        if let symbol = spec.symbol {
            WidgetSymbolView(symbol: symbol, style: spec.style)
        }
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spec.primaryText)
                .font(spec.style.primaryFont.fontValue)
                .foregroundStyle(spec.style.primaryTextColor.colorValue)
                .lineLimit(family == .systemSmall ? spec.layout.primaryLineLimitSmall : spec.layout.primaryLineLimit)

            if let secondary = spec.secondaryText {
                Text(secondary)
                    .font(spec.style.secondaryFont.fontValue)
                    .foregroundStyle(spec.style.secondaryTextColor.colorValue)
                    .lineLimit(spec.layout.secondaryLineLimit)
            }
        }
    }
}

// MARK: - Poster Layout

private struct PosterLayoutView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            Text(spec.primaryText)
                .font(spec.style.primaryFont.fontValue)
                .foregroundStyle(.white)
                .lineLimit(family == .systemSmall ? spec.layout.primaryLineLimitSmall : spec.layout.primaryLineLimit)

            if let secondary = spec.secondaryText {
                Text(secondary)
                    .font(spec.style.secondaryFont.fontValue)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(spec.layout.secondaryLineLimit)
            }
        }
    }
}

// MARK: - Weather Template

private struct WeatherBackgroundView: View {
    let style: StyleSpec

    var body: some View {
        LinearGradient(
            colors: [
                style.backgroundColor.colorValue,
                style.backgroundColor.colorValue.opacity(0.75)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct WeatherLayoutView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(spec.primaryText)
                    .font(spec.style.primaryFont.fontValue)
                    .foregroundStyle(spec.style.primaryTextColor.colorValue)
                Spacer()
                Text("☀️")
            }

            if let secondary = spec.secondaryText {
                Text(secondary)
                    .font(spec.style.secondaryFont.fontValue)
                    .foregroundStyle(spec.style.secondaryTextColor.colorValue)
            }

            Spacer(minLength: 0)

            if family != .systemSmall {
                Text("Weather template placeholder")
                    .font(.caption)
                    .foregroundStyle(spec.style.secondaryTextColor.colorValue.opacity(0.7))
            }
        }
    }
}

// MARK: - Next Up Calendar Template

private struct NextUpBackgroundView: View {
    let style: StyleSpec

    var body: some View {
        LinearGradient(
            colors: [
                style.backgroundColor.colorValue.opacity(0.9),
                style.backgroundColor.colorValue
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct NextUpLayoutView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(spec.primaryText)
                    .font(spec.style.primaryFont.fontValue)
                    .foregroundStyle(spec.style.primaryTextColor.colorValue)
                Spacer()
                Image(systemName: "calendar")
                    .foregroundStyle(spec.style.secondaryTextColor.colorValue)
            }

            if let secondary = spec.secondaryText {
                Text(secondary)
                    .font(spec.style.secondaryFont.fontValue)
                    .foregroundStyle(spec.style.secondaryTextColor.colorValue)
                    .lineLimit(spec.layout.secondaryLineLimit)
            }

            Spacer(minLength: 0)

            Text("Next Up template placeholder")
                .font(.caption)
                .foregroundStyle(spec.style.secondaryTextColor.colorValue.opacity(0.7))
        }
    }
}

// MARK: - Checklist Template

private struct ChecklistBackgroundView: View {
    let style: StyleSpec

    var body: some View {
        style.backgroundColor.colorValue
    }
}

private struct ChecklistLayoutView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(spec.primaryText)
                    .font(spec.style.primaryFont.fontValue)
                    .foregroundStyle(spec.style.primaryTextColor.colorValue)
                Spacer()
                Image(systemName: "checklist")
                    .foregroundStyle(spec.style.secondaryTextColor.colorValue)
            }

            if let secondary = spec.secondaryText {
                Text(secondary)
                    .font(spec.style.secondaryFont.fontValue)
                    .foregroundStyle(spec.style.secondaryTextColor.colorValue)
            }

            Spacer(minLength: 0)

            Text("Checklist template placeholder")
                .font(.caption)
                .foregroundStyle(spec.style.secondaryTextColor.colorValue.opacity(0.7))
        }
    }
}

// MARK: - Symbol View

private struct WidgetSymbolView: View {
    let symbol: SymbolSpec
    let style: StyleSpec

    var body: some View {
        Image(systemName: symbol.name)
            .symbolRenderingMode(symbol.renderingMode.swiftUISymbolRenderingMode)
            .font(.system(size: symbol.size, weight: symbol.weight.swiftUIFontWeight))
            .foregroundStyle(symbol.tint.colorValue)
            .frame(width: symbol.size * 1.4, height: symbol.size * 1.4, alignment: .center)
    }
}

private extension SymbolWeightToken {
    var swiftUIFontWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

private extension SymbolRenderingModeToken {
    var swiftUISymbolRenderingMode: SymbolRenderingMode {
        switch self {
        case .monochrome: return .monochrome
        case .hierarchical: return .hierarchical
        case .palette: return .palette
        case .multicolor: return .multicolor
        }
    }
}

private extension LayoutAlignmentToken {
    var horizontalStackAlignment: VerticalAlignment {
        switch self {
        case .leading: return .center
        case .center: return .center
        case .trailing: return .center
        }
    }

    var verticalStackAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

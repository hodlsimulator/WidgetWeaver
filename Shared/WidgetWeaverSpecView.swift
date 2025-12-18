//
//  WidgetWeaverSpecView.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import SwiftUI
import WidgetKit
import UIKit

// MARK: - Renderer

public enum WidgetWeaverRenderContext: String, Codable, Hashable {
    case widget
    case preview
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
        let spec = spec.normalised()
        let layout = spec.layout
        let style = spec.style
        let accent = style.accent.swiftUIColor
        let background = style.background.shapeStyle(accent: accent)

        Group {
            if layout.axis == .horizontal {
                HStack(alignment: .top, spacing: layout.spacing) {
                    accentBar(isHorizontal: true, accent: accent)
                    contentStack(spec: spec, layout: layout, style: style, accent: accent)
                }
            } else {
                VStack(alignment: .leading, spacing: layout.spacing) {
                    accentBar(isHorizontal: false, accent: accent)
                    contentStack(spec: spec, layout: layout, style: style, accent: accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.alignment.swiftUIAlignment)
        .padding(style.padding)
        .modifier(
            WidgetWeaverBackgroundModifier(
                context: context,
                background: background,
                cornerRadius: style.cornerRadius
            )
        )
    }

    private func contentStack(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: layout.spacing) {
            if let img = spec.image {
                bannerImage(img, style: style)
            }

            header(spec: spec, style: style, accent: accent)

            Text(spec.primaryText)
                .font(style.primaryTextStyle.font(fallback: defaultPrimaryFont(for: family)))
                .foregroundStyle(.primary)
                .lineLimit(primaryLineLimit(layout: layout))
                .minimumScaleFactor(0.85)

            if let secondary = spec.secondaryText, shouldShowSecondary(layout: layout) {
                Text(secondary)
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(layout.secondaryLineLimit)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
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
            .foregroundStyle(
                sym.tint == .accent ? accent : sym.tint.swiftUIColor
            )
            .font(.system(size: sym.size, weight: sym.weight.swiftUIFontWeight))
            .accessibilityHidden(true)
    }

    private func bannerImage(_ image: ImageSpec, style: StyleSpec) -> some View {
        let requested = image.height.normalised().clamped(to: 40...240)
        let maxH: Double
        switch family {
        case .systemSmall:
            maxH = 110
        case .systemMedium:
            maxH = 130
        case .systemLarge:
            maxH = 160
        default:
            maxH = 120
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

    private func accentBar(isHorizontal: Bool, accent: Color) -> some View {
        let barThickness: Double = 4

        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(accent.opacity(0.9))
            .frame(
                width: isHorizontal ? barThickness : nil,
                height: isHorizontal ? nil : barThickness
            )
            .padding(.top, isHorizontal ? 0 : 2)
    }

    private func defaultPrimaryFont(for family: WidgetFamily) -> Font {
        switch family {
        case .systemSmall:
            return .subheadline
        case .systemMedium:
            return .headline
        case .systemLarge:
            return .title3
        default:
            return .subheadline
        }
    }

    private func primaryLineLimit(layout: LayoutSpec) -> Int {
        switch family {
        case .systemSmall:
            return layout.primaryLineLimitSmall
        default:
            return layout.primaryLineLimit
        }
    }

    private func shouldShowSecondary(layout: LayoutSpec) -> Bool {
        switch family {
        case .systemSmall:
            return false
        default:
            return true
        }
    }
}

private struct WidgetWeaverBackgroundModifier: ViewModifier {
    let context: WidgetWeaverRenderContext
    let background: AnyShapeStyle
    let cornerRadius: Double

    func body(content: Content) -> some View {
        switch context {
        case .widget:
            content
                .containerBackground(background, for: .widget)
        case .preview:
            content
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

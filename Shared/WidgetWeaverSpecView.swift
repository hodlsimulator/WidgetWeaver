//
//  WidgetWeaverSpecView.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import SwiftUI
import WidgetKit

struct WidgetWeaverSpecView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetRenderingContext

    var body: some View {
        let resolved = spec.resolvingVariables(context: context, now: WidgetWeaverRenderClock.now)
        let style = resolved.style
        let layout = resolved.layout
        let accent = style.accent.color

        ZStack {
            backgroundView(spec: resolved, layout: layout, style: style, accent: accent)

            contentView(spec: resolved, layout: layout, style: style, accent: accent)
                .padding(layout.padding)
        }
    }

    // MARK: - Content

    private func contentView(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        switch layout.template {
        case .classic:
            return AnyView(classic(spec: spec, layout: layout, style: style, accent: accent))

        case .hero:
            return AnyView(hero(spec: spec, layout: layout, style: style, accent: accent))

        case .poster:
            return AnyView(poster(spec: spec, layout: layout, style: style, accent: accent))

        case .weather:
            return AnyView(weather(spec: spec, layout: layout, style: style, accent: accent))

        case .nextUpCalendar:
            return AnyView(nextUpCalendar(spec: spec, layout: layout, style: style, accent: accent))
        }
    }

    private func classic(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let text = WidgetWeaverResolvedText(spec: spec)
        let symbol = spec.symbol

        return VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            if layout.showsAccentBar {
                Rectangle()
                    .fill(accent)
                    .frame(height: 4)
                    .cornerRadius(2)
            }

            if let symbol {
                symbolView(symbol: symbol, accent: accent)
            }

            textView(
                text: text.primary,
                role: spec.primaryTextRole,
                style: style,
                maxLines: spec.primaryMaxLines,
                alignment: spec.primaryTextAlignment
            )

            if let secondary = text.secondary {
                textView(
                    text: secondary,
                    role: spec.secondaryTextRole,
                    style: style,
                    maxLines: spec.secondaryMaxLines,
                    alignment: spec.secondaryTextAlignment
                )
            }

            if let tertiary = text.tertiary {
                textView(
                    text: tertiary,
                    role: spec.tertiaryTextRole,
                    style: style,
                    maxLines: spec.tertiaryMaxLines,
                    alignment: spec.tertiaryTextAlignment
                )
            }

            Spacer(minLength: 0)

            if spec.actionBar.enabled {
                actionBar(spec: spec, style: style, accent: accent)
            }
        }
    }

    private func hero(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let text = WidgetWeaverResolvedText(spec: spec)
        let symbol = spec.symbol

        return VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            HStack(spacing: 10) {
                if let symbol {
                    symbolView(symbol: symbol, accent: accent)
                }

                VStack(alignment: layout.alignment.alignment, spacing: 2) {
                    textView(
                        text: text.primary,
                        role: spec.primaryTextRole,
                        style: style,
                        maxLines: spec.primaryMaxLines,
                        alignment: spec.primaryTextAlignment
                    )

                    if let secondary = text.secondary {
                        textView(
                            text: secondary,
                            role: spec.secondaryTextRole,
                            style: style,
                            maxLines: spec.secondaryMaxLines,
                            alignment: spec.secondaryTextAlignment
                        )
                    }
                }

                Spacer(minLength: 0)
            }

            if let tertiary = text.tertiary {
                textView(
                    text: tertiary,
                    role: spec.tertiaryTextRole,
                    style: style,
                    maxLines: spec.tertiaryMaxLines,
                    alignment: spec.tertiaryTextAlignment
                )
            }

            Spacer(minLength: 0)

            if spec.actionBar.enabled {
                actionBar(spec: spec, style: style, accent: accent)
            }
        }
    }

    private func poster(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let text = WidgetWeaverResolvedText(spec: spec)

        return VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            Spacer(minLength: 0)

            VStack(alignment: layout.alignment.alignment, spacing: 2) {
                textView(
                    text: text.primary,
                    role: spec.primaryTextRole,
                    style: style,
                    maxLines: spec.primaryMaxLines,
                    alignment: spec.primaryTextAlignment
                )

                if let secondary = text.secondary {
                    textView(
                        text: secondary,
                        role: spec.secondaryTextRole,
                        style: style,
                        maxLines: spec.secondaryMaxLines,
                        alignment: spec.secondaryTextAlignment
                    )
                }

                if let tertiary = text.tertiary {
                    textView(
                        text: tertiary,
                        role: spec.tertiaryTextRole,
                        style: style,
                        maxLines: spec.tertiaryMaxLines,
                        alignment: spec.tertiaryTextAlignment
                    )
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .cornerRadius(16)

            if spec.actionBar.enabled {
                actionBar(spec: spec, style: style, accent: accent)
            }
        }
    }

    private func weather(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        WidgetWeaverWeatherWidgetView(
            spec: spec,
            family: family,
            context: context
        )
    }

    private func nextUpCalendar(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        WidgetWeaverNextUpCalendarWidgetView(
            spec: spec,
            family: family,
            context: context
        )
    }

    // MARK: - Components

    private func textView(text: String, role: TextRoleToken, style: StyleSpec, maxLines: Int, alignment: TextAlignmentToken) -> some View {
        let resolved = style.textSpec(for: role)
        let colour = resolved.colour(for: role).color

        return Text(text)
            .font(resolved.font.swiftUIFont(size: resolved.size, weight: resolved.weight.swiftUIFontWeight))
            .foregroundColor(colour)
            .multilineTextAlignment(alignment.swiftUI)
            .lineLimit(maxLines)
            .shadow(
                color: style.shadowStyle.shadowColor.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                x: style.shadowX,
                y: style.shadowY
            )
    }

    private func symbolView(symbol: SymbolSpec, accent: Color) -> some View {
        let colour: Color = {
            switch symbol.tint {
            case .accent:
                return accent
            case .white:
                return .white
            case .black:
                return .black
            }
        }()

        return Image(systemName: symbol.name)
            .symbolRenderingMode(symbol.renderingMode.swiftUISymbolRenderingMode)
            .font(.system(size: 36 * symbol.scale))
            .fontWeight(symbol.weight.swiftUIFontWeight)
            .foregroundColor(colour.opacity(symbol.opacity))
    }

    private func actionBar(spec: WidgetSpec, style: StyleSpec, accent: Color) -> some View {
        let bar = spec.actionBar
        let colour = style.textSpec(for: .secondary).colour(for: .secondary).color
        let tint = bar.tint.color

        return HStack(spacing: 8) {
            if bar.showsIcon {
                Image(systemName: bar.icon.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(tint)
            }

            Text(bar.label)
                .font(.system(size: bar.labelSize, weight: bar.labelWeight.swiftUIFontWeight))
                .foregroundColor(colour)

            Spacer(minLength: 0)
        }
        .padding(bar.padding)
        .background(tint.opacity(bar.backgroundOpacity))
        .cornerRadius(bar.cornerRadius)
    }

    // MARK: - Background

    private func backgroundView(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        ZStack {
            if layout.template == .weather {
                weatherBackdrop(style: style, accent: accent)
            } else if layout.template == .poster,
                      let image = spec.image,
                      let uiImage = image.loadUIImageFromAppGroup(for: family) {
                Color(uiColor: .systemBackground)

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [
                                .black.opacity(0.55),
                                .black.opacity(0.12),
                                .clear
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    }
                    .clipped()
            } else {
                style.background.view
            }
        }
        .ignoresSafeArea()
    }

    /// Weather uses a lot of `.ultraThinMaterial`. In WidgetKit, materials take their blur source from the
    /// widget container background. If the container background is clear, materials render as black.
    /// This backdrop is used as the widget container background so the weather glass has a real source.
    private func weatherBackdrop(style: StyleSpec, accent: Color) -> some View {
        let store = WidgetWeaverWeatherStore.shared
        let now = WidgetWeaverRenderClock.now
        let snapshot = store.snapshotForRender(context: context)

        let palette: WeatherPalette = {
            if let snapshot {
                return WeatherPalette.forSnapshot(snapshot, now: now, accent: accent)
            }
            return WeatherPalette.fallback(accent: accent)
        }()

        return ZStack {
            palette.background
                .overlay(palette.vignette.opacity(style.weatherBlur.clamped(to: 0...1)))

            if style.weatherBlur > 0.001 {
                palette.background
                    .blur(radius: 12 * style.weatherBlur)
                    .opacity(0.55)
            }
        }
    }
}

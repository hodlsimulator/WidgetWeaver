//
//  WidgetWeaverSpecView.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import SwiftUI
import WidgetKit

public struct WidgetWeaverSpecView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily

    public init(spec: WidgetSpec, family: WidgetFamily) {
        self.spec = spec
        self.family = family
    }

    private var layout: LayoutSpec {
        spec.layout
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundView
            contentView
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if let bg = spec.backgroundColor {
            Color(hex: bg)
        } else if layout.template == .poster,
                  let image = spec.image,
                  let uiImage = image.loadUIImageFromAppGroup(for: family) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.25),
                            Color.black.opacity(0.60),
                            Color.black.opacity(0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(hex: "#1D1D1F"),
                    Color(hex: "#0F0F12")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch layout.template {
        case .chips:
            chipsTemplate
        case .poster:
            posterTemplate
        case .minimal:
            minimalTemplate
        }
    }

    // MARK: - Chips template

    @ViewBuilder
    private var chipsTemplate: some View {
        VStack(alignment: .leading, spacing: layout.vSpacing) {
            if let title = spec.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: layout.titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: spec.titleColor ?? "#FFFFFF"))
                    .lineLimit(layout.titleMaxLines)
            }

            if let subtitle = spec.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: layout.subtitleFontSize, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: spec.subtitleColor ?? "#BFBFBF"))
                    .lineLimit(layout.subtitleMaxLines)
            }

            Spacer(minLength: 0)

            if let chips = spec.chips, !chips.isEmpty {
                chipsGrid(chips)
            }
        }
        .padding(layout.paddingInsets(for: family))
    }

    private func chipsGrid(_ chips: [ChipSpec]) -> some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: layout.hSpacing), count: layout.chipsColumns(for: family))

        return LazyVGrid(columns: columns, alignment: .leading, spacing: layout.vSpacing) {
            ForEach(chips) { chip in
                chipView(chip)
            }
        }
    }

    private func chipView(_ chip: ChipSpec) -> some View {
        HStack(spacing: 8) {
            if let icon = chip.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: layout.chipIconSize, weight: .semibold))
                    .foregroundColor(Color(hex: chip.iconColor ?? "#FFFFFF"))
            }

            Text(chip.text)
                .font(.system(size: layout.chipFontSize, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: chip.textColor ?? "#FFFFFF"))
                .lineLimit(1)
        }
        .padding(.horizontal, layout.chipHorizontalPadding)
        .padding(.vertical, layout.chipVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.chipCornerRadius, style: .continuous)
                .fill(Color(hex: chip.backgroundColor ?? "#2A2A2E").opacity(layout.chipBackgroundOpacity))
        )
    }

    // MARK: - Poster template

    @ViewBuilder
    private var posterTemplate: some View {
        VStack(alignment: .leading, spacing: layout.vSpacing) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                if let title = spec.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: layout.posterTitleFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: spec.titleColor ?? "#FFFFFF"))
                        .lineLimit(layout.titleMaxLines)
                }

                if let subtitle = spec.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: layout.posterSubtitleFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: spec.subtitleColor ?? "#E6E6E6"))
                        .lineLimit(layout.subtitleMaxLines)
                }
            }
            .padding(layout.paddingInsets(for: family))
        }
    }

    // MARK: - Minimal template

    @ViewBuilder
    private var minimalTemplate: some View {
        VStack(alignment: .leading, spacing: layout.vSpacing) {
            if let title = spec.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: layout.titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: spec.titleColor ?? "#FFFFFF"))
                    .lineLimit(layout.titleMaxLines)
            }

            if let subtitle = spec.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: layout.subtitleFontSize, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: spec.subtitleColor ?? "#BFBFBF"))
                    .lineLimit(layout.subtitleMaxLines)
            }

            Spacer(minLength: 0)
        }
        .padding(layout.paddingInsets(for: family))
    }
}

// MARK: - Layout helpers

private extension LayoutSpec {
    func paddingInsets(for family: WidgetFamily) -> EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        case .systemMedium:
            return EdgeInsets(top: padding, leading: padding * 1.2, bottom: padding, trailing: padding * 1.2)
        case .systemLarge:
            return EdgeInsets(top: padding * 1.2, leading: padding * 1.2, bottom: padding * 1.2, trailing: padding * 1.2)
        default:
            return EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        }
    }

    func chipsColumns(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return max(1, min(chipsColumnsSmall, 2))
        case .systemMedium:
            return max(2, min(chipsColumnsMedium, 3))
        case .systemLarge:
            return max(2, min(chipsColumnsLarge, 4))
        default:
            return max(2, chipsColumnsMedium)
        }
    }
}

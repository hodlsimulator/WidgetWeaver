//
//  WidgetWeaverRemixSheet.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import SwiftUI
import WidgetKit

@MainActor
struct WidgetWeaverRemixSheet: View {
    let variants: [WidgetWeaverRemixEngine.Variant]
    let family: WidgetFamily
    let onApply: (WidgetSpec) -> Void
    let onAgain: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(groupedVariants, id: \.0) { kind, items in
                        section(kind: kind, variants: items)
                    }
                }
                .padding(14)
            }
            .navigationTitle("Remix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Again") { onAgain() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap a card to apply a look to the current draft.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Text, symbols, images, and actions stay the same. Only layout + style knobs change.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
    }

    private var groupedVariants: [(WidgetWeaverRemixEngine.Kind, [WidgetWeaverRemixEngine.Variant])] {
        let grouped = Dictionary(grouping: variants, by: { $0.kind })
        let orderedKinds = grouped.keys.sorted(by: { $0.sortOrder < $1.sortOrder })

        return orderedKinds.compactMap { kind in
            guard let items = grouped[kind] else { return nil }
            return (kind, items)
        }
    }

    @ViewBuilder
    private func section(kind: WidgetWeaverRemixEngine.Kind, variants: [WidgetWeaverRemixEngine.Variant]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(kind.displayName, systemImage: kind.systemImageName)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.leading, 2)

            LazyVStack(spacing: 14) {
                ForEach(variants) { v in
                    VariantCard(variant: v, family: family) {
                        onApply(v.spec)
                    }
                }
            }
        }
    }
}

private struct VariantCard: View {
    let variant: WidgetWeaverRemixEngine.Variant
    let family: WidgetFamily
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetPreviewThumbnail(spec: variant.spec, family: family, height: 120)
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(variant.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if !variant.subtitle.isEmpty {
                        Text(variant.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                tagGrid

                Text(detailsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Applies this look to the current draft.")
    }

    private var tagGrid: some View {
        let tags = tagsForSpec(variant.spec)

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(tags, id: \.self) { t in
                TagPill(text: t)
            }
        }
    }

    private var detailsLine: String {
        let s = variant.spec

        var parts: [String] = []
        parts.append("Spacing \(Int(s.layout.spacing.rounded()))")
        parts.append("Padding \(Int(s.style.padding.rounded()))")

        if s.symbol != nil {
            parts.append("Symbol \(Int(s.style.symbolSize.rounded()))")
        }

        if s.layout.template == .weather {
            parts.append(String(format: "Scale %.2f×", s.style.weatherScale))
        }

        parts.append("Align \(s.layout.alignment.displayName)")

        if s.layout.showsAccentBar {
            parts.append("Accent Bar")
        }

        return parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let s = variant.spec
        return "\(variant.title). \(s.layout.template.displayName), \(s.style.background.displayName), \(s.style.accent.displayName)."
    }

    private func tagsForSpec(_ spec: WidgetSpec) -> [String] {
        var tags: [String] = []

        tags.append(spec.layout.template.displayName)
        tags.append(spec.style.background.displayName)
        tags.append("Accent: \(spec.style.accent.displayName)")

        let type = typographyLabel(style: spec.style)
        tags.append(type)

        if spec.style.backgroundOverlayOpacity > 0.01 {
            let pct = Int((spec.style.backgroundOverlayOpacity * 100.0).rounded())
            tags.append("Overlay: \(spec.style.backgroundOverlay.displayName) \(pct)%")
        }

        if spec.style.backgroundGlowEnabled {
            tags.append("Glow")
        }

        return tags
    }

    private func typographyLabel(style: StyleSpec) -> String {
        let p = style.primaryTextStyle.displayName
        let s = style.secondaryTextStyle.displayName
        if p == s {
            return "Type: \(p)"
        }
        return "Type: \(p) / \(s)"
    }
}

private struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06))
            )
    }
}

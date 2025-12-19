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
                LazyVStack(spacing: 14) {
                    ForEach(variants) { v in
                        VariantCard(spec: v.spec, family: family) {
                            onApply(v.spec)
                        }
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
}

private struct VariantCard: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetPreviewThumbnail(spec: spec, family: family, height: 120)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(alignment: .firstTextBaseline) {
                    Text(spec.layout.template.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text(spec.style.accent.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("\(spec.style.background.displayName) · \(typographyLabel(style: spec.style))")
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
    }

    private func typographyLabel(style: StyleSpec) -> String {
        let p = style.primaryTextStyle.displayName
        let s = style.secondaryTextStyle.displayName
        if p == s {
            return "Typography: \(p)"
        }
        return "Typography: \(p) / \(s)"
    }
}

//
//  SmartPhotoPreviewStripView.swift
//  WidgetWeaver
//
//  Created by . . on 2026-01-05.
//

import SwiftUI
import UIKit

struct SmartPhotoPreviewStripView: View {
    let smart: SmartPhotoSpec
    let selectedFamily: EditingFamily
    let onSelectFamily: (EditingFamily) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                previewButton(family: .small, variant: smart.small)
                previewButton(family: .medium, variant: smart.medium)
                previewButton(family: .large, variant: smart.large)
            }

            Text("Tap a preview to edit that size.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewButton(family: EditingFamily, variant: SmartPhotoVariantSpec?) -> some View {
        Button {
            onSelectFamily(family)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    previewImage(variant: variant)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            selectionBorder(family: family)
                        }

                    if isManual(variant: variant) {
                        manualBadge
                    }
                }

                Text(family.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(family.label) preview")
        .accessibilityHint("Switch editor to \(family.label).")
    }

    @ViewBuilder
    private func selectionBorder(family: EditingFamily) -> some View {
        if family == selectedFamily {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.tint, lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func isManual(variant: SmartPhotoVariantSpec?) -> Bool {
        guard let variant else { return false }
        return variant.renderFileName.contains("-manual")
    }

    private var manualBadge: some View {
        Text("Manual")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
    }

    @ViewBuilder
    private func previewImage(variant: SmartPhotoVariantSpec?) -> some View {
        if let renderName = variant?.renderFileName,
           let uiImage = AppGroup.loadUIImage(fileName: renderName) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle()
                    .fill(.quaternary)

                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

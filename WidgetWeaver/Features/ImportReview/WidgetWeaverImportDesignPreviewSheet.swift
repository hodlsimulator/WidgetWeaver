//
//  WidgetWeaverImportDesignPreviewSheet.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

import SwiftUI
import WidgetKit

struct WidgetWeaverImportDesignPreviewSheet: View {
    let item: WidgetWeaverImportReviewItem
    let spec: WidgetSpec

    @Binding var selection: Set<UUID>

    let isImporting: Bool

    @Environment(\.dismiss) private var dismiss

    private var isSelected: Bool {
        selection.contains(item.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    previewCard(title: "Small", family: .systemSmall, maxHeight: 180)
                    previewCard(title: "Medium", family: .systemMedium, maxHeight: 180)
                    previewCard(title: "Large", family: .systemLarge, maxHeight: 320)

                    selectionCard
                }
                .padding(16)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(item.templateDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if item.hasImage {
                    Text("•")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Image")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func previewCard(title: String, family: WidgetFamily, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            WidgetPreview(spec: spec, family: family, maxHeight: maxHeight, isLive: false)
                .frame(maxWidth: .infinity)
                .frame(height: maxHeight)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSelected {
                Label("Selected for import", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Label("Not selected", systemImage: "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if isSelected {
                Button(role: .destructive) {
                    selection.remove(item.id)
                } label: {
                    Label("Remove from import", systemImage: "minus.circle")
                }
                .disabled(isImporting)
            } else {
                Button {
                    selection.insert(item.id)
                } label: {
                    Label("Add to import", systemImage: "plus.circle.fill")
                }
                .disabled(isImporting)
            }

            Text("Preview uses current in-app data (variables, Weather, Steps, Activity).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

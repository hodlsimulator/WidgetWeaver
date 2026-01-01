//
//  WidgetWeaverImportReviewSheet.swift
//  WidgetWeaver
//
//  Created by . . on 01/01/26.
//

import SwiftUI

struct WidgetWeaverImportReviewSheet: View {
    let model: WidgetWeaverImportReviewModel
    @Binding var selection: Set<UUID>
    let limitState: WidgetWeaverImportReviewLimitState
    let isImporting: Bool
    let showUnlockPro: Bool

    let onCancel: () -> Void
    let onImport: () -> Void
    let onSelectAll: () -> Void
    let onSelectNone: () -> Void
    let onUnlockPro: (() -> Void)?

    private var selectedCount: Int { selection.count }

    private var canImport: Bool {
        guard selectedCount > 0 else { return false }
        guard limitState.isImportAllowed else { return false }
        return !isImporting
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection

                if case .exceedsFreeLimit = limitState {
                    limitWarningSection
                }

                designsSection

                if showUnlockPro {
                    unlockProSection
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .disabled(isImporting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { onImport() }
                        .disabled(!canImport)
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Select all") { onSelectAll() }
                            .disabled(isImporting)
                        Button("Select none") { onSelectNone() }
                            .disabled(isImporting)
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .accessibilityLabel("Selection")
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("File", value: model.fileName)

            if let createdAt = model.createdAt {
                LabeledContent("Created", value: createdAt.formatted(date: .abbreviated, time: .shortened))
            }

            LabeledContent("Selected", value: "\(selectedCount) of \(model.items.count)")

            if isImporting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Importing…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedCount == 0 {
                Text("Select at least one design to import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var limitWarningSection: some View {
        Section {
            switch limitState {
            case .ok:
                EmptyView()

            case .exceedsFreeLimit(let available):
                Label(
                    "Selection exceeds free-tier limit. Available slots: \(available).",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.callout)
            }
        }
    }

    private var designsSection: some View {
        Section {
            ForEach(model.items) { item in
                Button {
                    toggle(item.id)
                } label: {
                    ItemRow(item: item, isSelected: selection.contains(item.id))
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .accessibilityLabel(accessibilityLabel(item: item))
            }
        } header: {
            Text("Designs")
        }
    }

    private var unlockProSection: some View {
        Section {
            Button {
                onUnlockPro?()
            } label: {
                Label("Unlock Pro", systemImage: "crown.fill")
            }
        } footer: {
            Text("Free tier is limited to a small number of saved designs. Pro unlocks unlimited designs.")
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func accessibilityLabel(item: WidgetWeaverImportReviewItem) -> String {
        let hasImage = item.hasImage ? ", has image" : ""
        return "\(item.name), \(item.templateDisplay), updated \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))\(hasImage)"
    }
}

private struct ItemRow: View {
    let item: WidgetWeaverImportReviewItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)

                Text("\(item.templateDisplay) • \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.hasImage {
                Text("Image")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.secondary.opacity(0.15))
                    )
            }
        }
        .contentShape(Rectangle())
    }
}

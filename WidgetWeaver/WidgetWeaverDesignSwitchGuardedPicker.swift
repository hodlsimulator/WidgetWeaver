//
//  WidgetWeaverDesignSwitchGuardedPicker.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI
import WidgetKit

struct WidgetWeaverDesignSwitchGuardedPicker: View {
    let title: String
    let specs: [WidgetSpec]
    @Binding var selectedSpecID: UUID

    let displayName: (WidgetSpec) -> String
    let isDirty: () -> Bool
    let onSaveCurrent: () -> Void

    @State private var pendingSelection: UUID?
    @State private var showUnsavedChangesDialog: Bool = false

    @State private var showPickerSheet: Bool = false
    @State private var searchText: String = ""

    var body: some View {
        Group {
            Button {
                showPickerSheet = true
            } label: {
                selectionSummaryRow
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("DesignPicker.Open")

            if isDirty() {
                unsavedChangesRow
            }
        }
        .sheet(isPresented: $showPickerSheet) {
            NavigationStack {
                WidgetWeaverDesignPickerSheet(
                    specs: filteredSpecs,
                    selectedSpecID: selectedSpecID,
                    displayName: displayName,
                    onSelect: { id in
                        attemptSelection(id)
                    },
                    onDone: {
                        showPickerSheet = false
                    }
                )
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Unsaved changes",
            isPresented: $showUnsavedChangesDialog,
            titleVisibility: .visible
        ) {
            Button {
                onSaveCurrent()
                commitPendingSelection(dismissPickerSheet: true)
            } label: {
                Label("Save & Switch", systemImage: "tray.and.arrow.down")
            }

            Button(role: .destructive) {
                commitPendingSelection(dismissPickerSheet: true)
            } label: {
                Label("Discard & Switch", systemImage: "trash")
            }

            Button("Cancel", role: .cancel) {
                pendingSelection = nil
            }
        } message: {
            Text(unsavedChangesDialogMessage)
        }
    }

    private var selectionSummaryRow: some View {
        Group {
            if let currentSpec {
                HStack(spacing: 12) {
                    WidgetPreviewThumbnail(
                        spec: currentSpec,
                        family: .systemSmall,
                        height: 44,
                        renderingStyle: currentSpec.normalised().usesTimeDependentRendering() ? .live : .rasterCached
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName(currentSpec))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("\(currentSpec.layout.template.displayName) • \(currentSpec.style.accent.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Design")
                .accessibilityValue(displayName(currentSpec))
                .accessibilityHint("Opens the design picker.")
            } else {
                HStack {
                    Text("Design")
                    Spacer(minLength: 0)
                    Text("No designs")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var unsavedChangesRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text("Unsaved changes")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unsaved changes")

            Spacer(minLength: 0)

            Button {
                onSaveCurrent()
            } label: {
                Label("Save", systemImage: "tray.and.arrow.down")
            }
            .font(.caption)
            .controlSize(.small)
            .buttonStyle(.borderless)
            .accessibilityLabel("Save changes")
        }
    }

    private var currentSpec: WidgetSpec? {
        specs.first(where: { $0.id == selectedSpecID }) ?? specs.first
    }

    private var filteredSpecs: [WidgetSpec] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return specs }

        return specs.filter { spec in
            if spec.name.lowercased().contains(q) { return true }

            let template = spec.layout.template.displayName.lowercased()
            if template.contains(q) { return true }

            let accent = spec.style.accent.displayName.lowercased()
            if accent.contains(q) { return true }

            return false
        }
    }

    private func attemptSelection(_ id: UUID) {
        guard id != selectedSpecID else {
            showPickerSheet = false
            return
        }

        if isDirty() {
            pendingSelection = id
            showUnsavedChangesDialog = true
        } else {
            selectedSpecID = id
            showPickerSheet = false
        }
    }

    private var unsavedChangesDialogMessage: String {
        guard let pendingSelection else {
            return "Switching designs will discard unsaved changes."
        }

        let fromName = designName(for: selectedSpecID)
        let toName = designName(for: pendingSelection)
        return "Switching from “\(fromName)” to “\(toName)” will discard unsaved changes. Save before switching?"
    }

    private func commitPendingSelection(dismissPickerSheet: Bool) {
        guard let pendingSelection else { return }
        selectedSpecID = pendingSelection
        self.pendingSelection = nil

        if dismissPickerSheet {
            showPickerSheet = false
        }
    }

    private func designName(for id: UUID) -> String {
        specs.first(where: { $0.id == id }).map(displayName) ?? "this design"
    }
}

private struct WidgetWeaverDesignPickerSheet: View {
    let specs: [WidgetSpec]
    let selectedSpecID: UUID
    let displayName: (WidgetSpec) -> String

    let onSelect: (UUID) -> Void
    let onDone: () -> Void

    var body: some View {
        List {
            if specs.isEmpty {
                Text("No designs.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(specs) { spec in
                    Button {
                        onSelect(spec.id)
                    } label: {
                        row(for: spec)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("DesignPicker.Row.\(spec.id.uuidString)")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onDone() }
            }
        }
    }

    private func row(for spec: WidgetSpec) -> some View {
        HStack(spacing: 12) {
            WidgetPreviewThumbnail(
                spec: spec,
                family: .systemSmall,
                height: 52,
                renderingStyle: spec.normalised().usesTimeDependentRendering() ? .live : .rasterCached
            )
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(spec))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(spec.layout.template.displayName) • \(spec.style.accent.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(spec.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if spec.id == selectedSpecID {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

//
//  WidgetWeaverDesignSwitchGuardedPicker.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

struct WidgetWeaverDesignSwitchGuardedPicker: View {
    let title: String
    let specs: [WidgetSpec]
    @Binding var selectedSpecID: UUID

    let displayName: (WidgetSpec) -> String
    let isDirty: () -> Bool
    let onSaveCurrent: () -> Void

    @State private var pendingSelection: UUID?
    @State private var showUnsavedChangesDialog: Bool = false

    var body: some View {
        Group {
            Picker(title, selection: guardedSelection) {
                ForEach(specs) { spec in
                    Text(displayName(spec)).tag(spec.id)
                }
            }
            .pickerStyle(.menu)

            if isDirty() {
                HStack(spacing: 10) {
                    Label("Unsaved changes", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
        }
        .confirmationDialog(
            "Unsaved changes",
            isPresented: $showUnsavedChangesDialog,
            titleVisibility: .visible
        ) {
            Button {
                onSaveCurrent()
                commitPendingSelection()
            } label: {
                Label("Save & Switch", systemImage: "tray.and.arrow.down")
            }

            Button(role: .destructive) {
                commitPendingSelection()
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

    private var guardedSelection: Binding<UUID> {
        Binding(
            get: { selectedSpecID },
            set: { newValue in
                guard newValue != selectedSpecID else { return }

                if isDirty() {
                    pendingSelection = newValue
                    showUnsavedChangesDialog = true
                } else {
                    selectedSpecID = newValue
                }
            }
        )
    }

    private var unsavedChangesDialogMessage: String {
        guard let pendingSelection else {
            return "Switching designs will discard unsaved changes."
        }

        let fromName = designName(for: selectedSpecID)
        let toName = designName(for: pendingSelection)
        return "Switching from “\(fromName)” to “\(toName)” will discard unsaved changes. Save before switching?"
    }

    private func commitPendingSelection() {
        guard let pendingSelection else { return }
        selectedSpecID = pendingSelection
        self.pendingSelection = nil
    }

    private func designName(for id: UUID) -> String {
        specs.first(where: { $0.id == id }).map(displayName) ?? "this design"
    }
}

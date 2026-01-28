//
//  WidgetWeaverLibraryDesignPreviewSheet.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI
import WidgetKit

@MainActor
struct WidgetWeaverLibraryDesignPreviewSheet: View {
    let spec: WidgetSpec
    let isDefault: Bool
    let sharePackage: ContentView.WidgetWeaverSharePackage
    let onEdit: @MainActor () -> Void
    let onMakeDefault: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var family: WidgetFamily = .systemSmall
    @State private var restrictToSmallOnly: Bool = false

    var body: some View {
        NavigationStack {
            List {
                previewSection
                detailsSection
                actionsSection
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                restrictToSmallOnly = spec.layout.template.isClock
                clampFamilyIfNeeded()
            }
            .onChange(of: family) { _, _ in
                clampFamilyIfNeeded()
            }
        }
    }

    private var displayTitle: String {
        let trimmed = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Preview" : trimmed
    }

    private func clampFamilyIfNeeded() {
        if restrictToSmallOnly, family != .systemSmall {
            family = .systemSmall
        }
    }

    private var previewSection: some View {
        Section {
            Picker("Preview size", selection: $family) {
                Text("Small").tag(WidgetFamily.systemSmall)
                if !restrictToSmallOnly {
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            WidgetPreview(spec: spec, family: family, maxHeight: 320)
                .frame(height: 320)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        } header: {
            Text("Preview")
        }
    }

    private var detailsSection: some View {
        Section {
            LabeledContent("Template", value: spec.layout.template.displayName)
            LabeledContent("Accent", value: spec.style.accent.displayName)
            LabeledContent(
                "Updated",
                value: spec.updatedAt.formatted(date: .abbreviated, time: .shortened)
            )

            LabeledContent("Default", value: isDefault ? "Yes" : "No")

            let hasMatched = (spec.normalised().matchedSet != nil)
            LabeledContent("Matched set", value: hasMatched ? "Yes" : "No")

            if !spec.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledContent("Primary") {
                    Text(spec.primaryText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let secondary = spec.secondaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !secondary.isEmpty {
                LabeledContent("Secondary") {
                    Text(secondary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Details")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                onEdit()
                dismiss()
            } label: {
                Label("Edit in Editor", systemImage: "pencil")
            }

            if !isDefault {
                Button {
                    onMakeDefault()
                    dismiss()
                } label: {
                    Label("Make Default", systemImage: "star")
                }
            }

            ShareLink(item: sharePackage, preview: SharePreview(displayTitle)) {
                Label("Share design", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Actions")
        }
    }
}

//
//  EditorWidgetListSelectionSurface.swift
//  WidgetWeaver
//
//  Created by . . on 1/10/26.
//

import Foundation
import SwiftUI

/// A lightweight, production selection surface that can emit origin-backed focus snapshots.
///
/// The editor's single source of truth remains `EditorFocusSnapshot`, but list-style selection
/// surfaces can use `EditorSelectionSet` to derive origin-backed snapshots with explicit
/// `selectionCount` and `selectionComposition`.
struct EditorWidgetListSelectionSurface: View {
    struct Row: Identifiable, Hashable {
        var id: String
        var title: String
        var subtitle: String?
        var item: EditorSelectionItem
        var accessibilityID: String

        init(
            id: String,
            title: String,
            subtitle: String? = nil,
            item: EditorSelectionItem,
            accessibilityID: String
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.item = item
            self.accessibilityID = accessibilityID
        }
    }

    @Binding var focus: EditorFocusSnapshot
    let rows: [Row]

    @State private var selection = EditorSelectionSet()
    @State private var lastWrittenSnapshot: EditorFocusSnapshot?

    var body: some View {
        Group {
            selectionSummaryRow
            clearButtonRow

            ForEach(rows) { row in
                rowButton(row)
            }
        }
        .onAppear {
            selection = EditorSelectionSet()
            lastWrittenSnapshot = nil
        }
        .onChange(of: focus) { _, newValue in
            handleExternalFocusChange(newValue)
        }
    }

    private var selectionSummaryRow: some View {
        Text(selectionSummaryText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("EditorWidgetListSelection.Root")
    }

    private var clearButtonRow: some View {
        Button {
            clearSelection()
        } label: {
            Label("Clear selection", systemImage: "xmark.circle")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityIdentifier("EditorWidgetListSelection.Clear")
    }

    private var selectionSummaryText: String {
        let count = selection.selectionCount
        if count <= 0 { return "Selected: none" }

        let composition = compositionLabel(selection.selectionComposition)
        return "Selected: \(count) • \(composition)"
    }

    @ViewBuilder
    private func rowButton(_ row: Row) -> some View {
        Button {
            toggle(row.item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)

                    if let subtitle = row.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if selection.items.contains(row.item) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(row.accessibilityID)
        .accessibilityValue(selection.items.contains(row.item) ? "Selected" : "Not selected")
    }

    private func toggle(_ item: EditorSelectionItem) {
        if selection.items.contains(item) {
            selection.items.remove(item)
        } else {
            selection.items.insert(item)
        }

        let snapshot = selection.toFocusSnapshot()
        focus = snapshot
        lastWrittenSnapshot = snapshot
    }

    private func clearSelection() {
        selection = EditorSelectionSet()

        let snapshot = selection.toFocusSnapshot()
        focus = snapshot
        lastWrittenSnapshot = snapshot
    }

    private func handleExternalFocusChange(_ newValue: EditorFocusSnapshot) {
        guard let lastWrittenSnapshot else {
            selection = EditorSelectionSet()
            return
        }

        if newValue != lastWrittenSnapshot {
            selection = EditorSelectionSet()
            self.lastWrittenSnapshot = nil
        }
    }

    private func compositionLabel(_ composition: EditorSelectionComposition) -> String {
        switch composition {
        case .unknown:
            return "unknown"
        case .known(let categories):
            if categories.isEmpty { return "none" }
            let labels = categories.map { $0.selectionLabel }.sorted()
            return labels.joined(separator: ", ")
        }
    }
}

private extension EditorSelectionCategory {
    var selectionLabel: String {
        switch self {
        case .nonAlbum:
            return "non‑album"
        case .albumContainer:
            return "album"
        case .albumPhotoItem:
            return "album photo"
        }
    }
}

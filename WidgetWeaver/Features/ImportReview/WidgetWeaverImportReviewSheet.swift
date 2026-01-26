//
//  WidgetWeaverImportReviewSheet.swift
//  WidgetWeaver
//
//  Created by . . on 01/01/26.
//

import SwiftUI
import UIKit
import WidgetKit

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

    private enum ListScope: String, CaseIterable, Identifiable {
        case all = "All"
        case selected = "Selected"

        var id: String { rawValue }
    }

    private enum Sort: String, CaseIterable, Identifiable {
        case updated = "Updated"
        case name = "Name"
        case template = "Template"

        var id: String { rawValue }
    }

    private struct PreviewState: Identifiable {
        let id: UUID
        let item: WidgetWeaverImportReviewItem
        let spec: WidgetSpec
    }

    @State private var listScope: ListScope = .all
    @State private var sort: Sort = .updated

    @State private var filterWithImageOnly: Bool = false
    @State private var templateFilter: String = "All"

    @State private var searchText: String = ""

    @State private var isListScrolling: Bool = false

    @State private var preview: PreviewState?

    private var selectedCount: Int { selection.count }

    private var canImport: Bool {
        guard selectedCount > 0 else { return false }
        guard limitState.isImportAllowed else { return false }
        return !isImporting
    }

    private var isFiltering: Bool {
        filterWithImageOnly || templateFilter != "All" || listScope == .selected
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowShownSelectionActions: Bool {
        isFiltering || isSearching
    }

    private var shownIDs: Set<UUID> {
        Set(displayedItems.map(\.id))
    }

    private var availableTemplates: [String] {
        let unique = Set(model.items.map(\.templateDisplay))
        return unique.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var specsByID: [UUID: WidgetSpec] {
        var out: [UUID: WidgetSpec] = [:]
        for spec in model.payload.specs {
            out[spec.id] = spec.normalised()
        }
        return out
    }

    private var displayedItems: [WidgetWeaverImportReviewItem] {
        var items = model.items

        if listScope == .selected {
            items = items.filter { selection.contains($0.id) }
        }

        if filterWithImageOnly {
            items = items.filter(\.hasImage)
        }

        if templateFilter != "All" {
            items = items.filter { $0.templateDisplay == templateFilter }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.name.lowercased().contains(q)
                || $0.templateDisplay.lowercased().contains(q)
            }
        }

        switch sort {
        case .updated:
            items.sort {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        case .name:
            items.sort {
                let a = $0.name.localizedStandardCompare($1.name)
                if a != .orderedSame { return a == .orderedAscending }
                return $0.updatedAt > $1.updatedAt
            }

        case .template:
            items.sort {
                let a = $0.templateDisplay.localizedStandardCompare($1.templateDisplay)
                if a != .orderedSame { return a == .orderedAscending }

                let b = $0.name.localizedStandardCompare($1.name)
                if b != .orderedSame { return b == .orderedAscending }

                return $0.updatedAt > $1.updatedAt
            }
        }

        return items
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .environment(\.wwThumbnailRenderingEnabled, !isListScrolling)
            .onScrollPhaseChange { _, newPhase in
                isListScrolling = newPhase.isScrolling
            }
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
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }

                        Divider()

                        Toggle("With image only", isOn: $filterWithImageOnly)

                        if availableTemplates.count > 1 {
                            Picker("Template", selection: $templateFilter) {
                                Text("All").tag("All")
                                ForEach(availableTemplates, id: \.self) { template in
                                    Text(template).tag(template)
                                }
                            }
                        }

                        if isFiltering || isSearching {
                            Divider()

                            Button("Clear filters") {
                                listScope = .all
                                filterWithImageOnly = false
                                templateFilter = "All"
                                searchText = ""
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Sort and filter")
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if shouldShowShownSelectionActions {
                            let shownCount = displayedItems.count

                            Button("Select shown (\(shownCount))") {
                                withAnimation(.spring(duration: 0.35)) {
                                    selectShown(replacingExisting: true)
                                }
                            }
                            .disabled(isImporting || shownCount == 0)

                            Button("Add shown (\(shownCount))") {
                                withAnimation(.spring(duration: 0.35)) {
                                    selectShown(replacingExisting: false)
                                }
                            }
                            .disabled(isImporting || shownCount == 0)

                            Button("Deselect shown (\(shownCount))") {
                                withAnimation(.spring(duration: 0.35)) {
                                    deselectShown()
                                }
                            }
                            .disabled(isImporting || shownCount == 0)

                            Divider()
                        }

                        Button("Select all (\(model.items.count))") { onSelectAll() }
                            .disabled(isImporting)

                        if case .exceedsFreeLimit(let available) = limitState {
                            Button("Trim selection to \(available)") {
                                withAnimation(.spring(duration: 0.35)) {
                                    trimSelectionToFreeLimit(available: available)
                                }
                            }
                            .disabled(isImporting)
                        }

                        Button("Select none") { onSelectNone() }
                            .disabled(isImporting)
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .accessibilityLabel("Selection")
                }
            }
            .sheet(item: $preview) { state in
                WidgetWeaverImportDesignPreviewSheet(
                    item: state.item,
                    spec: state.spec,
                    selection: $selection,
                    isImporting: isImporting
                )
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

            Picker("Showing", selection: $listScope) {
                ForEach(ListScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isImporting)

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
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "Selection exceeds free-tier limit. Available slots: \(available).",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)

                    Text("Trim the selection to import the most recent designs that fit the free tier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        withAnimation(.spring(duration: 0.35)) {
                            trimSelectionToFreeLimit(available: available)
                        }
                    } label: {
                        Label("Trim selection to \(available)", systemImage: "scissors")
                    }
                    .disabled(isImporting)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var designsSection: some View {
        Section {
            if displayedItems.isEmpty {
                VStack(spacing: 10) {
                    Text(emptyDesignsMessage)
                        .foregroundStyle(.secondary)

                    if listScope == .selected {
                        Button("Show all") { listScope = .all }
                            .disabled(isImporting)
                    }

                    if isFiltering || isSearching {
                        Button("Clear filters") {
                            listScope = .all
                            filterWithImageOnly = false
                            templateFilter = "All"
                            searchText = ""
                        }
                        .disabled(isImporting)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                ForEach(displayedItems) { item in
                    let spec = specsByID[item.id]
                    let canPreview = spec != nil

                    HStack(spacing: 8) {
                        Button {
                            toggle(item.id)
                        } label: {
                            ImportItemRow(
                                item: item,
                                spec: spec,
                                isSelected: selection.contains(item.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                        .accessibilityLabel(accessibilityLabel(item: item))

                        Button {
                            presentPreview(for: item)
                        } label: {
                            Image(systemName: "eye")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(.secondary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting || !canPreview)
                        .accessibilityLabel("Preview")
                    }
                    .contextMenu {
                        Button {
                            presentPreview(for: item)
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }

                        Button {
                            UIPasteboard.general.string = item.name
                        } label: {
                            Label("Copy name", systemImage: "doc.on.doc")
                        }

                        Button {
                            UIPasteboard.general.string = item.templateDisplay
                        } label: {
                            Label("Copy template", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button {
                            selectOnly(item.id)
                        } label: {
                            Label("Select only this", systemImage: "checkmark.circle")
                        }
                        .disabled(isImporting)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            presentPreview(for: item)
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }
                        .tint(.blue)
                    }
                }
            }
        } header: {
            Text("Designs")
        } footer: {
            Text("Tip: tap the eye, swipe right, or press and hold a row to preview. Use filters, then Selection → Select shown to bulk-select what is on screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyDesignsMessage: String {
        if listScope == .selected && selectedCount == 0 {
            return "No designs selected."
        }

        if isFiltering || isSearching {
            return "No matches."
        }

        return "No designs found in this file."
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

    private func selectOnly(_ id: UUID) {
        selection = [id]
    }

    private func trimSelectionToFreeLimit(available: Int) {
        let limit = max(0, available)
        guard limit > 0 else {
            selection.removeAll()
            return
        }

        let selectedItems = model.items.filter { selection.contains($0.id) }
        let sortedSelected = selectedItems.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        selection = Set(sortedSelected.prefix(limit).map(\.id))
    }

    private func selectShown(replacingExisting: Bool) {
        let ids = shownIDs

        if replacingExisting {
            selection = ids
        } else {
            selection.formUnion(ids)
        }
    }

    private func deselectShown() {
        selection.subtract(shownIDs)
    }

    private func presentPreview(for item: WidgetWeaverImportReviewItem) {
        guard let spec = specsByID[item.id] else { return }
        preview = PreviewState(id: item.id, item: item, spec: spec)
    }

    private func accessibilityLabel(item: WidgetWeaverImportReviewItem) -> String {
        let hasImage = item.hasImage ? ", has image" : ""
        let selected = selection.contains(item.id) ? ", selected" : ""
        return "\(item.name), \(item.templateDisplay), updated \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))\(hasImage)\(selected)"
    }
}

private struct ImportItemRow: View {
    let item: WidgetWeaverImportReviewItem
    let spec: WidgetSpec?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)

            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)

                Text("\(item.templateDisplay) • \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

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

    @ViewBuilder
    private var thumbnail: some View {
        if let spec {
            let isTimeDependent = spec.normalised().usesTimeDependentRendering()

            WidgetPreviewThumbnail(
                spec: spec,
                family: .systemSmall,
                height: 54,
                renderingStyle: isTimeDependent ? .live : .rasterCached
            )
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "square")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

//
//  ContentView.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI
import WidgetKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct ContentView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @StateObject var proManager = WidgetWeaverProManager()

    @State var store: WidgetWeaverDesignStore = .shared
    @State var selectedSpecID: String = ""
    @State var defaultSpecID: String = ""

    @State var draftSpecs: [String: WidgetSpec] = [:]

    @State var savedSpecs: [WidgetSpec] = []
    @State var activeSheet: ActiveSheet? = nil

    @State var saveStatusMessage: String = ""

    @State var previewFamily: WidgetFamily = .systemSmall
    @State var previewLockFamilyRaw: LockWidgetFamilyToken = .accessoryRectangular

    @State var remixVariants: [WidgetSpec] = []

    @State var selectedTab: AppTab = .explore

    @State var showDeleteConfirmation: Bool = false
    @State var showRevertConfirmation: Bool = false
    @State var showImageCleanupConfirmation: Bool = false

    @State var showImportPicker: Bool = false

    @State var librarySearchText: String = ""
    @State var librarySortRaw: String = LibrarySort.recent.rawValue
    @State var libraryFilterRaw: String = LibraryFilter.all.rawValue

    @State var pickedPhoto: PhotosPickerItem? = nil

    enum AppTab: Hashable {
        case explore
        case library
        case editor
    }

    enum ActiveSheet: Hashable, Identifiable {
        case widgetHelp
        case pro
        case variables
        case inspector
        case remix
        case weather
        case steps
        case importReview

        var id: String {
            switch self {
            case .widgetHelp: return "widgetHelp"
            case .pro: return "pro"
            case .variables: return "variables"
            case .inspector: return "inspector"
            case .remix: return "remix"
            case .weather: return "weather"
            case .steps: return "steps"
            case .importReview: return "importReview"
            }
        }
    }

    enum LibrarySort: String, CaseIterable, Identifiable {
        case recent
        case name

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent: return "Recent"
            case .name: return "Name"
            }
        }

        static var ordered: [LibrarySort] { [.recent, .name] }
    }

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all
        case home
        case lock
        case weather
        case steps

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .home: return "Home"
            case .lock: return "Lock"
            case .weather: return "Weather"
            case .steps: return "Steps"
            }
        }

        static var ordered: [LibraryFilter] { [.all, .home, .lock, .weather, .steps] }
    }

    var librarySort: LibrarySort {
        LibrarySort(rawValue: librarySortRaw) ?? .recent
    }

    var libraryFilter: LibraryFilter {
        LibraryFilter(rawValue: libraryFilterRaw) ?? .all
    }

    var libraryIsFilteringOrSearching: Bool {
        !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || libraryFilter != .all
    }

    private var libraryDisplayedSpecs: [WidgetSpec] {
        var items = savedSpecs

        if libraryFilter != .all {
            items = items.filter { spec in
                switch libraryFilter {
                case .all:
                    return true
                case .home:
                    return spec.layout.template.supportsHomeWidgets
                case .lock:
                    return spec.layout.template.supportsLockWidgets
                case .weather:
                    return spec.layout.template.category == .weather
                case .steps:
                    return spec.layout.template.category == .steps
                }
            }
        }

        let search = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            let lower = search.lowercased()
            items = items.filter { spec in
                spec.name.lowercased().contains(lower)
                || spec.layout.template.displayName.lowercased().contains(lower)
                || spec.style.accent.displayName.lowercased().contains(lower)
            }
        }

        switch librarySort {
        case .recent:
            items.sort { a, b in
                if a.id == defaultSpecID { return true }
                if b.id == defaultSpecID { return false }
                return a.updatedAt > b.updatedAt
            }
        case .name:
            items.sort { a, b in
                if a.id == defaultSpecID { return true }
                if b.id == defaultSpecID { return false }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }

        return items
    }

    private func draftSpec(id: String) -> WidgetSpec {
        if let draft = draftSpecs[id] { return draft }
        if let saved = savedSpecs.first(where: { $0.id == id }) { return saved }
        return WidgetSpec.defaultSpec()
    }

    private func applySpec(_ spec: WidgetSpec) {
        draftSpecs[spec.id] = spec
        selectedSpecID = spec.id
    }

    private func specDisplayName(_ spec: WidgetSpec) -> String {
        let name = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled" : name
    }

    private func isDraftDirty(id: String) -> Bool {
        guard let draft = draftSpecs[id] else { return false }
        guard let saved = savedSpecs.first(where: { $0.id == id }) else { return true }
        return draft.normalised() != saved.normalised()
    }

    private func currentSavedSpec() -> WidgetSpec? {
        savedSpecs.first(where: { $0.id == selectedSpecID })
    }

    private func currentDraftSpec() -> WidgetSpec {
        draftSpec(id: selectedSpecID)
    }

    private func updateSavedSpecsCache() {
        savedSpecs = store.loadAllSorted()
    }

    private func loadSelected() {
        if selectedSpecID.isEmpty {
            selectedSpecID = store.defaultSpecID()
        }
        if selectedSpecID.isEmpty, let first = savedSpecs.first {
            selectedSpecID = first.id
        }
        if selectedSpecID.isEmpty {
            var spec = WidgetSpec.defaultSpec()
            spec.id = UUID().uuidString
            spec.createdAt = Date()
            spec.updatedAt = Date()
            store.save(spec: spec)
            updateSavedSpecsCache()
            selectedSpecID = spec.id
        }

        defaultSpecID = store.defaultSpecID()
        if defaultSpecID.isEmpty, let first = savedSpecs.first {
            store.setDefault(id: first.id)
            defaultSpecID = first.id
        }

        draftSpecs[selectedSpecID] = currentSavedSpec() ?? WidgetSpec.defaultSpec()
    }

    private func bootstrap() {
        updateSavedSpecsCache()
        loadSelected()
        refreshWidgets()
    }

    private func clearLibrarySearchAndFilter() {
        librarySearchText = ""
        libraryFilterRaw = LibraryFilter.all.rawValue
    }

    private var libraryFilterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.ordered) { filter in
                    libraryFilterChip(filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func libraryFilterChip(_ filter: LibraryFilter) -> some View {
        let isSelected = filter == libraryFilter

        return Button {
            libraryFilterRaw = filter.rawValue
        } label: {
            Text(filter.title)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.primary.opacity(0.25) : Color.secondary.opacity(0.2),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
    }

    init() {
        Self.applyAppearanceIfNeeded()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                exploreRoot
            }
            .tabItem { Label("Explore", systemImage: "sparkles") }
            .tag(AppTab.explore)

            NavigationStack {
                libraryRoot
            }
            .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            .tag(AppTab.library)

            NavigationStack {
                editorRoot
            }
            .tabItem { Label("Editor", systemImage: "pencil.and.outline") }
            .tag(AppTab.editor)
        }
        .sheet(item: $activeSheet, content: sheetContent)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: WidgetWeaverSharePackage.importableTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImportResult
        )
        .confirmationDialog(
            "Delete this design?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteCurrentDesign() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the design from the library.\nAny widget using it will fall back to another design.")
        }
        .confirmationDialog(
            "Clean up unused images?",
            isPresented: $showImageCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Up", role: .destructive) { cleanupUnusedImages() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes image files in the App Group container that are not referenced by any saved design.\nWidgets will refresh after cleanup.")
        }
        .confirmationDialog(
            "Revert unsaved changes?",
            isPresented: $showRevertConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revert", role: .destructive) { revertUnsavedChanges() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This discards current draft edits and reloads the last saved version of this design.")
        }
        .onAppear(perform: bootstrap)
        .onChange(of: selectedSpecID) { _, _ in loadSelected() }
        .onChange(of: pickedPhoto) { _, newItem in handlePickedPhotoChange(newItem) }
    }

    private var exploreRoot: some View {
        WidgetWeaverAboutView(
            proManager: proManager,
            onAddTemplate: { spec, makeDefault in
                addTemplateDesign(spec, makeDefault: makeDefault)
                selectedTab = .editor
            },
            onShowPro: { activeSheet = .pro },
            onShowWidgetHelp: { activeSheet = .widgetHelp },
            onOpenWeatherSettings: { activeSheet = .weather },
            onOpenStepsSettings: { activeSheet = .steps },
            onGoToLibrary: { selectedTab = .library }
        )
    }

    private var libraryRoot: some View {
        let displayedSpecs = libraryDisplayedSpecs

        return ZStack {
            WidgetWeaverAboutBackground()

            List {
                Section {
                    libraryFilterChipsRow
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowSeparator(.hidden)
                }

                Section {
                    if savedSpecs.isEmpty {
                        Text("No designs yet. Create one in Explore.")
                            .foregroundStyle(.secondary)

                    } else if displayedSpecs.isEmpty {
                        VStack(spacing: 10) {
                            Text("No matches. Clear search or choose All.")
                                .foregroundStyle(.secondary)

                            if libraryIsFilteringOrSearching {
                                Button("Clear") { clearLibrarySearchAndFilter() }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                    } else {
                        ForEach(displayedSpecs) { spec in
                            Button {
                                selectDesignFromLibrary(spec)
                            } label: {
                                libraryRow(spec: spec)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    selectDesignFromLibrary(spec)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                if spec.id != defaultSpecID {
                                    Button {
                                        makeDefaultFromLibrary(spec)
                                    } label: {
                                        Label("Make Default", systemImage: "star")
                                    }
                                }

                                Button {
                                    duplicateDesignFromLibrary(spec)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }

                                Button(role: .destructive) {
                                    deleteDesignFromLibrary(spec)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(savedSpecs.count <= 1)
                            }
                        }
                    }
                } header: {
                    Text("Designs")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tip: add a WidgetWeaver widget on your Home Screen, then long-press → Edit Widget to choose a Design.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !proManager.isProUnlocked {
                            Text("Free tier designs: \(savedSpecs.count)/\(WidgetWeaverEntitlements.maxFreeDesigns)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        selectedTab = .explore
                    } label: {
                        Label("Browse templates (Explore)", systemImage: "sparkles")
                    }

                    Button {
                        createNewDesign()
                        selectedTab = .editor
                    } label: {
                        Label("New blank design", systemImage: "plus")
                    }
                } header: {
                    Text("Quick start")
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $librarySearchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $librarySortRaw) {
                        ForEach(LibrarySort.ordered) { sort in
                            Text(sort.title).tag(sort.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        selectedTab = .explore
                    } label: {
                        Label("Explore templates", systemImage: "sparkles")
                    }

                    Button {
                        createNewDesign()
                        selectedTab = .editor
                    } label: {
                        Label("New design", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
    }

    private func libraryRow(spec: WidgetSpec) -> some View {
        HStack(spacing: 12) {
            WidgetPreviewThumbnail(spec: spec, family: .systemSmall, height: 62)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(specDisplayName(spec))
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

            if spec.id == defaultSpecID {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Default design")
            }
        }
        .contentShape(Rectangle())
    }

    private func selectDesignFromLibrary(_ spec: WidgetSpec) {
        selectedSpecID = spec.id
        applySpec(spec)
        selectedTab = .editor
    }

    private func makeDefaultFromLibrary(_ spec: WidgetSpec) {
        store.setDefault(id: spec.id)
        defaultSpecID = store.defaultSpecID()
        refreshWidgets()
        saveStatusMessage = "Made default.\nWidgets refreshed."
    }

    private func duplicateDesignFromLibrary(_ spec: WidgetSpec) {
        selectedSpecID = spec.id
        applySpec(spec)
        duplicateCurrentDesign()
        selectedTab = .editor
    }

    private func deleteDesignFromLibrary(_ spec: WidgetSpec) {
        selectedSpecID = spec.id
        applySpec(spec)
        showDeleteConfirmation = true
    }

    private var editorRoot: some View {
        ZStack {
            WidgetWeaverAboutBackground()
            editorLayout
        }
        .navigationTitle("Editor")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { editorToolbar }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { remixToolbarButton }
        ToolbarItem(placement: .topBarTrailing) { toolbarMenu }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { Keyboard.dismiss() }
        }
    }

    private func sheetContent(_ sheet: ActiveSheet) -> AnyView {
        switch sheet {
        case .widgetHelp:
            return AnyView(WidgetWorkflowHelpView())

        case .pro:
            return AnyView(WidgetWeaverProView(manager: proManager))

        case .variables:
            return AnyView(
                WidgetWeaverVariablesView(
                    proManager: proManager,
                    onShowPro: { activeSheet = .pro }
                )
            )

        case .inspector:
            return AnyView(
                WidgetWeaverDesignInspectorView(
                    spec: draftSpec(id: selectedSpecID),
                    initialFamily: previewFamily
                )
            )

        case .remix:
            return AnyView(
                WidgetWeaverRemixSheet(
                    variants: remixVariants,
                    family: previewFamily,
                    onApply: { spec in applyRemixVariant(spec) },
                    onAgain: { remixAgain() },
                    onClose: { activeSheet = nil }
                )
            )

        case .weather:
            return AnyView(
                NavigationStack {
                    WidgetWeaverWeatherSettingsView(onClose: { activeSheet = nil })
                }
            )

        case .steps:
            return AnyView(
                NavigationStack {
                    WidgetWeaverStepsSettingsView(onClose: { activeSheet = nil })
                }
            )
            
        case .importReview:
            return importReviewSheetAnyView()

        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await prepareImportReview(from: url) }

        case .failure(let error):
            if (error as NSError).code == NSUserCancelledError { return }
            saveStatusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func handlePickedPhotoChange(_ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        Task { await importPickedImage(newItem) }
    }
}

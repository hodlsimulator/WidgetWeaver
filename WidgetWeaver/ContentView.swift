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
    @Environment(\.scenePhase) private var scenePhase

    @StateObject var proManager = WidgetWeaverProManager()

    @AppStorage("widgetweaver.editor.autoThemeFromImage") var autoThemeFromImage: Bool = true

#if DEBUG
    @AppStorage("widgetweaver.editor.debug.diagnostics") var showEditorDiagnostics: Bool = false
#endif

    @State private var librarySearchText: String = ""
    @AppStorage("library.sort") private var librarySortRaw: String = "updated"
    @AppStorage("library.filter") private var libraryFilterRaw: String = "all"

    @State var savedSpecs: [WidgetSpec] = []
    @State var defaultSpecID: UUID?
    @State var selectedSpecID: UUID = UUID()

    @State var designName: String = "WidgetWeaver"
    @State var styleDraft: StyleDraft = .defaultDraft
    @State var actionBarDraft: ActionBarDraft = .defaultDraft

    @State var baseDraft: FamilyDraft = .defaultDraft
    @State var matchedSetEnabled: Bool = false
    @State var matchedDrafts: MatchedDrafts = MatchedDrafts(
        small: .defaultDraft,
        medium: .defaultDraft,
        large: .defaultDraft
    )

    @State var editorFocusSnapshot: EditorFocusSnapshot = .widgetDefault

    @State private var editorFocusRestorationStack: EditorFocusRestorationStack = .init()

    @State var albumShufflePickerPresented: Bool = false
    @State private var previousVisibleToolIDs: [EditorToolID] = []

    @State var editorToolCapabilitiesDidChangeTick: UInt = 0
    @State var editorToolCapabilitiesDidChangeObserverToken: NSObjectProtocol?

    @State var pickedPhoto: PhotosPickerItem?
    @State var lastImageThemeFileName: String = ""
    @State var lastImageThemeSuggestion: WidgetWeaverImageThemeSuggestion?

    @State var remixVariants: [WidgetWeaverRemixEngine.Variant] = []

    @State var aiPrompt: String = ""
    @State var aiMakeGeneratedDefault: Bool = true
    @State var aiPatchInstruction: String = ""
    @State var aiStatusMessage: String = ""

    @State var previewFamily: WidgetFamily = .systemSmall

    @State var lastSavedAt: Date?
    @State var lastWidgetRefreshAt: Date?
    @State var saveStatusMessage: String = ""

    @State var showDeleteConfirmation: Bool = false
    @State var showImageCleanupConfirmation: Bool = false
    @State var showRevertConfirmation: Bool = false

    enum AppTab: Int, Hashable {
        case explore = 1
        case library = 2
        case editor = 3
    }

    @State var selectedTab: AppTab = .explore

    enum ActiveSheet: Identifiable {
        case widgetHelp
        case pro
        case variables
        case inspector
        case remix
        case weather
        case steps
        case activity
        case reminders
        case importReview

        var id: Int {
            switch self {
            case .widgetHelp: return 1
            case .pro: return 2
            case .variables: return 3
            case .weather: return 4
            case .inspector: return 5
            case .remix: return 6
            case .steps: return 7
            case .activity: return 8
            case .reminders: return 10
            case .importReview: return 9
            }
        }
    }

    @State var activeSheet: ActiveSheet?

    @State var showImportPicker: Bool = false
    @State var importInProgress: Bool = false

    @State var importReviewModel: WidgetWeaverImportReviewModel?
    @State var importReviewSelection: Set<UUID> = []

    let store = WidgetSpecStore.shared

    enum LibrarySort: String, CaseIterable, Identifiable {
        case updated
        case name
        case template
        case accent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .updated: return "Updated"
            case .name: return "Name"
            case .template: return "Template"
            case .accent: return "Accent"
            }
        }

        static var ordered: [LibrarySort] { [.updated, .name, .template, .accent] }
    }

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all
        case `default` = "default"
        case weather
        case nextUp = "nextUp"
        case steps
        case withImage = "withImage"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .default: return "Default"
            case .weather: return "Weather"
            case .nextUp: return "Next Up"
            case .steps: return "Steps"
            case .withImage: return "With Image"
            }
        }

        static var ordered: [LibraryFilter] { [.all, .default, .weather, .nextUp, .steps, .withImage] }
    }

    private struct LibraryItem: Identifiable {
        let index: Int
        let spec: WidgetSpec

        let nameKey: String
        let templateKey: String
        let accentKey: String
        let searchKey: String
        let updatedAt: Date

        var id: UUID { spec.id }

        init(index: Int, spec: WidgetSpec) {
            self.index = index
            self.spec = spec

            self.nameKey = spec.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.templateKey = spec.layout.template.displayName.lowercased()
            self.accentKey = spec.style.accent.displayName.lowercased()

            let secondary = spec.secondaryText ?? ""
            self.searchKey = (spec.name + "\n" + spec.primaryText + "\n" + secondary).lowercased()
            self.updatedAt = spec.updatedAt
        }
    }

    private var librarySort: LibrarySort { LibrarySort(rawValue: librarySortRaw) ?? .updated }
    private var libraryFilter: LibraryFilter { LibraryFilter(rawValue: libraryFilterRaw) ?? .all }

    private var libraryIsFilteringOrSearching: Bool {
        if libraryFilter != .all { return true }
        return !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var libraryDisplayedSpecs: [WidgetSpec] {
        let q = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = savedSpecs.enumerated().map { LibraryItem(index: $0.offset, spec: $0.element) }

        items = items.filter { item in
            switch libraryFilter {
            case .all:
                return true

            case .default:
                guard let defaultSpecID else { return false }
                return item.spec.id == defaultSpecID

            case .weather:
                return item.spec.layout.template == .weather

            case .nextUp:
                return item.spec.layout.template == .nextUpCalendar

            case .steps:
                return item.spec.usesStepsRendering()

            case .withImage:
                return item.spec.image != nil
            }
        }

        if !q.isEmpty {
            items = items.filter { $0.searchKey.contains(q) }
        }

        switch librarySort {
        case .updated:
            items.sort {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.index < $1.index
            }

        case .name:
            items.sort {
                if $0.nameKey != $1.nameKey { return $0.nameKey < $1.nameKey }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.index < $1.index
            }

        case .template:
            items.sort {
                if $0.templateKey != $1.templateKey { return $0.templateKey < $1.templateKey }
                if $0.nameKey != $1.nameKey { return $0.nameKey < $1.nameKey }
                return $0.index < $1.index
            }

        case .accent:
            items.sort {
                if $0.accentKey != $1.accentKey { return $0.accentKey < $1.accentKey }
                if $0.nameKey != $1.nameKey { return $0.nameKey < $1.nameKey }
                return $0.index < $1.index
            }
        }

        return items.map(\.spec)
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
        .onAppear {
            bootstrap()
            installEditorToolCapabilitiesDidChangeObserverIfNeeded()
            previousVisibleToolIDs = editorVisibleToolIDs
        }
        .onDisappear {
            uninstallEditorToolCapabilitiesDidChangeObserverIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
            }
        }
        .onChange(of: proManager.isProUnlocked) { _, _ in
            EditorToolRegistry.capabilitiesDidChange(reason: .proStateChanged)
        }
        .onChange(of: matchedSetEnabled) { _, _ in
            EditorToolRegistry.capabilitiesDidChange(reason: .matchedSetEnabledChanged)
        }
        .onChange(of: editorFocusSnapshot) { oldValue, newValue in
            editorFocusRestorationStack.recordFocusChange(old: oldValue, new: newValue)
        }
        .onChange(of: editorVisibleToolIDs) { _, newValue in
            let actions = editorToolTeardownActions(
                old: previousVisibleToolIDs,
                new: newValue,
                currentFocus: editorFocusSnapshot.focus
            )

            for action in actions {
                switch action {
                case .dismissAlbumShufflePicker:
                    albumShufflePickerPresented = false

                case .resetEditorFocusToWidgetDefault:
                    if let restored = editorFocusRestorationStack.restoreFocusAfterTeardown(currentFocusSnapshot: editorFocusSnapshot) {
                        editorFocusSnapshot = restored
                    } else {
                        editorFocusSnapshot = .widgetDefault
                    }
                }
            }

            previousVisibleToolIDs = newValue
        }
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

#if DEBUG
            if showEditorDiagnostics {
                editorDiagnosticsOverlay
            }
#endif
        }
        .navigationTitle("Editor")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { editorToolbar }
    }

#if DEBUG
    private var editorDiagnosticsOverlay: some View {
        let ctx = editorToolContext
        let caps = EditorToolRegistry.capabilities(for: ctx)

        let capabilityLabels: [String] = [
            (caps.contains(.canEditLayout), "layout"),
            (caps.contains(.canEditTextContent), "text"),
            (caps.contains(.canEditSymbol), "symbol"),
            (caps.contains(.canEditImage), "image"),
            (caps.contains(.canEditSmartPhoto), "smartPhoto"),
            (caps.contains(.canEditStyle), "style"),
            (caps.contains(.canEditTypography), "typography"),
            (caps.contains(.canEditActions), "actions"),
        ].compactMap { $0.0 ? $0.1 : nil }

        let tools = editorVisibleToolIDs.map(\.rawValue).joined(separator: ", ")

        let focusLabel: String = {
            switch ctx.focus {
            case .widget:
                return "widget"
            case .element(let id):
                return "element(\(id))"
            case .albumContainer(let id, let subtype):
                return "albumContainer(\(id), \(subtype.rawValue))"
            case .albumPhoto(let albumID, let itemID, let subtype):
                return "albumPhoto(\(albumID), \(itemID), \(subtype.rawValue))"
            case .smartRuleEditor(let albumID):
                return "smartRuleEditor(\(albumID))"
            case .clock:
                return "clock"
            }
        }()

        return VStack(alignment: .leading, spacing: 4) {
            Text("Editor Diagnostics")
                .font(.caption.weight(.semibold))

            Text("Template: \(ctx.template.displayName)")
            Text("Matched set: \(ctx.matchedSetEnabled ? "on" : "off") • Pro: \(ctx.isProUnlocked ? "on" : "off")")
            Text("Selection: \(ctx.selection.rawValue) • Focus: \(focusLabel)")
            Text("Capabilities: \(capabilityLabels.joined(separator: ", "))")
            Text("Visible tools: \(tools)")
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.primary)
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
#endif

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

        case .activity:
            return AnyView(
                NavigationStack {
                    WidgetWeaverActivitySettingsView(onClose: { activeSheet = nil })
                }
            )

        case .reminders:
            return AnyView(
                NavigationStack {
                    WidgetWeaverRemindersSettingsView(onClose: { activeSheet = nil })
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

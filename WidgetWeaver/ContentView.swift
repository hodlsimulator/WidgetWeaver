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

    @State private var editorCapabilityChangeEpoch: UInt64 = 0

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

        var id: String { rawValue }

        var title: String {
            switch self {
            case .updated:
                return "Updated"
            case .name:
                return "Name"
            }
        }
    }

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all
        case free
        case pro

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .free:
                return "Free"
            case .pro:
                return "Pro"
            }
        }

        static var ordered: [LibraryFilter] {
            [.all, .free, .pro]
        }
    }

    var librarySort: LibrarySort {
        LibrarySort(rawValue: librarySortRaw) ?? .updated
    }

    var libraryFilter: LibraryFilter {
        LibraryFilter(rawValue: libraryFilterRaw) ?? .all
    }

    var libraryIsFilteringOrSearching: Bool {
        libraryFilter != .all || !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var libraryDisplayedSpecs: [WidgetSpec] {
        var specs = savedSpecs

        // Filter
        switch libraryFilter {
        case .all:
            break
        case .free:
            specs = specs.filter { !$0.isProDesign }
        case .pro:
            specs = specs.filter { $0.isProDesign }
        }

        // Search
        let q = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            specs = specs.filter { $0.name.lowercased().contains(q) }
        }

        // Sort
        switch librarySort {
        case .updated:
            specs.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            specs.sort { $0.name.lowercased() < $1.name.lowercased() }
        }

        return specs
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

    private func noteEditorCapabilitiesDidChange(_ reason: EditorToolCapabilityChangeReason) {
        EditorToolRegistry.capabilitiesDidChange(reason: reason)
        editorCapabilityChangeEpoch &+= 1
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
            previousVisibleToolIDs = editorVisibleToolIDs
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                noteEditorCapabilitiesDidChange(.photoLibraryAccessChanged)
            }
        }
        .onChange(of: proManager.isProUnlocked) { _, _ in
            noteEditorCapabilitiesDidChange(.proStateChanged)
        }
        .onChange(of: matchedSetEnabled) { _, _ in
            noteEditorCapabilitiesDidChange(.matchedSetEnabledChanged)
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
                                        Label("Make default", systemImage: "checkmark.seal")
                                    }
                                }

                                Button {
                                    exportSpec(spec)
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }

                                Button {
                                    duplicateSpec(spec)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    deleteSpec(spec)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Designs")
                        Spacer()
                        Menu {
                            Picker("Sort", selection: $librarySortRaw) {
                                ForEach(LibrarySort.allCases) { s in
                                    Text(s.title).tag(s.rawValue)
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel("Sort designs")
                    }
                }

                Section {
                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import design", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showImageCleanupConfirmation = true
                    } label: {
                        Label("Clean up unused images", systemImage: "sparkles")
                    }
                } header: {
                    Text("Tools")
                }

                Section {
                    Text("Free tier: up to \(WidgetWeaverEntitlements.maxFreeDesigns) saved designs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !proManager.isProUnlocked {
                        Button {
                            activeSheet = .pro
                        } label: {
                            Label("Unlock Pro", systemImage: "crown.fill")
                        }
                    }
                } header: {
                    Text("Pro")
                }
            }
            .searchable(text: $librarySearchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .widgetHelp
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
            }
        }
    }

    private func libraryRow(spec: WidgetSpec) -> some View {
        let label = specDisplayName(spec)
        let updated = WidgetWeaverDateFormat.relative(spec.updatedAt)

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.headline)
                        .lineLimit(1)

                    if spec.isProDesign {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pro design")
                    }
                }

                Text(updated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if spec.id == selectedSpecID {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Selected")
            }
        }
        .padding(.vertical, 6)
    }

    private var editorRoot: some View {
        ZStack {
            WidgetWeaverAboutBackground()

            Form {
                Section {
                    HStack {
                        TextField("Design name", text: $designName)
                            .textInputAutocapitalization(.words)

                        if hasUnsavedChanges {
                            Image(systemName: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Unsaved changes")
                        }
                    }

                    Picker("Preview size", selection: $previewFamily) {
                        Text("Small").tag(WidgetFamily.systemSmall)
                        Text("Medium").tag(WidgetFamily.systemMedium)
                        Text("Large").tag(WidgetFamily.systemLarge)
                    }

                    HStack {
                        Button {
                            save()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!hasUnsavedChanges || importInProgress)

                        Button {
                            showRevertConfirmation = true
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!hasUnsavedChanges || importInProgress)

                        Spacer()

                        Menu {
                            Button {
                                exportCurrentDesign()
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                duplicateSelectedDesign()
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }

                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel("More actions")
                    }
                } header: {
                    sectionHeader("Design")
                }

                Section {
                    widgetPreviewSection
                } header: {
                    sectionHeader("Preview")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let lastSavedAt {
                            Text("Last saved: \(WidgetWeaverDateFormat.relative(lastSavedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let lastWidgetRefreshAt {
                            Text("Last widget refresh: \(WidgetWeaverDateFormat.relative(lastWidgetRefreshAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !saveStatusMessage.isEmpty {
                            Text(saveStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("Editor.SaveStatus")
                        }
                    }
                }

                if FeatureFlags.contextAwareEditorToolSuiteEnabled {
                    toolSuiteSection
                } else {
                    legacyToolsSection
                }

#if DEBUG
                if showEditorDiagnostics {
                    diagnosticsSection
                }
#endif
            }
            .navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            activeSheet = .widgetHelp
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                        }

                        Button {
                            activeSheet = .inspector
                        } label: {
                            Label("Inspector", systemImage: "magnifyingglass")
                        }

                        Button {
                            activeSheet = .variables
                        } label: {
                            Label("Variables", systemImage: "curlybraces")
                        }

                        Button {
                            activeSheet = .activity
                        } label: {
                            Label("Activity", systemImage: "bolt.fill")
                        }

                        Divider()

#if DEBUG
                        Toggle("Show editor diagnostics", isOn: $showEditorDiagnostics)
#endif
                    } label: {
                        Label("Tools", systemImage: "gear")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Editor tools")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .pro
                        } label: {
                            Label("Pro", systemImage: "crown.fill")
                        }

                        Button {
                            activeSheet = .weather
                        } label: {
                            Label("Weather", systemImage: "cloud.sun")
                        }

                        Button {
                            activeSheet = .steps
                        } label: {
                            Label("Steps", systemImage: "figure.walk")
                        }
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
#if DEBUG
            if FeatureFlags.uiTestHooksEnabled {
                WidgetWeaverUITestHooksOverlayButton()
                    .accessibilityIdentifier("Editor.HookOverlay")
            }
#endif
        }
    }

    private var widgetPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetWeaverPreviewHost(
                draft: currentFamilyDraft().toPreviewSpec(
                    style: styleDraft.toStyleSpec(),
                    actionBar: actionBarDraft.toActionBarSpec()
                ),
                family: previewFamily,
                lastRefreshAt: $lastWidgetRefreshAt
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            if matchedSetEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Matched set enabled", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        copyCurrentSizeToAllSizes()
                    } label: {
                        Label("Copy current size to all sizes", systemImage: "square.on.square")
                    }
                    .font(.caption)
                    .disabled(importInProgress)
                }
            }
        }
    }

    private var toolSuiteSection: some View {
        let ctx = editorToolContext
        let visible = editorVisibleToolIDs

        let anyTools = !visible.isEmpty
        let multiSelectionReduced = ctx.selection == .multi

        return Section {
            if multiSelectionReduced {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.multiSelectionToolListReduced(),
                    isBusy: importInProgress
                )
            }

            if !anyTools {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.noToolsAvailableForSelection(),
                    isBusy: importInProgress
                )
            } else {
                ForEach(visible) { toolID in
                    toolRow(toolID: toolID)
                }
            }
        } header: {
            sectionHeader("Tools")
        }
    }

    private func toolRow(toolID: EditorToolID) -> some View {
        let ctx = editorToolContext
        let unavailable = EditorToolRegistry.unavailableState(for: toolID, context: ctx)

        return NavigationLink {
            toolDestination(toolID: toolID, unavailableState: unavailable)
        } label: {
            HStack {
                Label(toolID.title, systemImage: toolID.systemImage)
                Spacer()
                if unavailable != nil {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Unavailable")
                }
            }
        }
        .disabled(importInProgress)
        .accessibilityIdentifier("Editor.Tool.\(toolID.rawValue)")
    }

    private func toolDestination(toolID: EditorToolID, unavailableState: EditorUnavailableState?) -> some View {
        Group {
            if let unavailableState {
                EditorUnavailableStateView(
                    state: unavailableState,
                    isBusy: importInProgress,
                    onCTA: { kind in
                        Task { await performEditorUnavailableCTA(kind) }
                    }
                )
            } else {
                toolEditor(toolID: toolID)
            }
        }
        .navigationTitle(toolID.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toolEditor(toolID: EditorToolID) -> some View {
        switch toolID {
        case .layout:
            layoutSection(focus: $editorFocusSnapshot)
        case .text:
            textContentSection
        case .symbol:
            symbolSection
        case .image:
            imageSection
        case .smartPhoto:
            smartPhotoSection(focus: $editorFocusSnapshot)
        case .smartRules:
            smartRulesSection(focus: $editorFocusSnapshot)
        case .smartPhotoFraming:
            smartPhotoFramingSection(focus: $editorFocusSnapshot)
        case .albumShuffle:
            albumShuffleSection(focus: $editorFocusSnapshot)
        case .typography:
            typographySection
        case .style:
            styleSection
        case .actions:
            actionsSection
        case .variables:
            variablesToolSection
        case .matchedSet:
            matchedSetSection
        case .share:
            shareSection
        case .ai:
            aiSection
        case .purchasePro:
            purchaseProSection
        case .clock:
            clockSection(focus: $editorFocusSnapshot)
        }
    }

    private var legacyToolsSection: some View {
        let tools = editorVisibleToolIDs

        return Section {
            ForEach(tools) { tool in
                NavigationLink {
                    toolEditor(toolID: tool)
                        .navigationTitle(tool.title)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
                .disabled(importInProgress)
                .accessibilityIdentifier("Editor.Tool.\(tool.rawValue)")
            }
        } header: {
            sectionHeader("Tools")
        }
    }

#if DEBUG
    private var diagnosticsSection: some View {
        let ctx = editorToolContext
        let tools = editorVisibleToolIDs.map(\.rawValue).joined(separator: ", ")

        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Context")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(ctx.debugSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("Editor.Diagnostics.Context")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Visible tools")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(tools.isEmpty ? "—" : tools)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("Editor.Diagnostics.Tools")
            }
        } header: {
            sectionHeader("Diagnostics")
        }
    }
#endif
}

private extension ContentView {
    static var didApplyAppearance: Bool = false

    static func applyAppearanceIfNeeded() {
        guard !didApplyAppearance else { return }
        didApplyAppearance = true

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor.systemGray5

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.label
        ]
        UISegmentedControl.appearance().setTitleTextAttributes(attrs, for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes(attrs, for: .normal)
    }
}

private extension WidgetSpec {
    var isProDesign: Bool {
        matchedSet != nil || actionBar?.buttons.isEmpty == false || variables?.isEmpty == false
    }
}

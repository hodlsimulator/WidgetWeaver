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

    @AppStorage("widgetweaver.editor.autoThemeFromImage") var autoThemeFromImage: Bool = true

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

        var id: Int {
            switch self {
            case .widgetHelp: return 1
            case .pro: return 2
            case .variables: return 3
            case .weather: return 4
            case .inspector: return 5
            case .remix: return 6
            case .steps: return 7
            }
        }
    }

    @State var activeSheet: ActiveSheet?

    @State var showImportPicker: Bool = false
    @State var importInProgress: Bool = false

    let store = WidgetSpecStore.shared

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
        ZStack {
            EditorBackground()

            List {
                Section {
                    if savedSpecs.isEmpty {
                        Text("No saved designs yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(savedSpecs) { spec in
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
                        Text("Tip: add a WidgetWeaver widget on your Home Screen, then long‑press → Edit Widget to choose a Design.")
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
        .toolbar {
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

                Text(spec.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
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
            EditorBackground()
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
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importDesigns(from: url) }

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

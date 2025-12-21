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

    enum ActiveSheet: Identifiable {
        case widgetHelp
        case pro
        case about
        case variables
        case inspector
        case remix
        case weather
        case steps

        var id: Int {
            switch self {
            case .widgetHelp: return 1
            case .pro: return 2
            case .about: return 3
            case .variables: return 4
            case .weather: return 5
            case .inspector: return 6
            case .remix: return 7
            case .steps: return 8
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
        NavigationStack {
            editorRoot
        }
    }

    private var editorRoot: some View {
        ZStack {
            EditorBackground()
            editorLayout
        }
        .navigationTitle("WidgetWeaver")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { editorToolbar }
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
        .sheet(item: $activeSheet, content: sheetContent)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: WidgetWeaverSharePackage.importableTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImportResult
        )
        .onAppear(perform: bootstrap)
        .onChange(of: selectedSpecID) { _, _ in loadSelected() }
        .onChange(of: pickedPhoto) { _, newItem in
            handlePickedPhotoChange(newItem)
        }
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

        case .about:
            return AnyView(
                WidgetWeaverAboutView(
                    proManager: proManager,
                    onAddTemplate: { spec, makeDefault in
                        addTemplateDesign(spec, makeDefault: makeDefault)
                    },
                    onShowPro: { activeSheet = .pro },
                    onShowWidgetHelp: { activeSheet = .widgetHelp }
                )
            )

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

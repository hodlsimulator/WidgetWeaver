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

    @State var savedSpecs: [WidgetSpec] = []
    @State var defaultSpecID: UUID?
    @State var selectedSpecID: UUID = UUID()

    @State var designName: String = "WidgetWeaver"
    @State var styleDraft: StyleDraft = .defaultDraft

    @State var baseDraft: FamilyDraft = .defaultDraft

    @State var matchedSetEnabled: Bool = false
    @State var matchedDrafts: MatchedDrafts = MatchedDrafts(
        small: .defaultDraft,
        medium: .defaultDraft,
        large: .defaultDraft
    )

    @State var pickedPhoto: PhotosPickerItem?

    @State var aiPrompt: String = ""
    @State var aiMakeGeneratedDefault: Bool = true
    @State var aiPatchInstruction: String = ""
    @State var aiStatusMessage: String = ""

    @State var previewFamily: WidgetFamily = .systemSmall

    @State var lastSavedAt: Date?
    @State var lastWidgetRefreshAt: Date?
    @State var saveStatusMessage: String = ""

    @State var showDeleteConfirmation: Bool = false

    enum ActiveSheet: Identifiable {
        case widgetHelp
        case pro

        var id: Int {
            switch self {
            case .widgetHelp: return 1
            case .pro: return 2
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
            ZStack {
                EditorBackground()
                editorLayout
            }
            .navigationTitle("WidgetWeaver")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { toolbarMenu }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { Keyboard.dismiss() }
                }
            }
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .widgetHelp:
                    WidgetWorkflowHelpView()
                case .pro:
                    WidgetWeaverProView(manager: proManager)
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: WidgetWeaverSharePackage.importableTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await importDesigns(from: url) }

                case .failure(let error):
                    if (error as NSError).code == NSUserCancelledError { return }
                    saveStatusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            .onAppear { bootstrap() }
            .onChange(of: selectedSpecID) { _, _ in loadSelected() }
            .onChange(of: pickedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await importPickedImage(newItem) }
            }
        }
    }
}

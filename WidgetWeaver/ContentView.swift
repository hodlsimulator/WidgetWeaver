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
                return $0.index < $1.index
            }
        case .template:
            items.sort {
                if $0.templateKey != $1.templateKey { return $0.templateKey < $1.templateKey }
                return $0.index < $1.index
            }
        case .accent:
            items.sort {
                if $0.accentKey != $1.accentKey { return $0.accentKey < $1.accentKey }
                return $0.index < $1.index
            }
        }

        return items.map(\.spec)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                exploreRoot
                    .tag(AppTab.explore)
                    .tabItem { Label("Explore", systemImage: "sparkles") }

                libraryRoot
                    .tag(AppTab.library)
                    .tabItem { Label("Library", systemImage: "square.grid.2x2") }

                editorRoot
                    .tag(AppTab.editor)
                    .tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
            }
            .onAppear { loadSavedSpecs() }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(sheet)
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert("Delete Design?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteSelected() }
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Clean unused images?", isPresented: $showImageCleanupConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clean", role: .destructive) { cleanUnusedImages() }
            } message: {
                Text("This removes files that are not referenced by any saved design.")
            }
            .alert("Revert changes?", isPresented: $showRevertConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Revert", role: .destructive) { revertUnsavedChanges() }
            } message: {
                Text("This will reset the draft back to the last saved version.")
            }
        }
    }

    private var exploreRoot: some View {
        ZStack {
            WidgetWeaverAboutBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WidgetWeaverAboutHeader()

                    WidgetWeaverAboutSection(
                        title: "WidgetWeaver",
                        subtitle: "Design widgets by mixing templates, colours, text, and Smart Photos."
                    )

                    WidgetWeaverAboutSection(
                        title: "Smart Photos",
                        subtitle: "Create a crop + framing that looks good across widget sizes."
                    )

                    WidgetWeaverAboutSection(
                        title: "Variables",
                        subtitle: "Insert dynamic content like steps, activity, date/time, and counters."
                    )

                    WidgetWeaverAboutSection(
                        title: "Pro",
                        subtitle: "Unlock matched sets, action bar widgets, and more."
                    )

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { exploreToolbar }
    }

    @ToolbarContentBuilder
    private var exploreToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { toolbarMenu }
    }

    private var libraryRoot: some View {
        ZStack {
            WidgetWeaverAboutBackground()

            VStack(spacing: 12) {
                libraryHeader

                if savedSpecs.isEmpty {
                    ContentUnavailableView(
                        "No designs yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Create a design in the editor, then save it to appear here.")
                    )
                    .padding(.top, 30)
                } else {
                    libraryList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { libraryToolbar }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { toolbarMenu }
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

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { remixToolbarButton }
        ToolbarItem(placement: .topBarTrailing) { toolbarMenu }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { Keyboard.dismiss() }
        }
    }

#if DEBUG
    private var editorDiagnosticsOverlay: some View {
        let ctx = editorToolContext
        let caps = EditorToolRegistry.capabilities(for: ctx)

        let capLabels: [String] = [
            (EditorCapabilities.canEditLayout, "layout"),
            (EditorCapabilities.canEditTextContent, "text"),
            (EditorCapabilities.canEditSymbol, "symbol"),
            (EditorCapabilities.canEditImage, "image"),
            (EditorCapabilities.canEditSmartPhoto, "smartPhoto"),
            (EditorCapabilities.canEditStyle, "style"),
            (EditorCapabilities.canEditTypography, "typography"),
            (EditorCapabilities.canEditActions, "actions")
        ]
            .compactMap { caps.contains($0.0) ? $0.1 : nil }

        let tools = editorVisibleToolIDs.map { $0.rawValue }

        return VStack(alignment: .leading, spacing: 4) {
            Text("Context: \(ctx.template.displayName)")
            Text("Matched: \(ctx.matchedSetEnabled ? "On" : "Off") • Editing: \(editingFamilyLabel)")
            Text("Configured: image \(ctx.hasImageConfigured ? "yes" : "no"), smart \(ctx.hasSmartPhotoConfigured ? "yes" : "no"), symbol \(ctx.hasSymbolConfigured ? "yes" : "no")")
            Text("Capabilities: \(capLabels.joined(separator: ", "))")
            Text("Tools: \(tools.joined(separator: ", "))")
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
#endif

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

        case .importReview:
            guard let importReviewModel else { return AnyView(EmptyView()) }
            return AnyView(
                NavigationStack {
                    WidgetWeaverImportReviewView(
                        model: importReviewModel,
                        selection: $importReviewSelection,
                        onClose: { activeSheet = nil }
                    )
                }
            )
        }
    }
}

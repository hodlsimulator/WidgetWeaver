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

    @State var lastSavedAt: Date?
    @State var lastWidgetRefreshAt: Date?
    @State var saveStatusMessage: String = ""

    @State var selectedTab: ContentTab = .library
    @State var activeSheet: ContentSheet? = nil

    @AppStorage("widgetweaver.preview.family") var previewFamily: WidgetFamily = .systemSmall
    @AppStorage("widgetweaver.preview.device") var previewDevice: WidgetPreviewDeviceToken = .current
    @AppStorage("widgetweaver.preview.colorScheme") var previewColorScheme: WidgetPreviewColorSchemeToken = .system

    @AppStorage("widgetweaver.internal.showTools") var showInternalTools: Bool = false
    @AppStorage("widgetweaver.internal.thumbnailRenderingEnabled") var thumbnailRenderingEnabled: Bool = true

    // MARK: - Store

    let store = WidgetSpecStore.shared

    // MARK: - Tabs

    enum ContentTab: String, CaseIterable, Identifiable {
        case library
        case editor
        case preview
        case weather
        case variables

        var id: String { rawValue }

        var title: String {
            switch self {
            case .library: return "Library"
            case .editor: return "Editor"
            case .preview: return "Preview"
            case .weather: return "Weather"
            case .variables: return "Variables"
            }
        }

        var systemImage: String {
            switch self {
            case .library: return "square.grid.2x2"
            case .editor: return "slider.horizontal.3"
            case .preview: return "rectangle.inset.filled"
            case .weather: return "cloud.sun"
            case .variables: return "curlybraces"
            }
        }
    }

    enum ContentSheet: Identifiable {
        case share
        case importReview(model: WidgetWeaverImportReviewModel)
        case widgetsHelp
        case support(spec: WidgetSpec)
        case pro
        case calendarPermission
        case weatherPermission
        case variablesHelp

        var id: String {
            switch self {
            case .share: return "share"
            case .importReview(let model): return "importReview.\(model.id.uuidString)"
            case .widgetsHelp: return "widgetsHelp"
            case .support(let spec): return "support.\(spec.id.uuidString)"
            case .pro: return "pro"
            case .calendarPermission: return "calendarPermission"
            case .weatherPermission: return "weatherPermission"
            case .variablesHelp: return "variablesHelp"
            }
        }
    }

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
    }

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all
        case `default`
        case weather
        case nextUp
        case steps
        case withImage

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

        static var ordered: [LibraryFilter] {
            [.all, .default, .weather, .nextUp, .steps, .withImage]
        }
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
                return !item.spec.normalised().allReferencedImageFileNames().isEmpty
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
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func libraryFilterChip(_ filter: LibraryFilter) -> some View {
        let isSelected = (libraryFilter == filter)

        return Button {
            libraryFilterRaw = filter.rawValue
        } label: {
            Text(filter.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var librarySortMenu: some View {
        Menu {
            Picker("Sort", selection: $librarySortRaw) {
                ForEach(LibrarySort.allCases) { sort in
                    Text(sort.title).tag(sort.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            libraryTab
                .tabItem { Label(ContentTab.library.title, systemImage: ContentTab.library.systemImage) }
                .tag(ContentTab.library)

            editorTab
                .tabItem { Label(ContentTab.editor.title, systemImage: ContentTab.editor.systemImage) }
                .tag(ContentTab.editor)

            previewTab
                .tabItem { Label(ContentTab.preview.title, systemImage: ContentTab.preview.systemImage) }
                .tag(ContentTab.preview)

            weatherTab
                .tabItem { Label(ContentTab.weather.title, systemImage: ContentTab.weather.systemImage) }
                .tag(ContentTab.weather)

            variablesTab
                .tabItem { Label(ContentTab.variables.title, systemImage: ContentTab.variables.systemImage) }
                .tag(ContentTab.variables)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .share:
                WidgetWeaverShareSheet(
                    specs: savedSpecs,
                    defaultSpecID: defaultSpecID,
                    onDismiss: { activeSheet = nil }
                )

            case .importReview(let model):
                WidgetWeaverImportReviewContainer(
                    model: model,
                    proManager: proManager,
                    onDismiss: { activeSheet = nil },
                    onImported: {
                        refreshSavedSpecs(preservingSelection: true)
                        activeSheet = nil
                    }
                )

            case .widgetsHelp:
                WidgetWorkflowHelpView()

            case .support(let spec):
                WidgetWeaverSupportSheet(spec: spec)

            case .pro:
                WidgetWeaverProSheet()

            case .calendarPermission:
                WidgetWeaverCalendarPermissionSheet()

            case .weatherPermission:
                WidgetWeaverWeatherPermissionSheet()

            case .variablesHelp:
                WidgetWeaverVariablesHelpSheet()
            }
        }
        .task {
            refreshSavedSpecs(preservingSelection: false)
        }
        .onChange(of: selectedTab) { _ in
            if selectedTab == .library {
                refreshSavedSpecs(preservingSelection: true)
            }
        }
    }

    // MARK: - Tabs

    private var libraryTab: some View {
        NavigationStack {
            ZStack {
                EditorBackground()

                VStack(spacing: 0) {
                    libraryHeader

                    if libraryDisplayedSpecs.isEmpty {
                        libraryEmptyState
                    } else {
                        libraryList
                    }
                }
            }
            .navigationTitle("WidgetWeaver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    librarySortMenu
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .share
                        } label: {
                            Label("Share designs", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            importTapped()
                        } label: {
                            Label("Import designs", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            activeSheet = .widgetsHelp
                        } label: {
                            Label("Widgets help", systemImage: "questionmark.circle")
                        }

                        Button {
                            activeSheet = .pro
                        } label: {
                            Label("Pro", systemImage: "crown")
                        }

                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var editorTab: some View {
        NavigationStack {
            ZStack {
                EditorBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        editorHeader
                        editorSections
                        proUpsellIfNeeded
                        internalToolsIfNeeded
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .widgetsHelp
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
        }
    }

    private var previewTab: some View {
        WidgetPreviewDock(
            spec: draftSpec(id: selectedSpecID),
            previewFamily: $previewFamily,
            previewDevice: $previewDevice,
            previewColorScheme: $previewColorScheme,
            selectedTab: $selectedTab
        )
    }

    private var weatherTab: some View {
        WidgetWeaverWeatherScreen(
            proManager: proManager,
            onNeedPermission: { activeSheet = .weatherPermission }
        )
    }

    private var variablesTab: some View {
        WidgetWeaverVariablesScreen(
            proManager: proManager,
            onNeedHelp: { activeSheet = .variablesHelp },
            onNeedPro: { activeSheet = .pro }
        )
    }

    // MARK: - Editor sections

    private var editorSections: some View {
        VStack(spacing: 14) {
            contentSection
            matchedSetSection
            textSection
            symbolSection
            imageSection
            layoutSection
            styleSection
            actionBarSection
        }
    }

    private var proUpsellIfNeeded: some View {
        Group {
            if !proManager.isProUnlocked {
                proUpsellSection
            }
        }
    }

    private var internalToolsIfNeeded: some View {
        Group {
            if showInternalTools {
                internalToolsSection
            }
        }
    }
}

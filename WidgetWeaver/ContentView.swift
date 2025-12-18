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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var savedSpecs: [WidgetSpec] = []
    @State private var defaultSpecID: UUID?
    @State private var selectedSpecID: UUID = UUID()

    // Global (shared across sizes)
    @State private var designName: String = "WidgetWeaver"
    @State private var styleDraft: StyleDraft = .defaultDraft

    // Single-spec mode draft (legacy behaviour)
    @State private var baseDraft: FamilyDraft = .defaultDraft

    // Matched set drafts (per size). Medium acts as the base.
    @State private var matchedSetEnabled: Bool = false
    @State private var matchedDrafts: MatchedDrafts = MatchedDrafts(
        small: .defaultDraft,
        medium: .defaultDraft,
        large: .defaultDraft
    )

    // Photos picker
    @State private var pickedPhoto: PhotosPickerItem?

    // AI
    @State private var aiPrompt: String = ""
    @State private var aiMakeGeneratedDefault: Bool = true
    @State private var aiPatchInstruction: String = ""
    @State private var aiStatusMessage: String = ""

    // Preview
    @State private var previewFamily: WidgetFamily = .systemSmall

    // Status
    @State private var lastSavedAt: Date?
    @State private var lastWidgetRefreshAt: Date?
    @State private var saveStatusMessage: String = ""

    // UI
    @State private var showDeleteConfirmation: Bool = false
    @State private var showWidgetHelp: Bool = false

    // Sharing / Import
    @State private var showImportPicker: Bool = false
    @State private var importInProgress: Bool = false

    private let store = WidgetSpecStore.shared

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
            .sheet(isPresented: $showWidgetHelp) {
                WidgetWorkflowHelpView()
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
                    if (error as NSError).code == NSUserCancelledError {
                        return
                    }
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

    // MARK: - Share package (Transferable)

    private struct WidgetWeaverSharePackage: Transferable {
        let fileName: String
        let data: Data

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .json) { package in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(package.fileName)
                try package.data.write(to: url, options: [.atomic])
                return SentTransferredFile(url)
            } importing: { received in
                let data = try Data(contentsOf: received.file)
                return WidgetWeaverSharePackage(fileName: received.file.lastPathComponent, data: data)
            }
        }

        static var importableTypes: [UTType] {
            [.json, .data]
        }

        static func suggestedFileName(prefix: String, suffix: String) -> String {
            let safePrefix = sanitise(prefix)
            let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            return "\(safePrefix)-\(suffix)-\(date).json"
        }

        private static func sanitise(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = trimmed.isEmpty ? "WidgetWeaver" : trimmed

            var out = ""
            out.reserveCapacity(min(fallback.count, 64))

            for ch in fallback {
                if ch.isLetter || ch.isNumber {
                    out.append(ch)
                } else if ch == " " || ch == "-" || ch == "_" {
                    out.append("-")
                } else {
                    out.append("-")
                }

                if out.count >= 64 { break }
            }

            while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
            out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

            return out.isEmpty ? "WidgetWeaver" : out
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var editorLayout: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 16) {
                previewDock(presentation: .sidebar)
                    .frame(width: 420)
                    .padding(.top, 8)

                editorForm
            }
            .padding(.horizontal, 16)
        } else {
            editorForm
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: WidgetPreviewDock.reservedInsetHeight(verticalSizeClass: verticalSizeClass))
                }
                .overlay(alignment: .bottom) {
                    previewDock(presentation: .dock)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
        }
    }

    private var editorForm: some View {
        Form {
            designsSection
            sharingSection
            matchedSetSection
            widgetWorkflowSection
            textSection
            symbolSection
            imageSection
            layoutSection
            styleSection
            typographySection
            aiSection
            statusSection
        }
        .font(.subheadline)
        .controlSize(.small)
        .environment(\.defaultMinListRowHeight, 36)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
    }

    private func previewDock(presentation: WidgetPreviewDock.Presentation) -> some View {
        WidgetPreviewDock(
            spec: draftSpec(id: selectedSpecID),
            family: $previewFamily,
            presentation: presentation
        )
    }

    // MARK: - Toolbar

    private var toolbarMenu: some View {
        Menu {
            Button { showWidgetHelp = true } label: {
                Label("Widget Help", systemImage: "questionmark.circle")
            }

            Divider()

            Button { createNewDesign() } label: {
                Label("New Design", systemImage: "plus")
            }

            Button { duplicateCurrentDesign() } label: {
                Label("Duplicate Design", systemImage: "doc.on.doc")
            }
            .disabled(savedSpecs.isEmpty)

            Divider()

            Button { saveSelected(makeDefault: true) } label: {
                Label("Save & Make Default", systemImage: "checkmark.circle")
            }

            Button { saveSelected(makeDefault: false) } label: {
                Label("Save (Keep Default)", systemImage: "tray.and.arrow.down")
            }

            Divider()

            // Sharing / Import (Milestone 7)
            ShareLink(item: sharePackageForCurrentDesign(), preview: SharePreview("WidgetWeaver Design")) {
                Label("Share This Design", systemImage: "square.and.arrow.up")
            }

            ShareLink(item: sharePackageForAllDesigns(), preview: SharePreview("WidgetWeaver Designs")) {
                Label("Share All Designs", systemImage: "square.and.arrow.up.on.square")
            }

            Button { showImportPicker = true } label: {
                Label("Import Designs…", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button { refreshWidgets() } label: {
                Label("Refresh Widgets", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label("Delete Design", systemImage: "trash")
            }
            .disabled(savedSpecs.count <= 1)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Section styling

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Editing family (driven by preview size)

    private var editingFamily: EditingFamily {
        EditingFamily(widgetFamily: previewFamily) ?? .small
    }

    private var editingFamilyLabel: String {
        editingFamily.label
    }

    // MARK: - Active draft helpers

    private func currentFamilyDraft() -> FamilyDraft {
        matchedSetEnabled ? matchedDrafts[editingFamily] : baseDraft
    }

    private func setCurrentFamilyDraft(_ newValue: FamilyDraft) {
        if matchedSetEnabled {
            matchedDrafts[editingFamily] = newValue
        } else {
            baseDraft = newValue
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<FamilyDraft, T>) -> Binding<T> {
        Binding(
            get: { currentFamilyDraft()[keyPath: keyPath] },
            set: { newValue in
                var d = currentFamilyDraft()
                d[keyPath: keyPath] = newValue
                setCurrentFamilyDraft(d)
            }
        )
    }

    private var matchedSetBinding: Binding<Bool> {
        Binding(
            get: { matchedSetEnabled },
            set: { setMatchedSetEnabled($0) }
        )
    }

    private func setMatchedSetEnabled(_ enabled: Bool) {
        guard enabled != matchedSetEnabled else { return }

        if enabled {
            matchedDrafts = MatchedDrafts(small: baseDraft, medium: baseDraft, large: baseDraft)
            matchedSetEnabled = true
        } else {
            baseDraft = matchedDrafts.medium
            matchedSetEnabled = false
        }
    }

    private func copyCurrentSizeToAllSizes() {
        guard matchedSetEnabled else { return }
        let d = matchedDrafts[editingFamily]
        matchedDrafts = MatchedDrafts(small: d, medium: d, large: d)
        saveStatusMessage = "Copied \(editingFamilyLabel) settings to Small/Medium/Large (draft only)."
    }

    // MARK: - Sections

    private var designsSection: some View {
        Section {
            if savedSpecs.isEmpty {
                Text("No saved designs yet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Design", selection: $selectedSpecID) {
                    ForEach(savedSpecs) { spec in
                        Text(specDisplayName(spec)).tag(spec.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let defaultName {
                LabeledContent("App default", value: defaultName)
            }

            if selectedSpecID == defaultSpecID {
                Text("This design is the app default.\nWidgets set to \"Default (App)\" will show it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This design is not the app default.\nUse \"Save & Make Default\" to update widgets set to \"Default (App)\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                Button { createNewDesign() } label: {
                    Label("New", systemImage: "plus")
                }

                Button { duplicateCurrentDesign() } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .disabled(savedSpecs.isEmpty)

                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(savedSpecs.count <= 1)
            }
            .controlSize(.small)
        } header: {
            sectionHeader("Design")
        } footer: {
            Text("Each widget instance can be configured to follow \"Default (App)\" or a specific saved design (long-press the widget → Edit Widget).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sharingSection: some View {
        Section {
            if importInProgress {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Importing…")
                        .foregroundStyle(.secondary)
                }
            }

            ShareLink(item: sharePackageForCurrentDesign(), preview: SharePreview("WidgetWeaver Design")) {
                Label("Share This Design", systemImage: "square.and.arrow.up")
            }

            ShareLink(item: sharePackageForAllDesigns(), preview: SharePreview("WidgetWeaver Designs")) {
                Label("Share All Designs", systemImage: "square.and.arrow.up.on.square")
            }

            Button {
                showImportPicker = true
            } label: {
                Label("Import designs…", systemImage: "square.and.arrow.down")
            }
        } header: {
            sectionHeader("Sharing")
        } footer: {
            Text("Exports are JSON and include embedded images when available. Imported designs are duplicated with new IDs to avoid overwriting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var matchedSetSection: some View {
        Section {
            Toggle("Matched set (Small/Medium/Large)", isOn: matchedSetBinding)

            if matchedSetEnabled {
                Text("Editing is per preview size: \(editingFamilyLabel).\nUse the preview size picker to edit Small/Medium/Large. Style and typography are shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button { copyCurrentSizeToAllSizes() } label: {
                    Label("Copy \(editingFamilyLabel) to all sizes", systemImage: "square.on.square")
                }
            } else {
                Text("When enabled, Small and Large can differ while sharing the same style tokens.\nMedium is treated as the base.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Matched set")
        }
    }

    private var widgetWorkflowSection: some View {
        Section {
            Button { saveSelected(makeDefault: true) } label: {
                Label("Save & Make Default", systemImage: "checkmark.circle.fill")
            }

            Button { saveSelected(makeDefault: false) } label: {
                Label("Save (Keep Default)", systemImage: "tray.and.arrow.down")
            }

            if selectedSpecID != defaultSpecID {
                Button {
                    store.setDefault(id: selectedSpecID)
                    defaultSpecID = store.defaultSpecID()
                    lastWidgetRefreshAt = Date()
                    saveStatusMessage = "Made default.\nWidgets refreshed."
                } label: {
                    Label("Make This Design Default", systemImage: "star")
                }
            }

            Button { refreshWidgets() } label: {
                Label("Refresh Widgets", systemImage: "arrow.clockwise")
            }

            if !saveStatusMessage.isEmpty {
                Text(saveStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastWidgetRefreshAt {
                Text("Last refresh: \(lastWidgetRefreshAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Widgets")
        } footer: {
            Text("If a widget doesn’t change, check which Design it is using (Edit Widget).\nWidgets set to \"Default (App)\" always follow the app default design.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var textSection: some View {
        Section {
            TextField("Design name", text: $designName)
                .textInputAutocapitalization(.words)

            TextField("Primary text", text: binding(\.primaryText))

            TextField("Secondary text (optional)", text: binding(\.secondaryText))

            if matchedSetEnabled {
                Text("Text fields are currently editing: \(editingFamilyLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Text")
        }
    }

    private var symbolSection: some View {
        Section {
            TextField("SF Symbol name (optional)", text: binding(\.symbolName))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Picker("Placement", selection: binding(\.symbolPlacement)) {
                ForEach(SymbolPlacementToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            HStack {
                Text("Size")
                Slider(value: binding(\.symbolSize), in: 8...96, step: 1)
                Text("\(Int(currentFamilyDraft().symbolSize))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Picker("Weight", selection: binding(\.symbolWeight)) {
                ForEach(SymbolWeightToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Rendering", selection: binding(\.symbolRenderingMode)) {
                ForEach(SymbolRenderingModeToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Tint", selection: binding(\.symbolTint)) {
                ForEach(SymbolTintToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }
        } header: {
            sectionHeader("Symbol")
        }
    }

    private var imageSection: some View {
        let currentImageFileName = currentFamilyDraft().imageFileName
        let hasImage = !currentImageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Section {
            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                Label(hasImage ? "Replace photo" : "Choose photo (optional)", systemImage: "photo")
            }

            if hasImage {
                if let uiImage = AppGroup.loadUIImage(fileName: currentImageFileName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text("Selected image file not found in App Group.")
                        .foregroundStyle(.secondary)
                }

                Picker("Content mode", selection: binding(\.imageContentMode)) {
                    ForEach(ImageContentModeToken.allCases) { token in
                        Text(token.rawValue).tag(token)
                    }
                }

                HStack {
                    Text("Height")
                    Slider(value: binding(\.imageHeight), in: 40...240, step: 1)
                    Text("\(Int(currentFamilyDraft().imageHeight))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Corner radius")
                    Slider(value: binding(\.imageCornerRadius), in: 0...44, step: 1)
                    Text("\(Int(currentFamilyDraft().imageCornerRadius))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    var d = currentFamilyDraft()
                    d.imageFileName = ""
                    setCurrentFamilyDraft(d)
                } label: {
                    Text("Remove image")
                }
            } else {
                Text("No image selected.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Image")
        }
    }

    private var layoutSection: some View {
        Section {
            Picker("Axis", selection: binding(\.axis)) {
                ForEach(LayoutAxisToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Alignment", selection: binding(\.alignment)) {
                ForEach(LayoutAlignmentToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            HStack {
                Text("Spacing")
                Slider(value: binding(\.spacing), in: 0...32, step: 1)
                Text("\(Int(currentFamilyDraft().spacing))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if editingFamily == .small {
                Stepper(
                    "Primary line limit: \(currentFamilyDraft().primaryLineLimitSmall)",
                    value: binding(\.primaryLineLimitSmall),
                    in: 1...8
                )
            } else {
                Stepper(
                    "Primary line limit: \(currentFamilyDraft().primaryLineLimit)",
                    value: binding(\.primaryLineLimit),
                    in: 1...10
                )

                Stepper(
                    "Secondary line limit: \(currentFamilyDraft().secondaryLineLimit)",
                    value: binding(\.secondaryLineLimit),
                    in: 1...10
                )
            }
        } header: {
            sectionHeader("Layout")
        }
    }

    private var styleSection: some View {
        Section {
            HStack {
                Text("Padding")
                Slider(value: $styleDraft.padding, in: 0...32, step: 1)
                Text("\(Int(styleDraft.padding))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Corner radius")
                Slider(value: $styleDraft.cornerRadius, in: 0...44, step: 1)
                Text("\(Int(styleDraft.cornerRadius))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Picker("Background", selection: $styleDraft.background) {
                ForEach(BackgroundToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Accent", selection: $styleDraft.accent) {
                ForEach(AccentToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            if matchedSetEnabled {
                Text("Style is shared across Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Style")
        }
    }

    private var typographySection: some View {
        Section {
            Picker("Name text style", selection: $styleDraft.nameTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Primary text style", selection: $styleDraft.primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Secondary text style", selection: $styleDraft.secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            if matchedSetEnabled {
                Text("Typography is shared across Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Typography")
        }
    }

    private var aiSection: some View {
        Section {
            Text(WidgetSpecAIService.availabilityMessage())
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Optional on-device generation/edits.\nImages are never generated.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Prompt (new design)", text: $aiPrompt, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            Toggle("Make generated design default", isOn: $aiMakeGeneratedDefault)

            Button("Generate New Design") {
                Task { await generateNewDesignFromPrompt() }
            }
            .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Divider()

            TextField("Patch instruction (edit current design)", text: $aiPatchInstruction, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            Button("Apply Patch To Current Design") {
                Task { await applyPatchToCurrentDesign() }
            }
            .disabled(aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !aiStatusMessage.isEmpty {
                Text(aiStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("AI")
        }
    }

    private var statusSection: some View {
        Section {
            if let lastSavedAt {
                Text("Saved: \(lastSavedAt.formatted(date: .abbreviated, time: .standard))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Not saved yet.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Status")
        }
    }

    // MARK: - Derived helpers

    private var defaultName: String? {
        guard let defaultSpecID else { return nil }
        return savedSpecs.first(where: { $0.id == defaultSpecID })?.name ?? store.loadDefault().name
    }

    private func specDisplayName(_ spec: WidgetSpec) -> String {
        if spec.id == defaultSpecID { return "\(spec.name) (Default)" }
        return spec.name
    }

    // MARK: - Model glue

    private func bootstrap() {
        refreshSavedSpecs(preservingSelection: false)
        loadSelected()
    }

    private func refreshSavedSpecs(preservingSelection: Bool = true) {
        let specs = store
            .loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }

        savedSpecs = specs
        defaultSpecID = store.defaultSpecID()

        if preservingSelection, specs.contains(where: { $0.id == selectedSpecID }) {
            return
        }

        let fallback = store.loadDefault()
        selectedSpecID = defaultSpecID ?? fallback.id
    }

    private func applySpec(_ spec: WidgetSpec) {
        let n = spec.normalised()

        designName = n.name
        styleDraft = StyleDraft(from: n.style)
        lastSavedAt = n.updatedAt

        if n.matchedSet != nil {
            matchedSetEnabled = true

            let smallFlat = n.resolved(for: .systemSmall)
            let mediumFlat = n.resolved(for: .systemMedium)
            let largeFlat = n.resolved(for: .systemLarge)

            matchedDrafts = MatchedDrafts(
                small: FamilyDraft(from: smallFlat),
                medium: FamilyDraft(from: mediumFlat),
                large: FamilyDraft(from: largeFlat)
            )

            baseDraft = matchedDrafts.medium
        } else {
            matchedSetEnabled = false
            baseDraft = FamilyDraft(from: n)
            matchedDrafts = MatchedDrafts(small: baseDraft, medium: baseDraft, large: baseDraft)
        }
    }

    private func draftSpec(id: UUID) -> WidgetSpec {
        let trimmedName = designName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "WidgetWeaver" : trimmedName
        let style = styleDraft.toStyleSpec()

        if matchedSetEnabled {
            let base = matchedDrafts.medium
            let baseSpec = base.toFlatSpec(
                id: id,
                name: finalName,
                style: style,
                updatedAt: lastSavedAt ?? Date()
            )

            let matched = WidgetSpecMatchedSet(
                small: matchedDrafts.small.toVariantSpec(),
                medium: nil,
                large: matchedDrafts.large.toVariantSpec()
            )

            var out = baseSpec
            out.matchedSet = matched
            return out.normalised()
        } else {
            let out = baseDraft.toFlatSpec(
                id: id,
                name: finalName,
                style: style,
                updatedAt: lastSavedAt ?? Date()
            )
            return out.normalised()
        }
    }

    // MARK: - Photos import

    private func importPickedImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: data) else { return }

            let fileName = AppGroup.createImageFileName(ext: "jpg")
            try AppGroup.writeUIImage(uiImage, fileName: fileName, compressionQuality: 0.85)

            await MainActor.run {
                var d = currentFamilyDraft()
                d.imageFileName = fileName
                setCurrentFamilyDraft(d)
                pickedPhoto = nil
            }
        } catch {
            // Intentionally ignored (image remains unchanged).
        }
    }

    // MARK: - Actions

    private func loadSelected() {
        let spec = store.load(id: selectedSpecID) ?? store.loadDefault()
        applySpec(spec)
    }

    private func saveSelected(makeDefault: Bool) {
        var spec = draftSpec(id: selectedSpecID)
        spec.updatedAt = Date()
        spec = spec.normalised()

        store.save(spec, makeDefault: makeDefault)

        lastSavedAt = spec.updatedAt
        defaultSpecID = store.defaultSpecID()
        lastWidgetRefreshAt = Date()

        saveStatusMessage = makeDefault
            ? "Saved and set as default.\nWidgets refreshed."
            : "Saved.\nWidgets refreshed."

        refreshSavedSpecs(preservingSelection: true)
    }

    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        lastWidgetRefreshAt = Date()
        saveStatusMessage = "Widgets refreshed."
    }

    private func createNewDesign() {
        var spec = WidgetSpec.defaultSpec().normalised()
        spec.id = UUID()
        spec.updatedAt = Date()
        spec.name = "New Design"

        store.save(spec, makeDefault: false)

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        saveStatusMessage = "Created a new design."
    }

    private func duplicateCurrentDesign() {
        let base = draftSpec(id: selectedSpecID)

        var spec = base
        spec.id = UUID()
        spec.updatedAt = Date()
        spec.name = "Copy of \(base.name)"

        store.save(spec, makeDefault: false)

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        saveStatusMessage = "Duplicated design."
    }

    private func deleteCurrentDesign() {
        store.delete(id: selectedSpecID)
        refreshSavedSpecs(preservingSelection: false)
        loadSelected()
        lastWidgetRefreshAt = Date()
        saveStatusMessage = "Deleted design.\nWidgets refreshed."
    }

    // MARK: - AI

    @MainActor
    private func generateNewDesignFromPrompt() async {
        aiStatusMessage = ""

        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let result = await WidgetSpecAIService.shared.generateNewSpec(from: prompt)

        var spec = result.spec.normalised()
        spec.updatedAt = Date()

        store.save(spec, makeDefault: aiMakeGeneratedDefault)

        defaultSpecID = store.defaultSpecID()
        lastWidgetRefreshAt = Date()
        aiStatusMessage = result.note
        aiPrompt = ""

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        saveStatusMessage = "Generated design saved.\nWidgets refreshed."
    }

    @MainActor
    private func applyPatchToCurrentDesign() async {
        aiStatusMessage = ""

        let instruction = aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        let style = styleDraft.toStyleSpec()
        let current = currentFamilyDraft().toFlatSpec(
            id: selectedSpecID,
            name: designName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "WidgetWeaver" : designName.trimmingCharacters(in: .whitespacesAndNewlines),
            style: style,
            updatedAt: Date()
        )

        let result = await WidgetSpecAIService.shared.applyPatch(to: current, instruction: instruction)
        let patched = result.spec.normalised()

        // Apply back to drafts (current size + shared style/name).
        designName = patched.name
        styleDraft = StyleDraft(from: patched.style)

        var d = currentFamilyDraft()
        d.apply(flatSpec: patched)
        setCurrentFamilyDraft(d)

        // Save combined spec back to store.
        var combined = draftSpec(id: selectedSpecID).normalised()
        combined.updatedAt = Date()
        store.save(combined, makeDefault: false)

        lastSavedAt = combined.updatedAt
        lastWidgetRefreshAt = Date()
        aiStatusMessage = result.note
        aiPatchInstruction = ""

        refreshSavedSpecs(preservingSelection: true)

        saveStatusMessage = "Patched design saved.\nWidgets refreshed."
    }

    // MARK: - Import

    private func importDesigns(from url: URL) async {
        guard !importInProgress else { return }
        importInProgress = true
        defer { importInProgress = false }

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let result = try store.importDesigns(from: data, makeDefault: false)

            refreshSavedSpecs(preservingSelection: false)

            if let firstID = result.importedIDs.first {
                selectedSpecID = firstID
                loadSelected()
            }

            lastWidgetRefreshAt = Date()

            if result.importedCount == 0 {
                saveStatusMessage = "Import complete.\nNo designs were added."
            } else {
                saveStatusMessage = "Imported \(result.importedCount) design\(result.importedCount == 1 ? "" : "s").\nWidgets refreshed."
            }

            if !result.notes.isEmpty {
                let suffix = result.notes.prefix(2).joined(separator: "\n")
                saveStatusMessage += "\n\(suffix)"
            }
        } catch {
            saveStatusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sharing

    private func sharePackageForCurrentDesign() -> WidgetWeaverSharePackage {
        let spec = draftSpec(id: selectedSpecID).normalised()
        let fileName = WidgetWeaverSharePackage.suggestedFileName(prefix: spec.name, suffix: "design")

        let data = (try? store.exportExchangeData(specs: [spec], includeImages: true)) ?? Data()
        return WidgetWeaverSharePackage(fileName: fileName, data: data)
    }

    private func sharePackageForAllDesigns() -> WidgetWeaverSharePackage {
        let fileName = WidgetWeaverSharePackage.suggestedFileName(prefix: "WidgetWeaver", suffix: "designs")
        let data = (try? store.exportAllExchangeData(includeImages: true)) ?? Data()
        return WidgetWeaverSharePackage(fileName: fileName, data: data)
    }

    // MARK: - Appearance

    private static func applyAppearanceIfNeeded() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Draft models

private enum EditingFamily: String, CaseIterable {
    case small
    case medium
    case large

    init?(widgetFamily: WidgetFamily) {
        switch widgetFamily {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        case .systemLarge: self = .large
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

private struct MatchedDrafts: Hashable {
    var small: FamilyDraft
    var medium: FamilyDraft
    var large: FamilyDraft

    subscript(_ family: EditingFamily) -> FamilyDraft {
        get {
            switch family {
            case .small: return small
            case .medium: return medium
            case .large: return large
            }
        }
        set {
            switch family {
            case .small: small = newValue
            case .medium: medium = newValue
            case .large: large = newValue
            }
        }
    }
}

private struct StyleDraft: Hashable {
    var padding: Double
    var cornerRadius: Double
    var background: BackgroundToken
    var accent: AccentToken
    var nameTextStyle: TextStyleToken
    var primaryTextStyle: TextStyleToken
    var secondaryTextStyle: TextStyleToken

    static var defaultDraft: StyleDraft { StyleDraft(from: .defaultStyle) }

    init(from style: StyleSpec) {
        self.padding = style.padding
        self.cornerRadius = style.cornerRadius
        self.background = style.background
        self.accent = style.accent
        self.nameTextStyle = style.nameTextStyle
        self.primaryTextStyle = style.primaryTextStyle
        self.secondaryTextStyle = style.secondaryTextStyle
    }

    func toStyleSpec() -> StyleSpec {
        StyleSpec(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            accent: accent,
            nameTextStyle: nameTextStyle,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle
        ).normalised()
    }
}

private struct FamilyDraft: Hashable {
    // Text
    var primaryText: String
    var secondaryText: String

    // Symbol
    var symbolName: String
    var symbolPlacement: SymbolPlacementToken
    var symbolSize: Double
    var symbolWeight: SymbolWeightToken
    var symbolRenderingMode: SymbolRenderingModeToken
    var symbolTint: SymbolTintToken

    // Image
    var imageFileName: String
    var imageContentMode: ImageContentModeToken
    var imageHeight: Double
    var imageCornerRadius: Double

    // Layout
    var axis: LayoutAxisToken
    var alignment: LayoutAlignmentToken
    var spacing: Double
    var primaryLineLimitSmall: Int
    var primaryLineLimit: Int
    var secondaryLineLimit: Int

    static var defaultDraft: FamilyDraft { FamilyDraft(from: WidgetSpec.defaultSpec()) }

    init(from spec: WidgetSpec) {
        let s = spec.normalised()

        self.primaryText = s.primaryText
        self.secondaryText = s.secondaryText ?? ""

        if let sym = s.symbol {
            self.symbolName = sym.name
            self.symbolPlacement = sym.placement
            self.symbolSize = sym.size
            self.symbolWeight = sym.weight
            self.symbolRenderingMode = sym.renderingMode
            self.symbolTint = sym.tint
        } else {
            self.symbolName = ""
            self.symbolPlacement = .beforeName
            self.symbolSize = 18
            self.symbolWeight = .regular
            self.symbolRenderingMode = .monochrome
            self.symbolTint = .accent
        }

        if let img = s.image {
            self.imageFileName = img.fileName
            self.imageContentMode = img.contentMode
            self.imageHeight = img.height
            self.imageCornerRadius = img.cornerRadius
        } else {
            self.imageFileName = ""
            self.imageContentMode = .fill
            self.imageHeight = 120
            self.imageCornerRadius = 16
        }

        self.axis = s.layout.axis
        self.alignment = s.layout.alignment
        self.spacing = s.layout.spacing
        self.primaryLineLimitSmall = s.layout.primaryLineLimitSmall
        self.primaryLineLimit = s.layout.primaryLineLimit
        self.secondaryLineLimit = s.layout.secondaryLineLimit
    }

    func toFlatSpec(id: UUID, name: String, style: StyleSpec, updatedAt: Date) -> WidgetSpec {
        let trimmedPrimary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        let symName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol: SymbolSpec? = symName.isEmpty ? nil : SymbolSpec(
            name: symName,
            size: symbolSize,
            weight: symbolWeight,
            renderingMode: symbolRenderingMode,
            tint: symbolTint,
            placement: symbolPlacement
        )

        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius
        )

        let layout = LayoutSpec(
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        ).normalised()

        return WidgetSpec(
            id: id,
            name: name,
            primaryText: trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary,
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            updatedAt: updatedAt,
            symbol: symbol,
            image: image,
            layout: layout,
            style: style,
            matchedSet: nil
        ).normalised()
    }

    func toVariantSpec() -> WidgetSpecVariant {
        let trimmedPrimary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        let symName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol: SymbolSpec? = symName.isEmpty ? nil : SymbolSpec(
            name: symName,
            size: symbolSize,
            weight: symbolWeight,
            renderingMode: symbolRenderingMode,
            tint: symbolTint,
            placement: symbolPlacement
        )

        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius
        )

        let layout = LayoutSpec(
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        ).normalised()

        return WidgetSpecVariant(
            primaryText: trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary,
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            symbol: symbol,
            image: image,
            layout: layout
        ).normalised()
    }

    mutating func apply(flatSpec spec: WidgetSpec) {
        let s = spec.normalised()

        primaryText = s.primaryText
        secondaryText = s.secondaryText ?? ""

        if let sym = s.symbol {
            symbolName = sym.name
            symbolPlacement = sym.placement
            symbolSize = sym.size
            symbolWeight = sym.weight
            symbolRenderingMode = sym.renderingMode
            symbolTint = sym.tint
        } else {
            symbolName = ""
        }

        if let img = s.image {
            imageFileName = img.fileName
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius
        } else {
            imageFileName = ""
        }

        axis = s.layout.axis
        alignment = s.layout.alignment
        spacing = s.layout.spacing
        primaryLineLimitSmall = s.layout.primaryLineLimitSmall
        primaryLineLimit = s.layout.primaryLineLimit
        secondaryLineLimit = s.layout.secondaryLineLimit
    }
}

// MARK: - Preview Dock (collapsible, from 698df1)

private extension ContentView {

    struct WidgetPreviewDock: View {
        enum Presentation { case dock, sidebar }

        static func reservedInsetHeight(verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
            collapsedCardHeight(verticalSizeClass: verticalSizeClass) + outerBottomPadding
        }

        private static let outerBottomPadding: CGFloat = 10

        private static func collapsedCardHeight(verticalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
            (verticalSizeClass == .compact) ? 62 : 72
        }

        let spec: WidgetSpec
        @Binding var family: WidgetFamily
        let presentation: Presentation

        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @SceneStorage("widgetPreviewDock.isExpanded") private var isExpanded: Bool = false

        var body: some View {
            switch presentation {
            case .sidebar: expandedCard
            case .dock: dockCard
            }
        }

        private var dockCard: some View {
            ZStack {
                if isExpanded {
                    expandedCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    collapsedCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: isExpanded)
            .gesture(dragGesture)
            .onChange(of: verticalSizeClass) { _, newValue in
                guard presentation == .dock else { return }
                if newValue == .compact { setExpanded(false) }
            }
        }

        private var expandedCard: some View {
            VStack(spacing: 12) {

                if presentation == .dock {
                    grabber
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                }

                HStack(spacing: 10) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Picker("Size", selection: $family) {
                        Text("Small").tag(WidgetFamily.systemSmall)
                        Text("Medium").tag(WidgetFamily.systemMedium)
                        Text("Large").tag(WidgetFamily.systemLarge)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: presentation == .sidebar ? 280 : 240)

                    if presentation == .dock {
                        Button { setExpanded(false) } label: {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse preview")
                    }
                }

                WidgetPreview(spec: spec, family: family, maxHeight: expandedPreviewMaxHeight)

                Text("Preview is approximate; final widget size is device-dependent.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.regularMaterial, in: cardShape)
            .overlay(cardShape.strokeBorder(.primary.opacity(0.10)))
            .shadow(color: .black.opacity(presentation == .dock ? 0.10 : 0.06), radius: 18, y: 8)
        }

        private var collapsedCard: some View {
            HStack(spacing: 12) {
                WidgetPreviewThumbnail(spec: spec, family: family, height: collapsedThumbnailHeight)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(familyLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                familyMenu

                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(height: collapsedHeight)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: cardShape)
            .overlay(cardShape.strokeBorder(.primary.opacity(0.10)))
            .contentShape(cardShape)
            .onTapGesture { setExpanded(true) }
        }

        private var grabber: some View {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpanded() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isExpanded ? "Collapse preview" : "Expand preview")
        }

        private var familyMenu: some View {
            Menu {
                Button { family = .systemSmall } label: { Label("Small", systemImage: "square") }
                Button { family = .systemMedium } label: { Label("Medium", systemImage: "rectangle") }
                Button { family = .systemLarge } label: { Label("Large", systemImage: "rectangle.portrait") }
            } label: {
                Text(familyAbbreviation)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }

        private var dragGesture: some Gesture {
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onEnded { value in
                    let dy = value.translation.height
                    if dy > 24 {
                        setExpanded(false)
                    } else if dy < -24 {
                        setExpanded(true)
                    }
                }
        }

        private var cardShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
        }

        private var collapsedHeight: CGFloat {
            Self.collapsedCardHeight(verticalSizeClass: verticalSizeClass)
        }

        private var collapsedThumbnailHeight: CGFloat {
            (verticalSizeClass == .compact) ? 30 : 38
        }

        private var expandedPreviewMaxHeight: CGFloat {
            switch presentation {
            case .sidebar:
                return 420
            case .dock:
                return (verticalSizeClass == .compact) ? 150 : 260
            }
        }

        private var familyLabel: String {
            switch family {
            case .systemSmall: return "Small"
            case .systemMedium: return "Medium"
            case .systemLarge: return "Large"
            default: return "Small"
            }
        }

        private var familyAbbreviation: String {
            switch family {
            case .systemSmall: return "S"
            case .systemMedium: return "M"
            case .systemLarge: return "L"
            default: return "S"
            }
        }

        private func toggleExpanded() {
            setExpanded(!isExpanded)
        }

        private func setExpanded(_ expanded: Bool) {
            guard presentation == .dock else { return }
            withAnimation(.snappy(duration: 0.25)) {
                isExpanded = expanded
            }
        }
    }

    @MainActor
    struct WidgetPreview: View {
        let spec: WidgetSpec
        let family: WidgetFamily
        var maxHeight: CGFloat?

        var body: some View {
            GeometryReader { proxy in
                let base = Self.widgetSize(for: family)
                let scaleX = proxy.size.width / base.width
                let scaleY = proxy.size.height / base.height
                let scale = min(scaleX, scaleY)

                WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
                    .frame(width: base.width, height: base.height)
                    .scaleEffect(scale, anchor: .center)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .frame(height: maxHeight)
            .clipped()
        }

        static func widgetSize(for family: WidgetFamily) -> CGSize {
            let sizes = WidgetPreviewSizing.sizesForCurrentDevice()
            switch family {
            case .systemSmall: return sizes.small
            case .systemMedium: return sizes.medium
            case .systemLarge: return sizes.large
            default: return sizes.small
            }
        }

        private struct WidgetPreviewSizing {
            struct Sizes {
                let small: CGSize
                let medium: CGSize
                let large: CGSize
            }

            @MainActor
            static func sizesForCurrentDevice() -> Sizes {
                let screen = currentScreen()
                let native = screen.nativeBounds.size
                let w = Int(min(native.width, native.height))
                let h = Int(max(native.width, native.height))
                let key = "\(w)x\(h)"

                if let sizes = knownSizesByNativeResolution[key] {
                    return sizes
                }

                let points = screen.bounds.size
                let maxSide = max(points.width, points.height)
                let minSide = min(points.width, points.height)

                if UIDevice.current.userInterfaceIdiom == .pad {
                    if minSide >= 1024 || maxSide >= 1366 {
                        return Sizes(
                            small: CGSize(width: 170, height: 170),
                            medium: CGSize(width: 379, height: 170),
                            large: CGSize(width: 379, height: 379)
                        )
                    } else {
                        return Sizes(
                            small: CGSize(width: 155, height: 155),
                            medium: CGSize(width: 342, height: 155),
                            large: CGSize(width: 342, height: 342)
                        )
                    }
                }

                if maxSide >= 926 {
                    return Sizes(
                        small: CGSize(width: 170, height: 170),
                        medium: CGSize(width: 364, height: 170),
                        large: CGSize(width: 364, height: 382)
                    )
                } else if maxSide >= 844 {
                    return Sizes(
                        small: CGSize(width: 158, height: 158),
                        medium: CGSize(width: 338, height: 158),
                        large: CGSize(width: 338, height: 354)
                    )
                } else if maxSide >= 812 {
                    return Sizes(
                        small: CGSize(width: 155, height: 155),
                        medium: CGSize(width: 329, height: 155),
                        large: CGSize(width: 329, height: 345)
                    )
                } else if maxSide >= 736 {
                    return Sizes(
                        small: CGSize(width: 157, height: 157),
                        medium: CGSize(width: 348, height: 157),
                        large: CGSize(width: 348, height: 351)
                    )
                } else if maxSide >= 667 {
                    return Sizes(
                        small: CGSize(width: 148, height: 148),
                        medium: CGSize(width: 321, height: 148),
                        large: CGSize(width: 321, height: 324)
                    )
                } else {
                    return Sizes(
                        small: CGSize(width: 141, height: 141),
                        medium: CGSize(width: 292, height: 141),
                        large: CGSize(width: 292, height: 311)
                    )
                }
            }

            @MainActor
            private static func currentScreen() -> UIScreen {
                if let activeScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) {
                    return activeScene.screen
                }

                if let anyScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first {
                    return anyScene.screen
                }

                return UIScreen()
            }

            private static let knownSizesByNativeResolution: [String: Sizes] = [
                // MARK: - iPhone
                "1170x2532": Sizes(small: CGSize(width: 158, height: 158), medium: CGSize(width: 338, height: 158), large: CGSize(width: 338, height: 354)), // 12/13/14/15 (non‑Pro 6.1")
                "1179x2556": Sizes(small: CGSize(width: 158, height: 158), medium: CGSize(width: 338, height: 158), large: CGSize(width: 338, height: 354)), // 14/15 Pro (6.1")
                "1080x2340": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 329, height: 155), large: CGSize(width: 329, height: 345)), // 12/13 mini
                "1284x2778": Sizes(small: CGSize(width: 170, height: 170), medium: CGSize(width: 364, height: 170), large: CGSize(width: 364, height: 382)), // 12/13 Pro Max
                "1290x2796": Sizes(small: CGSize(width: 170, height: 170), medium: CGSize(width: 364, height: 170), large: CGSize(width: 364, height: 382)), // 14/15 Pro Max
                "828x1792": Sizes(small: CGSize(width: 169, height: 169), medium: CGSize(width: 360, height: 169), large: CGSize(width: 360, height: 379)), // XR / 11
                "1125x2436": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 329, height: 155), large: CGSize(width: 329, height: 345)), // X / XS / 11 Pro
                "1242x2688": Sizes(small: CGSize(width: 169, height: 169), medium: CGSize(width: 360, height: 169), large: CGSize(width: 360, height: 379)), // XS Max / 11 Pro Max
                "750x1334": Sizes(small: CGSize(width: 148, height: 148), medium: CGSize(width: 321, height: 148), large: CGSize(width: 321, height: 324)), // 6/7/8/SE2/SE3
                "1080x1920": Sizes(small: CGSize(width: 157, height: 157), medium: CGSize(width: 348, height: 157), large: CGSize(width: 348, height: 351)), // Plus
                "640x1136": Sizes(small: CGSize(width: 141, height: 141), medium: CGSize(width: 292, height: 141), large: CGSize(width: 292, height: 311)), // SE 1st gen

                // MARK: - iPad
                "2732x2048": Sizes(small: CGSize(width: 170, height: 170), medium: CGSize(width: 379, height: 170), large: CGSize(width: 379, height: 379)), // 12.9" iPad Pro
                "2388x1668": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 342, height: 155), large: CGSize(width: 342, height: 342)), // 11" iPad Pro
                "2360x1640": Sizes(small: CGSize(width: 155, height: 155), medium: CGSize(width: 342, height: 155), large: CGSize(width: 342, height: 342)), // iPad Air 4/5
                "2266x1488": Sizes(small: CGSize(width: 141, height: 141), medium: CGSize(width: 306, height: 141), large: CGSize(width: 306, height: 306)), // iPad mini 6
                "2224x1668": Sizes(small: CGSize(width: 150, height: 150), medium: CGSize(width: 328, height: 150), large: CGSize(width: 328, height: 328)), // iPad Pro 10.5"
                "2160x1620": Sizes(small: CGSize(width: 146, height: 146), medium: CGSize(width: 321, height: 146), large: CGSize(width: 321, height: 321)), // iPad 7/8/9
                "2048x1536": Sizes(small: CGSize(width: 141, height: 141), medium: CGSize(width: 306, height: 141), large: CGSize(width: 306, height: 306))  // older iPads bucket
            ]
        }
    }

    @MainActor
    struct WidgetPreviewThumbnail: View {
        let spec: WidgetSpec
        let family: WidgetFamily
        var height: CGFloat

        var body: some View {
            let base = WidgetPreview.widgetSize(for: family)
            let scale = height / base.height
            let scaledWidth = base.width * scale

            WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
                .frame(width: base.width, height: base.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: scaledWidth, height: height, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10))
                )
                .clipped()
        }
    }
}

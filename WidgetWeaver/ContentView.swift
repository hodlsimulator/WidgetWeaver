//
//  ContentView.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI
import WidgetKit
import PhotosUI
import UIKit

@MainActor
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var savedSpecs: [WidgetSpec] = []
    @State private var defaultSpecID: UUID?
    @State private var selectedSpecID: UUID = UUID()

    // Draft fields (manual editor)
    @State private var name: String = "WidgetWeaver"
    @State private var primaryText: String = "Hello"
    @State private var secondaryText: String = ""

    @State private var symbolName: String = "sparkles"
    @State private var symbolPlacement: SymbolPlacementToken = .beforeName
    @State private var symbolSize: Double = 18
    @State private var symbolWeight: SymbolWeightToken = .semibold
    @State private var symbolRenderingMode: SymbolRenderingModeToken = .hierarchical
    @State private var symbolTint: SymbolTintToken = .accent

    @State private var imageFileName: String = ""
    @State private var imageContentMode: ImageContentModeToken = .fill
    @State private var imageHeight: Double = 120
    @State private var imageCornerRadius: Double = 16

    @State private var axis: LayoutAxisToken = .vertical
    @State private var alignment: LayoutAlignmentToken = .leading
    @State private var spacing: Double = 8
    @State private var primaryLineLimitSmall: Int = 1
    @State private var primaryLineLimit: Int = 2
    @State private var secondaryLineLimit: Int = 2

    @State private var padding: Double = 16
    @State private var cornerRadius: Double = 20
    @State private var background: BackgroundToken = .accentGlow
    @State private var accent: AccentToken = .blue

    @State private var nameTextStyle: TextStyleToken = .automatic
    @State private var primaryTextStyle: TextStyleToken = .automatic
    @State private var secondaryTextStyle: TextStyleToken = .automatic

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
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarMenu
                }
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
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the design from the library.\nAny widget using it will fall back to another design.")
            }
            .sheet(isPresented: $showWidgetHelp) {
                WidgetWorkflowHelpView()
            }
            .onAppear { bootstrap() }
            .onChange(of: selectedSpecID) { _, _ in loadSelected() }
            .onChange(of: pickedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await importPickedImage(newItem) }
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var editorLayout: some View {
        if horizontalSizeClass == .regular {
            // iPad / wide layouts: keep preview visible as a side panel.
            HStack(alignment: .top, spacing: 16) {
                previewDock(presentation: .sidebar)
                    .frame(width: 420)
                    .padding(.top, 8)

                editorForm
            }
            .padding(.horizontal, 16)
        } else {
            // iPhone / compact: keep preview visible in a persistent bottom dock.
            editorForm
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    previewDock(presentation: .dock)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
        }
    }

    private var editorForm: some View {
        Form {
            designsSection
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

    private var toolbarMenu: some View {
        Menu {
            Button {
                showWidgetHelp = true
            } label: {
                Label("Widget Help", systemImage: "questionmark.circle")
            }

            Divider()

            Button {
                createNewDesign()
            } label: {
                Label("New Design", systemImage: "plus")
            }

            Button {
                duplicateCurrentDesign()
            } label: {
                Label("Duplicate Design", systemImage: "doc.on.doc")
            }
            .disabled(savedSpecs.isEmpty)

            Divider()

            Button {
                saveSelected(makeDefault: true)
            } label: {
                Label("Save & Make Default", systemImage: "checkmark.circle")
            }

            Button {
                saveSelected(makeDefault: false)
            } label: {
                Label("Save (Keep Default)", systemImage: "tray.and.arrow.down")
            }

            Button {
                refreshWidgets()
            } label: {
                Label("Refresh Widgets", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
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

    // MARK: - Sections

    private var designsSection: some View {
        Section {
            if savedSpecs.isEmpty {
                Text("No saved designs yet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Design", selection: $selectedSpecID) {
                    ForEach(savedSpecs) { spec in
                        Text(specDisplayName(spec))
                            .tag(spec.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let defaultName {
                LabeledContent("App default", value: defaultName)
            }

            if selectedSpecID == defaultSpecID {
                Text("This design is the app default. Widgets set to \"Default (App)\" will show it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This design is not the app default. Use \"Save & Make Default\" to update widgets set to \"Default (App)\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                Button { createNewDesign() } label: { Label("New", systemImage: "plus") }
                Button { duplicateCurrentDesign() } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    .disabled(savedSpecs.isEmpty)
                Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
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

    private var widgetWorkflowSection: some View {
        Section {
            Button {
                saveSelected(makeDefault: true)
            } label: {
                Label("Save & Make Default", systemImage: "checkmark.circle.fill")
            }

            Button {
                saveSelected(makeDefault: false)
            } label: {
                Label("Save (Keep Default)", systemImage: "tray.and.arrow.down")
            }

            if selectedSpecID != defaultSpecID {
                Button {
                    store.setDefault(id: selectedSpecID)
                    defaultSpecID = store.defaultSpecID()
                    lastWidgetRefreshAt = Date()
                    saveStatusMessage = "Made default. Widgets refreshed."
                } label: {
                    Label("Make This Design Default", systemImage: "star")
                }
            }

            Button {
                refreshWidgets()
            } label: {
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
            Text("If a widget doesn’t change, check which Design it is using (Edit Widget). Widgets set to \"Default (App)\" always follow the app default design.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var textSection: some View {
        Section {
            TextField("Design name", text: $name)
                .textInputAutocapitalization(.words)
            TextField("Primary text", text: $primaryText)
            TextField("Secondary text (optional)", text: $secondaryText)
        } header: {
            sectionHeader("Text")
        }
    }

    private var symbolSection: some View {
        Section {
            TextField("SF Symbol name (optional)", text: $symbolName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Picker("Placement", selection: $symbolPlacement) {
                ForEach(SymbolPlacementToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            HStack {
                Text("Size")
                Slider(value: $symbolSize, in: 8...96, step: 1)
                Text("\(Int(symbolSize))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Picker("Weight", selection: $symbolWeight) {
                ForEach(SymbolWeightToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Rendering", selection: $symbolRenderingMode) {
                ForEach(SymbolRenderingModeToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Tint", selection: $symbolTint) {
                ForEach(SymbolTintToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

        } header: {
            sectionHeader("Symbol")
        }
    }

    private var imageSection: some View {
        let hasImage = !imageFileName.isEmpty

        return Section {
            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                Label(hasImage ? "Replace photo" : "Choose photo (optional)", systemImage: "photo")
            }

            if !imageFileName.isEmpty {
                if let uiImage = AppGroup.loadUIImage(fileName: imageFileName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text("Selected image file not found in App Group.")
                        .foregroundStyle(.secondary)
                }

                Picker("Content mode", selection: $imageContentMode) {
                    ForEach(ImageContentModeToken.allCases) { token in
                        Text(token.rawValue).tag(token)
                    }
                }

                HStack {
                    Text("Height")
                    Slider(value: $imageHeight, in: 40...240, step: 1)
                    Text("\(Int(imageHeight))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Corner radius")
                    Slider(value: $imageCornerRadius, in: 0...44, step: 1)
                    Text("\(Int(imageCornerRadius))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    imageFileName = ""
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
            Picker("Axis", selection: $axis) {
                ForEach(LayoutAxisToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Alignment", selection: $alignment) {
                ForEach(LayoutAlignmentToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            HStack {
                Text("Spacing")
                Slider(value: $spacing, in: 0...32, step: 1)
                Text("\(Int(spacing))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Stepper("Primary line limit (Small): \(primaryLineLimitSmall)", value: $primaryLineLimitSmall, in: 1...8)
            Stepper("Primary line limit: \(primaryLineLimit)", value: $primaryLineLimit, in: 1...10)
            Stepper("Secondary line limit: \(secondaryLineLimit)", value: $secondaryLineLimit, in: 1...10)

        } header: {
            sectionHeader("Layout")
        }
    }

    private var styleSection: some View {
        Section {
            HStack {
                Text("Padding")
                Slider(value: $padding, in: 0...32, step: 1)
                Text("\(Int(padding))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Corner radius")
                Slider(value: $cornerRadius, in: 0...44, step: 1)
                Text("\(Int(cornerRadius))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Picker("Background", selection: $background) {
                ForEach(BackgroundToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Accent", selection: $accent) {
                ForEach(AccentToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

        } header: {
            sectionHeader("Style")
        }
    }

    private var typographySection: some View {
        Section {
            Picker("Name text style", selection: $nameTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Primary text style", selection: $primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Secondary text style", selection: $secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
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

            Text("Optional on-device generation/edits. Images are never generated.")
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
        if spec.id == defaultSpecID {
            return "\(spec.name) (Default)"
        }
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

        name = n.name
        primaryText = n.primaryText
        secondaryText = n.secondaryText ?? ""

        if let sym = n.symbol {
            symbolName = sym.name
            symbolPlacement = sym.placement
            symbolSize = sym.size
            symbolWeight = sym.weight
            symbolRenderingMode = sym.renderingMode
            symbolTint = sym.tint
        } else {
            symbolName = ""
            symbolPlacement = .beforeName
            symbolSize = 18
            symbolWeight = .semibold
            symbolRenderingMode = .hierarchical
            symbolTint = .accent
        }

        if let img = n.image {
            imageFileName = img.fileName
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius
        } else {
            imageFileName = ""
            imageContentMode = .fill
            imageHeight = 120
            imageCornerRadius = 16
        }

        axis = n.layout.axis
        alignment = n.layout.alignment
        spacing = n.layout.spacing
        primaryLineLimitSmall = n.layout.primaryLineLimitSmall
        primaryLineLimit = n.layout.primaryLineLimit
        secondaryLineLimit = n.layout.secondaryLineLimit

        padding = n.style.padding
        cornerRadius = n.style.cornerRadius
        background = n.style.background
        accent = n.style.accent

        nameTextStyle = n.style.nameTextStyle
        primaryTextStyle = n.style.primaryTextStyle
        secondaryTextStyle = n.style.secondaryTextStyle

        lastSavedAt = n.updatedAt
    }

    private func draftSpec(id: UUID) -> WidgetSpec {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrimary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        let symbolSpec: SymbolSpec? = {
            let symName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !symName.isEmpty else { return nil }
            return SymbolSpec(
                name: symName,
                size: symbolSize,
                weight: symbolWeight,
                renderingMode: symbolRenderingMode,
                tint: symbolTint,
                placement: symbolPlacement
            )
        }()

        let imageSpec: ImageSpec? = {
            let fn = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fn.isEmpty else { return nil }
            return ImageSpec(
                fileName: fn,
                contentMode: imageContentMode,
                height: imageHeight,
                cornerRadius: imageCornerRadius
            )
        }()

        let layout = LayoutSpec(
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        )

        let style = StyleSpec(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            accent: accent,
            nameTextStyle: nameTextStyle,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle
        )

        return WidgetSpec(
            id: id,
            name: trimmedName.isEmpty ? "WidgetWeaver" : trimmedName,
            primaryText: trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary,
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            updatedAt: lastSavedAt ?? Date(),
            symbol: symbolSpec,
            image: imageSpec,
            layout: layout,
            style: style
        )
        .normalised()
    }

    // MARK: - Photos import

    private func importPickedImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: data) else { return }

            let fileName = AppGroup.createImageFileName(ext: "jpg")
            try AppGroup.writeUIImage(uiImage, fileName: fileName, compressionQuality: 0.85)

            await MainActor.run {
                imageFileName = fileName
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

        saveStatusMessage = makeDefault
            ? "Saved and set as default. Widgets refreshed."
            : "Saved. Widgets refreshed."

        lastWidgetRefreshAt = Date()
        refreshSavedSpecs(preservingSelection: true)
    }

    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }

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
        saveStatusMessage = "Deleted design. Widgets refreshed."
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
        saveStatusMessage = "Generated design saved. Widgets refreshed."
    }

    @MainActor
    private func applyPatchToCurrentDesign() async {
        aiStatusMessage = ""

        let instruction = aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        let base = draftSpec(id: selectedSpecID)
        let result = await WidgetSpecAIService.shared.applyPatch(to: base, instruction: instruction)

        var spec = result.spec.normalised()
        spec.updatedAt = Date()

        store.save(spec, makeDefault: (defaultSpecID == selectedSpecID))

        defaultSpecID = store.defaultSpecID()
        lastWidgetRefreshAt = Date()

        aiStatusMessage = result.note
        aiPatchInstruction = ""

        refreshSavedSpecs(preservingSelection: true)
        applySpec(spec)
        saveStatusMessage = "Patch saved. Widgets refreshed."
    }

    // MARK: - Appearance

    private static var didApplyAppearance: Bool = false

    private static func applyAppearanceIfNeeded() {
        guard !didApplyAppearance else { return }
        didApplyAppearance = true

        let standard = UINavigationBarAppearance()
        standard.configureWithTransparentBackground()
        standard.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        standard.backgroundColor = .clear
        standard.shadowColor = .clear

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.backgroundEffect = nil
        scrollEdge.backgroundColor = .clear
        scrollEdge.shadowColor = .clear

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = standard
        navBar.compactAppearance = standard
        navBar.scrollEdgeAppearance = scrollEdge
        navBar.compactScrollEdgeAppearance = scrollEdge

        UITableView.appearance().backgroundColor = .clear
    }
}

// MARK: - Preview Dock

private struct WidgetPreviewDock: View {
    enum Presentation {
        case dock
        case sidebar
    }

    let spec: WidgetSpec
    @Binding var family: WidgetFamily
    let presentation: Presentation

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 12) {
            headerRow
            WidgetPreview(spec: spec, family: family, maxHeight: previewMaxHeight)
            Text("Preview is approximate; final widget size is device-dependent.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.10))
        )
    }

    private var headerRow: some View {
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
        }
    }

    private var previewMaxHeight: CGFloat {
        switch presentation {
        case .sidebar:
            return 420
        case .dock:
            return (verticalSizeClass == .compact) ? 120 : 190
        }
    }
}

private struct WidgetPreview: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    var maxHeight: CGFloat?

    var body: some View {
        let size = widgetSize(for: family)
        let ratio = size.width / size.height

        WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxHeight)
            .padding(.horizontal, 8)
    }

    private func widgetSize(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall:
            return CGSize(width: 170, height: 170)
        case .systemMedium:
            return CGSize(width: 364, height: 170)
        case .systemLarge:
            return CGSize(width: 364, height: 382)
        default:
            return CGSize(width: 170, height: 170)
        }
    }
}

// MARK: - Help

private struct WidgetWorkflowHelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("How widgets update") {
                    Text("Widgets update when the saved design changes and WidgetKit reloads timelines.")
                        .foregroundStyle(.secondary)
                }
                Section("Design selection") {
                    Text("Each widget instance can follow \"Default (App)\" or a specific saved design.")
                        .foregroundStyle(.secondary)
                    Text("To change this: long-press the widget → Edit Widget → Design.")
                        .foregroundStyle(.secondary)
                }
                Section("If a widget doesn’t change") {
                    Text("Try \"Refresh Widgets\" in the app, then wait a moment.")
                        .foregroundStyle(.secondary)
                    Text("If it still doesn’t update, reselect the Design in Edit Widget. Removing and re-adding the widget is only needed after major schema changes.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Background

private struct EditorBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.22),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 640
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 760
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Keyboard

private enum Keyboard {
    static func dismiss() {
        Task { @MainActor in
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

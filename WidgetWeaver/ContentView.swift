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

    @State private var nameTextStyle: TextStyleToken = .caption
    @State private var primaryTextStyle: TextStyleToken = .headline
    @State private var secondaryTextStyle: TextStyleToken = .caption2

    // Photos picker
    @State private var pickedPhoto: PhotosPickerItem?

    // AI
    @State private var aiPrompt: String = ""
    @State private var aiMakeGeneratedDefault: Bool = true
    @State private var aiPatchInstruction: String = ""
    @State private var aiStatusMessage: String = ""

    // Status
    @State private var lastSavedAt: Date?

    private let store = WidgetSpecStore.shared

    var body: some View {
        NavigationStack {
            Form {
                savedDesignsSection
                textSection
                symbolSection
                imageSection
                layoutSection
                styleSection
                typographySection
                aiSection
                previewSection
                actionsSection
                statusSection
            }
            .navigationTitle("WidgetWeaver")
            .scrollDismissesKeyboard(.interactively)
            .background(KeyboardDismissOnTap())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        Keyboard.dismiss()
                    }
                }
            }
            .onAppear {
                bootstrap()
            }
            .onChange(of: selectedSpecID) { _, _ in
                loadSelected()
            }
            .onChange(of: pickedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await importPickedImage(newItem) }
            }
        }
    }

    // MARK: - Sections

    private var savedDesignsSection: some View {
        Section("Saved Designs") {
            if savedSpecs.isEmpty {
                Text("No saved designs yet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Design", selection: $selectedSpecID) {
                    ForEach(savedSpecs) { spec in
                        let isDefault = (spec.id == defaultSpecID)
                        Text(isDefault ? "\(spec.name) (Default)" : spec.name)
                            .tag(spec.id)
                    }
                }
            }
        }
    }

    private var textSection: some View {
        Section("Text") {
            TextField("Design name", text: $name)
                .textInputAutocapitalization(.words)

            TextField("Primary text", text: $primaryText)

            TextField("Secondary text (optional)", text: $secondaryText)
        }
    }

    private var symbolSection: some View {
        Section("Symbol") {
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
        }
    }

    private var imageSection: some View {
        let hasImage = !imageFileName.isEmpty

        return Section("Image") {
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
        }
    }

    private var layoutSection: some View {
        Section("Layout") {
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
        }
    }

    private var styleSection: some View {
        Section("Style") {
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
        }
    }

    private var typographySection: some View {
        Section("Typography") {
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
        }
    }

    private var aiSection: some View {
        Section("AI") {
            Text("Optional on-device generation/edits. Images are never generated.")
                .font(.footnote)
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            let spec = draftSpec(id: selectedSpecID)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    PreviewTile(title: "Small", family: .systemSmall, spec: spec, cornerRadius: cornerRadius)
                    PreviewTile(title: "Medium", family: .systemMedium, spec: spec, cornerRadius: cornerRadius)
                    PreviewTile(title: "Large", family: .systemLarge, spec: spec, cornerRadius: cornerRadius)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button("Save to Widget") {
                saveSelected(makeDefault: true)
            }

            Button("Save (do not change default)") {
                saveSelected(makeDefault: false)
            }

            Button("Make This Default") {
                store.setDefault(id: selectedSpecID)
                defaultSpecID = selectedSpecID
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
            }
            .disabled(selectedSpecID == defaultSpecID)

            Button(role: .destructive) {
                store.delete(id: selectedSpecID)
                refreshSavedSpecs(preservingSelection: false)
                loadSelected()
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
            } label: {
                Text("Delete Design")
            }
            .disabled(savedSpecs.count <= 1)
        }
    }

    private var statusSection: some View {
        Group {
            if let lastSavedAt {
                Section("Status") {
                    Text("Saved: \(lastSavedAt.formatted(date: .abbreviated, time: .standard))")
                }
            }
        }
    }

    // MARK: - Model glue

    private func bootstrap() {
        let specs = store
            .loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }

        savedSpecs = specs
        defaultSpecID = store.defaultSpecID()

        let fallback = store.loadDefault()
        selectedSpecID = defaultSpecID ?? fallback.id

        applySpec(store.load(id: selectedSpecID) ?? fallback)
    }

    private func refreshSavedSpecs(preservingSelection: Bool = true) {
        let specs = store
            .loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }

        savedSpecs = specs
        defaultSpecID = store.defaultSpecID()

        if preservingSelection {
            if specs.contains(where: { $0.id == selectedSpecID }) {
                return
            }
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

        refreshSavedSpecs(preservingSelection: true)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
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
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)

        aiStatusMessage = result.note
        aiPrompt = ""

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)
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
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)

        aiStatusMessage = result.note
        aiPatchInstruction = ""

        refreshSavedSpecs(preservingSelection: true)
        applySpec(spec)
    }
}

private struct PreviewTile: View {
    let title: String
    let family: WidgetFamily
    let spec: WidgetSpec
    let cornerRadius: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var size: CGSize {
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

private struct KeyboardDismissOnTap: UIViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.gesture == nil else { return }

        DispatchQueue.main.async {
            guard context.coordinator.gesture == nil else { return }

            let g = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleTap)
            )
            g.cancelsTouchesInView = false
            g.delegate = context.coordinator

            if let window = uiView.window {
                window.addGestureRecognizer(g)
                context.coordinator.hostView = window
                context.coordinator.gesture = g
                return
            }

            if let superview = uiView.superview {
                superview.addGestureRecognizer(g)
                context.coordinator.hostView = superview
                context.coordinator.gesture = g
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let gesture = coordinator.gesture, let host = coordinator.hostView {
            host.removeGestureRecognizer(gesture)
        }
        coordinator.gesture = nil
        coordinator.hostView = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var hostView: UIView?
        weak var gesture: UITapGestureRecognizer?

        @objc func handleTap() {
            Keyboard.dismiss()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = touch.view else { return true }

            // Allow normal text editing gestures without dismissing.
            if view is UITextField || view is UITextView {
                return false
            }

            // SwiftUI sometimes wraps the underlying UIKit view.
            // If the tap lands inside a UITextField/UITextView hierarchy, ignore it.
            if view.isDescendant(ofType: UITextField.self) || view.isDescendant(ofType: UITextView.self) {
                return false
            }

            return true
        }
    }
}

private extension UIView {
    func isDescendant<T: UIView>(ofType type: T.Type) -> Bool {
        var v: UIView? = self
        while let current = v {
            if current is T { return true }
            v = current.superview
        }
        return false
    }
}

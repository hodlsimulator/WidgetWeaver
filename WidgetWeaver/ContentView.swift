//
//  ContentView.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var savedSpecs: [WidgetSpec] = []
    @State private var selectedSpecID: UUID = UUID()
    @State private var defaultSpecID: UUID?

    @State private var name: String = ""
    @State private var primaryText: String = ""
    @State private var secondaryText: String = ""

    @State private var symbolName: String = ""
    @State private var symbolPlacement: SymbolPlacementToken = .beforeName
    @State private var symbolSize: Double = 18
    @State private var symbolWeight: SymbolWeightToken = .semibold
    @State private var symbolRenderingMode: SymbolRenderingModeToken = .hierarchical
    @State private var symbolTint: SymbolTintToken = .accent

    @State private var axis: LayoutAxisToken = LayoutSpec.defaultLayout.axis
    @State private var alignment: LayoutAlignmentToken = LayoutSpec.defaultLayout.alignment
    @State private var spacing: Double = LayoutSpec.defaultLayout.spacing
    @State private var showSecondaryInSmall: Bool = LayoutSpec.defaultLayout.showSecondaryInSmall

    @State private var padding: Double = StyleSpec.defaultStyle.padding
    @State private var cornerRadius: Double = StyleSpec.defaultStyle.cornerRadius
    @State private var background: BackgroundToken = StyleSpec.defaultStyle.background
    @State private var accent: AccentToken = StyleSpec.defaultStyle.accent
    @State private var primaryTextStyle: TextStyleToken = StyleSpec.defaultStyle.primaryTextStyle
    @State private var secondaryTextStyle: TextStyleToken = StyleSpec.defaultStyle.secondaryTextStyle

    @State private var lastSavedAt: Date?

    private let store = WidgetSpecStore.shared

    var body: some View {
        NavigationStack {
            Form {
                savedDesignsSection
                specSection
                symbolSection
                layoutSection
                styleSection
                previewSection
                actionsSection
                statusSection
            }
            .navigationTitle("WidgetWeaver")
            .onAppear { bootstrap() }
            .onChange(of: selectedSpecID) { _, _ in
                loadSelected()
            }
        }
    }

    // MARK: - Sections

    private var savedDesignsSection: some View {
        Section("Saved Designs") {
            if savedSpecs.isEmpty {
                Text("No saved designs found.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Design", selection: $selectedSpecID) {
                    ForEach(savedSpecs) { spec in
                        let isDefault = (spec.id == defaultSpecID)
                        Text(isDefault ? "\(spec.name) (Default)" : spec.name)
                            .tag(spec.id)
                    }
                }

                Button("New Design (Copy Current)") {
                    createNewFromCurrentDraft()
                }

                Button("Make This Default") {
                    makeSelectedDefault()
                }
                .disabled(savedSpecs.isEmpty)

                Button("Delete Design", role: .destructive) {
                    deleteSelected()
                }
                .disabled(savedSpecs.count <= 1)
            }
        }
    }

    private var specSection: some View {
        Section("Spec") {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)

            TextField("Primary text", text: $primaryText)

            TextField("Secondary text (optional)", text: $secondaryText)
        }
    }

    private var symbolSection: some View {
        Section("Symbol") {
            TextField("SF Symbol name (optional)", text: $symbolName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Picker("Placement", selection: $symbolPlacement) {
                ForEach(SymbolPlacementToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Rendering", selection: $symbolRenderingMode) {
                ForEach(SymbolRenderingModeToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Tint", selection: $symbolTint) {
                ForEach(SymbolTintToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Weight", selection: $symbolWeight) {
                ForEach(SymbolWeightToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(symbolSize))").foregroundStyle(.secondary)
                }
                Slider(value: $symbolSize, in: 8...96, step: 1)
            }

            if !symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 10) {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: symbolName.trimmingCharacters(in: .whitespacesAndNewlines))
                        .symbolRenderingMode(symbolRenderingMode.swiftUISymbolRenderingMode)
                        .font(.system(size: symbolSize, weight: symbolWeight.fontWeight))
                        .foregroundStyle(symbolTint == .accent ? accent.swiftUIColor : (symbolTint == .primary ? Color.primary : Color.secondary))
                }
            }
        }
    }

    private var layoutSection: some View {
        Section("Layout") {
            Picker("Axis", selection: $axis) {
                ForEach(LayoutAxisToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Alignment", selection: $alignment) {
                ForEach(LayoutAlignmentToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Spacing")
                    Spacer()
                    Text("\(Int(spacing))").foregroundStyle(.secondary)
                }
                Slider(value: $spacing, in: 0...24, step: 1)
            }

            Toggle("Show secondary in Small", isOn: $showSecondaryInSmall)
        }
    }

    private var styleSection: some View {
        Section("Style") {
            Picker("Background", selection: $background) {
                ForEach(BackgroundToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Accent", selection: $accent) {
                ForEach(AccentToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Padding")
                    Spacer()
                    Text("\(Int(padding))").foregroundStyle(.secondary)
                }
                Slider(value: $padding, in: 0...24, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Corner radius")
                    Spacer()
                    Text("\(Int(cornerRadius))").foregroundStyle(.secondary)
                }
                Slider(value: $cornerRadius, in: 0...44, step: 1)
            }

            Picker("Primary font", selection: $primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Secondary font", selection: $secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    PreviewTile(
                        title: "Small",
                        family: .systemSmall,
                        spec: draftSpec(id: selectedSpecID),
                        cornerRadius: cornerRadius
                    )

                    PreviewTile(
                        title: "Medium",
                        family: .systemMedium,
                        spec: draftSpec(id: selectedSpecID),
                        cornerRadius: cornerRadius
                    )

                    PreviewTile(
                        title: "Large",
                        family: .systemLarge,
                        spec: draftSpec(id: selectedSpecID),
                        cornerRadius: cornerRadius
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Save to Widget") {
                saveSelected(makeDefault: true)
            }
            .disabled(primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Reload From Store") {
                loadSelected()
            }

            Button("Reset Selected To Template", role: .destructive) {
                resetSelectedToTemplate()
            }
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

        axis = n.layout.axis
        alignment = n.layout.alignment
        spacing = n.layout.spacing
        showSecondaryInSmall = n.layout.showSecondaryInSmall

        padding = n.style.padding
        cornerRadius = n.style.cornerRadius
        background = n.style.background
        accent = n.style.accent
        primaryTextStyle = n.style.primaryTextStyle
        secondaryTextStyle = n.style.secondaryTextStyle

        lastSavedAt = n.updatedAt
    }

    private func draftSpec(id: UUID) -> WidgetSpec {
        let trimmedSymbolName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)

        let symbolSpec: SymbolSpec? =
            trimmedSymbolName.isEmpty
            ? nil
            : SymbolSpec(
                name: trimmedSymbolName,
                size: symbolSize,
                weight: symbolWeight,
                renderingMode: symbolRenderingMode,
                tint: symbolTint,
                placement: symbolPlacement
            )

        let layout = LayoutSpec(
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            showSecondaryInSmall: showSecondaryInSmall,
            primaryLineLimitSmall: LayoutSpec.defaultLayout.primaryLineLimitSmall,
            primaryLineLimit: LayoutSpec.defaultLayout.primaryLineLimit,
            secondaryLineLimit: LayoutSpec.defaultLayout.secondaryLineLimit
        )

        let style = StyleSpec(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            accent: accent,
            nameTextStyle: .caption,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle
        )

        return WidgetSpec(
            id: id,
            name: name,
            primaryText: primaryText,
            secondaryText: secondaryText.isEmpty ? nil : secondaryText,
            updatedAt: lastSavedAt ?? Date(),
            symbol: symbolSpec,
            layout: layout,
            style: style
        )
        .normalised()
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

    private func createNewFromCurrentDraft() {
        var spec = draftSpec(id: UUID())
        spec.updatedAt = Date()

        let trimmedName = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            spec.name = "New Design"
        }

        spec = spec.normalised()

        store.save(spec, makeDefault: false)

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
    }

    private func makeSelectedDefault() {
        store.setDefault(id: selectedSpecID)
        defaultSpecID = selectedSpecID
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
    }

    private func deleteSelected() {
        store.delete(id: selectedSpecID)

        let fallback = store.loadDefault()
        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = store.defaultSpecID() ?? fallback.id
        applySpec(store.load(id: selectedSpecID) ?? fallback)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
    }

    private func resetSelectedToTemplate() {
        let template = WidgetSpec.defaultSpec().normalised()

        var spec = template
        spec.id = selectedSpecID

        let currentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentName.isEmpty {
            spec.name = currentName
        }

        spec.updatedAt = Date()
        spec = spec.normalised()

        store.save(spec, makeDefault: true)
        refreshSavedSpecs(preservingSelection: true)
        applySpec(spec)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
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

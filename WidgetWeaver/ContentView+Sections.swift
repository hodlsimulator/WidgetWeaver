//
//  ContentView+Sections.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import PhotosUI
import UIKit

extension ContentView {
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
 
    // MARK: - New: Content (template + data sources)
    var contentSection: some View {
        let currentTemplate = currentFamilyDraft().template
        let canReadCalendar = WidgetWeaverCalendarStore.shared.canReadEvents()

        return Section {
            Picker("Template", selection: binding(\.template)) {
                ForEach(LayoutTemplateToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            ControlGroup {
                Button {
                    addTemplateDesign(WidgetWeaverAboutView.featuredWeatherTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Weather", systemImage: "cloud.sun.fill")
                }

                Button {
                    addTemplateDesign(WidgetWeaverAboutView.featuredStepsTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Steps", systemImage: "figure.walk")
                }
                
                Button {
                    addTemplateDesign(WidgetWeaverAboutView.featuredActivityTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Activity", systemImage: "figure.run")
                }

                Button {
                    addTemplateDesign(WidgetWeaverAboutView.featuredMinimalTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Minimal", systemImage: "rectangle.grid.1x2")
                }
            }
            .controlGroupStyle(.navigation)

            if currentTemplate.usesWeather {
                Button {
                    activeSheet = .weather
                } label: {
                    Label("Weather settings", systemImage: "cloud.sun")
                }

                Text("Weather is app-driven. Widget reads cached forecast and renders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentTemplate.usesSteps {
                Button {
                    activeSheet = .steps
                } label: {
                    Label("Steps settings", systemImage: "figure.walk")
                }

                Text("Steps are read from HealthKit (Pro). Widget renders the current total.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if currentTemplate.usesActivity {
                Button {
                    activeSheet = .activity
                } label: {
                    Label("Activity settings", systemImage: "figure.run")
                }

                Text("Activity is app-driven. Widget renders the current active energy progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentTemplate.usesCalendar {
                if canReadCalendar {
                    Text("Calendar access: Granted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Calendar access: Not granted")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        WidgetWeaverCalendarStore.shared.requestAccess()
                    } label: {
                        Label("Request Calendar access", systemImage: "calendar.badge.exclamationmark")
                    }
                }

                Text("Calendar content is app-driven. Widget reads cached entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        } header: {
            sectionHeader("Content")
        } footer: {
            Text("Template controls what data sources are used. Styles and layout still apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Name section
    var nameSection: some View {
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

    var symbolSection: some View {
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

    var imageSection: some View {
        let currentImageFileName = currentFamilyDraft().imageFileName
        let hasImage = !currentImageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let legacyFamilies: [EditingFamily] = {
            guard matchedSetEnabled else { return [] }

            var out: [EditingFamily] = []

            let small = matchedDrafts.small
            let medium = matchedDrafts.medium
            let large = matchedDrafts.large

            if !small.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, small.imageSmartPhoto == nil {
                out.append(.small)
            }
            if !medium.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, medium.imageSmartPhoto == nil {
                out.append(.medium)
            }
            if !large.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, large.imageSmartPhoto == nil {
                out.append(.large)
            }

            return out
        }()

        let legacyFamiliesLabel = legacyFamilies.map { $0.label }.joined(separator: ", ")

        return Section {
            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                Label(hasImage ? "Replace photo" : "Choose photo (optional)", systemImage: "photo")
            }

            imageThemeControls(currentImageFileName: currentImageFileName, hasImage: hasImage)

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

                // Smart Photo controls
                if let smart = currentFamilyDraft().imageSmartPhoto {
                    Button {
                        Task { await regenerateSmartPhotoRenders() }
                    } label: {
                        Label("Regenerate smart renders", systemImage: "arrow.clockwise")
                    }
                    .disabled(importInProgress)

                    Text("Smart Photo: v\(smart.algorithmVersion) • prepared \(smart.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)


    let variant: SmartPhotoVariantSpec? = {
        switch editingFamily {
        case .small: return smart.small
        case .medium: return smart.medium
        case .large: return smart.large
        }
    }()

    if let variant {
        NavigationLink {
            SmartPhotoCropEditorView(
                family: editingFamily,
                masterFileName: smart.masterFileName,
                targetPixels: variant.pixelSize,
                initialCropRect: variant.cropRect,
                onApply: { rect in
                    await applyManualSmartCrop(family: editingFamily, cropRect: rect)
                }
            )
        } label: {
            Label("Fix framing (\(editingFamily.label))", systemImage: "crop")
        }
        .disabled(importInProgress)
    } else {
        Text("Smart render data missing for \(editingFamily.label).")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
                } else {
                    Button {
                        Task { await regenerateSmartPhotoRenders() }
                    } label: {
                        Label("Make Smart Photo (per-size renders)", systemImage: "sparkles")
                    }
                    .disabled(importInProgress)

                    Text("Generates per-size crops for Small/Medium/Large.")
                        .font(.caption)
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
                    d.imageSmartPhoto = nil
                    setCurrentFamilyDraft(d)
                } label: {
                    Text("Remove image")
                }
            } else {
                Text("No image selected.")
                    .foregroundStyle(.secondary)
            }

            if matchedSetEnabled, !legacyFamilies.isEmpty {
                Button {
                    Task { await upgradeLegacyPhotosInCurrentDesign(maxUpgrades: 3) }
                } label: {
                    Label("Upgrade legacy photos in this design", systemImage: "wand.and.stars")
                }
                .disabled(importInProgress)

                Text("Upgrades up to 3 legacy images across sizes. Legacy in: \(legacyFamiliesLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Image")
        }
    }

    // MARK: - Updated: Layout is now layout-only (no templates, no steps)
    var layoutSection: some View {
        Section {
            Toggle("Accent bar", isOn: binding(\.showsAccentBar))

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

    var styleSection: some View {
        Section {
            HStack {
                Text("Padding")
                Slider(value: $styleDraft.padding, in: 0...32, step: 1)
                Text("\(Int(styleDraft.padding))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
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
            }

            VStack(alignment: .leading, spacing: 6) {
                Picker("Primary font", selection: $styleDraft.primaryTextStyle) {
                    ForEach(TextStyleToken.allCases) { token in
                        Text(token.rawValue).tag(token)
                    }
                }

                Picker("Secondary font", selection: $styleDraft.secondaryTextStyle) {
                    ForEach(TextStyleToken.allCases) { token in
                        Text(token.rawValue).tag(token)
                    }
                }

                Picker("Name font", selection: $styleDraft.nameTextStyle) {
                    ForEach(TextStyleToken.allCases) { token in
                        Text(token.rawValue).tag(token)
                    }
                }
            }

            HStack {
                Text("Corner radius")
                Slider(value: $styleDraft.cornerRadius, in: 0...44, step: 1)
                Text("\(Int(styleDraft.cornerRadius))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Style")
        } footer: {
            Text("Styles apply to all templates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var matchedSetSection: some View {
        Section {
            Toggle("Matched set (Small/Medium/Large)", isOn: $matchedSetEnabled)

            if matchedSetEnabled {
                Picker("Editing size", selection: $editingFamily) {
                    Text("Small").tag(EditingFamily.small)
                    Text("Medium").tag(EditingFamily.medium)
                    Text("Large").tag(EditingFamily.large)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                Text("Matched set uses per-size overrides. Widget will prefer the matching size variant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Single design is used for all widget sizes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Sizes")
        }
    }

    var variablesSection: some View {
        Section {
            if proManager.isProUnlocked {
                NavigationLink {
                    WidgetWeaverVariablesView(
                        proManager: proManager,
                        onShowPro: { activeSheet = .pro }
                    )
                } label: {
                    Label("Variables", systemImage: "number")
                }

                Text("Variables can be referenced in text using {key}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    activeSheet = .pro
                } label: {
                    Label("Unlock variables (Pro)", systemImage: "sparkles")
                }

                Text("Variables are a Pro feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Variables")
        }
    }

    var actionsSection: some View {
        Section {
            Button {
                saveSelected(makeDefault: false)
            } label: {
                Label("Save", systemImage: "tray.and.arrow.down")
            }

            Button {
                saveSelected(makeDefault: true)
            } label: {
                Label("Save as Default", systemImage: "star.fill")
            }

            Button {
                showRevertConfirmation = true
            } label: {
                Label("Revert Unsaved Changes", systemImage: "arrow.uturn.backward")
            }

            Button {
                refreshWidgets()
            } label: {
                Label("Refresh Widgets", systemImage: "arrow.clockwise")
            }

            Button {
                createNewDesign()
                selectedTab = .editor
            } label: {
                Label("New Design", systemImage: "plus")
            }

            Button {
                duplicateCurrentDesign()
                selectedTab = .editor
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button(role: .destructive) {
                showImageCleanupConfirmation = true
            } label: {
                Label("Clean up unused images", systemImage: "trash.slash")
            }
        } header: {
            sectionHeader("Actions")
        } footer: {
            Text(saveStatusMessage.isEmpty ? " " : saveStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var aiSection: some View {
        Section {
            if proManager.isProUnlocked {
                TextField("Prompt", text: $aiPrompt, axis: .vertical)
                    .lineLimit(1...4)

                Toggle("Make generated default", isOn: $aiMakeGeneratedDefault)

                Button {
                    Task { await generateNewDesignFromPrompt() }
                } label: {
                    Label("Generate design", systemImage: "sparkles")
                }
                .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Divider()

                TextField("Patch instruction", text: $aiPatchInstruction, axis: .vertical)
                    .lineLimit(1...4)

                Button {
                    Task { await applyPatchToCurrentDesign() }
                } label: {
                    Label("Apply patch", systemImage: "wand.and.stars")
                }
                .disabled(aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !aiStatusMessage.isEmpty {
                    Text(aiStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    activeSheet = .pro
                } label: {
                    Label("Unlock AI (Pro)", systemImage: "sparkles")
                }

                Text("AI generation and patching are Pro features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("AI")
        }
    }

    var exportSection: some View {
        Section {
            Button {
                activeSheet = .widgetHelp
            } label: {
                Label("Widget workflow help", systemImage: "questionmark.circle")
            }

            Button {
                activeSheet = .inspector
            } label: {
                Label("Open Inspector", systemImage: "doc.text.magnifyingglass")
            }

            Button {
                showImportPicker = true
            } label: {
                Label("Import design package", systemImage: "square.and.arrow.down")
            }
            .disabled(importInProgress)

            if importInProgress {
                Text("Importing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ShareLink(item: sharePackageForCurrentDesign()) {
                Label("Share current design", systemImage: "square.and.arrow.up")
            }

            ShareLink(item: sharePackageForAllDesigns()) {
                Label("Share all designs", systemImage: "square.and.arrow.up.on.square")
            }
        } header: {
            sectionHeader("Share / Help")
        }
    }

    // MARK: - Image theme helper UI

    private func imageThemeControls(currentImageFileName: String, hasImage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto theme from image", isOn: $autoThemeFromImage)

            if hasImage {
                Button {
                    if let img = AppGroup.loadUIImage(fileName: currentImageFileName) {
                        let suggestion = WidgetWeaverImageThemeExtractor.suggestTheme(from: img)
                        lastImageThemeFileName = currentImageFileName
                        lastImageThemeSuggestion = suggestion
                        saveStatusMessage = "Suggested theme extracted (draft only)."
                    } else {
                        saveStatusMessage = "Image not found for theme extraction."
                    }
                } label: {
                    Label("Suggest theme", systemImage: "wand.and.stars")
                }

                if lastImageThemeFileName == currentImageFileName,
                   let suggestion = lastImageThemeSuggestion {
                    HStack(spacing: 8) {
                        Text("Suggested:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(suggestion.background.rawValue) + \(suggestion.accent.rawValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        styleDraft.accent = suggestion.accent
                        styleDraft.background = suggestion.background
                        saveStatusMessage = "Applied suggested theme (draft only)."
                    } label: {
                        Label("Apply suggested theme", systemImage: "paintbrush")
                    }
                }
            } else {
                Text("Theme suggestion is available after selecting an image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

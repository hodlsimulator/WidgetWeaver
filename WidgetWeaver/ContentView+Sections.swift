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
                    addTemplateDesign(WidgetWeaverAboutView.featuredCalendarTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Next Up", systemImage: "calendar")
                }

                Menu {
                    Button {
                        applyStepsStarterPreset(copyToAllSizes: false)
                    } label: {
                        Label("Apply to this size (\(editingFamilyLabel))", systemImage: "figure.walk")
                    }

                    if matchedSetEnabled {
                        Button {
                            applyStepsStarterPreset(copyToAllSizes: true)
                        } label: {
                            Label("Apply to all sizes", systemImage: "square.on.square")
                        }
                    }

                    Divider()

                    Button {
                        activeSheet = .steps
                    } label: {
                        Label("Open Steps settings", systemImage: "heart")
                    }
                } label: {
                    Label("Steps", systemImage: "figure.walk")
                }
            }
            .controlSize(.small)

            if currentTemplate == .weather {
                Button {
                    activeSheet = .weather
                } label: {
                    Label("Weather settings", systemImage: "cloud.rain")
                }

                Text("Weather template renders from cached Weather snapshots.\nUse Weather settings to pick a location and force an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentTemplate == .nextUpCalendar {
                Button {
                    Task {
                        let granted = await WidgetWeaverCalendarEngine.shared.requestAccessIfNeeded()
                        if granted {
                            _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true)
                            await MainActor.run { saveStatusMessage = "Calendar refreshed.\nWidgets will update on next reload." }
                        } else {
                            await MainActor.run { saveStatusMessage = "Calendar access is off.\nEnable access to use Next Up." }
                        }
                    }
                } label: {
                    Label(
                        canReadCalendar ? "Refresh Calendar cache" : "Enable Calendar access",
                        systemImage: canReadCalendar ? "arrow.clockwise" : "checkmark.circle.fill"
                    )
                }

                Text("Next Up reads events on-device via EventKit and caches a small snapshot for widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectedTab = .explore
            } label: {
                Label("Browse templates (Explore)", systemImage: "sparkles")
            }
        } header: {
            sectionHeader("Content")
        } footer: {
            Text("Template controls the overall renderer.\nUse Explore for curated starters (Weather / Next Up / Steps) and then customise here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Existing sections (unchanged)
    var designsSection: some View {
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

            if !proManager.isProUnlocked {
                LabeledContent("Free tier designs", value: "\(savedSpecs.count)/\(WidgetWeaverEntitlements.maxFreeDesigns)")
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

    var proSection: some View {
        Section {
            if proManager.isProUnlocked {
                Label("WidgetWeaver Pro is unlocked.", systemImage: "checkmark.seal.fill")
                Button { activeSheet = .pro } label: { Label("Manage Pro", systemImage: "crown.fill") }
            } else {
                Label("Free tier", systemImage: "sparkles")
                Text("Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) saved designs.\nPro unlocks unlimited designs, matched sets, and variables.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
                if !proManager.statusMessage.isEmpty {
                    Text(proManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Pro")
        }
    }

    var variablesManagerSection: some View {
        Section {
            if proManager.isProUnlocked {
                let vars = WidgetWeaverVariableStore.shared.loadAll()
                LabeledContent("Saved variables", value: "\(vars.count)")
                if vars.isEmpty {
                    Text("No variables yet.\nAdd some here, or update via Shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let preview = vars.keys.sorted().prefix(3)
                    ForEach(Array(preview), id: \.self) { k in
                        let v = vars[k] ?? ""
                        LabeledContent(k, value: v.isEmpty ? " " : v)
                    }
                }

                Button { activeSheet = .variables } label: { Label("Manage Variables", systemImage: "slider.horizontal.3") }
            } else {
                Text("Variables are a Pro feature.\nUse {{key}} templates in text fields, then update values via Shortcuts or in-app once Pro is unlocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
            }
        } header: {
            sectionHeader("Variables")
        } footer: {
            Text("Variables render at widget render time.\nTemplate syntax: {{key}} or {{key|fallback}}.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var sharingSection: some View {
        Section {
            if importInProgress {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Importing…").foregroundStyle(.secondary)
                }
            }

            ShareLink(item: sharePackageForCurrentDesign(), preview: SharePreview("WidgetWeaver Design")) {
                Label("Share This Design", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: sharePackageForAllDesigns(), preview: SharePreview("WidgetWeaver Designs")) {
                Label("Share All Designs", systemImage: "square.and.arrow.up.on.square")
            }
            Button { showImportPicker = true } label: { Label("Import designs…", systemImage: "square.and.arrow.down") }
            Button(role: .destructive) { showImageCleanupConfirmation = true } label: { Label("Clean Up Unused Images", systemImage: "trash.slash") }
        } header: {
            sectionHeader("Sharing")
        } footer: {
            Text("Exports are JSON and include embedded images when available.\nImported designs are duplicated with new IDs to avoid overwriting.\n\"Clean Up\" removes image files not referenced by any saved design.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var matchedSetSection: some View {
        Section {
            Toggle("Matched set (Small/Medium/Large)", isOn: matchedSetBinding)
                .disabled(!proManager.isProUnlocked)

            if !proManager.isProUnlocked {
                Text("Matched sets are a Pro feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
            } else if matchedSetEnabled {
                Text("Editing is per preview size: \(editingFamilyLabel).\nUse the preview size picker to edit Small/Medium/Large.\nStyle and typography are shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { copyCurrentSizeToAllSizes() } label: { Label("Copy \(editingFamilyLabel) to all sizes", systemImage: "square.on.square") }
            } else {
                Text("When enabled, Small and Large can differ while sharing the same style tokens.\nMedium is treated as the base.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Matched set")
        }
    }

    var widgetWorkflowSection: some View {
        Section {
            Button { saveSelected(makeDefault: true) } label: { Label("Save & Make Default", systemImage: "checkmark.circle.fill") }
            Button { saveSelected(makeDefault: false) } label: { Label("Save (Keep Default)", systemImage: "tray.and.arrow.down") }

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

            Button { refreshWidgets() } label: { Label("Refresh Widgets", systemImage: "arrow.clockwise") }

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

    var textSection: some View {
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
                HStack {
                    Text("Corner radius")
                    Slider(value: $styleDraft.cornerRadius, in: 0...44, step: 1)
                    Text("\(Int(styleDraft.cornerRadius))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text("Widget outer corners are fixed by iOS; this radius affects inner cards and panels.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if currentFamilyDraft().template == .weather {
                HStack {
                    Text("Weather scale")
                    Slider(value: $styleDraft.weatherScale, in: 0.75...1.25, step: 0.01)
                    Text(String(format: "%.2f×", styleDraft.weatherScale))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Background", selection: $styleDraft.background) {
                ForEach(BackgroundToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Accent", selection: $styleDraft.accent) {
                ForEach(AccentToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Button { randomiseStyleDraft() } label: { Label("Randomise Style (Draft)", systemImage: "shuffle") }

            if matchedSetEnabled {
                Text("Style is shared across Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Style")
        }
    }

    var typographySection: some View {
        Section {
            Picker("Name text style", selection: $styleDraft.nameTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Primary text style", selection: $styleDraft.primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Secondary text style", selection: $styleDraft.secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
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

    var actionsSection: some View {
        Section {
            if !proManager.isProUnlocked {
                Toggle("Interactive buttons (Pro)", isOn: .constant(false))
                    .disabled(true)

                Text("Interactive widget buttons are a Pro feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
            } else {
                Toggle("Interactive buttons", isOn: $actionBarDraft.isEnabled)

                if actionBarDraft.isEnabled {
                    Picker("Button style", selection: $actionBarDraft.style) {
                        ForEach(WidgetActionButtonStyleToken.allCases) { token in
                            Text(token.displayName).tag(token)
                        }
                    }

                    if actionBarDraft.actions.isEmpty {
                        Button { actionBarDraft.actions = [ .defaultIncrement(), .defaultDone() ] } label: {
                            Label("Add starter buttons", systemImage: "sparkles")
                        }
                    } else {
                        ForEach($actionBarDraft.actions) { $action in
                            DisclosureGroup {
                                TextField("Button title", text: $action.title)
                                    .textInputAutocapitalization(.words)

                                TextField("SF Symbol (optional)", text: $action.systemImage)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)

                                Picker("Action", selection: $action.kind) {
                                    ForEach(WidgetActionKindToken.allCases) { token in
                                        Text(token.displayName).tag(token)
                                    }
                                }

                                TextField("Variable key", text: $action.variableKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)

                                switch action.kind {
                                case .incrementVariable:
                                    Stepper(
                                        "Increment amount: \(action.incrementAmount)",
                                        value: $action.incrementAmount,
                                        in: -99...99
                                    )
                                case .setVariableToNow:
                                    Picker("Now format", selection: $action.nowFormat) {
                                        ForEach(WidgetNowFormatToken.allCases) { token in
                                            Text(token.displayName).tag(token)
                                        }
                                    }
                                }

                                Button(role: .destructive) {
                                    actionBarDraft.actions.removeAll { $0.id == action.id }
                                } label: {
                                    Label("Remove button", systemImage: "trash")
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? action.kind.displayName : action.title)
                                        .lineLimit(1)

                                    if !action.variableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(action.variableKey)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }

                        Button {
                            if actionBarDraft.actions.count < WidgetActionBarSpec.maxActions {
                                actionBarDraft.actions.append(.defaultIncrement())
                            }
                        } label: {
                            Label("Add button", systemImage: "plus")
                        }
                        .disabled(actionBarDraft.actions.count >= WidgetActionBarSpec.maxActions)
                    }

                    Text("Buttons render on iOS 17+ as interactive widgets.\nThey update variables stored in the App Group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Actions")
        }
    }

    var aiSection: some View {
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

            Button("Generate New Design") { Task { await generateNewDesignFromPrompt() } }
                .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Divider()

            TextField("Patch instruction (edit current design)", text: $aiPatchInstruction, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            Button("Apply Patch To Current Design") { Task { await applyPatchToCurrentDesign() } }
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

    var statusSection: some View {
        Section {
            if hasUnsavedChanges {
                Label("Unsaved changes", systemImage: "pencil.tip.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.secondary)

                Button(role: .destructive) { showRevertConfirmation = true } label: {
                    Label("Revert to last saved", systemImage: "arrow.uturn.backward")
                }

                Button { activeSheet = .inspector } label: {
                    Label("Open Inspector", systemImage: "doc.text.magnifyingglass")
                }
            } else {
                Button { activeSheet = .inspector } label: {
                    Label("Open Inspector", systemImage: "doc.text.magnifyingglass")
                }
            }

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
}
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
                    addTemplateDesign(WidgetWeaverAboutView.featuredCalendarTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Next Up", systemImage: "calendar")
                }

                Menu {
                    Button {
                        applyStepsStarterPreset(copyToAllSizes: false)
                    } label: {
                        Label("Apply to this size (\(editingFamilyLabel))", systemImage: "figure.walk")
                    }

                    if matchedSetEnabled {
                        Button {
                            applyStepsStarterPreset(copyToAllSizes: true)
                        } label: {
                            Label("Apply to all sizes", systemImage: "square.on.square")
                        }
                    }

                    Divider()

                    Button {
                        activeSheet = .steps
                    } label: {
                        Label("Open Steps settings", systemImage: "heart")
                    }
                } label: {
                    Label("Steps", systemImage: "figure.walk")
                }
            }
            .controlSize(.small)

            if currentTemplate == .weather {
                Button {
                    activeSheet = .weather
                } label: {
                    Label("Weather settings", systemImage: "cloud.rain")
                }

                Text("Weather template renders from cached Weather snapshots.\nUse Weather settings to pick a location and force an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentTemplate == .nextUpCalendar {
                Button {
                    Task {
                        let granted = await WidgetWeaverCalendarEngine.shared.requestAccessIfNeeded()
                        if granted {
                            _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true)
                            await MainActor.run { saveStatusMessage = "Calendar refreshed.\nWidgets will update on next reload." }
                        } else {
                            await MainActor.run { saveStatusMessage = "Calendar access is off.\nEnable access to use Next Up." }
                        }
                    }
                } label: {
                    Label(
                        canReadCalendar ? "Refresh Calendar cache" : "Enable Calendar access",
                        systemImage: canReadCalendar ? "arrow.clockwise" : "checkmark.circle.fill"
                    )
                }

                Text("Next Up reads events on-device via EventKit and caches a small snapshot for widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectedTab = .explore
            } label: {
                Label("Browse templates (Explore)", systemImage: "sparkles")
            }
        } header: {
            sectionHeader("Content")
        } footer: {
            Text("Template controls the overall renderer.\nUse Explore for curated starters (Weather / Next Up / Steps) and then customise here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Existing sections (unchanged)
    var designsSection: some View {
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

            if !proManager.isProUnlocked {
                LabeledContent("Free tier designs", value: "\(savedSpecs.count)/\(WidgetWeaverEntitlements.maxFreeDesigns)")
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

    var proSection: some View {
        Section {
            if proManager.isProUnlocked {
                Label("WidgetWeaver Pro is unlocked.", systemImage: "checkmark.seal.fill")
                Button { activeSheet = .pro } label: { Label("Manage Pro", systemImage: "crown.fill") }
            } else {
                Label("Free tier", systemImage: "sparkles")
                Text("Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) saved designs.\nPro unlocks unlimited designs, matched sets, and variables.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
                if !proManager.statusMessage.isEmpty {
                    Text(proManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Pro")
        }
    }

    var variablesManagerSection: some View {
        Section {
            if proManager.isProUnlocked {
                let vars = WidgetWeaverVariableStore.shared.loadAll()
                LabeledContent("Saved variables", value: "\(vars.count)")
                if vars.isEmpty {
                    Text("No variables yet.\nAdd some here, or update via Shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let preview = vars.keys.sorted().prefix(3)
                    ForEach(Array(preview), id: \.self) { k in
                        let v = vars[k] ?? ""
                        LabeledContent(k, value: v.isEmpty ? " " : v)
                    }
                }

                Button { activeSheet = .variables } label: { Label("Manage Variables", systemImage: "slider.horizontal.3") }
            } else {
                Text("Variables are a Pro feature.\nUse {{key}} templates in text fields, then update values via Shortcuts or in-app once Pro is unlocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
            }
        } header: {
            sectionHeader("Variables")
        } footer: {
            Text("Variables render at widget render time.\nTemplate syntax: {{key}} or {{key|fallback}}.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var sharingSection: some View {
        Section {
            if importInProgress {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Importing…").foregroundStyle(.secondary)
                }
            }

            ShareLink(item: sharePackageForCurrentDesign(), preview: SharePreview("WidgetWeaver Design")) {
                Label("Share This Design", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: sharePackageForAllDesigns(), preview: SharePreview("WidgetWeaver Designs")) {
                Label("Share All Designs", systemImage: "square.and.arrow.up.on.square")
            }
            Button { showImportPicker = true } label: { Label("Import designs…", systemImage: "square.and.arrow.down") }
            Button(role: .destructive) { showImageCleanupConfirmation = true } label: { Label("Clean Up Unused Images", systemImage: "trash.slash") }
        } header: {
            sectionHeader("Sharing")
        } footer: {
            Text("Exports are JSON and include embedded images when available.\nImported designs are duplicated with new IDs to avoid overwriting.\n\"Clean Up\" removes image files not referenced by any saved design.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var matchedSetSection: some View {
        Section {
            Toggle("Matched set (Small/Medium/Large)", isOn: matchedSetBinding)
                .disabled(!proManager.isProUnlocked)

            if !proManager.isProUnlocked {
                Text("Matched sets are a Pro feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
            } else if matchedSetEnabled {
                Text("Editing is per preview size: \(editingFamilyLabel).\nUse the preview size picker to edit Small/Medium/Large.\nStyle and typography are shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { copyCurrentSizeToAllSizes() } label: { Label("Copy \(editingFamilyLabel) to all sizes", systemImage: "square.on.square") }
            } else {
                Text("When enabled, Small and Large can differ while sharing the same style tokens.\nMedium is treated as the base.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Matched set")
        }
    }

    var widgetWorkflowSection: some View {
        Section {
            Button { saveSelected(makeDefault: true) } label: { Label("Save & Make Default", systemImage: "checkmark.circle.fill") }
            Button { saveSelected(makeDefault: false) } label: { Label("Save (Keep Default)", systemImage: "tray.and.arrow.down") }

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

            Button { refreshWidgets() } label: { Label("Refresh Widgets", systemImage: "arrow.clockwise") }

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

    var textSection: some View {
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
                HStack {
                    Text("Corner radius")
                    Slider(value: $styleDraft.cornerRadius, in: 0...44, step: 1)
                    Text("\(Int(styleDraft.cornerRadius))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text("Widget outer corners are fixed by iOS; this radius affects inner cards and panels.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if currentFamilyDraft().template == .weather {
                HStack {
                    Text("Weather scale")
                    Slider(value: $styleDraft.weatherScale, in: 0.75...1.25, step: 0.01)
                    Text(String(format: "%.2f×", styleDraft.weatherScale))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Background", selection: $styleDraft.background) {
                ForEach(BackgroundToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Accent", selection: $styleDraft.accent) {
                ForEach(AccentToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Button { randomiseStyleDraft() } label: { Label("Randomise Style (Draft)", systemImage: "shuffle") }

            if matchedSetEnabled {
                Text("Style is shared across Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Style")
        }
    }

    var typographySection: some View {
        Section {
            Picker("Name text style", selection: $styleDraft.nameTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Primary text style", selection: $styleDraft.primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Secondary text style", selection: $styleDraft.secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
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

    var actionsSection: some View {
        Section {
            if !proManager.isProUnlocked {
                Toggle("Interactive buttons (Pro)", isOn: .constant(false))
                    .disabled(true)

                Text("Interactive widget buttons are a Pro feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
            } else {
                Toggle("Interactive buttons", isOn: $actionBarDraft.isEnabled)

                if actionBarDraft.isEnabled {
                    Picker("Button style", selection: $actionBarDraft.style) {
                        ForEach(WidgetActionButtonStyleToken.allCases) { token in
                            Text(token.displayName).tag(token)
                        }
                    }

                    if actionBarDraft.actions.isEmpty {
                        Button { actionBarDraft.actions = [ .defaultIncrement(), .defaultDone() ] } label: {
                            Label("Add starter buttons", systemImage: "sparkles")
                        }
                    } else {
                        ForEach($actionBarDraft.actions) { $action in
                            DisclosureGroup {
                                TextField("Button title", text: $action.title)
                                    .textInputAutocapitalization(.words)

                                TextField("SF Symbol (optional)", text: $action.systemImage)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)

                                Picker("Action", selection: $action.kind) {
                                    ForEach(WidgetActionKindToken.allCases) { token in
                                        Text(token.displayName).tag(token)
                                    }
                                }

                                TextField("Variable key", text: $action.variableKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)

                                switch action.kind {
                                case .incrementVariable:
                                    Stepper(
                                        "Increment amount: \(action.incrementAmount)",
                                        value: $action.incrementAmount,
                                        in: -99...99
                                    )
                                case .setVariableToNow:
                                    Picker("Now format", selection: $action.nowFormat) {
                                        ForEach(WidgetNowFormatToken.allCases) { token in
                                            Text(token.displayName).tag(token)
                                        }
                                    }
                                }

                                Button(role: .destructive) {
                                    actionBarDraft.actions.removeAll { $0.id == action.id }
                                } label: {
                                    Label("Remove button", systemImage: "trash")
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? action.kind.displayName : action.title)
                                        .lineLimit(1)

                                    if !action.variableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(action.variableKey)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }

                        Button {
                            if actionBarDraft.actions.count < WidgetActionBarSpec.maxActions {
                                actionBarDraft.actions.append(.defaultIncrement())
                            }
                        } label: {
                            Label("Add button", systemImage: "plus")
                        }
                        .disabled(actionBarDraft.actions.count >= WidgetActionBarSpec.maxActions)
                    }

                    Text("Buttons render on iOS 17+ as interactive widgets.\nThey update variables stored in the App Group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Actions")
        }
    }

    var aiSection: some View {
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

            Button("Generate New Design") { Task { await generateNewDesignFromPrompt() } }
                .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Divider()

            TextField("Patch instruction (edit current design)", text: $aiPatchInstruction, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            Button("Apply Patch To Current Design") { Task { await applyPatchToCurrentDesign() } }
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

    var statusSection: some View {
        Section {
            if hasUnsavedChanges {
                Label("Unsaved changes", systemImage: "pencil.tip.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.secondary)

                Button(role: .destructive) { showRevertConfirmation = true } label: {
                    Label("Revert to last saved", systemImage: "arrow.uturn.backward")
                }

                Button { activeSheet = .inspector } label: {
                    Label("Open Inspector", systemImage: "doc.text.magnifyingglass")
                }
            } else {
                Button { activeSheet = .inspector } label: {
                    Label("Open Inspector", systemImage: "doc.text.magnifyingglass")
                }
            }

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
}

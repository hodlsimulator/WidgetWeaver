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
                } label: {
                    Label("Steps", systemImage: "figure.walk.circle.fill")
                }
            }

            if currentTemplate == .nextUpCalendar {
                if canReadCalendar {
                    Label("Calendar access granted", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        activeSheet = .calendarPermission
                    } label: {
                        Label("Enable Calendar access", systemImage: "calendar.badge.exclamationmark")
                    }
                }
            }

        } header: {
            sectionHeader("Content")
        } footer: {
            switch currentTemplate {
            case .nextUpCalendar:
                Text("Calendar widgets show the next event from the selected calendar(s).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .weather:
                Text("Weather widgets use the device’s saved location. You can refresh it from the Weather screen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
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

        let smart = currentFamilyDraft().imageSmartPhoto

        let previewFileName: String = {
            guard let smart else { return currentImageFileName }

            let candidate: String?
            switch editingFamily {
            case .small:
                candidate = smart.small?.renderFileName
            case .medium:
                candidate = smart.medium?.renderFileName
            case .large:
                candidate = smart.large?.renderFileName
            }

            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }

            return currentImageFileName
        }()
        return Section {
            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                Label(hasImage ? "Replace photo" : "Choose photo (optional)", systemImage: "photo")
            }

            imageThemeControls(currentImageFileName: currentImageFileName, hasImage: hasImage)

            if hasImage {
                if let uiImage = AppGroup.loadUIImage(fileName: previewFileName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let smart = smart {
                        DisclosureGroup("Smart Photo details") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Previewing: \(previewFileName)")
                                Text("Master: \(smart.masterFileName)")
                                Text("Small: \(smart.small?.renderFileName ?? "—")")
                                Text("Medium: \(smart.medium?.renderFileName ?? "—")")
                                Text("Large: \(smart.large?.renderFileName ?? "—")")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                        }
                    }

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

            Picker("Accent", selection: $styleDraft.accent) {
                ForEach(AccentColorToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Background", selection: $styleDraft.background) {
                ForEach(BackgroundStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Text style: Name", selection: $styleDraft.nameTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Text style: Primary", selection: $styleDraft.primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Text style: Secondary", selection: $styleDraft.secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Toggle("Show icon shadow", isOn: $styleDraft.showSymbolShadow)
            Toggle("Show text shadow", isOn: $styleDraft.showTextShadow)

        } header: {
            sectionHeader("Style")
        }
    }

    var actionBarSection: some View {
        Section {
            Toggle("Show action bar", isOn: $actionBarDraft.enabled)

            if actionBarDraft.enabled {
                Picker("Style", selection: $actionBarDraft.style) {
                    ForEach(ActionBarStyleToken.allCases) { token in
                        Text(token.displayName).tag(token)
                    }
                }

                Picker("Accent", selection: $actionBarDraft.accent) {
                    ForEach(AccentColorToken.allCases) { token in
                        Text(token.displayName).tag(token)
                    }
                }

                Stepper(
                    "Items: \(actionBarDraft.items.count)",
                    value: Binding(
                        get: { actionBarDraft.items.count },
                        set: { newCount in
                            actionBarDraft.items = ActionBarDraft.adjustedItems(actionBarDraft.items, targetCount: newCount)
                        }
                    ),
                    in: 1...6
                )

                ForEach(Array(actionBarDraft.items.enumerated()), id: \.offset) { idx, _ in
                    NavigationLink {
                        ActionBarItemEditor(
                            item: $actionBarDraft.items[idx],
                            index: idx,
                            showInternalTools: showInternalTools
                        )
                    } label: {
                        HStack {
                            Text("Item \(idx + 1)")
                            Spacer()
                            Text(actionBarDraft.items[idx].kind.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

        } header: {
            sectionHeader("Action Bar")
        }
    }

    var matchedSetSection: some View {
        Section {
            Toggle("Matched set (Small / Medium / Large)", isOn: matchedSetBinding)

            if matchedSetEnabled {
                Picker("Editing", selection: $previewFamily) {
                    Text("Small").tag(WidgetFamily.systemSmall)
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                Button {
                    copyCurrentSizeToAllSizes()
                } label: {
                    Label("Copy \(editingFamilyLabel) to all sizes (draft)", systemImage: "square.on.square")
                }
            } else {
                Text("When enabled, Small/Medium/Large can have different text, images, and layouts.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Matched Set")
        } footer: {
            if matchedSetEnabled {
                Text("Matched sets are stored inside the design and resolved by widget size at render time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var proUpsellSection: some View {
        Section {
            Button {
                activeSheet = .pro
            } label: {
                Label("Unlock Pro", systemImage: "crown.fill")
            }
        } footer: {
            Text("Pro unlocks variables, matched sets, and unlimited saved designs.")
        }
    }

    var internalToolsSection: some View {
        Section {
            Toggle("Show internal tools", isOn: $showInternalTools)

            if showInternalTools {
                Toggle("Enable thumbnail rendering", isOn: $thumbnailRenderingEnabled)
                    .onChange(of: thumbnailRenderingEnabled) { _ in
                        WidgetPreviewThumbnailCacheSignal.shared.bumpCoalesced()
                    }

                Button {
                    WidgetWeaverEntitlements.setProUnlocked(true)
                    proManager.syncFromLocalEntitlements(status: "Pro unlocked (internal).")
                } label: {
                    Label("Unlock Pro flag (internal)", systemImage: "wand.and.stars")
                }

                Button(role: .destructive) {
                    WidgetWeaverEntitlements.setProUnlocked(false)
                    proManager.syncFromLocalEntitlements(status: "Pro locked (internal).")
                } label: {
                    Label("Reset Pro flag (internal)", systemImage: "xmark.seal")
                }
            }
        } header: {
            sectionHeader("Internal")
        }
    }
}

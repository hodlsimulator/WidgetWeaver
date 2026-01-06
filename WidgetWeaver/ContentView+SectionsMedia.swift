//
//  ContentView+SectionsMedia.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
import PhotosUI
import UIKit
import WidgetKit

extension ContentView {
    private func widgetFamily(for family: EditingFamily) -> WidgetFamily {
        switch family {
        case .small: return .systemSmall
        case .medium: return .systemMedium
        case .large: return .systemLarge
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

                    SmartPhotoPreviewStripView(
                        smart: smart,
                        selectedFamily: editingFamily,
                        onSelectFamily: { family in
                            previewFamily = widgetFamily(for: family)
                        }
                    )

                    let family = editingFamily
                    let familyLabel = editingFamilyLabel

                    let variant: SmartPhotoVariantSpec? = {
                        switch family {
                        case .small: return smart.small
                        case .medium: return smart.medium
                        case .large: return smart.large
                        }
                    }()

                    if let variant {
                        NavigationLink {
                            SmartPhotoCropEditorView(
                                family: family,
                                masterFileName: smart.masterFileName,
                                targetPixels: variant.pixelSize,
                                initialCropRect: variant.cropRect,
                                onApply: { rect in
                                    await applyManualSmartCrop(family: family, cropRect: rect)
                                }
                            )
                        } label: {
                            Label("Fix framing (\(familyLabel))", systemImage: "crop")
                        }
                        .disabled(importInProgress)
                    } else {
                        Text("Smart render data missing for \(familyLabel).")
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
                    Label("Upgrade legacy photos to Smart Photo (\(legacyFamiliesLabel))", systemImage: "sparkles")
                }
                .disabled(importInProgress)

                Text("Upgrades up to 3 legacy image files per tap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Image")
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

                    HStack {
                        Menu {
                            ForEach(ActionBarPreset.allCases) { preset in
                                Button {
                                    withAnimation {
                                        actionBarDraft.replace(with: preset)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.title)
                                        Text(preset.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } label: {
                            Label("Presets", systemImage: "sparkles")
                        }

                        Spacer()

                        Button {
                            if actionBarDraft.actions.count < WidgetActionBarSpec.maxActions {
                                actionBarDraft.actions.append(.defaultIncrement())
                            }
                        } label: {
                            Label("Add button", systemImage: "plus")
                        }
                        .disabled(actionBarDraft.actions.count >= WidgetActionBarSpec.maxActions)
                    }
                    .controlSize(.small)

                    if actionBarDraft.actions.isEmpty {
                        Button { actionBarDraft.actions = [ .defaultIncrement(), .defaultDone() ] } label: {
                            Label("Add starter buttons", systemImage: "sparkles")
                        }
                    } else {
                        ForEach($actionBarDraft.actions) { action in
                            let actionValue = action.wrappedValue
                            let idx = actionBarDraft.actions.firstIndex(where: { $0.id == actionValue.id })
                            let canMoveUp = (idx ?? 0) > 0
                            let canMoveDown = idx != nil && idx! < (actionBarDraft.actions.count - 1)
                            let keyValidation = actionValue.validateVariableKey()

                            DisclosureGroup {
                                TextField("Button title", text: action.title)
                                    .textInputAutocapitalization(.words)

                                TextField("SF Symbol (optional)", text: action.systemImage)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)

                                Picker("Action", selection: action.kind) {
                                    ForEach(WidgetActionKindToken.allCases) { token in
                                        Text(token.displayName).tag(token)
                                    }
                                }

                                TextField("Variable key", text: action.variableKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)

                                if case .warning(let message) = keyValidation {
                                    Label(message, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }

                                switch actionValue.kind {
                                case .incrementVariable:
                                    Stepper(
                                        "Increment amount: \(actionValue.incrementAmount)",
                                        value: action.incrementAmount,
                                        in: -99...99
                                    )
                                case .setVariableToNow:
                                    Picker("Now format", selection: action.nowFormat) {
                                        ForEach(WidgetNowFormatToken.allCases) { token in
                                            Text(token.displayName).tag(token)
                                        }
                                    }
                                }

                                ControlGroup {
                                    Button {
                                        withAnimation { actionBarDraft.moveUp(id: actionValue.id) }
                                    } label: {
                                        Label("Move Up", systemImage: "arrow.up")
                                    }
                                    .disabled(!canMoveUp)

                                    Button {
                                        withAnimation { actionBarDraft.moveDown(id: actionValue.id) }
                                    } label: {
                                        Label("Move Down", systemImage: "arrow.down")
                                    }
                                    .disabled(!canMoveDown)
                                }
                                .controlSize(.small)

                                Button(role: .destructive) {
                                    withAnimation { actionBarDraft.actions.removeAll(where: { $0.id == actionValue.id }) }
                                } label: {
                                    Label("Remove button", systemImage: "trash")
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(actionValue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Button" : actionValue.title)
                                        .font(.headline)

                                    Text(actionValue.kind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            sectionHeader("Actions")
        } footer: {
            Text("Interactive buttons trigger App Intents.\nThey can update variables and refresh widgets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

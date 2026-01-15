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
    var imageSection: some View {
        let d = currentFamilyDraft()
        let currentImageFileName = d.imageFileName
        let hasImage = !currentImageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Section {
            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                Label(hasImage ? "Replace photo" : "Choose photo (optional)", systemImage: "photo")
            }

            imageThemeControls(currentImageFileName: currentImageFileName, hasImage: hasImage)

            if hasImage {
                EditorResolvedImagePreview(
                    imageSpec: ImageSpec(
                        fileName: currentImageFileName,
                        contentMode: d.imageContentMode,
                        height: d.imageHeight,
                        cornerRadius: d.imageCornerRadius,
                        smartPhoto: d.imageSmartPhoto
                    ),
                    family: previewFamily,
                    maxHeight: 140
                )

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
        } header: {
            sectionHeader("Image")
        }
    }

    var actionsSection: some View {
        Section {
            if !proManager.isProUnlocked {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.proRequiredForActions(),
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
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

private struct EditorResolvedImagePreview: View {
    let imageSpec: ImageSpec
    let family: WidgetFamily
    let maxHeight: CGFloat

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    private var shuffleManifestFileName: String {
        (imageSpec.smartPhoto?.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shuffleEnabled: Bool {
        !shuffleManifestFileName.isEmpty
    }

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken

        Group {
            if shuffleEnabled {
                TimelineView(.periodic(from: Date(), by: shuffleTickIntervalSeconds())) { ctx in
                    WidgetWeaverRenderClock.withNow(ctx.date) {
                        previewBody
                    }
                }
            } else {
                previewBody
            }
        }
    }

    private var previewBody: some View {
        let uiImage = imageSpec.loadUIImageForRender(family: family, debugContext: nil)

        return VStack(alignment: .leading, spacing: 6) {
            if let label = previewLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary)
                        .frame(maxHeight: maxHeight)

                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text(missingImageMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private var previewLabel: String? {
        if shuffleEnabled { return "Current shuffle photo" }
        if imageSpec.smartPhoto != nil { return "Smart Photo render" }
        return nil
    }

    private var missingImageMessage: String {
        if shuffleEnabled { return "No prepared shuffle photo yet." }
        return "Selected image file not found in App Group."
    }

    private func shuffleTickIntervalSeconds() -> TimeInterval {
        let mf = shuffleManifestFileName
        guard !mf.isEmpty, let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            return 30
        }

        let minutes = manifest.rotationIntervalMinutes
        guard minutes > 0 else { return 60 }

        let seconds = Double(minutes) * 60.0
        return max(5, min(60, seconds / 4.0))
    }
}

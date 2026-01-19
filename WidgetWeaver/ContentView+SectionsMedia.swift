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
    private enum AlbumShuffleQuickStartGate: Hashable {
        case choosePhoto
        case prepareSmartPhoto
        case allowAccess
        case openSettings
        case chooseAlbum
        case changeAlbum
        case preparing
        case tryAgain
    }

    var imageSection: some View {
        let d = currentFamilyDraft()
        let currentImageFileName = d.imageFileName
        let hasImage = !currentImageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let isPoster = d.template == .poster
        let pickButtonTitle = hasImage ? "Replace photo" : (isPoster ? "Choose photo" : "Choose photo (optional)")

        return Section {
            Button {
                photoPickerPresented = true
            } label: {
                Label(pickButtonTitle, systemImage: "photo")
            }

            if isPoster {
                let gate = albumShuffleQuickStartGate(draft: d, hasImage: hasImage)

                VStack(alignment: .leading, spacing: 4) {
                    albumShuffleQuickStartRow(gate: gate)
                        .disabled(importInProgress)

                    if albumShuffleQuickStartFailureSpecID == selectedSpecID,
                       let message = albumShuffleQuickStartFailureMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !message.isEmpty
                    {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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

    private func albumShuffleQuickStartGate(draft: FamilyDraft, hasImage: Bool) -> AlbumShuffleQuickStartGate {
        if albumShuffleQuickStartInProgress {
            return .preparing
        }

        let hasFailureForCurrentSpec: Bool = {
            guard albumShuffleQuickStartFailureSpecID == selectedSpecID else { return false }
            let msg = (albumShuffleQuickStartFailureMessage ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !msg.isEmpty
        }()

        if !hasImage {
            return .choosePhoto
        }

        if draft.imageSmartPhoto == nil {
            return hasFailureForCurrentSpec ? .tryAgain : .prepareSmartPhoto
        }

        let photoAccess = editorToolContext.photoLibraryAccess
        if !photoAccess.allowsReadWrite {
            if photoAccess.isRequestable {
                return .allowAccess
            }
            return .openSettings
        }

        let manifestFileName = (draft.imageSmartPhoto?.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let baseGate: AlbumShuffleQuickStartGate = manifestFileName.isEmpty ? .chooseAlbum : .changeAlbum

        if hasFailureForCurrentSpec {
            switch baseGate {
            case .chooseAlbum, .changeAlbum:
                return .tryAgain
            default:
                break
            }
        }

        return baseGate
    }

    @ViewBuilder
    private func albumShuffleQuickStartRow(gate: AlbumShuffleQuickStartGate) -> some View {
        if gate == .openSettings, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            Link(destination: settingsURL) {
                albumShuffleQuickStartRowLabel(gate: gate)
            }
        } else {
            Button {
                Task { await quickStartAlbumShuffleFromImageSection() }
            } label: {
                albumShuffleQuickStartRowLabel(gate: gate)
            }
        }
    }

    @ViewBuilder
    private func albumShuffleQuickStartRowLabel(gate: AlbumShuffleQuickStartGate) -> some View {
        HStack(spacing: 10) {
            Label("Shuffle from an album…", systemImage: "shuffle")

            Spacer(minLength: 0)

            if gate == .preparing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(albumShuffleQuickStartGateLabel(gate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func albumShuffleQuickStartGateLabel(_ gate: AlbumShuffleQuickStartGate) -> String {
        switch gate {
        case .choosePhoto:
            return "Choose photo"
        case .prepareSmartPhoto:
            return "Prepare"
        case .allowAccess:
            return "Allow access"
        case .openSettings:
            return "Open Settings"
        case .chooseAlbum:
            return "Choose album"
        case .changeAlbum:
            return "Change album"
        case .preparing:
            return "Preparing…"
        case .tryAgain:
            return "Try again"
        }
    }

    // MARK: - Photo picker (Explore add → choose image immediately)

    func markPendingAutoPresentPhotoPickerIfNeeded(addedTemplate: WidgetSpec) {
        guard templateWantsImmediatePhotoSelection(addedTemplate) else { return }
        pendingAutoPresentPhotoPickerSpecID = selectedSpecID
    }

    func attemptAutoPresentPhotoPickerIfNeeded() {
        guard selectedTab == .editor else { return }
        guard pendingAutoPresentPhotoPickerSpecID == selectedSpecID else { return }

        // Consume the pending trigger regardless of whether the picker can be shown,
        // so a dismissed picker does not loop.
        pendingAutoPresentPhotoPickerSpecID = nil

        guard activeSheet == nil else { return }

        let d = currentFamilyDraft()
        guard d.template == .poster else { return }

        let hasImage = !d.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !hasImage else { return }

        photoPickerPresented = true
    }

    private func templateWantsImmediatePhotoSelection(_ template: WidgetSpec) -> Bool {
        if template.layout.template == .poster { return true }

        // Future-proofing: if a template uses matched-set variants with poster,
        // treat it as photo-first as well.
        if let matched = template.matchedSet {
            let variants = [matched.small, matched.medium, matched.large]
            for variant in variants {
                if variant?.layout.template == .poster { return true }
            }
        }

        return false
    }

    // MARK: - Album Shuffle quick start

    @MainActor
    func quickStartAlbumShuffleFromImageSection() async {
        guard !importInProgress else { return }
        guard !albumShuffleQuickStartInProgress else { return }

        // Clear any previous error so the row state reflects the next attempt.
        albumShuffleQuickStartFailureMessage = nil
        albumShuffleQuickStartFailureSpecID = nil

        if activeSheet != nil {
            let msg = "Close the current sheet to set up Album Shuffle."
            saveStatusMessage = msg
            albumShuffleQuickStartFailureMessage = msg
            albumShuffleQuickStartFailureSpecID = selectedSpecID
            return
        }

        let draft = currentFamilyDraft()
        guard draft.template == .poster else { return }

        let baseFileName = draft.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseFileName.isEmpty {
            saveStatusMessage = "Choose a photo first."
            photoPickerPresented = true
            return
        }

        albumShuffleQuickStartInProgress = true
        importInProgress = true
        defer {
            importInProgress = false
            albumShuffleQuickStartInProgress = false
        }

        if draft.imageSmartPhoto == nil {
            await regenerateSmartPhotoRenders()
        }

        guard currentFamilyDraft().imageSmartPhoto != nil else {
            let msg = resolvedAlbumShuffleSmartPhotoFailureMessage()
            saveStatusMessage = msg
            albumShuffleQuickStartFailureMessage = msg
            albumShuffleQuickStartFailureSpecID = selectedSpecID
            return
        }

        if !EditorPhotoLibraryAccess.current().allowsReadWrite {
            saveStatusMessage = "Requesting Photos access…"
            let granted = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
            EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)

            if !granted {
                let access = EditorPhotoLibraryAccess.current()
                let msg: String
                if access.isBlockedInSettings {
                    msg = "Photos access is off.\nEnable access in Settings to choose an album."
                } else if access.isRequestable {
                    msg = "Photos access is required to choose an album."
                } else {
                    msg = "Photos access is not available."
                }
                saveStatusMessage = msg
                albumShuffleQuickStartFailureMessage = msg
                albumShuffleQuickStartFailureSpecID = selectedSpecID
                return
            }
        }

        let albumID = resolvedSmartAlbumContainerIDForAlbumShuffle(from: currentFamilyDraft())
        editorFocusSnapshot = .smartAlbumContainer(id: albumID)

        await Task.yield()

        if activeSheet != nil {
            let msg = "Close the current sheet to continue Album Shuffle setup."
            saveStatusMessage = msg
            albumShuffleQuickStartFailureMessage = msg
            albumShuffleQuickStartFailureSpecID = selectedSpecID
            return
        }

        albumShufflePickerPresented = true
    }

    private func resolvedAlbumShuffleSmartPhotoFailureMessage() -> String {
        let msg = saveStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty {
            let lower = msg.lowercased()
            if lower.hasPrefix("regeneration failed") { return msg }
            if lower.contains("not found") { return msg }
            if lower.contains("missing") { return msg }
            if lower.contains("no photo") { return msg }
        }

        return "Smart Photo could not be prepared.\nTry replacing the photo, then try again."
    }

    private func resolvedSmartAlbumContainerIDForAlbumShuffle(from draft: FamilyDraft) -> String {
        let fallbackAlbumID = "smartPhoto.album"

        guard
            let manifestFileName = draft.imageSmartPhoto?.shuffleManifestFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !manifestFileName.isEmpty,
            let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFileName)
        else {
            return fallbackAlbumID
        }

        let rawSourceID = manifest.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawSourceID.isEmpty {
            return fallbackAlbumID
        }

        return rawSourceID
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

    @AppStorage("preview.liveEnabled")
    private var liveEnabled: Bool = true

    private var shuffleManifestFileName: String {
        (imageSpec.smartPhoto?.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shuffleEnabled: Bool {
        !shuffleManifestFileName.isEmpty
    }

    private var usesShuffleRotation: Bool {
        guard shuffleEnabled else { return false }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else { return true }
        return manifest.rotationIntervalMinutes > 0
    }

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken

        Group {
            if usesShuffleRotation {
                let interval: TimeInterval = liveEnabled ? 5 : 60
                let start = WidgetWeaverRenderClock.alignedTimelineStartDate(interval: interval)

                TimelineView(.periodic(from: start, by: interval)) { ctx in
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
}

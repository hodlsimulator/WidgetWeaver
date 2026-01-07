//
//  ContentView+SectionSmartPhoto.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
import UIKit

extension ContentView {
    func smartPhotoSection(focus _: Binding<EditorFocusSnapshot>) -> some View {
        let d = currentFamilyDraft()
        let hasImage = !d.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSmartPhoto = d.imageSmartPhoto != nil

        let photoAccess = editorToolContext.photoLibraryAccess

        let legacyFamilies: [EditingFamily] = {
            guard matchedSetEnabled else { return [] }
            return EditingFamily.allCases.filter { $0 != selectedFamily }
        }()

        return Section {
            if !hasImage {
                Text("Add an image first to enable Smart Photos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasSmartPhoto, let unavailable = EditorUnavailableState.albumShufflePhotosAccess(access: photoAccess) {
                EditorUnavailableStateView(
                    state: unavailable,
                    importInProgress: $importInProgress,
                    saveStatusMessage: $saveStatusMessage,
                    onRequestPhotoLibraryAccess: {
                        await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
                    }
                )
            }

            if hasImage {
                SmartPhotoImportButton(
                    currentFamily: selectedFamily,
                    currentDraft: d,
                    setDraft: setFamilyDraft(_:),
                    legacyFamiliesToUpgrade: legacyFamilies,
                    importInProgress: $importInProgress,
                    saveStatusMessage: $saveStatusMessage
                )
                .disabled(importInProgress)

                Text("Upgrades up to 3 legacy image files per tap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Smart Photo")
        }
    }
}


// MARK: - Unavailable state (Photos first)

/// A small, reusable model for “why unavailable” guidance and CTAs.
///
/// This is intentionally minimal (Photos first) so more permission/availability patterns can be
/// centralised without duplicating conditional UI logic across sections.
struct EditorUnavailableState: Hashable, Sendable {
    var message: String
    var actions: [EditorUnavailableAction]

    init(message: String, actions: [EditorUnavailableAction] = []) {
        self.message = message
        self.actions = actions
    }

    static func albumShufflePhotosAccess(access: EditorPhotoLibraryAccess) -> EditorUnavailableState? {
        guard !access.allowsReadWrite else { return nil }

        var actions: [EditorUnavailableAction] = []

        if access.isRequestable {
            actions.append(
                EditorUnavailableAction(
                    kind: .requestPhotoLibraryAccess,
                    title: "Enable Photos access",
                    systemImage: "photo.on.rectangle.angled"
                )
            )
        } else if access.isBlockedInSettings {
            actions.append(
                EditorUnavailableAction(
                    kind: .openAppSettings,
                    title: "Open Photos Settings",
                    systemImage: "gear"
                )
            )
        } else {
            actions.append(
                EditorUnavailableAction(
                    kind: .openAppSettings,
                    title: "Open App Settings",
                    systemImage: "gear"
                )
            )
        }

        return EditorUnavailableState(
            message: "Album Shuffle uses the Photo Library and is hidden until Photos access is granted.",
            actions: actions
        )
    }
}

struct EditorUnavailableAction: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case requestPhotoLibraryAccess
        case openAppSettings
    }

    var kind: Kind
    var title: String
    var systemImage: String
}

struct EditorUnavailableStateView: View {
    var state: EditorUnavailableState
    var importInProgress: Binding<Bool>
    var saveStatusMessage: Binding<String>
    var onRequestPhotoLibraryAccess: (() async -> Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(state.actions, id: \.self) { action in
                switch action.kind {
                case .requestPhotoLibraryAccess:
                    Button {
                        Task { @MainActor in
                            guard let onRequestPhotoLibraryAccess else { return }
                            guard !importInProgress.wrappedValue else { return }

                            importInProgress.wrappedValue = true
                            defer { importInProgress.wrappedValue = false }

                            let granted = await onRequestPhotoLibraryAccess()
                            saveStatusMessage.wrappedValue = granted ? "Photos access enabled." : "Photos access not granted."
                        }
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .disabled(importInProgress.wrappedValue || onRequestPhotoLibraryAccess == nil)

                case .openAppSettings:
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: settingsURL) {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                }
            }
        }
    }
}

//
//  EditorUnavailableState.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

enum EditorUnavailableCTAKind: String, CaseIterable, Hashable, Sendable {
    case requestPhotosAccess
    case openAppSettings

    case showPro
}

struct EditorUnavailableCTA: Hashable, Sendable {
    var title: String
    var systemImage: String
    var kind: EditorUnavailableCTAKind

    static func requestPhotosAccess(
        title: String = "Enable Photos access",
        systemImage: String = "photo.on.rectangle.angled"
    ) -> EditorUnavailableCTA {
        EditorUnavailableCTA(
            title: title,
            systemImage: systemImage,
            kind: .requestPhotosAccess
        )
    }

    static func openPhotosSettings(
        title: String = "Open Photos Settings",
        systemImage: String = "gear"
    ) -> EditorUnavailableCTA {
        EditorUnavailableCTA(
            title: title,
            systemImage: systemImage,
            kind: .openAppSettings
        )
    }

    static func showPro(
        title: String = "Unlock Pro",
        systemImage: String = "crown.fill"
    ) -> EditorUnavailableCTA {
        EditorUnavailableCTA(
            title: title,
            systemImage: systemImage,
            kind: .showPro
        )
    }
}

struct EditorUnavailableState: Hashable, Sendable {
    var message: String
    var cta: EditorUnavailableCTA?

    // MARK: - Editor-level selection / context messaging

    static func multiSelectionToolListReduced() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Multiple items selected. Most tools apply to a single item, so the tool list is reduced. Select one item to see more tools.",
            cta: nil
        )
    }

    static func noToolsAvailableForSelection() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "No tools are available for this selection. Select a single item, or clear selection to return to widget editing.",
            cta: nil
        )
    }

    // MARK: - Missing data / setup guidance

    static func imageRequiredForSmartPhoto() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Choose a photo in Image first to enable Smart Photo.",
            cta: nil
        )
    }

    static func imageRequiredForSmartPhotoFraming() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Choose a photo in Image first to enable Smart Photo Framing.",
            cta: nil
        )
    }

    static func smartPhotoRequiredForSmartPhotoFraming() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Make Smart Photo in Smart Photo first to enable framing controls.",
            cta: nil
        )
    }

    static func imageRequiredForSmartRules() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Choose a photo in Image first to enable Smart Rules.",
            cta: nil
        )
    }

    static func smartPhotoRequiredForSmartRules() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Make Smart Photo in Smart Photo first.\nSmart Rules are applied when building an Album Shuffle list.",
            cta: nil
        )
    }

    static func imageRequiredForAlbumShuffle() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Choose a photo in Image first. Then make Smart Photo renders in Smart Photo to enable Album Shuffle.",
            cta: nil
        )
    }

    static func smartPhotoRequiredForAlbumShuffle() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Album Shuffle requires Smart Photo. In Smart Photo, tap ‘Make Smart Photo (per-size renders)’.",
            cta: nil
        )
    }

    // MARK: - Monetisation

    static func proRequiredForVariables() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Variables require WidgetWeaver Pro.",
            cta: .showPro()
        )
    }

    static func proRequiredForMatchedSet() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Matched sets require WidgetWeaver Pro.",
            cta: .showPro()
        )
    }

    static func proRequiredForActions() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Interactive widget buttons are a Pro feature.",
            cta: .showPro()
        )
    }

    static func proRequiredForAI() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "AI tools require WidgetWeaver Pro.",
            cta: .showPro()
        )
    }

    // MARK: - Permissions (Photos)

    static func photosAccessRequiredForAlbumShuffle(
        photoAccess: EditorPhotoLibraryAccess
    ) -> EditorUnavailableState? {
        guard !photoAccess.allowsReadWrite else { return nil }

        let message = "Album Shuffle uses the Photo Library and is hidden until Photos access is granted."

        let cta: EditorUnavailableCTA? = {
            if photoAccess.isRequestable {
                return .requestPhotosAccess()
            }
            if photoAccess.isBlockedInSettings || !photoAccess.isRequestable {
                return .openPhotosSettings()
            }
            return nil
        }()

        return EditorUnavailableState(
            message: message,
            cta: cta
        )
    }
}

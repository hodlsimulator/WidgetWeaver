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
}

struct EditorUnavailableState: Hashable, Sendable {
    var message: String
    var cta: EditorUnavailableCTA?

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

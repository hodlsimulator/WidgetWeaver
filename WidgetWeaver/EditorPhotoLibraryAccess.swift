//
//  EditorPhotoLibraryAccess.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation
import Photos

/// A small, test-friendly wrapper around Photos authorisation status.
///
/// This keeps Photos framework references out of the core context/capability vocabulary.
enum EditorPhotoLibraryAccessStatus: String, CaseIterable, Hashable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorised
    case limited
    case unknown

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized:
            self = .authorised
        case .limited:
            self = .limited
        @unknown default:
            self = .unknown
        }
    }

    var allowsReadWrite: Bool {
        switch self {
        case .authorised, .limited:
            return true
        case .notDetermined, .restricted, .denied, .unknown:
            return false
        }
    }

    var isRequestable: Bool {
        self == .notDetermined
    }

    var isBlockedInSettings: Bool {
        switch self {
        case .denied, .restricted:
            return true
        case .notDetermined, .authorised, .limited, .unknown:
            return false
        }
    }
}

/// A snapshot of Photo Library access relevant to editor tooling.
struct EditorPhotoLibraryAccess: Hashable, Sendable {
    var status: EditorPhotoLibraryAccessStatus

    var allowsReadWrite: Bool { status.allowsReadWrite }
    var isRequestable: Bool { status.isRequestable }
    var isBlockedInSettings: Bool { status.isBlockedInSettings }

    static func current() -> EditorPhotoLibraryAccess {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return EditorPhotoLibraryAccess(status: EditorPhotoLibraryAccessStatus(status))
    }
}

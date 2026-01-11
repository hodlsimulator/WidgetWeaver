//
//  EditorUnavailableState.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

struct EditorUnavailableState: Hashable, Sendable {
    var message: String
    var cta: EditorUnavailableCTA?
}

struct EditorUnavailableCTA: Hashable, Sendable {
    var kind: EditorUnavailableCTAKind
    var label: String?

    init(kind: EditorUnavailableCTAKind, label: String? = nil) {
        self.kind = kind
        self.label = label
    }
}

enum EditorUnavailableCTAKind: Hashable, Sendable {
    case showPro
    case requestPhotosAccess
    case openPhotosSettings
}

extension EditorUnavailableCTA {
    static func showPro(label: String = "Unlock Pro…") -> EditorUnavailableCTA {
        EditorUnavailableCTA(kind: .showPro, label: label)
    }

    static func requestPhotosAccess(label: String = "Allow Photos Access…") -> EditorUnavailableCTA {
        EditorUnavailableCTA(kind: .requestPhotosAccess, label: label)
    }

    static func openPhotosSettings(label: String = "Open Settings…") -> EditorUnavailableCTA {
        EditorUnavailableCTA(kind: .openPhotosSettings, label: label)
    }
}

// MARK: - Common states (centralised copy)

extension EditorUnavailableState {
    // MARK: Smart Photos / Smart Rules

    static func missingImageForSmartRules() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Add an image to enable Smart Rules.",
            cta: nil
        )
    }

    static func missingSmartPhotoForSmartRules() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Enable Smart Photo to edit Smart Rules.",
            cta: nil
        )
    }

    static func missingImageForSmartPhotoFraming() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Add an image to adjust Smart Photo framing.",
            cta: nil
        )
    }

    static func missingSmartPhotoForSmartPhotoFraming() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Enable Smart Photo to adjust framing.",
            cta: nil
        )
    }

    // MARK: Monetisation

    static func proRequiredForVariables() -> EditorUnavailableState {
        EditorUnavailableState(
            message: "Custom variables require WidgetWeaver Pro.",
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

    // MARK: Photos permission

    static func missingPhotosAccess(photoAccess: EditorPhotoLibraryAccess) -> EditorUnavailableState {
        let message: String = {
            if photoAccess.isRequestable {
                return "Allow Photos access to pick images."
            }
            if photoAccess.isBlockedInSettings || !photoAccess.isRequestable {
                return "Photos access is blocked.\nEnable it in Settings to pick images."
            }
            return "Photos access is unavailable."
        }()

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

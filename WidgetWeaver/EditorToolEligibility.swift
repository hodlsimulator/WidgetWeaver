//
//  EditorToolEligibility.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Eligibility rules for a single editor tool.
struct EditorToolEligibility: Hashable, Sendable {
    var focus: EditorToolFocusConstraint
    var selection: EditorToolSelectionConstraint
    var selectionDescriptor: EditorToolSelectionDescriptorConstraint
    var supportsMultiSelection: Bool

    init(
        focus: EditorToolFocusConstraint = .any,
        selection: EditorToolSelectionConstraint = .any,
        selectionDescriptor: EditorToolSelectionDescriptorConstraint = .any,
        supportsMultiSelection: Bool = true
    ) {
        self.focus = focus
        self.selection = selection
        self.selectionDescriptor = selectionDescriptor
        self.supportsMultiSelection = supportsMultiSelection
    }
}

struct EditorToolFocusConstraint: Hashable, Sendable {
    var allowWidget: Bool
    var allowClock: Bool
    var allowElement: Bool
    var allowSmartRuleEditor: Bool
    var allowAlbumContainer: Bool
    var allowAlbumPhoto: Bool

    /// If set, `.element(id:)` is only allowed when the id begins with one of these prefixes.
    var allowedElementIDPrefixes: Set<String>?

    /// If set, `.albumContainer` is only allowed for the specified subtypes.
    var allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype>?

    /// If set, `.albumPhoto` is only allowed for the specified subtypes.
    var allowedAlbumPhotoSubtypes: Set<EditorAlbumSubtype>?

    init(
        allowWidget: Bool = true,
        allowClock: Bool = true,
        allowElement: Bool = true,
        allowSmartRuleEditor: Bool = true,
        allowAlbumContainer: Bool = true,
        allowAlbumPhoto: Bool = true,
        allowedElementIDPrefixes: Set<String>? = nil,
        allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype>? = nil,
        allowedAlbumPhotoSubtypes: Set<EditorAlbumSubtype>? = nil
    ) {
        self.allowWidget = allowWidget
        self.allowClock = allowClock
        self.allowElement = allowElement
        self.allowSmartRuleEditor = allowSmartRuleEditor
        self.allowAlbumContainer = allowAlbumContainer
        self.allowAlbumPhoto = allowAlbumPhoto
        self.allowedElementIDPrefixes = allowedElementIDPrefixes
        self.allowedAlbumContainerSubtypes = allowedAlbumContainerSubtypes
        self.allowedAlbumPhotoSubtypes = allowedAlbumPhotoSubtypes
    }

    func allows(focus: EditorFocusTarget) -> Bool {
        switch focus {
        case .widget:
            return allowWidget

        case .clock:
            return allowClock

        case .smartRuleEditor:
            return allowSmartRuleEditor

        case .element(let id):
            guard allowElement else { return false }
            if let prefixes = allowedElementIDPrefixes {
                return prefixes.contains(where: { id.hasPrefix($0) })
            }
            return true

        case .albumContainer(_, let subtype):
            guard allowAlbumContainer else { return false }
            if let allowed = allowedAlbumContainerSubtypes {
                return allowed.contains(subtype)
            }
            return true

        case .albumPhoto(_, _, let subtype):
            guard allowAlbumPhoto else { return false }
            if let allowed = allowedAlbumPhotoSubtypes {
                return allowed.contains(subtype)
            }
            return true
        }
    }
}

extension EditorToolFocusConstraint {
    static let any = EditorToolFocusConstraint()

    static let widgetOnly = EditorToolFocusConstraint(
        allowWidget: true,
        allowClock: false,
        allowElement: false,
        allowSmartRuleEditor: false,
        allowAlbumContainer: false,
        allowAlbumPhoto: false
    )

    static let smartPhotoTarget = EditorToolFocusConstraint(
        allowWidget: false,
        allowClock: false,
        allowElement: true,
        allowSmartRuleEditor: false,
        allowAlbumContainer: true,
        allowAlbumPhoto: true,
        allowedElementIDPrefixes: ["smartPhoto"]
    )

    static let smartRules = EditorToolFocusConstraint(
        allowWidget: false,
        allowClock: false,
        allowElement: true,
        allowSmartRuleEditor: true,
        allowAlbumContainer: true,
        allowAlbumPhoto: true,
        allowedElementIDPrefixes: ["smartRules"]
    )

    static let albumShuffle = EditorToolFocusConstraint(
        allowWidget: false,
        allowClock: false,
        allowElement: true,
        allowSmartRuleEditor: false,
        allowAlbumContainer: true,
        allowAlbumPhoto: true,
        allowedElementIDPrefixes: ["albumShuffle"]
    )

    static let importReview = EditorToolFocusConstraint(
        allowWidget: false,
        allowClock: false,
        allowElement: true,
        allowSmartRuleEditor: false,
        allowAlbumContainer: false,
        allowAlbumPhoto: false,
        allowedElementIDPrefixes: ["importReview"]
    )
}

struct EditorToolSelectionConstraint: Hashable, Sendable {
    var allowedKinds: Set<EditorSelectionKind>

    init(allowedKinds: Set<EditorSelectionKind> = Set(EditorSelectionKind.allCases)) {
        self.allowedKinds = allowedKinds
    }

    func allows(selection: EditorSelectionKind) -> Bool {
        allowedKinds.contains(selection)
    }
}

extension EditorToolSelectionConstraint {
    static let any = EditorToolSelectionConstraint()
    static let allowsNoneOrSingle = EditorToolSelectionConstraint(allowedKinds: [.none, .single])
    static let singleOnly = EditorToolSelectionConstraint(allowedKinds: [.single])
}

struct EditorToolSelectionDescriptorConstraint: Hashable, Sendable {
    var allowedHomogeneity: Set<EditorSelectionHomogeneity>
    var allowedAlbumSpecificity: Set<EditorAlbumSelectionSpecificity>

    init(
        allowedHomogeneity: Set<EditorSelectionHomogeneity> = Set(EditorSelectionHomogeneity.allCases),
        allowedAlbumSpecificity: Set<EditorAlbumSelectionSpecificity> = Set(EditorAlbumSelectionSpecificity.allCases)
    ) {
        self.allowedHomogeneity = allowedHomogeneity
        self.allowedAlbumSpecificity = allowedAlbumSpecificity
    }

    func allows(selectionDescriptor: EditorSelectionDescriptor) -> Bool {
        allowedHomogeneity.contains(selectionDescriptor.homogeneity) &&
        allowedAlbumSpecificity.contains(selectionDescriptor.albumSpecificity)
    }
}

extension EditorToolSelectionDescriptorConstraint {
    static let any = EditorToolSelectionDescriptorConstraint()

    static let allowsNonAlbumOnly = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: Set(EditorSelectionHomogeneity.allCases),
        allowedAlbumSpecificity: [.none]
    )

    static let allowsAlbumContainerOrNone = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: Set(EditorSelectionHomogeneity.allCases),
        allowedAlbumSpecificity: [.none, .albumContainer]
    )

    static let allowsAlbumContainerOrNonAlbumHomogeneousOrNone = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: Set(EditorSelectionHomogeneity.allCases),
        allowedAlbumSpecificity: [.none, .albumContainer]
    )
}

/// Central evaluator used by the tool registry.
enum EditorToolEligibilityEvaluator {
    static func isEligible(
        eligibility: EditorToolEligibility,
        selection: EditorSelectionKind,
        selectionDescriptor: EditorSelectionDescriptor,
        focus: EditorFocusTarget
    ) -> Bool {
        if selection == .multi, eligibility.supportsMultiSelection == false {
            return false
        }
        if eligibility.selection.allows(selection: selection) == false {
            return false
        }
        if eligibility.selectionDescriptor.allows(selectionDescriptor: selectionDescriptor) == false {
            return false
        }
        if eligibility.focus.allows(focus: focus) == false {
            return false
        }
        return true
    }
}

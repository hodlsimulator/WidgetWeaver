//
//  EditorToolEligibility.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

// MARK: - Selection constraint

enum EditorToolSelectionConstraint: Hashable, Sendable {
    case any
    case allowsNoneOrSingle
    case allowsSingleOnly

    func allows(_ selection: EditorSelectionKind) -> Bool {
        switch self {
        case .any:
            return true
        case .allowsNoneOrSingle:
            return selection == .none || selection == .single
        case .allowsSingleOnly:
            return selection == .single
        }
    }
}

// MARK: - Focus constraint

struct EditorToolFocusConstraint: Hashable, Sendable {
    var allowWidget: Bool
    var allowClock: Bool
    var allowSmartRuleEditor: Bool

    var allowAnyElement: Bool
    var allowedElementIDPrefixes: Set<String>

    var allowAnyAlbumContainer: Bool
    var allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype>

    var allowAnyAlbumPhotoItem: Bool
    var allowedAlbumPhotoItemSubtypes: Set<EditorAlbumSubtype>

    init(
        allowWidget: Bool = true,
        allowClock: Bool = true,
        allowSmartRuleEditor: Bool = true,
        allowAnyElement: Bool = true,
        allowedElementIDPrefixes: Set<String> = [],
        allowAnyAlbumContainer: Bool = true,
        allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype> = [],
        allowAnyAlbumPhotoItem: Bool = true,
        allowedAlbumPhotoItemSubtypes: Set<EditorAlbumSubtype> = []
    ) {
        self.allowWidget = allowWidget
        self.allowClock = allowClock
        self.allowSmartRuleEditor = allowSmartRuleEditor
        self.allowAnyElement = allowAnyElement
        self.allowedElementIDPrefixes = allowedElementIDPrefixes
        self.allowAnyAlbumContainer = allowAnyAlbumContainer
        self.allowedAlbumContainerSubtypes = allowedAlbumContainerSubtypes
        self.allowAnyAlbumPhotoItem = allowAnyAlbumPhotoItem
        self.allowedAlbumPhotoItemSubtypes = allowedAlbumPhotoItemSubtypes
    }

    func allows(_ focus: EditorFocusTarget) -> Bool {
        switch focus {
        case .widget:
            return allowWidget

        case .clock:
            return allowClock

        case .smartRuleEditor:
            return allowSmartRuleEditor

        case .element(let id):
            if allowAnyElement { return true }
            return allowedElementIDPrefixes.contains(where: { id.hasPrefix($0) })

        case .albumContainer(_, let subtype):
            if allowAnyAlbumContainer { return true }
            if allowedAlbumContainerSubtypes.isEmpty { return false }
            return allowedAlbumContainerSubtypes.contains(subtype)

        case .albumPhoto(_, _, let subtype):
            if allowAnyAlbumPhotoItem { return true }
            if allowedAlbumPhotoItemSubtypes.isEmpty { return false }
            return allowedAlbumPhotoItemSubtypes.contains(subtype)
        }
    }

    static let any = EditorToolFocusConstraint()

    static let smartPhotoContainerSuite = EditorToolFocusConstraint(
        allowClock: false,
        allowSmartRuleEditor: true,
        allowAnyElement: false,
        allowedElementIDPrefixes: ["smartPhoto"],
        allowAnyAlbumContainer: false,
        allowedAlbumContainerSubtypes: [.smart],
        allowAnyAlbumPhotoItem: false,
        allowedAlbumPhotoItemSubtypes: [.smart]
    )

    static let smartPhotoPhotoItemSuite = EditorToolFocusConstraint(
        allowClock: false,
        allowSmartRuleEditor: true,
        allowAnyElement: false,
        allowedElementIDPrefixes: ["smartPhoto"],
        allowAnyAlbumContainer: false,
        allowedAlbumContainerSubtypes: [.smart],
        allowAnyAlbumPhotoItem: false,
        allowedAlbumPhotoItemSubtypes: [.smart]
    )
}

// MARK: - Selection descriptor constraint

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

    func allows(_ descriptor: EditorSelectionDescriptor) -> Bool {
        allowedHomogeneity.contains(descriptor.homogeneity) &&
        allowedAlbumSpecificity.contains(descriptor.albumSpecificity)
    }

    static let any = EditorToolSelectionDescriptorConstraint()

    /// Explicitly allows mixed selections.
    ///
    /// This is semantically the same as `.any`, but is used in the tool manifest
    /// to make mixed-selection policy explicit tool-by-tool.
    static let allowsAnyIncludingMixedSelection = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: Set(EditorSelectionHomogeneity.allCases),
        allowedAlbumSpecificity: Set(EditorAlbumSelectionSpecificity.allCases)
    )

    /// Explicitly allows mixed selection descriptors.
    ///
    /// This is a naming-only alias for `allowsAnyIncludingMixedSelection`.
    static let mixedAllowed = allowsAnyIncludingMixedSelection

    static let allowsHomogeneousOrNoneSelection = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: [.homogeneous],
        allowedAlbumSpecificity: [.nonAlbum, .albumContainer, .albumPhotoItem]
    )

    /// Explicitly disallows mixed selection descriptors.
    ///
    /// This is a naming-only alias for `allowsHomogeneousOrNoneSelection`.
    static let mixedDisallowed = allowsHomogeneousOrNoneSelection

    static let allowsAlbumContainerOrNonAlbumHomogeneousOrNone = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: [.homogeneous],
        allowedAlbumSpecificity: [.nonAlbum, .albumContainer]
    )

    static let allowsAlbumPhotoItemHomogeneousOrNone = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: [.homogeneous],
        allowedAlbumSpecificity: [.nonAlbum, .albumPhotoItem]
    )
}

// MARK: - Convenience presets

extension EditorToolEligibility {
    static func singleTarget(
        focus: EditorToolFocusConstraint = .any,
        selectionDescriptor: EditorToolSelectionDescriptorConstraint
    ) -> EditorToolEligibility {
        EditorToolEligibility(
            focus: focus,
            selection: .allowsNoneOrSingle,
            selectionDescriptor: selectionDescriptor,
            supportsMultiSelection: false
        )
    }

    static func multiSafe(
        focus: EditorToolFocusConstraint = .any,
        selection: EditorToolSelectionConstraint = .any,
        selectionDescriptor: EditorToolSelectionDescriptorConstraint
    ) -> EditorToolEligibility {
        EditorToolEligibility(
            focus: focus,
            selection: selection,
            selectionDescriptor: selectionDescriptor,
            supportsMultiSelection: true
        )
    }
}

// MARK: - Eligibility

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

enum EditorToolEligibilityEvaluator {
    static func isEligible(
        eligibility: EditorToolEligibility,
        selection: EditorSelectionKind,
        selectionDescriptor: EditorSelectionDescriptor,
        focus: EditorFocusTarget,
        multiSelectionPolicy: EditorMultiSelectionPolicy
    ) -> Bool {
        guard eligibility.focus.allows(focus) else { return false }
        guard eligibility.selection.allows(selection) else { return false }
        guard eligibility.selectionDescriptor.allows(selectionDescriptor) else { return false }

        if selection == .multi {
            switch multiSelectionPolicy {
            case .intersection:
                return eligibility.supportsMultiSelection
            }
        }

        return true
    }
}

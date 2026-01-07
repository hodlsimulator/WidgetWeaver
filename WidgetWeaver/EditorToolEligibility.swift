//
//  EditorToolEligibility.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

// MARK: - Selection constraint

struct EditorToolSelectionConstraint: Hashable, Sendable {
    var allowedKinds: Set<EditorSelectionKind>

    init(allowedKinds: Set<EditorSelectionKind> = [.none, .single, .multi]) {
        self.allowedKinds = allowedKinds
    }

    func allows(_ selection: EditorSelectionKind) -> Bool {
        allowedKinds.contains(selection)
    }

    static let any = EditorToolSelectionConstraint()

    static let allowsNoneOrSingle = EditorToolSelectionConstraint(allowedKinds: [.none, .single])
    static let allowsNone = EditorToolSelectionConstraint(allowedKinds: [.none])
}

// MARK: - Focus constraint

struct EditorToolFocusConstraint: Hashable, Sendable {
    var allowWidget: Bool
    var allowClock: Bool

    var allowAnyElement: Bool
    var allowedElementIDPrefixes: Set<String>

    var allowSmartRuleEditor: Bool

    var allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype>
    var allowedAlbumPhotoSubtypes: Set<EditorAlbumSubtype>

    init(
        allowWidget: Bool = true,
        allowClock: Bool = true,
        allowAnyElement: Bool = true,
        allowedElementIDPrefixes: Set<String> = Set<String>(),
        allowSmartRuleEditor: Bool = true,
        allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype> = Set<EditorAlbumSubtype>(),
        allowedAlbumPhotoSubtypes: Set<EditorAlbumSubtype> = Set<EditorAlbumSubtype>()
    ) {
        self.allowWidget = allowWidget
        self.allowClock = allowClock
        self.allowAnyElement = allowAnyElement
        self.allowedElementIDPrefixes = allowedElementIDPrefixes
        self.allowSmartRuleEditor = allowSmartRuleEditor
        self.allowedAlbumContainerSubtypes = allowedAlbumContainerSubtypes
        self.allowedAlbumPhotoSubtypes = allowedAlbumPhotoSubtypes
    }

    func allows(_ focus: EditorFocusTarget) -> Bool {
        switch focus {
        case .widget:
            return allowWidget

        case .clock:
            return allowClock

        case .element(let id):
            if allowAnyElement { return true }
            for prefix in allowedElementIDPrefixes where id.hasPrefix(prefix) {
                return true
            }
            return false

        case .smartRuleEditor:
            return allowSmartRuleEditor

        case .albumContainer(_, let subtype):
            // If the set is empty, treat it as “any subtype”.
            if allowedAlbumContainerSubtypes.isEmpty { return true }
            return allowedAlbumContainerSubtypes.contains(subtype)

        case .albumPhoto(_, _, let subtype):
            if allowedAlbumPhotoSubtypes.isEmpty { return true }
            return allowedAlbumPhotoSubtypes.contains(subtype)
        }
    }

    static let any = EditorToolFocusConstraint()
}

// MARK: - Multi-selection policy

enum EditorMultiSelectionPolicy: String, CaseIterable, Hashable, Sendable {
    case intersection
}

// MARK: - Eligibility

struct EditorToolEligibility: Hashable, Sendable {
    var focus: EditorToolFocusConstraint
    var selection: EditorToolSelectionConstraint
    var selectionDescriptor: EditorToolSelectionDescriptorConstraint

    /// Whether the tool remains visible when selection is `.multi` (subject to policy).
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

        // Multi-selection policy: tools must explicitly opt in.
        if selection == .multi {
            switch multiSelectionPolicy {
            case .intersection:
                if !eligibility.supportsMultiSelection { return false }
            }
        }

        return true
    }
}

// MARK: - Selection descriptor constraints

struct EditorToolSelectionDescriptorConstraint: Hashable, Sendable {
    var allowedHomogeneity: Set<EditorSelectionHomogeneity>
    var allowedAlbumSpecificity: Set<EditorAlbumSelectionSpecificity>

    init(
        allowedHomogeneity: Set<EditorSelectionHomogeneity> = [.homogeneous, .mixed],
        allowedAlbumSpecificity: Set<EditorAlbumSelectionSpecificity> = [.nonAlbum, .albumContainer, .albumPhotoItem, .mixed]
    ) {
        self.allowedHomogeneity = allowedHomogeneity
        self.allowedAlbumSpecificity = allowedAlbumSpecificity
    }

    func allows(_ descriptor: EditorSelectionDescriptor) -> Bool {
        allowedHomogeneity.contains(descriptor.homogeneity) &&
        allowedAlbumSpecificity.contains(descriptor.albumSpecificity)
    }

    static let any = EditorToolSelectionDescriptorConstraint()

    static let allowsHomogeneousOrNoneSelection = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: [.homogeneous],
        allowedAlbumSpecificity: [.nonAlbum, .albumContainer, .albumPhotoItem]
    )

    static let allowsAlbumContainerOrNonAlbumHomogeneousOrNone = EditorToolSelectionDescriptorConstraint(
        allowedHomogeneity: [.homogeneous],
        allowedAlbumSpecificity: [.nonAlbum, .albumContainer]
    )
}

// MARK: - Convenience presets

extension EditorToolEligibility {
    static func singleTarget(
        focus: EditorToolFocusConstraint = .any,
        selectionDescriptor: EditorToolSelectionDescriptorConstraint = .any
    ) -> EditorToolEligibility {
        EditorToolEligibility(
            focus: focus,
            selection: .allowsNoneOrSingle,
            selectionDescriptor: selectionDescriptor,
            supportsMultiSelection: false
        )
    }
}

extension EditorToolFocusConstraint {
    /// Widget + Smart Photo container-level subflows.
    static var smartPhotoContainerSuite: EditorToolFocusConstraint {
        EditorToolFocusConstraint(
            allowWidget: true,
            allowClock: false,
            allowAnyElement: false,
            allowedElementIDPrefixes: ["smartPhoto"],
            allowSmartRuleEditor: true,
            allowedAlbumContainerSubtypes: [.smart],
            allowedAlbumPhotoSubtypes: Set<EditorAlbumSubtype>()
        )
    }

    /// Widget + Smart Photo subflows + any Smart album photo-item focus.
    static var smartPhotoPhotoItemSuite: EditorToolFocusConstraint {
        EditorToolFocusConstraint(
            allowWidget: true,
            allowClock: false,
            allowAnyElement: false,
            allowedElementIDPrefixes: ["smartPhoto"],
            allowSmartRuleEditor: true,
            allowedAlbumContainerSubtypes: [.smart],
            allowedAlbumPhotoSubtypes: [.smart]
        )
    }
}

extension EditorToolEligibility {
    static func multiSafe(
        focus: EditorToolFocusConstraint = .any,
        selection: EditorToolSelectionConstraint = .any,
        selectionDescriptor: EditorToolSelectionDescriptorConstraint = .any
    ) -> EditorToolEligibility {
        EditorToolEligibility(
            focus: focus,
            selection: selection,
            selectionDescriptor: selectionDescriptor,
            supportsMultiSelection: true
        )
    }
}

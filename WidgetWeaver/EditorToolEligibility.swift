//
//  EditorToolEligibility.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

// MARK: - Eligibility constraints (beyond capabilities)

/// Global policy for how the editor behaves when multiple items are selected.
///
/// The current editor UI is mostly single-target, but the tool suite must have a
/// deterministic policy for future multi-selection.
enum EditorToolMultiSelectionPolicy: String, CaseIterable, Hashable, Sendable {
    /// Tools must explicitly opt into multi-selection visibility.
    ///
    /// This avoids applying single-target tools in an ambiguous context.
    case intersection
}

/// Data-driven constraints for whether a tool can be shown for a given editor context.
///
/// Capability checks happen separately. Eligibility is evaluated *after* capabilities.
struct EditorToolEligibility: Hashable, Sendable {
    var focus: EditorToolFocusConstraint
    var selection: EditorToolSelectionConstraint

    /// Whether this tool can appear when the current selection is `.multi`.
    ///
    /// Under the `.intersection` policy, tools that do not opt in are hidden.
    var supportsMultiSelection: Bool

    init(
        focus: EditorToolFocusConstraint = .any,
        selection: EditorToolSelectionConstraint = .any,
        supportsMultiSelection: Bool = false
    ) {
        self.focus = focus
        self.selection = selection
        self.supportsMultiSelection = supportsMultiSelection
    }

    static let unconstrained = EditorToolEligibility()

    func isEligible(
        context: EditorToolContext,
        multiSelectionPolicy: EditorToolMultiSelectionPolicy
    ) -> Bool {
        let effectiveSelection = EditorToolEligibilityEngine.effectiveSelection(
            selection: context.selection,
            focus: context.focus
        )

        if effectiveSelection.kind == .multi {
            switch multiSelectionPolicy {
            case .intersection:
                if !supportsMultiSelection { return false }
            }
        }

        guard focus.allows(context.focus) else { return false }
        guard selection.allows(effectiveSelection) else { return false }
        return true
    }
}

/// Selection-count constraints.
///
/// This is intentionally coarse: the editor currently stores selection as `.none/.single/.multi`.
struct EditorToolSelectionConstraint: Hashable, Sendable {
    var allowedKinds: Set<EditorSelectionKind>?
    var minCount: Int?
    var maxCount: Int?

    init(
        allowedKinds: Set<EditorSelectionKind>? = nil,
        minCount: Int? = nil,
        maxCount: Int? = nil
    ) {
        self.allowedKinds = allowedKinds
        self.minCount = minCount
        self.maxCount = maxCount
    }

    static let any = EditorToolSelectionConstraint()

    func allows(_ selection: EditorToolEligibilityEngine.EffectiveSelection) -> Bool {
        if let allowedKinds, !allowedKinds.contains(selection.kind) {
            return false
        }

        if let minCount, selection.count < minCount {
            return false
        }

        if let maxCount, selection.count > maxCount {
            return false
        }

        return true
    }
}

/// Focus-target constraints.
///
/// This avoids scattered `if focus == ...` checks throughout the tool suite.
struct EditorToolFocusConstraint: Hashable, Sendable {
    var allowWidget: Bool
    var allowClock: Bool

    /// If true, any `.element(id:)` focus is allowed.
    var allowAnyElement: Bool

    /// Optional allowlist for `.element(id:)` focus, expressed as ID prefixes.
    /// When non-empty and `allowAnyElement == false`, the element must match at least one prefix.
    var allowedElementIDPrefixes: [String]

    var allowSmartRuleEditor: Bool

    /// Allowed subtypes for album container focus.
    var allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype>

    /// Allowed subtypes for album photo focus.
    var allowedAlbumPhotoSubtypes: Set<EditorAlbumSubtype>

    init(
        allowWidget: Bool = true,
        allowClock: Bool = true,
        allowAnyElement: Bool = true,
        allowedElementIDPrefixes: [String] = [],
        allowSmartRuleEditor: Bool = true,
        allowedAlbumContainerSubtypes: Set<EditorAlbumSubtype> = Set(EditorAlbumSubtype.allCases),
        allowedAlbumPhotoSubtypes: Set<EditorAlbumSubtype> = Set(EditorAlbumSubtype.allCases)
    ) {
        self.allowWidget = allowWidget
        self.allowClock = allowClock
        self.allowAnyElement = allowAnyElement
        self.allowedElementIDPrefixes = allowedElementIDPrefixes
        self.allowSmartRuleEditor = allowSmartRuleEditor
        self.allowedAlbumContainerSubtypes = allowedAlbumContainerSubtypes
        self.allowedAlbumPhotoSubtypes = allowedAlbumPhotoSubtypes
    }

    static let any = EditorToolFocusConstraint()

    func allows(_ focus: EditorFocusTarget) -> Bool {
        switch focus {
        case .widget:
            return allowWidget

        case .clock:
            return allowClock

        case .element(let id):
            if allowAnyElement { return true }
            if allowedElementIDPrefixes.isEmpty { return false }
            return allowedElementIDPrefixes.contains(where: { id.hasPrefix($0) })

        case .albumContainer(_, let subtype):
            return allowedAlbumContainerSubtypes.contains(subtype)

        case .albumPhoto(_, _, let subtype):
            return allowedAlbumPhotoSubtypes.contains(subtype)

        case .smartRuleEditor:
            return allowSmartRuleEditor
        }
    }
}

enum EditorToolEligibilityEngine {
    struct EffectiveSelection: Hashable, Sendable {
        var kind: EditorSelectionKind
        var count: Int
    }

    /// Converts the editor’s coarse selection state into a deterministic selection count.
    ///
    /// Policy:
    /// - If focus is `.widget` or `.clock`, selection is treated as 0.
    /// - If focus targets a specific thing (element/album), and selection is `.none`,
    ///   treat it as a single-target selection. This is defensive: focus is considered
    ///   the stronger signal.
    /// - `.multi` is treated as 2 (minimally) because the exact count is not currently stored.
    static func effectiveSelection(
        selection: EditorSelectionKind,
        focus: EditorFocusTarget
    ) -> EffectiveSelection {
        func selectionForFocusedTarget(_ selection: EditorSelectionKind) -> EffectiveSelection {
            switch selection {
            case .none:
                return EffectiveSelection(kind: .single, count: 1)
            case .single:
                return EffectiveSelection(kind: .single, count: 1)
            case .multi:
                return EffectiveSelection(kind: .multi, count: 2)
            }
        }

        switch focus {
        case .widget, .clock:
            return EffectiveSelection(kind: .none, count: 0)

        case .element:
            return selectionForFocusedTarget(selection)

        case .albumContainer:
            return selectionForFocusedTarget(selection)

        case .albumPhoto:
            return selectionForFocusedTarget(selection)

        case .smartRuleEditor:
            return selectionForFocusedTarget(selection)
        }
    }
}

// MARK: - Convenience presets

extension EditorToolFocusConstraint {
    /// Widget + Smart Photo subflows (element IDs that start with `smartPhoto`) + Smart album container focus + Smart Rules editor.
    /// Excludes `.albumPhoto` focus (photo-item editing) to avoid showing container-level tools in item contexts.
    static var smartPhotoContainerSuite: EditorToolFocusConstraint {
        EditorToolFocusConstraint(
            allowWidget: true,
            allowClock: true,
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
            allowClock: true,
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
        selection: EditorToolSelectionConstraint = .any
    ) -> EditorToolEligibility {
        EditorToolEligibility(
            focus: focus,
            selection: selection,
            supportsMultiSelection: true
        )
    }
}

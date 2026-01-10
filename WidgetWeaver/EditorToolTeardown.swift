//
//  EditorToolTeardown.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

enum EditorToolTeardownAction: Hashable, Sendable {
    case dismissAlbumShufflePicker
    case resetEditorFocusToWidgetDefault
}

/// A data-only rule that describes which tool must remain visible for a given focus target.
///
/// If the required tool disappears (or was never eligible), the editor should teardown the sub-flow
/// and reset focus so the UI doesn't get stuck.
private struct EditorToolFocusRequirement: Hashable, Sendable {
    var requiredToolID: EditorToolID
    var actions: [EditorToolTeardownAction]
}

private func editorToolFocusRequirement(for focus: EditorFocusTarget) -> EditorToolFocusRequirement? {
    switch focus {
    case .albumContainer(let id, let subtype)
        where id == "smartPhotoAlbumPicker" && subtype == .smart:
        return EditorToolFocusRequirement(
            requiredToolID: .albumShuffle,
            actions: [
                .dismissAlbumShufflePicker,
                .resetEditorFocusToWidgetDefault,
            ]
        )

    case .smartRuleEditor:
        return EditorToolFocusRequirement(
            requiredToolID: .smartRules,
            actions: [
                .resetEditorFocusToWidgetDefault,
            ]
        )

    case .element(let id) where id == "smartPhotoCrop":
        return EditorToolFocusRequirement(
            requiredToolID: .smartPhotoCrop,
            actions: [
                .resetEditorFocusToWidgetDefault,
            ]
        )

    case .clock:
        // Defensive: clock focus should always have access to core editor tools.
        //
        // This does not touch ticking/timing logic; it only ensures focus cannot remain stuck
        // if the tool surface becomes invalid.
        return EditorToolFocusRequirement(
            requiredToolID: .widgets,
            actions: [
                .resetEditorFocusToWidgetDefault,
            ]
        )

    case .widget, .element, .albumContainer, .albumPhoto:
        return nil
    }
}

private func teardownActionsForRemovedTool(_ toolID: EditorToolID) -> [EditorToolTeardownAction] {
    switch toolID {
    case .albumShuffle:
        // If the tool disappears, ensure any transient picker UI is dismissed.
        return [.dismissAlbumShufflePicker]
    default:
        return []
    }
}

func editorToolTeardownActions(
    old: [EditorToolID],
    new: [EditorToolID],
    currentFocus: EditorFocusTarget
) -> [EditorToolTeardownAction] {
    var actions: [EditorToolTeardownAction] = []

    func appendIfMissing(_ action: EditorToolTeardownAction) {
        if actions.contains(action) { return }
        actions.append(action)
    }

    func appendAllIfMissing(_ newActions: [EditorToolTeardownAction]) {
        for a in newActions { appendIfMissing(a) }
    }

    let removedTools = Set(old).subtracting(Set(new))

    // 1) Tool-specific teardown for tools that own transient UI.
    for toolID in removedTools {
        appendAllIfMissing(teardownActionsForRemovedTool(toolID))
    }

    // 2) Focus-based teardown: if the current focus implies a sub-flow tool, but that tool is not visible,
    // reset focus to a safe default (and teardown any transient UI owned by that flow).
    if let requirement = editorToolFocusRequirement(for: currentFocus) {
        if !new.contains(requirement.requiredToolID) {
            appendAllIfMissing(requirement.actions)
        }
    }

    return actions
}

// MARK: - Focus teardown restoration

/// Tracks transient editor sub-flows that temporarily override `EditorFocusSnapshot`
/// and should restore to the previous snapshot if the sub-flow is torn down.
///
/// This is plain data (no SwiftUI) so it can be stored in view state and unit-tested.
struct EditorFocusRestorationStack: Hashable, Sendable {
    struct Entry: Hashable, Sendable {
        var kind: Kind
        var targetFocus: EditorFocusTarget
        var previousSnapshot: EditorFocusSnapshot

        init(
            kind: Kind,
            targetFocus: EditorFocusTarget,
            previousSnapshot: EditorFocusSnapshot
        ) {
            self.kind = kind
            self.targetFocus = targetFocus
            self.previousSnapshot = previousSnapshot
        }
    }

    /// The set of focus targets that are treated as nested “sub-flows” with restoration behaviour.
    ///
    /// Notes:
    /// - These are not intended to cover generic widget selection or layout focus.
    /// - They exist to prevent the editor getting stuck if an in-flight tool becomes ineligible.
    enum Kind: String, Hashable, Sendable {
        /// Album Shuffle “Choose Album” picker presented as a sheet.
        case albumShufflePicker

        /// Smart Rules editor (exclusive screen).
        case smartRulesEditor

        /// Smart Photo crop / framing editor (exclusive screen).
        case smartPhotoCropEditor

        /// Clock editor focus. This does not touch ticking/timing logic.
        case clockEditor
    }

    private(set) var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Records a focus transition, updating the restoration stack if the transition enters or exits
    /// a tracked sub-flow.
    mutating func recordFocusChange(old: EditorFocusSnapshot, new: EditorFocusSnapshot) {
        // 1) If leaving a tracked focus target, drop its entry (and any nested entries above it).
        if let oldKind = kind(for: old.focus) {
            if let idx = entries.lastIndex(where: { $0.kind == oldKind && $0.targetFocus == old.focus }) {
                entries.removeSubrange(idx..<entries.count)
            }
        }

        // 2) If entering a tracked focus target, push a new restoration entry.
        if let newKind = kind(for: new.focus) {
            if let last = entries.last, last.kind == newKind, last.targetFocus == new.focus {
                return
            }

            entries.append(
                Entry(
                    kind: newKind,
                    targetFocus: new.focus,
                    previousSnapshot: old
                )
            )
        }
    }

    /// Pops and returns the previous focus snapshot for the current focus, if the current focus
    /// is a tracked sub-flow.
    ///
    /// Intended usage:
    /// - A tool suite update removes a required tool for the current focus.
    /// - The editor tears down the sub-flow UI (dismiss sheet / pop nav).
    /// - The focus snapshot is restored to the last known pre-sub-flow snapshot, preventing
    ///   the UI getting stuck in an unreachable context.
    mutating func restoreFocusAfterTeardown(currentFocusSnapshot: EditorFocusSnapshot) -> EditorFocusSnapshot? {
        guard let currentKind = kind(for: currentFocusSnapshot.focus) else { return nil }
        guard let idx = entries.lastIndex(where: { $0.kind == currentKind && $0.targetFocus == currentFocusSnapshot.focus }) else { return nil }

        let previous = entries[idx].previousSnapshot
        entries.removeSubrange(idx..<entries.count)
        return previous
    }

    // MARK: - Focus classification

    private func kind(for focus: EditorFocusTarget) -> Kind? {
        switch focus {
        case .albumContainer(let id, let subtype)
            where id == "smartPhotoAlbumPicker" && subtype == .smart:
            return .albumShufflePicker

        case .smartRuleEditor:
            return .smartRulesEditor

        case .element(let id) where id == "smartPhotoCrop":
            return .smartPhotoCropEditor

        case .clock:
            return .clockEditor

        case .widget, .element, .albumContainer, .albumPhoto:
            return nil
        }
    }
}

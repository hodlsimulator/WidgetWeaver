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

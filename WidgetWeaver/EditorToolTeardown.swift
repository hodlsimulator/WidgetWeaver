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

func editorToolTeardownActions(
    old: [EditorToolID],
    new: [EditorToolID],
    currentFocus: EditorFocusTarget
) -> [EditorToolTeardownAction] {
    let oldSet = Set(old)
    let newSet = Set(new)

    let removedTools = oldSet.subtracting(newSet)

    var actions: [EditorToolTeardownAction] = []

    func appendOnce(_ action: EditorToolTeardownAction) {
        guard !actions.contains(action) else { return }
        actions.append(action)
    }

    // Tool disappearance actions (e.g. dismiss transient sheets/pickers).
    if removedTools.contains(.albumShuffle) {
        appendOnce(.dismissAlbumShufflePicker)
    }

    // Focus ownership:
    // If the current focus represents a nested sub-flow, and the tool that owns that sub-flow is no longer
    // visible, reset focus back to a stable widget-level default.
    if let owningTool = editorToolOwningFocus(currentFocus), !newSet.contains(owningTool) {
        appendOnce(.resetEditorFocusToWidgetDefault)
    }

    // Focus group guards:
    // If a focus group is active but none of its primary tools remain, the editor is effectively “inside”
    // a sub-flow with no surface to exit, so reset focus defensively.
    switch editorToolFocusGroup(for: currentFocus) {
    case .smartPhotos:
        let primarySmartPhotoTools: Set<EditorToolID> = [.albumShuffle, .smartPhotoCrop, .smartRules, .smartPhoto, .image]
        if primarySmartPhotoTools.isDisjoint(with: newSet) {
            appendOnce(.resetEditorFocusToWidgetDefault)
        }

    case .clock:
        let primaryClockTools: Set<EditorToolID> = [.widgets, .layout, .style]
        if primaryClockTools.isDisjoint(with: newSet) {
            appendOnce(.resetEditorFocusToWidgetDefault)
        }

    case .widget, .other:
        break
    }

    return actions
}

private func editorToolOwningFocus(_ focus: EditorFocusTarget) -> EditorToolID? {
    switch focus {
    case .smartRuleEditor:
        return .smartRules

    case .element(let id) where id == "smartPhotoCrop":
        return .smartPhotoCrop

    case .albumContainer(let id, let subtype) where subtype == .smart && id == "smartPhotoAlbumPicker":
        return .albumShuffle

    case .clock:
        // Clock focus is a sub-flow even when no dedicated clock tool exists.
        // Use a stable, always-present tool as an owner so focus can be reset if the clock surface
        // ever becomes unavailable.
        return .layout

    case .widget, .element, .albumContainer, .albumPhoto:
        return nil
    }
}

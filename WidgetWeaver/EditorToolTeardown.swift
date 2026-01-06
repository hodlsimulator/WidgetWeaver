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

enum EditorToolTeardown {
    static func teardownActions(
        previousVisibleTools: [EditorToolID],
        newVisibleTools: [EditorToolID],
        currentFocus: EditorFocusTarget
    ) -> [EditorToolTeardownAction] {
        let previousSet = Set(previousVisibleTools)
        let newSet = Set(newVisibleTools)
        let removedTools = previousSet.subtracting(newSet)

        var actions: [EditorToolTeardownAction] = []

        // If Album Shuffle disappears, dismiss the picker and reset focus if needed.
        if removedTools.contains(.albumShuffle) {
            actions.append(.dismissAlbumShufflePicker)

            if case .albumContainer(id: "smartPhotoAlbumPicker", subtype: _) = currentFocus {
                actions.append(.resetEditorFocusToWidgetDefault)
            }
        }


        if removedTools.contains(.smartRules), case .smartRuleEditor = currentFocus {
            actions.append(.resetEditorFocusToWidgetDefault)
        }

        return actions
    }
}

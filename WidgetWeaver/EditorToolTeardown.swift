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
    var actions: [EditorToolTeardownAction] = []

    let removedTools = Set(old).subtracting(Set(new))

    if removedTools.contains(.albumShuffle) {
        actions.append(.dismissAlbumShufflePicker)

        let albumPickerTarget: EditorFocusTarget = .albumContainer(
            id: "smartPhotoAlbumPicker",
            subtype: .smart
        )

        if currentFocus == albumPickerTarget {
            actions.append(.resetEditorFocusToWidgetDefault)
        }
    }

    return actions
}

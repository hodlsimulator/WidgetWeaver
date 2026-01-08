//
//  ContentView+SectionAlbumShuffle.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI

extension ContentView {
    var albumShuffleSection: some View {
        let hasImage = editorToolContext.hasImageConfigured
        let hasSmartPhoto = editorToolContext.hasSmartPhotoConfigured
        let photoAccess = editorToolContext.photoLibraryAccess

        return Section {
            if !hasImage {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.imageRequiredForAlbumShuffle(),
                    isBusy: false
                )
            } else if !hasSmartPhoto {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.smartPhotoRequiredForAlbumShuffle(),
                    isBusy: false
                )
            } else if let unavailable = EditorUnavailableState.photosAccessRequiredForAlbumShuffle(photoAccess: photoAccess) {
                EditorUnavailableStateView(
                    state: unavailable,
                    isBusy: importInProgress,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                SmartPhotoAlbumShuffleControls(
                    smartPhoto: binding(\.imageSmartPhoto),
                    importInProgress: $importInProgress,
                    saveStatusMessage: $saveStatusMessage,
                    focus: $editorFocusSnapshot,
                    albumPickerPresented: $albumShufflePickerPresented
                )
            }
        } header: {
            sectionHeader("Album Shuffle")
        }
    }
}

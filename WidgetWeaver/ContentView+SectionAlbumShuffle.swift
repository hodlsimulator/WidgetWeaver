//
//  ContentView+SectionAlbumShuffle.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI

extension ContentView {
    var albumShuffleSection: some View {
        let d = currentFamilyDraft()
        let hasImage = !d.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSmartPhoto = d.imageSmartPhoto != nil

        return Section {
            if !hasImage {
                Text("Choose a photo in Image first.\nThen make Smart Photo renders in Smart Photo to enable Album Shuffle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !hasSmartPhoto {
                Text("Album Shuffle requires Smart Photo.\nIn Smart Photo, tap ‘Make Smart Photo (per-size renders)’.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

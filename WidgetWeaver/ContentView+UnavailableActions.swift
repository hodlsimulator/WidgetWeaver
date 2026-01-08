//
//  ContentView+UnavailableActions.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

extension ContentView {
    @MainActor
    func requestPhotosAccessForAlbumShuffle() async {
        guard !importInProgress else { return }
        importInProgress = true
        defer { importInProgress = false }

        let granted = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        saveStatusMessage = granted ? "Photos access enabled." : "Photos access not granted."
    }
}

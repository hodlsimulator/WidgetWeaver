//
//  ContentView+UnavailableActions.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

extension ContentView {
    @MainActor
    func performEditorUnavailableCTA(_ kind: EditorUnavailableCTAKind) async {
        switch kind {
        case .requestPhotosAccess:
            await requestPhotosAccessForAlbumShuffle()

        case .showPro:
            activeSheet = .pro

        case .openAppSettings:
            // Handled via Link in `EditorUnavailableStateView`.
            break
        }
    }

    @MainActor
    private func requestPhotosAccessForAlbumShuffle() async {
        guard !importInProgress else { return }
        importInProgress = true
        defer { importInProgress = false }

        let granted = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        saveStatusMessage = granted ? "Photos access enabled." : "Photos access not granted."
    }
}

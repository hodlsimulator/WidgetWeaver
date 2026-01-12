//
//  ContentView+ToolCapabilityChanges.swift
//  WidgetWeaver
//
//  Created by . . on 1/12/26.
//

import Foundation

extension ContentView {
    func installEditorToolCapabilitiesDidChangeObserverIfNeeded() {
        guard editorToolCapabilitiesDidChangeObserverToken == nil else { return }

        editorToolCapabilitiesDidChangeObserverToken = NotificationCenter.default.addObserver(
            forName: .editorToolCapabilitiesDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                editorToolCapabilitiesDidChangeTick &+= 1
            }
        }
    }

    func uninstallEditorToolCapabilitiesDidChangeObserverIfNeeded() {
        guard let token = editorToolCapabilitiesDidChangeObserverToken else { return }
        NotificationCenter.default.removeObserver(token)
        editorToolCapabilitiesDidChangeObserverToken = nil
    }
}

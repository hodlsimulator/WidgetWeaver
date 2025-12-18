//
//  ContentView+Toolbar.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI

extension ContentView {

    // MARK: - Toolbar

    var toolbarMenu: some View {
        Menu {
            Button { showWidgetHelp = true } label: {
                Label("Widget Help", systemImage: "questionmark.circle")
            }

            Divider()

            Button { createNewDesign() } label: {
                Label("New Design", systemImage: "plus")
            }

            Button { duplicateCurrentDesign() } label: {
                Label("Duplicate Design", systemImage: "doc.on.doc")
            }
            .disabled(savedSpecs.isEmpty)

            Divider()

            Button { saveSelected(makeDefault: true) } label: {
                Label("Save & Make Default", systemImage: "checkmark.circle")
            }

            Button { saveSelected(makeDefault: false) } label: {
                Label("Save (Keep Default)", systemImage: "tray.and.arrow.down")
            }

            Divider()

            // Sharing / Import (Milestone 7)
            ShareLink(item: sharePackageForCurrentDesign(), preview: SharePreview("WidgetWeaver Design")) {
                Label("Share This Design", systemImage: "square.and.arrow.up")
            }

            ShareLink(item: sharePackageForAllDesigns(), preview: SharePreview("WidgetWeaver Designs")) {
                Label("Share All Designs", systemImage: "square.and.arrow.up.on.square")
            }

            Button { showImportPicker = true } label: {
                Label("Import Designs…", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button { refreshWidgets() } label: {
                Label("Refresh Widgets", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label("Delete Design", systemImage: "trash")
            }
            .disabled(savedSpecs.count <= 1)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

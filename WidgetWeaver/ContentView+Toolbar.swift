//
//  ContentView+Toolbar.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI

extension ContentView {

    var toolbarMenu: some View {
        Menu {
            Button { activeSheet = .weather } label: {
                Label("Weather", systemImage: "cloud.sun.fill")
            }

            Divider()

            Button { activeSheet = .about } label: {
                Label("About", systemImage: "info.circle")
            }

            Divider()

            Button { activeSheet = .inspector } label: {
                Label("Inspector", systemImage: "doc.text.magnifyingglass")
            }

            if hasUnsavedChanges {
                Button(role: .destructive) { showRevertConfirmation = true } label: {
                    Label("Revert Unsaved Changes", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()

            Button { activeSheet = .pro } label: {
                Label(proManager.isProUnlocked ? "WidgetWeaver Pro" : "Upgrade to Pro", systemImage: "crown.fill")
            }

            Button { activeSheet = .variables } label: {
                Label("Variables", systemImage: "slider.horizontal.3")
            }

            Button { activeSheet = .widgetHelp } label: {
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

            Button { randomiseStyleDraft() } label: {
                Label("Randomise Style (Draft)", systemImage: "shuffle")
            }

            Button { presentRemixSheet() } label: {
                Label("Remix (5 options)", systemImage: "wand.and.stars")
            }

            Button(role: .destructive) { showImageCleanupConfirmation = true } label: {
                Label("Clean Up Unused Images", systemImage: "trash.slash")
            }

            Divider()

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

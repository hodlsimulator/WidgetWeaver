//
//  SmartPhotoAlbumShufflePhotoDetailView.swift
//  WidgetWeaver
//
//  Created by . . on 1/9/26.
//

import SwiftUI

// MARK: - Album photo-item detail (selection origin)

/// A lightweight detail view used to treat a specific album photo item as a first-class editor selection origin.
///
/// This is intentionally metadata-only (it does not fetch Photos assets). It exists to provide a production
/// selection writer that pushes an origin-backed focus snapshot with explicit `selectionCount` and
/// `selectionComposition`.
struct SmartPhotoAlbumShufflePhotoDetailView: View {
    let manifestFileName: String
    let albumID: String?
    let itemID: String
    var focus: Binding<EditorFocusSnapshot>? = nil

    @State private var previousFocusSnapshot: EditorFocusSnapshot?

    private var resolvedAlbumID: String {
        (albumID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var targetFocus: EditorFocusTarget {
        .albumPhoto(
            albumID: resolvedAlbumID.isEmpty ? "unknownAlbum" : resolvedAlbumID,
            itemID: itemID,
            subtype: .smart
        )
    }

    var body: some View {
        Form {
            Section("Selection") {
                LabeledContent("Album", value: resolvedAlbumID.isEmpty ? "unknownAlbum" : resolvedAlbumID)
                    .textSelection(.enabled)
                LabeledContent("Item ID", value: itemID)
                    .textSelection(.enabled)
            }

            Section("Manifest") {
                LabeledContent("File", value: manifestFileName)
                    .textSelection(.enabled)
            }

            Section("Notes") {
                Text("This view exists to create a stable, typed editor selection origin for a specific album photo item. It does not load Photos assets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Album photo")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("AlbumShuffle.PhotoDetail")
        .onAppear {
            guard let focus else { return }

            if previousFocusSnapshot == nil {
                previousFocusSnapshot = focus.wrappedValue
            }

            focus.wrappedValue = .smartAlbumPhotoItem(
                albumID: resolvedAlbumID.isEmpty ? "unknownAlbum" : resolvedAlbumID,
                itemID: itemID
            )
        }
        .onDisappear {
            guard let focus else { return }
            guard let previous = previousFocusSnapshot else { return }
            defer { previousFocusSnapshot = nil }

            if focus.wrappedValue.focus == targetFocus {
                focus.wrappedValue = previous
            }
        }
    }
}
